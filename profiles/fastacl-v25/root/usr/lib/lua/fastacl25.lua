-- Device-only policy compiler. No wireless/AP sections or subnet assignments.
local M = {}
function M.ipnum(s)
  local a,b,c,d=tostring(s or ''):match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
  a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if not a or a>255 or b>255 or c>255 or d>255 then return nil end
  return ((a*256+b)*256+c)*256+d
end
function M.mac(s)
  s=tostring(s or ''):upper()
  if not s:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$') then return nil end
  if tonumber(s:sub(1,2),16)%2~=0 or s=='00:00:00:00:00:00' then return nil end
  return s
end
function M.id(s) return type(s)=='string' and s:match('^[%w_]+$') and #s<=64 end
function M.dev(s) return type(s)=='string' and s:match('^[%w_.:-]+$') and #s<=32 end
function M.prefix(mask)
  local p=tonumber(mask); if p and p>=1 and p<=30 and p%1==0 then return p end
  local n=M.ipnum(mask); if not n then return nil end
  local p=0; local zero=false
  for i=31,0,-1 do local b=math.floor(n/2^i)%2
    if b==0 then zero=true elseif zero then return nil else p=p+1 end
  end
  return p>=1 and p<=30 and p or nil
end
function M.in_lan(ip,router,mask)
  local n,r,p=M.ipnum(ip),M.ipnum(router),M.prefix(mask)
  if not n or not r or not p then return false end
  local size=2^(32-p); local base=math.floor(r/size)*size
  return n>base and n<base+size-1 and n~=r
end
function M.cidr(ip,mask)
  local p=assert(M.prefix(mask)); local n=assert(M.ipnum(ip)); n=math.floor(n/2^(32-p))*2^(32-p)
  return string.format('%d.%d.%d.%d/%d',math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256,p)
end
function M.validate(c,guards_only)
  assert(M.id(c.network),'Invalid LAN network')
  assert(M.dev(c.interface),'LAN interface unavailable')
  assert(M.ipnum(c.router_ip) and M.prefix(c.netmask),'Static IPv4 LAN required')
  assert(tonumber(c.port) and c.port>=1024 and c.port<=65535 and c.port%1==0,'Invalid port')
  assert(c.default_mode=='direct','Default mode must be direct')
  assert(c.dns_policy=='direct' or c.dns_policy=='private','Invalid DNS policy')
  for _,key in ipairs({'dns_server','private_dns_server'}) do assert(M.ipnum(c[key]),'DNS endpoint must be IPv4: '..key) end
  for _,key in ipairs({'dns_name','private_dns_name'}) do assert(type(c[key])=='string' and c[key]:match('^[%w.-]+$'),'Invalid TLS name') end
  local seenip,seenmac={},{}
  for _,d in ipairs(c.devices) do
    assert(M.mac(d.mac)==d.mac,'Invalid MAC')
    assert(M.in_lan(d.ip,c.router_ip,c.netmask),'Device IP outside LAN / router / network / broadcast')
    assert(not seenip[d.ip] and not seenmac[d.mac],'Duplicate device IP or MAC')
    seenip[d.ip],seenmac[d.mac]=true,true
    assert(d.mode=='direct' or d.mode=='proxy','Invalid device mode')
    if d.mode=='proxy' and not guards_only then
      assert(M.id(d.node) and c.nodes[d.node],'Missing proxy node')
      if d.preproxy and d.preproxy~='' then
        assert(M.id(d.preproxy) and c.nodes[d.preproxy] and d.preproxy~=d.node,'Invalid preproxy')
        local p=c.nodes[d.node].protocol
        assert(p=='socks' or p=='http','Preproxy supported for SOCKS5/HTTP landing nodes')
      end
    end
  end
  return c
end
local function https(tag,ip,name,detour)
  return {type='https',tag=tag,server=ip,server_port=443,path='/dns-query',tls={enabled=true,server_name=name},detour=detour}
