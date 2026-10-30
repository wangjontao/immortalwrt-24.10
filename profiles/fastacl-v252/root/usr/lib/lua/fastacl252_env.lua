local M={}
local json=require 'luci.jsonc'
local sys=require 'luci.sys'
local util=require 'luci.util'
local policy=require 'fastacl252'

local function status_for(net,u)
  local st=json.parse(sys.exec('ubus call network.interface.'..net..' status 2>/dev/null')) or {}
  local addr=u:get('network',net,'ipaddr'); if type(addr)=='table' then addr=addr[1] end
  local mask=u:get('network',net,'netmask') or '255.255.255.0'
  return st.l3_device or u:get('network',net,'device'),addr,mask
end

function M.capacity(main,cpus,mem_kb,identity)
  main=main or {}
  cpus=tonumber(cpus) or 1
  mem_kb=tonumber(mem_kb) or 0
  identity=identity or ''
  local forced_high=identity:find('CLX S20L',1,true) or identity:find('CLX S20P',1,true) or
    identity:find('Xiaomi Redmi Router AX6000',1,true) or identity:find('JDCloud RE-CP-03',1,true) or
    identity:find('clx,s20l',1,true) or identity:find('clx,s20p',1,true) or
    identity:find('redmi-router-ax6000',1,true) or identity:find('jdcloud,re-cp-03',1,true)
  local profile=main.capacity_profile or 'auto'
  if profile=='auto' then
    if forced_high then profile='high'
    elseif cpus>=4 and mem_kb>=1800000 then profile='high'
    elseif cpus>=4 and mem_kb>=900000 then profile='quad'
    elseif cpus>=2 and mem_kb>=900000 then profile='balanced'
    else profile='compact' end
  end
  local defaults={high={16384,128},quad={12288,112},balanced={8192,96},compact={4096,64}}
  local selected=defaults[profile] or defaults.compact
  return profile,tonumber(main.data_max_connections) or selected[1],tonumber(main.data_max_connections_per_session) or selected[2]
end

