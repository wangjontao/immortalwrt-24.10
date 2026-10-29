module('luci.controller.juliang_center',package.seeall)
function index()
  local p=entry({'admin','juliang'},firstchild(),_('JuLiang 控制面板'),1); p.dependent=false; p.acl_depends={'juliang-center'}
  local h=entry({'admin','juliang','home'},template('juliang_center/home'),_('监测中心'),1); h.leaf=true; h.acl_depends={'juliang-center'}
  local w=entry({'admin','juliang','wireless'},template('juliang_center/wireless'),_('无线设备'),2); w.leaf=true; w.acl_depends={'juliang-center'}
  local a=entry({'admin','juliang','status'},call('status'),nil); a.leaf=true; a.acl_depends={'juliang-center'}
  local r=entry({'admin','juliang','reboot'},post('reboot_action'),nil);r.leaf=true;r.acl_depends={'juliang-center'}
end
local function reply(t)
  local h=require 'luci.http'; h.prepare_content('application/json'); h.write(require('luci.jsonc').stringify(t))
end
function can_reboot()
  local sid=require('luci.dispatcher').context.authsession
  if not sid then return false end
  local ok,r=pcall(require('luci.util').ubus,'session','access',{ubus_rpc_session=sid,scope='ubus',object='system',['function']='reboot'})
  return ok and type(r)=='table' and r.access==true
end
function can_autoreboot()
  local sid=require('luci.dispatcher').context.authsession
  if not sid then return false end
  local ok,r=pcall(require('luci.util').ubus,'session','access',{ubus_rpc_session=sid,scope='uci',object='autoreboot',['function']='write'})
  return ok and type(r)=='table' and r.access==true
end
function reboot_action()
  local h=require'luci.http'
  if not can_reboot() then h.status(403,'Forbidden');reply({ok=false,error='当前帐号没有重启权限'});return end
  local ok,result=pcall(function()
    local scheduler=require('juliang_reboot').service();local action=h.formvalue('action')
    if action=='now' then return scheduler.schedule(2)
    elseif action=='delay' then return scheduler.schedule(60)
    elseif action=='cancel' then return scheduler.cancel()
    else error('重启操作无效',0) end
  end)
  if ok then reply({ok=true,reboot=result}) else reply({ok=false,error=tostring(result)}) end
