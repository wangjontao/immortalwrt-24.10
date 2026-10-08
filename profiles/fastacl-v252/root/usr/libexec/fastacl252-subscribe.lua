local fs=require 'nixio.fs'
local sys=require 'luci.sys'
local json=require 'luci.jsonc'
local util=require 'luci.util'
local importer=require 'fastacl252_import'
local manager=require 'fastacl252_nodes'
local policy=require 'fastacl252'
local mode=arg[1] or 'due'
assert(mode=='due' or mode=='all' or policy.id(mode),'Invalid subscription request')
if not fs.mkdir('/tmp/fastacl252-subscribe.lock') then os.exit(0) end
fs.mkdir('/tmp/fastacl252')
local function update(s)
  local id=s['.name']; local url=s.url or ''
  assert(url:match('^https://') and #url<=4096 and not url:find('[%c"\\]'),'订阅必须为有效 HTTPS 地址')
  local f='/tmp/fastacl252/subscription-curl.conf'
  assert(fs.writefile(f,'url = "'..url..'"\nuser-agent = "mihomo"\ndoh-url = "https://dns.alidns.com/dns-query"\nresolve = "dns.alidns.com:443:223.5.5.5"\nconnect-timeout = 10\nmax-time = 45\nmax-filesize = 2097152\nlocation\nmax-redirs = 3\nfail\nproto = "=https"\nproto-redir = "=https"\n'))
  fs.chmod(f,384)
  local rc=sys.call('curl --silent --show-error --config '..util.shellquote(f)..' -o /tmp/fastacl252/subscription-body >/tmp/fastacl252/subscription-curl.log 2>&1')
  fs.remove(f); assert(rc==0,'订阅下载失败，旧节点已保留')
  local text=assert(fs.readfile('/tmp/fastacl252/subscription-body')); fs.remove('/tmp/fastacl252/subscription-body')
  local nodes=importer.subscription(text)
  assert(fs.mkdir('/tmp/fastacl252-edit.lock'),'设备配置正在保存，请稍后更新订阅')
  local u=require('uci').cursor(); local original=fs.readfile('/etc/config/fastacl252')
  local ok,err=pcall(function()
    local pending=u:changes('fastacl252'); assert(not pending or not next(pending),'配置存在未提交修改')
    assert(u:get('fastacl252',id)=='subscription' and u:get('fastacl252',id,'url')==url,'订阅已变更，请重新更新')
    manager.check(nodes); manager.replace(u,nodes,id); assert(u:commit('fastacl252'),'保存订阅节点失败'); fs.chmod('/etc/config/fastacl252',384)
  end)
  if not ok then u:revert('fastacl252'); if original then fs.writefile('/etc/config/fastacl252',original) end end
  fs.rmdir('/tmp/fastacl252-edit.lock'); assert(ok,err)
  if u:get('fastacl252','main','enabled')=='1' then sys.call('/usr/bin/fastacl252 apply >/tmp/fastacl252/subscribe-apply.log 2>&1') end
  return #nodes
end
local topok,toperr=pcall(function()
  local u=require('uci').cursor(); local subs={}
  u:foreach('fastacl252','subscription',function(s) subs[#subs+1]=s end)
  for _,s in ipairs(subs) do
    local id=s['.name']; assert(policy.id(id),'Invalid subscription ID')
    local last=json.parse(fs.readfile('/tmp/fastacl252/sub-'..id..'.json') or '') or {}
    local now=os.time(); local hours=tonumber(s.interval_hours or '24') or 24
    local delay=last.ok and math.max(1,math.min(168,hours))*3600 or 300
    local due=not last.attempt or now-last.attempt>=delay
    if mode==id or mode=='all' or (mode=='due' and s.enabled~='0' and due) then
      local ok,count=pcall(update,s)
      local result={ok=ok,attempt=now,count=ok and count or nil,error=not ok and tostring(count) or nil}
      fs.writefile('/tmp/fastacl252/sub-'..id..'.json',json.stringify(result))
    end
  end
end)
fs.remove('/tmp/fastacl252/subscription-curl.conf'); fs.remove('/tmp/fastacl252/subscription-body')
fs.rmdir('/tmp/fastacl252-subscribe.lock')
if not topok then io.stderr:write(tostring(toperr)..'\n'); os.exit(1) end
