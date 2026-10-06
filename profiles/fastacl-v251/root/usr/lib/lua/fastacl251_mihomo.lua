local M={}
local function copy(v)
  if type(v)~='table' then return v end
  local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t
end
function M.node(n,name)
  local o=n.outbound or {type=n.protocol,server=n.address,server_port=tonumber(n.port),username=n.username,password=n.password}
  local supported={socks='socks5',http='http',vless='vless',vmess='vmess',trojan='trojan',shadowsocks='ss',hysteria2='hysteria2',tuic='tuic'}
  local p={name=name,type=assert(supported[o.type],'Unsupported Mihomo protocol'),server=o.server,port=tonumber(o.server_port),udp=o.type~='http'}
  local allowed={type=true,server=true,server_port=true,username=true,password=true,uuid=true,security=true,alter_id=true,flow=true,method=true,version=true,tls=true,transport=true,obfs=true,congestion_control=true,tag=true,domain_resolver=true,detour=true}
  for k in pairs(o) do assert(allowed[k],'Unsupported Mihomo field: '..k) end
  for _,k in ipairs({'username','password','uuid','flow'}) do p[k]=o[k] end
  if o.type=='vmess' then p.cipher=o.security or 'auto'; p.alterId=o.alter_id or 0 end
  if o.type=='shadowsocks' then p.cipher=o.method end
  if o.type=='tuic' then p['congestion-controller']=o.congestion_control or 'cubic' end
  if o.obfs then assert(o.type=='hysteria2' and o.obfs.type=='salamander','Unsupported obfs'); p.obfs=o.obfs.type; p['obfs-password']=o.obfs.password end
  if o.tls and o.tls.enabled then
    local t=o.tls
    for k in pairs(t) do assert(k=='enabled' or k=='server_name' or k=='insecure' or k=='alpn' or k=='utls' or k=='reality','Unsupported TLS field: '..k) end
    p.tls=true; p['skip-cert-verify']=t.insecure==true; p.sni=t.server_name; p.servername=t.server_name; p.alpn=copy(t.alpn)
    if t.utls and t.utls.enabled then p['client-fingerprint']=t.utls.fingerprint end
    if t.reality and t.reality.enabled then p['reality-opts']={['public-key']=t.reality.public_key,['short-id']=t.reality.short_id} end
  end
  if o.transport then
    local t=o.transport
    if t.type=='ws' then p.network='ws'; p['ws-opts']={path=t.path or '/',headers=copy(t.headers)}
    elseif t.type=='grpc' then p.network='grpc'; p['grpc-opts']={['grpc-service-name']=t.service_name or ''}
    else error('Unsupported Mihomo transport') end
    for k in pairs(t) do assert(k=='type' or k=='path' or k=='headers' or k=='service_name','Unsupported transport field: '..k) end
  end
  return p
end
function M.compile(c)
  local conf={['tproxy-port']=c.port,['allow-lan']=true,['bind-address']='*',mode='rule',ipv6=false,['log-level']='warning',proxies={},rules={},listeners={},dns={enable=true,ipv6=false,['enhanced-mode']='redir-host',['default-nameserver']={'https://'..c.dns_server..'/dns-query'},nameserver={'https://'..c.dns_server..'/dns-query'},['proxy-server-nameserver']={'https://'..c.dns_server..'/dns-query'}},hosts={[c.dns_name]=c.dns_server}}
  local relay={listen='0.0.0.0:12553',direct_ip=c.dns_server,direct_name=c.dns_name,private_ip=c.private_dns_server,private_name=c.private_dns_name,devices={}}
  local cached,ports={},{}; local nextport=12600
  local function node(id)
    local name='node-'..id
    if not cached[name] then local p=M.node(assert(c.nodes[id]),name); conf.proxies[#conf.proxies+1]=p; cached[name]=p end
    return name
  end
  for _,d in ipairs(c.devices) do if d.mode=='proxy' then
    local name
    if d.preproxy and d.preproxy~='' then
      local pre=node(d.preproxy); name='chain-'..d.node..'-'..d.preproxy
      if not cached[name] then local p=M.node(assert(c.nodes[d.node]),name); p['dialer-proxy']=pre; cached[name]=p; conf.proxies[#conf.proxies+1]=p end
    else name=node(d.node) end
    conf.rules[#conf.rules+1]='SRC-IP-CIDR,'..d.ip..'/32,'..name
    if c.dns_policy=='private' then
      if not ports[name] then ports[name]=nextport; nextport=nextport+1; assert(nextport<14000,'Too many DNS exits'); conf.listeners[#conf.listeners+1]={name='dns-'..name,type='socks',listen='127.0.0.1',port=ports[name],udp=false,proxy=name} end
      relay.devices[d.ip]=ports[name]
    end
  end end
  conf.rules[#conf.rules+1]='MATCH,DIRECT'
  -- Bootstrap queries use pinned IP HTTPS, never UDP system DNS.
  conf.dns['default-nameserver']={'127.0.0.1:12553'}
  conf.dns.nameserver=copy(conf.dns['default-nameserver']); conf.dns['proxy-server-nameserver']=copy(conf.dns['default-nameserver'])
  return conf,relay
end
return M
