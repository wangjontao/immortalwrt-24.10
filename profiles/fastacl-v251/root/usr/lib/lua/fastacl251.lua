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
function M.compile(c)
  M.validate(c)
  return require('fastacl251_mihomo').compile(c)
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
  identity[#identity+1]='iifname '..q..' meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 return'
  for _,line in ipairs(pre) do identity[#identity+1]=line end
  pre=identity
  local dns6='iifname '..q..' meta nfproto ipv6 meta l4proto { tcp, udp } th dport 53 drop'
  return {nft='table inet fastacl251 {\nchain prerouting { type filter hook prerouting priority -151; policy accept;\n'..table.concat(pre,'\n')..'\n}\nchain forward { type filter hook forward priority -10; policy accept;\n'..dns6..'\n'..table.concat(guard,'\n')..'\n}\nchain dns_redirect { type nat hook prerouting priority -100; policy accept;\n'..'iifname '..q..' meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 redirect to :12553\n'..'}\nchain input { type filter hook input priority -10; policy accept;\n'..dns6..'\n}\n}\n'}
end
return M
