local fs=require 'nixio.fs'
local json=require 'luci.jsonc'
local c=require('fastacl252_env').read(nil,false)
assert(c.dataplane=='tun','sing-box generator requires TUN dataplane')
local conf=require('fastacl252_singbox').compile(c)
local dir='/tmp/fastacl252'
fs.mkdir(dir)
fs.chmod(dir,'700')
local path=dir..'/singbox.next.json'
assert(fs.writefile(path,json.stringify(conf)),'Cannot write sing-box config')
fs.chmod(path,'600')