end
function M.compile(c)
  M.validate(c)
  local conf={log={level='warn',timestamp=true},inbounds={{type='tproxy',tag='devices',listen='0.0.0.0',listen_port=c.port}},outbounds={{type='direct',tag='direct'}},dns={servers={https('dns-direct',c.dns_server,c.dns_name,'direct')},rules={},final='dns-direct',strategy='ipv4_only'},route={rules={{port={53},action='hijack-dns'}},final='direct',default_domain_resolver='dns-direct'}}
  local cached,bridges={},{}
  local function copy(v)
    if type(v)~='table' then return v end
    local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t
  end
  local function outbound(id)
    local tag='node-'..id
    if cached[tag] then return tag end
    local n=assert(c.nodes[id]); local o=copy(n.outbound)
    if not o then
      o={type=n.protocol,server=n.address,server_port=tonumber(n.port),username=n.username,password=n.password}
      if o.type=='socks' then o.version='5' end
    end
    assert(o.type and o.server and tonumber(o.server_port),'Invalid native outbound')
    assert(o.type=='socks' or o.type=='http' or o.type=='vless' or o.type=='vmess' or o.type=='trojan' or o.type=='shadowsocks' or o.type=='hysteria2' or o.type=='tuic','Unsupported native protocol')
    o.tag=tag; o.domain_resolver='dns-direct'
    conf.outbounds[#conf.outbounds+1]=o; cached[tag]=o
    return tag
  end
  for _,d in ipairs(c.devices) do if d.mode=='proxy' then
    local tag
    if d.preproxy and d.preproxy~='' then
      local pre=outbound(d.preproxy)
      tag='chain-'..d.node..'-'..d.preproxy
      if not cached[tag] then
        local n=c.nodes[d.node]
        local o=copy(n.outbound or {type=n.protocol,server=n.address,server_port=tonumber(n.port),username=n.username,password=n.password})
        o.tag=tag; o.detour=pre; o.domain_resolver='dns-direct'
        if o.type=='socks' then o.version='5' end
        conf.outbounds[#conf.outbounds+1]=o; cached[tag]=o
      end
    else tag=outbound(d.node) end
    conf.route.rules[#conf.route.rules+1]={source_ip_cidr={d.ip..'/32'},action='route',outbound=tag}
    if c.dns_policy=='private' then
      local dns='dns-'..tag
      if not cached[dns] then conf.dns.servers[#conf.dns.servers+1]=https(dns,c.private_dns_server,c.private_dns_name,tag); cached[dns]=true end
      conf.dns.rules[#conf.dns.rules+1]={source_ip_cidr={d.ip..'/32'},action='route',server=dns}
    end
  end end
  return conf,bridges
end
local bypass={'0.0.0.0/8','127.0.0.0/8','169.254.0.0/16','224.0.0.0/4','240.0.0.0/4'}
function M.firewall(c,backend)
  M.validate(c,true)
  local ip,iface,port=c.router_ip,c.interface,c.port
  local cidr=M.cidr(ip,c.netmask)
  local proxy={}; for _,d in ipairs(c.devices) do if d.mode=='proxy' then proxy[#proxy+1]=d end end
  assert(backend=='nft','Invalid firewall backend')
  local q='"'..iface..'"'
  local guard,pre,identity={},{},{}
  for _,d in ipairs(proxy) do
    guard[#guard+1]='iifname '..q..' ether saddr '..d.mac..' drop'
    guard[#guard+1]='iifname '..q..' ip saddr '..d.ip..' drop'
    identity[#identity+1]='iifname '..q..' ether saddr '..d.mac..' ip saddr != '..d.ip..' udp sport 68 udp dport 67 return'
    identity[#identity+1]='iifname '..q..' ether saddr '..d.mac..' ip saddr != '..d.ip..' drop'
    identity[#identity+1]='iifname '..q..' ip saddr '..d.ip..' ether saddr != '..d.mac..' drop'
    pre[#pre+1]='iifname '..q..' ether saddr '..d.mac..' ip daddr '..cidr..' return'
    for _,dst in ipairs(bypass) do pre[#pre+1]='iifname '..q..' ether saddr '..d.mac..' ip daddr '..dst..' return' end
    pre[#pre+1]='iifname '..q..' ether saddr '..d.mac..' ip saddr '..d.ip..' meta l4proto { tcp, udp } meta mark set 0x65 tproxy ip to :'..port..' accept'
  end
  identity[#identity+1]='iifname '..q..' meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 meta mark set 0x65 tproxy ip to :'..port..' accept'
  for _,line in ipairs(pre) do identity[#identity+1]=line end
  pre=identity
  local dns6='iifname '..q..' meta nfproto ipv6 meta l4proto { tcp, udp } th dport 53 drop'
  return {nft='table inet fastacl25 {\nchain prerouting { type filter hook prerouting priority -151; policy accept;\n'..table.concat(pre,'\n')..'\n}\nchain forward { type filter hook forward priority -10; policy accept;\n'..dns6..'\n'..table.concat(guard,'\n')..'\n}\nchain input { type filter hook input priority -10; policy accept;\n'..dns6..'\n}\n}\n'}
end
return M
