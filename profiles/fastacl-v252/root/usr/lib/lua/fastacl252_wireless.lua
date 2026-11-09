-- Read-only per-SSID station telemetry. Never returns wireless keys.
local M={}
function M.parse(text)
 local out,row={}
 for line in tostring(text or ''):gmatch('[^\n]+') do
  local mac=line:match('^Station%s+([%x:]+)')
  if mac then row={mac=mac:upper()};out[#out+1]=row
  elseif row then
   local key,value=line:match('^%s*([^:]+):%s*(.*)')
   if key=='rx bytes' then row.rx_bytes=tonumber(value)
   elseif key=='tx bytes' then row.tx_bytes=tonumber(value)
   elseif key=='signal' then row.signal=tonumber(value:match('^(-?%d+)'))
   elseif key=='tx bitrate' then row.tx_link_mbps=tonumber(value:match('([%d.]+)%s+MBit/s'))
   elseif key=='rx bitrate' then row.rx_link_mbps=tonumber(value:match('([%d.]+)%s+MBit/s'))
   elseif key=='connected time' then row.connected_seconds=tonumber(value:match('^(%d+)'))
   end
  end
 end
 return out
end
function M.read()
 local sys=require'luci.sys';local json=require'luci.jsonc';local u=require('uci').cursor();local rows={};local names={};local ips={}
 local f=io.open('/tmp/dhcp.leases');if f then for line in f:lines() do local mac,ip,name=line:match('^%d+%s+(%S+)%s+(%S+)%s+(%S+)');if mac then names[mac:upper()]=name~='*' and name or '' end end;f:close() end
 u:foreach('fastacl252','device',function(d)if d.mac and d.name and d.name~='' then names[d.mac:upper()]=d.name end end)
 for line in sys.exec('ip -4 neigh show 2>/dev/null'):gmatch('[^\n]+') do local ip,dev,mac=line:match('^(%S+)%s+dev%s+(%S+).-lladdr%s+(%S+)');if mac then ips[dev..'/'..mac:upper()]=ip end end
 local status=json.parse(sys.exec('ubus call network.wireless status 2>/dev/null')) or {}
 local runtime={}
 for radio,info in pairs(status) do
  for _,iface in ipairs(info.interfaces or {}) do
   if iface.section then runtime[iface.section]={radio=radio,ifname=iface.ifname,config=iface.config or {},up=info.up==true} end
  end
 end
 u:foreach('wireless','wifi-iface',function(w)
  local section=w['.name'];local cfg=runtime[section] or {};local dev=cfg.ifname
  if (not w.mode or w.mode=='ap') and type(section)=='string' then
   local net=w.network or (cfg.config or {}).network;if type(net)=='table' then net=net[1] end
   local bridge=net and u:get('network',net,'device') or ''
   local stations={}
   if type(dev)=='string' and dev:match('^[%w_.%-]+$') then
    stations=M.parse(sys.exec('iw dev '..dev..' station dump 2>/dev/null'))
    for _,s in ipairs(stations) do s.name=names[s.mac] or '';s.ip=ips[(bridge or '')..'/'..s.mac] or '' end
   end
   rows[#rows+1]={
    id=dev or section,section=section,ssid=w.ssid or cfg.config.ssid or section,
    radio=cfg.radio or w.device or '',band=(w.device and u:get('wireless',w.device,'band')) or '',
    device=w.device or '',network=net or '',hidden=w.hidden=='1',disabled=w.disabled=='1',
    stations=stations,up=cfg.up==true
   }
  end
 end)
 table.sort(rows,function(a,b)return a.ssid<b.ssid end)
 local uptime=tonumber(sys.exec('cat /proc/uptime'):match('^[%d.]+')) or os.time()
 return {ok=true,interfaces=rows,timestamp=uptime,interval=3}
end
return M