function M.read(u,guards_only)
  u=u or require('uci').cursor()
  local main=u:get_all('fastacl252','main') or {}
  local net=main.network or 'lan'; assert(policy.id(net),'Invalid network')
  local iface,addr,mask=status_for(net,u)
  local cpus=tonumber(sys.exec("grep -c '^processor' /proc/cpuinfo 2>/dev/null")) or 1
  local mem_kb=tonumber(sys.exec("awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null")) or 0
  local identity=sys.exec("cat /tmp/sysinfo/model 2>/dev/null; tr '\\0' '\\n' < /proc/device-tree/compatible 2>/dev/null") or ''
  local wan_interface=sys.exec("ip -4 route show default 2>/dev/null | awk '$1 == \"default\" {print $5; exit}'") or ''
  wan_interface=wan_interface:gsub('%s+','')
  local capacity_profile,max_connections,max_connections_per_session=M.capacity(main,cpus,mem_kb,identity)
  local c={network=net,interface=iface,interfaces={},router_ip=addr,netmask=mask,port=tonumber(main.port or 12525),capacity_profile=capacity_profile,data_max_connections=max_connections,data_max_connections_per_session=max_connections_per_session,enabled=main.enabled=='1',dataplane=main.dataplane or 'singbox',tun_interface=main.tun_interface or 'fastacl-tun0',tun_address=main.tun_address or '172.19.0.1/30',tun_mtu=tonumber(main.tun_mtu or 9000),tun_stack=main.tun_stack or 'gvisor',default_mode=main.default_mode or 'direct',lan_default={mode=main.lan_mode or 'direct',node=main.lan_node or '',preproxy=main.lan_preproxy or '',split_mode=main.lan_split_mode or 'all',split_rules=main.lan_split_rules or '',platforms=main.lan_platforms or '',dns_split=main.lan_dns_split or '0',block_domains=main.lan_block_domains or '',dns=main.lan_dns or 'inherit',dns_type=main.lan_dns_type or '',dns_ip=main.lan_dns_ip or '',dns_name=main.lan_dns_name or ''},dns_policy=main.dns_policy or 'private',dns_server=main.dns_server or '223.5.5.5',dns_name=main.dns_name or 'dns.alidns.com',private_dns_server=main.private_dns_server or '1.1.1.1',private_dns_name=main.private_dns_name or 'cloudflare-dns.com',direct_dns=main.direct_dns or 'alidns',direct_dns_type=main.direct_dns_type or 'doh',direct_dns_ip=main.direct_dns_ip or '',direct_dns_name=main.direct_dns_name or '',proxy_dns=main.proxy_dns or 'cloudflare',proxy_dns_type=main.proxy_dns_type or 'doh',proxy_dns_ip=main.proxy_dns_ip or '',proxy_dns_name=main.proxy_dns_name or '',devices={},wifis={},nodes={}}
  if c.dataplane=='ebpf' then c.dataplane='singbox' end
  if policy.dev(wan_interface) then c.wan_interface=wan_interface end
  if iface and iface~='' then c.interfaces[#c.interfaces+1]=iface end
  u:foreach('fastacl252','node',function(n)
    n.outbound=json.parse(n.outbound or '')
    c.nodes[n['.name']]=n
  end)
  u:foreach('fastacl252','device',function(d)
    c.devices[#c.devices+1]={id=d['.name'],mac=policy.mac(d.mac),ip=d.ip,network=d.network or net,name=d.name or '',mode=d.mode or 'direct',node=d.node,preproxy=d.preproxy,platforms=d.platforms or '',dns_split=d.dns_split or '0',block_domains=d.block_domains or '',split_mode=d.split_mode or 'all',split_rules=d.split_rules or '',dns=d.dns or 'inherit',dns_type=d.dns_type,dns_ip=d.dns_ip,dns_name=d.dns_name}
  end)
  local function add_policy_network(w,kind)
    local wn=w.network or w['.name']; local wi,wip,wmask=status_for(wn,u)
    local subnet=w.subnet
    if not subnet and wip and policy.ipnum(wip) and policy.prefix(wmask) then subnet=policy.cidr(wip,wmask) end
    c.wifis[#c.wifis+1]={id=w['.name'],kind=kind,network=wn,interface=wi,router_ip=wip,netmask=wmask,subnet=subnet,ssid=w.ssid or '',band=w.band or '',mode=w.mode or 'direct',node=w.node,preproxy=w.preproxy,platforms=w.platforms or '',dns_split=w.dns_split or '0',block_domains=w.block_domains or '',split_mode=w.split_mode or 'all',split_rules=w.split_rules or '',dns=w.dns or 'inherit',dns_type=w.dns_type,dns_ip=w.dns_ip,dns_name=w.dns_name}
    if wi and wi~='' then c.interfaces[#c.interfaces+1]=wi end
  end
  u:foreach('fastacl252','wifi',function(w) add_policy_network(w,'wifi') end)
  u:foreach('fastacl252','vlan',function(w) add_policy_network(w,'vlan') end)
  table.sort(c.devices,function(a,b) return tostring(a.mac)<tostring(b.mac) end)
  table.sort(c.wifis,function(a,b) return a.id<b.id end)
  c.fixed_exit=main.fixed_exit=='1'
  if not guards_only then c.platform_secret=require('fastacl252_slots').key() end
  return policy.validate(c,guards_only)
end

function M.inventory(c,u)
  u=u or require('uci').cursor(); local rows={}; local function row(mac)
    mac=policy.mac(mac); if not mac then return nil end
    rows[mac]=rows[mac] or {mac=mac,name='',ip='',online=false,bound=false,mode='direct',dns='inherit'}; return rows[mac]
  end
  local networks={{network=c.network,router_ip=c.router_ip,netmask=c.netmask}}
  for _,w in ipairs(c.wifis or {}) do
    networks[#networks+1]={network=w.network,router_ip=w.router_ip,netmask=w.netmask}
  end
  local function managed_ip(ip)
    for _,network in ipairs(networks) do
      if network.router_ip and network.netmask and policy.in_lan(ip,network.router_ip,network.netmask) then return network.network end
    end
    return nil
  end
  local f=io.open('/tmp/dhcp.leases'); if f then
    for l in f:lines() do local exp,mac,ip,name=l:match('^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)')
      local network=exp and managed_ip(ip)
      if network and (tonumber(exp)==0 or tonumber(exp)>os.time()) then local r=row(mac); if r then r.ip=ip; r.network=network; r.name=name~='*' and name or ''; r.hostname=r.name; r.source='lease' end end
    end; f:close()
  end
  local seen_ifaces={}
  for _,iface in ipairs(c.interfaces or {c.interface}) do
    if iface and iface~='' and not seen_ifaces[iface] then
      seen_ifaces[iface]=true
      for l in sys.exec('ip -4 neigh show dev '..util.shellquote(iface)..' 2>/dev/null'):gmatch('[^\n]+') do
        local ip,mac=l:match('^(%S+).-lladdr%s+(%S+)')
        local network=ip and managed_ip(ip)
        if network then local r=row(mac); if r then r.ip=ip; r.network=network; r.online=l:find('REACHABLE',1,true)~=nil or l:find('DELAY',1,true)~=nil or l:find('PROBE',1,true)~=nil; r.neighbor_state=l:match('(%u+)%s*$') end end
      end
    end
  end
  for _,d in ipairs(c.devices) do local r=row(d.mac); if r then r.platforms=d.platforms or '';r.dns_split=d.dns_split or '0'; r.block_domains=d.block_domains or ''; r.split_mode=d.split_mode or 'all'; r.split_rules=d.split_rules or ''; r.bound=true; r.network=d.network or c.network; r.fixed_ip=d.ip; r.ip=r.ip~='' and r.ip or d.ip; r.name=d.name~='' and d.name or r.name; r.mode=d.mode; r.node=d.node or ''; r.preproxy=d.preproxy or ''; r.dns=d.dns or 'inherit'; r.dns_type=d.dns_type or ''; r.dns_ip=d.dns_ip or ''; r.dns_name=d.dns_name or ''; r.renew_required=r.ip~=d.ip end end
  u:foreach('fastacl252','device_alias',function(a)
    local mac=policy.mac(a.mac);local r=mac and rows[mac]
    if r and type(a.name)=='string' and a.name~='' then r.name=a.name;r.custom_name=a.name end
  end)
  local out={}; for _,r in pairs(rows) do out[#out+1]=r end
  table.sort(out,function(a,b) if a.bound~=b.bound then return a.bound end; return a.mac<b.mac end)
  return out
end
return M
