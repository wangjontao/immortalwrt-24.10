local json=require 'luci.jsonc'
local policy=require 'fastacl251'
local c=require('fastacl251_env').read(nil,arg[2]=='guard')
local backend=arg[1]; assert(backend=='nft')
local rules=policy.firewall(c,backend)
local dir='/tmp/fastacl251'
local function save(name,data) local f=assert(io.open(dir..'/'..name,'w')); f:write(data); f:close() end
for k,v in pairs(rules) do save(k..'.next.rules',v) end
if arg[2]=='guard' then return end
local conf,relay=policy.compile(c)
save('router.next.json',json.stringify(conf,true))
save('dns.next.json',json.stringify(relay,true))
