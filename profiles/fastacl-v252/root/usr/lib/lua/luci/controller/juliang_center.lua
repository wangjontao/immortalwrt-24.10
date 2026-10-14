module('luci.controller.juliang_center',package.seeall)
function index()
  local p=entry({'admin','juliang'},firstchild(),_('JuLiang 控制中心'),1); p.dependent=false; p.acl_depends={'juliang-center'}
  local h=entry({'admin','juliang','home'},template('juliang_center/home'),_('控制中心'),1); h.leaf=true; h.acl_depends={'juliang-center'}
  local a=entry({'admin','juliang','status'},call('status'),nil); a.leaf=true; a.acl_depends={'juliang-center'}
end
local function reply(t)
  local h=require 'luci.http'; h.prepare_content('application/json'); h.write(require('luci.jsonc').stringify(t))
end
function status()
  local json=require 'luci.jsonc'; local sys=require 'luci.sys'; local u=require('uci').cursor()
  local wan=json.parse(sys.exec('ubus call network.interface.wan status 2>/dev/null')) or {}
  local ip=''; for _,a in ipairs(wan['ipv4-address'] or {}) do if a.address then ip=a.address break end end
  local wifi=0; u:foreach('wireless','wifi-iface',function(s) if s.disabled~='1' then wifi=wifi+1 end end)
  local managed=0; u:foreach('fastacl252','wifi',function() managed=managed+1 end)
  local fast=json.parse(sys.exec('/usr/bin/fastacl252 status 2>/dev/null')) or {}
  local up=tonumber(sys.exec("cut -d. -f1 /proc/uptime 2>/dev/null") or '0') or 0
  reply({ok=true,hostname=sys.hostname() or 'JuLiangTK-S20L',uptime=up,wan_up=wan.up==true,wan_ip=ip,wan_device=wan.l3_device or wan.device or '',wifi_count=wifi,managed_wifi=managed,fastacl=fast,version='FastACL 2.5.2-dev.2 dae/eBPF'})
end