end
local function wired_ports()
  local fs=require'nixio.fs';local json=require'luci.jsonc'
  local board=json.parse(fs.readfile('/etc/board.json') or '') or {};local rows={};local seen={}
  local function add(dev,role)
    if type(dev)~='string' or not dev:match('^[%w_.%-]+$') or seen[dev] then return end
    seen[dev]=true;local base='/sys/class/net/'..dev..'/'
    local carrier=tonumber(fs.readfile(base..'carrier') or '')
    local speed=tonumber(fs.readfile(base..'speed') or '')
    local duplex=(fs.readfile(base..'duplex') or ''):match('%S+')
    rows[#rows+1]={device=dev,role=role,connected=carrier==1,known=carrier~=nil,speed=carrier==1 and speed and speed>0 and speed or nil,duplex=duplex}
  end
  for _,role in ipairs({'wan','lan'}) do
    local net=(board.network or {})[role] or {}
    if type(net.ports)=='table' then for _,dev in ipairs(net.ports) do add(dev,role) end else add(net.device,role) end
  end
  return rows
end
local function cpu_usage()
  local fs=require'nixio.fs';local text=fs.readfile('/proc/stat') or ''
  local values=text:match('^cpu%s+([^\n]+)')
  if not values then return nil end
  local total,idle=0,0;local index=0
  for value in values:gmatch('%d+') do
    index=index+1
    if index<=8 then total=total+tonumber(value) end
    if index==4 or index==5 then idle=idle+tonumber(value) end
  end
  if total<=0 then return nil end
  local old_total,old_idle=(fs.readfile('/tmp/juliang-center-cpu.stat') or ''):match('^(%d+)%s+(%d+)')
  old_total,old_idle=tonumber(old_total),tonumber(old_idle)
  fs.writefile('/tmp/juliang-center-cpu.stat',tostring(total)..' '..tostring(idle)..'\n')
  if not old_total or not old_idle or total<=old_total then return nil end
  local delta=total-old_total
  local percent=100*(delta-math.max(0,idle-old_idle))/delta
  return math.max(0,math.min(100,math.floor(percent+0.5)))
end
local function system_health()
  local fs=require'nixio.fs';local sys=require'luci.sys'
  local mem=fs.readfile('/proc/meminfo') or ''
  local total=tonumber(mem:match('MemTotal:%s+(%d+)'))
  local available=tonumber(mem:match('MemAvailable:%s+(%d+)'))
  if not available then
    local free=tonumber(mem:match('MemFree:%s+(%d+)')) or 0
    local buffers=tonumber(mem:match('Buffers:%s+(%d+)')) or 0
    local cached=tonumber(mem:match('Cached:%s+(%d+)')) or 0
    available=free+buffers+cached
  end
  local used=total and available and math.max(0,total-available) or nil
  local memory_percent=total and total>0 and used and math.floor(used*1000/total+0.5)/10 or nil
  local raw=tonumber(fs.readfile('/sys/class/thermal/thermal_zone0/temp') or '')
  local temperature=raw and (raw>1000 and math.floor(raw/100+0.5)/10 or raw) or nil
  local cores=tonumber((sys.exec('nproc 2>/dev/null') or ''):match('%d+'))
  if not cores then cores=tonumber((sys.exec("grep -c '^processor' /proc/cpuinfo 2>/dev/null") or ''):match('%d+')) end
  return {cpu_percent=cpu_usage(),cpu_cores=cores,memory_percent=memory_percent,memory_used_kb=used,memory_total_kb=total,temperature_c=temperature}
end
local traffic_cache,traffic_cache_at
local function traffic_totals()
  if traffic_cache and os.time()-traffic_cache_at<30 then return traffic_cache end
  local json=require'luci.jsonc';local sys=require'luci.sys'
  local result={available=false,today_rx=0,today_tx=0,month_rx=0,month_tx=0,total_rx=0,total_tx=0}
  local data=json.parse(sys.exec('/usr/bin/vnstat --json 2>/dev/null')) or {}
  local interface=data.interfaces and data.interfaces[1]
  if type(interface)~='table' then return result end
  local traffic=interface.traffic or {}
  local now=os.date('*t')
  local function match(rows,year,month,day)
    if type(rows)~='table' then return nil end
    for _,row in ipairs(rows) do
      local date=row.date or {}
      if tonumber(date.year)==year and tonumber(date.month)==month and (not day or tonumber(date.day)==day) then return row end
    end
    return nil
  end
  local today=match(traffic.day,now.year,now.month,now.day) or {}
  local month=match(traffic.month,now.year,now.month) or {}
  local total=traffic.total or {}
  result.available=true
  result.device=interface.name or ''
  result.today_rx=tonumber(today.rx) or 0
  result.today_tx=tonumber(today.tx) or 0
  result.month_rx=tonumber(month.rx) or 0
  result.month_tx=tonumber(month.tx) or 0
  result.total_rx=tonumber(total.rx) or 0
  result.total_tx=tonumber(total.tx) or 0
  traffic_cache=result
  traffic_cache_at=os.time()
  return result
end
function status()
  local json=require 'luci.jsonc'; local sys=require 'luci.sys'; local u=require('uci').cursor()
  local wan=json.parse(sys.exec('ubus call network.interface.wan status 2>/dev/null')) or {}
  local ip=''; for _,a in ipairs(wan['ipv4-address'] or {}) do if a.address then ip=a.address break end end
  local wifi=0; u:foreach('wireless','wifi-iface',function(s) if s.disabled~='1' then wifi=wifi+1 end end)
  local managed=0; u:foreach('fastacl252','wifi',function() managed=managed+1 end)
  local fast=json.parse(sys.exec('/usr/bin/fastacl252 status 2>/dev/null')) or {}
  local up=tonumber(sys.exec("cut -d. -f1 /proc/uptime 2>/dev/null") or '0') or 0
  local dev=wan.l3_device or wan.device or '';local counters={}
  if dev:match('^[%w_.%-]+$') then
    local fs=require'nixio.fs'
    counters.rx_bytes=tonumber(fs.readfile('/sys/class/net/'..dev..'/statistics/rx_bytes') or '')
    counters.tx_bytes=tonumber(fs.readfile('/sys/class/net/'..dev..'/statistics/tx_bytes') or '')
  end
  counters.timestamp=tonumber(sys.exec('cat /proc/uptime'):match('^[%d.]+')) or up
  counters.device=dev
  reply({ok=true,reboot=can_reboot() and require('juliang_reboot').service().status() or nil,ports=wired_ports(),system=system_health(),traffic=counters,traffic_totals=traffic_totals(),hostname=sys.hostname() or 'JuLiangTK-S20L',uptime=up,wan_up=wan.up==true,wan_ip=ip,wan_device=wan.l3_device or wan.device or '',wifi_count=wifi,managed_wifi=managed,fastacl=fast,version='FastACL 2.6.8 dae/eBPF'})
end
