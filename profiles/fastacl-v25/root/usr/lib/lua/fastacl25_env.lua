local M={}
local json=require 'luci.jsonc'
local sys=require 'luci.sys'
local util=require 'luci.util'
local policy=require 'fastacl25'
function M.read(u,guards_only)
  u=u or require('luci.model.uci').cursor()
  local main=u:get_all('fastacl25','main') or {}
  local net=main.network or 'lan'; assert(policy.id(net),'Invalid network')
  local st=json.parse(sys.exec('ubus call network.interface.'..net..' status 2>/dev/null')) or {}
  local addr=u:get('network',net,'ipaddr'); if type(addr)=='table' then addr=addr[1] end
  local c={network=net,interface=st.l3_device or u:get('network',net,'device'),router_ip=addr,netmask=u:get('network',net,'netmask') or '255.255.255.0',port=tonumber(main.port or 12525),enabled=main.enabled=='1',default_mode=main.default_mode or 'direct',dns_policy=main.dns_policy or 'direct',dns_server=main.dns_server or '223.5.5.5',dns_name=main.dns_name or 'dns.alidns.com',private_dns_server=main.private_dns_server or '9.9.9.9',private_dns_name=main.private_dns_name or 'dns.quad9.net',dns_path=main.dns_path or '/dns-query',dns_port=tonumber(main.dns_port or 443),private_dns_path=main.private_dns_path or '/dns-query',private_dns_port=tonumber(main.private_dns_port or 443),devices={},nodes={}}
  u:foreach('fastacl25','node',function(n)
    n.outbound=json.parse(n.outbound or '')
    c.nodes[n['.name']]=n
  end)
  u:foreach('fastacl25','device',function(d) c.devices[#c.devices+1]={id=d['.name'],mac=policy.mac(d.mac),ip=d.ip,name=d.name or '',mode=d.mode or 'direct',node=d.node,preproxy=d.preproxy} end)
  table.sort(c.devices,function(a,b) return a.mac<b.mac end)
  return policy.validate(c,guards_only)
end
function M.inventory(c,u)
  u=u or require('luci.model.uci').cursor(); local rows={}; local function row(mac)
    mac=policy.mac(mac); if not mac then return nil end
    rows[mac]=rows[mac] or {mac=mac,name='',ip='',online=false,bound=false,mode='direct'}; return rows[mac]
  end
  local f=io.open('/tmp/dhcp.leases'); if f then
    for l in f:lines() do local exp,mac,ip,name=l:match('^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)')
      if exp and (tonumber(exp)==0 or tonumber(exp)>os.time()) and policy.in_lan(ip,c.router_ip,c.netmask) then local r=row(mac); if r then r.ip=ip; r.name=name~='*' and name or ''; r.source='lease' end end
    end; f:close()
  end
  for l in sys.exec('ip -4 neigh show dev '..util.shellquote(c.interface)..' 2>/dev/null'):gmatch('[^\n]+') do
    local ip,mac=l:match('^(%S+).-lladdr%s+(%S+)')
    if ip and policy.in_lan(ip,c.router_ip,c.netmask) then local r=row(mac); if r then r.ip=ip; r.online=l:find('REACHABLE',1,true)~=nil or l:find('DELAY',1,true)~=nil or l:find('PROBE',1,true)~=nil; r.neighbor_state=l:match('(%u+)%s*$') end end
  end
  for _,d in ipairs(c.devices) do local r=row(d.mac); r.bound=true; r.fixed_ip=d.ip; r.ip=r.ip~='' and r.ip or d.ip; r.name=d.name~='' and d.name or r.name; r.mode=d.mode; r.node=d.node or ''; r.preproxy=d.preproxy or ''; r.renew_required=r.ip~=d.ip end
  local out={}; for _,r in pairs(rows) do out[#out+1]=r end
  table.sort(out,function(a,b) if a.bound~=b.bound then return a.bound end; return a.mac<b.mac end)
  return out
end
return M
