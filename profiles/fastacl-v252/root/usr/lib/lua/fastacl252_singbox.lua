-- FastACL 2.8.2 native sing-box dataplane compiler. FastACL still owns DNS,
-- identity guards and per-device/per-WiFi policy selection.
local M={}
local split=require 'fastacl252_split'

local SUPPORTED={socks=true,http=true,vless=true,vmess=true,trojan=true,shadowsocks=true,hysteria2=true,tuic=true,anytls=true}
local PRIVATE={'0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16','172.16.0.0/12','192.168.0.0/16','224.0.0.0/4','240.0.0.0/4'}

local function copy(v)
  if type(v)~='table' then return v end
  local out={}
  for k,x in pairs(v) do out[k]=copy(x) end
  return out
end

local function node_outbound(c,id,tag)
  local n=assert(c.nodes[id],'Missing proxy node')
  local out=copy(n.outbound)
  if not out then
    out={type=n.protocol,server=n.address,server_port=tonumber(n.port),username=n.username,password=n.password}
  end
  out.type=out.type or n.protocol
  out.server_port=tonumber(out.server_port)
  assert(SUPPORTED[out.type],'Unsupported sing-box protocol: '..tostring(out.type))
  assert(type(out.server)=='string' and out.server~='' and out.server_port,'Invalid sing-box outbound')
  if out.type=='socks' then out.version='5' end
  out.tag=tag
  out.domain_resolver='fastacl-dns'
  if c.wan_interface then out.bind_interface=c.wan_interface end
  return out
end

local function add_route(route,scope,outbound)
  local rule={source_ip_cidr={scope},action='route',outbound=outbound}
  route[#route+1]=rule
  return rule
end

function M.compile(c)
  assert(c.dataplane=='singbox' or c.dataplane=='tun','sing-box compiler requires dataplane=singbox or tun')
  local route_rules={}
  local direct={type='direct',tag='direct',domain_resolver='fastacl-dns'}
  if c.wan_interface then direct.bind_interface=c.wan_interface end
  local outbounds={direct}
  local by_tag={}
  local function cn_networks()
    if type(c.cn_ipv4)=='table' and #c.cn_ipv4>0 then return c.cn_ipv4 end
    return split.networks()
  end
  local function add_outbound(out)
    if not by_tag[out.tag] then by_tag[out.tag]=true;outbounds[#outbounds+1]=out end
    return out.tag
  end
  local function node(id)
    return add_outbound(node_outbound(c,id,'node-'..id))
  end
  local function proxy_target(x)
    local tag=node(x.node)
    if x.preproxy and x.preproxy~='' then
      local pre=node(x.preproxy)
      tag='chain-'..x.node..'-'..x.preproxy
      local out=node_outbound(c,x.node,tag)
      out.detour=pre
      add_outbound(out)
    end
    return tag
  end
  local function platform_target(x,scope)
    local selected=split.platforms(x)
    if #selected==0 then return end
    local key='platform_'..x.platform_scope
    local tag='platform-'..x.platform_scope
    add_outbound({type='socks',version='5',tag=tag,server='127.0.0.1',server_port=15443,username=key,password=c.platform_secret,domain_resolver='fastacl-dns'})
    route_rules[#route_rules+1]={source_ip_cidr={scope},ip_cidr={'198.19.0.0/16'},action='route',outbound=tag}
  end
  local function add_scope_rules(x,scope)
    if x.mode~='proxy' then return end
    platform_target(x,scope)
    local outbound=proxy_target(x)
    local mode,custom=split.parse(x)
    for _,r in ipairs(custom) do
      local rule={source_ip_cidr={scope},ip_cidr={r.cidr}}
      if r.action=='block' then
        rule.action='reject'
      else
        rule.action='route';rule.outbound=r.action=='proxy' and outbound or 'direct'
      end
      route_rules[#route_rules+1]=rule
    end
    if mode=='smart' then
      local nets=cn_networks()
      for start=1,#nets,400 do
        local chunk={}
        for index=start,math.min(start+399,#nets) do chunk[#chunk+1]=nets[index] end
        route_rules[#route_rules+1]={source_ip_cidr={scope},ip_cidr=chunk,action='route',outbound='direct'}
      end
    end
    add_route(route_rules,scope,outbound)
  end

  local main_lan_proxy=c.lan_default and c.lan_default.mode=='proxy'
  for _,d in ipairs(c.devices or {}) do
    d.platform_scope='device_'..d.mac:gsub(':','')
    add_scope_rules(d,d.ip..'/32')
    if main_lan_proxy and d.mode~='proxy' then
      route_rules[#route_rules+1]={source_ip_cidr={d.ip..'/32'},action='route',outbound='direct'}
    end
  end
  for _,w in ipairs(c.wifis or {}) do
    w.platform_scope='wifi_'..w.id
    add_scope_rules(w,w.subnet)
  end
  if main_lan_proxy then
    c.lan_default.platform_scope='main_lan'
    add_scope_rules(c.lan_default,require('fastacl252').cidr(c.router_ip,c.netmask))
  end

  local excluded={}
  local seen={}
  local function exclude(v)
    if v and v~='' and not seen[v] then seen[v]=true;excluded[#excluded+1]=v end
  end
  if c.router_ip then exclude(require('fastacl252').cidr(c.router_ip,c.netmask)) end
  for _,w in ipairs(c.wifis or {}) do exclude(w.subnet) end
  for _,v in ipairs(PRIVATE) do exclude(v) end

  local inbounds
  if c.dataplane=='tun' then
    inbounds={{
      type='tun',
      tag='tun-in',
      interface_name=c.tun_interface,
      address={c.tun_address},
      mtu=c.tun_mtu,
      auto_route=false,
      strict_route=false,
      stack=c.tun_stack,
      endpoint_independent_nat=true,
      route_exclude_address=excluded
    }}
  else
    inbounds={
      {type='tproxy',tag='tproxy-tcp-in',listen='0.0.0.0',listen_port=c.port,network='tcp'},
      {type='tproxy',tag='tproxy-udp-in',listen='0.0.0.0',listen_port=c.port,network='udp',udp_timeout='5m'}
    }
  end
  local conf={
    log={level='warn',timestamp=true},
    dns={
      servers={{type='udp',tag='fastacl-dns',server='127.0.0.1',server_port=12553}},
      final='fastacl-dns',
      strategy='ipv4_only'
    },
    inbounds=inbounds,
    outbounds=outbounds,
    route={
      rules=route_rules,
      final='direct',
      auto_detect_interface=false,
      default_domain_resolver='fastacl-dns'
    }
  }
  return conf
end

return M
