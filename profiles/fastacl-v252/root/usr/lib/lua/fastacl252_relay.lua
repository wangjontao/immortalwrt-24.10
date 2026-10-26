-- DNS helper policy mapping for the native sing-box dataplane.
local M={}

local function id(s)
  assert(type(s)=='string' and #s<=64 and s:match('^[%w_]+$'),'Invalid node ID')
  return s
end

function M.link(n)
  local uri=require('fastacl252_uri').node(n)
  local scheme=uri:match('^([%w]+)://')
  local supported={socks=true,socks5=true,http=true,https=true,ss=true,vmess=true,vless=true,trojan=true,tuic=true,hysteria2=true,hy2=true,anytls=true}
  assert(supported[scheme],'Unsupported proxy URI scheme')
  assert(not uri:find(' -> ',1,true),'Nested chain in imported node')
  assert(type(uri)=='string' and #uri>0 and #uri<=8192,'Invalid proxy URI')
  assert(not uri:find('[%z\1-\31\127]'),'Control character in proxy URI')
  return uri
end

function M.compile(c)
  local data_max_connections=tonumber(c.data_max_connections) or 8192
  local data_max_connections_per_session=tonumber(c.data_max_connections_per_session) or 96
  assert(data_max_connections>=1 and data_max_connections<=16384,'Invalid global connection cap')
  assert(data_max_connections_per_session>=1 and data_max_connections_per_session<=512,'Invalid per-session connection cap')
  local dns=require 'fastacl252_dns'
  local split=require 'fastacl252_split'
  local resolvers={}
  local relay={
    data_max_connections=data_max_connections,
    data_max_connections_per_session=data_max_connections_per_session,
    domestic_domains_file='/usr/share/fastacl252/cn-domains.txt',
    listen='0.0.0.0:12553',
    direct_ip=c.dns_server,
    direct_name=c.dns_name,
    private_ip=c.private_dns_server,
    private_name=c.private_dns_name,
    devices={},
    exits={},
    resolvers=resolvers,
    device_policies={},
    network_policies={},
    data_slots={},
  }
  if c.platform_secret then
    assert(type(c.platform_secret)=='string' and #c.platform_secret>=32 and #c.platform_secret<=128,'Invalid platform listener secret')
    relay.data_listen='127.0.0.1:15443'
    relay.data_secret=c.platform_secret
  end
  relay.platform_rules_file='/usr/share/fastacl252/platform-rules.json'
  relay.platform_state_file='/tmp/fastacl252/platform-map.json'

  local routes={}
  local nextid=12600
  local function ensure_exit(x)
    local name='exit_'..id(x.node)
    local uri=M.link(assert(c.nodes[x.node],'Missing exit node'))
    if x.preproxy and x.preproxy~='' then
      assert(x.preproxy~=x.node,'Self-referencing chain')
      local exit=c.nodes[x.node]
      assert(exit.protocol=='socks' or exit.protocol=='http','Chain requires SOCKS/HTTP landing')
      uri=uri..' -> '..M.link(assert(c.nodes[x.preproxy],'Missing front node'))
      name=name..'_via_'..id(x.preproxy)
    end
    if not routes[name] then
      routes[name]=nextid
      relay.exits[tostring(nextid)]=uri
      nextid=nextid+1
    end
    return name,routes[name]
  end
  local function platform_target(x,port)
    local selected=split.platforms(x)
    if #selected==0 then return end
    assert(relay.data_listen,'Platform proxy listener is not configured')
    relay.data_slots['platform_'..x.platform_scope]=port
  end
  local function fixed_target(key,port)
    assert(relay.data_listen and c.platform_secret,'Fixed entry listener is not configured')
    relay.data_slots[key]=port
  end

  local default_resolver=dns.resolve({},'direct',c,resolvers,'default')
  relay.default_policy={resolver=default_resolver,exit=0}

  for _,d in ipairs(c.devices or {}) do
    d.platform_scope='device_'..d.mac:gsub(':','')
    local port=0
    if d.mode=='proxy' then
      local _,route=ensure_exit(d)
      port=route
      if c.fixed_exit then fixed_target('device_'..d.mac:gsub(':',''),port) end
      platform_target(d,port)
      if c.dns_policy=='private' then relay.devices[d.ip]=port end
    end
    local did=tostring(d.id or d.mac or d.ip or 'device'):gsub('[^%w_]','_')
    local resolver=dns.resolve(d,d.mode,c,resolvers,'device_'..did)
    relay.device_policies[d.ip]=split.dns(d,{resolver=resolver,exit=port},c,resolvers)
  end

  for _,w in ipairs(c.wifis or {}) do
    w.platform_scope='wifi_'..id(w.id)
    local port=0
    if w.mode=='proxy' then
      local _,route=ensure_exit(w)
      port=route
      if c.fixed_exit then fixed_target('wifi_'..id(w.id),port) end
      platform_target(w,port)
    end
    local resolver=dns.resolve(w,w.mode,c,resolvers,'wifi_'..w.id)
    relay.network_policies[w.subnet]=split.dns(w,{resolver=resolver,exit=port},c,resolvers)
  end
  return relay
end

function M.encode(relay)
  local json=require 'luci.jsonc'
  local maps={
    devices=true,
    exits=true,
    resolvers=true,
    device_policies=true,
    network_policies=true,
    data_slots=true,
  }
  local function object(t)
    local keys,fields={},{}
    for k in pairs(t or {}) do keys[#keys+1]=k end
    table.sort(keys)
    for _,k in ipairs(keys) do
      fields[#fields+1]=json.stringify(k)..':'..json.stringify(t[k])
    end
    return '{'..table.concat(fields,',')..'}'
  end
  local keys,fields={},{}
  for k in pairs(relay) do keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do
    fields[#fields+1]=json.stringify(k)..':'..(maps[k] and object(relay[k]) or json.stringify(relay[k]))
  end
  return '{'..table.concat(fields,',')..'}'
end

return M
