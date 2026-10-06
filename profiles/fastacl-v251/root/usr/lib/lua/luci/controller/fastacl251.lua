module('luci.controller.fastacl251',package.seeall)
function index()
  if not nixio.fs.access('/etc/config/fastacl251') then return end
  local p=entry({'admin','services','fastacl251'},template('fastacl251/console'),_('FastACL 2.5.1 Mihomo 控制台'),27); p.dependent=false
  local s=entry({'admin','services','fastacl251_status'},call('status'),nil); s.leaf=true
  local a=entry({'admin','services','fastacl251_save'},post('save'),nil); a.leaf=true
  local i=entry({'admin','services','fastacl251_import'},post('import_nodes'),nil); i.leaf=true
  local sub=entry({'admin','services','fastacl251_subscription'},post('subscription'),nil); sub.leaf=true
  local del=entry({'admin','services','fastacl251_delete_node'},post('delete_node'),nil); del.leaf=true
end
local function reply(data) local h=require 'luci.http'; h.prepare_content('application/json'); h.write(require('luci.jsonc').stringify(data)) end
function status()
  local env=require 'fastacl251_env'; local u=require('uci').cursor()
  local ok,c=pcall(env.read,u,true); if not ok then reply({ok=false,error=tostring(c)}); return end
  local nodes={}; for id,n in pairs(c.nodes) do nodes[#nodes+1]={id=id,name=n.name or id,protocol=n.protocol or '',owner=n.owner or '',retired=n.retired=='1'} end
  table.sort(nodes,function(a,b) return a.name<b.name end)
  local json=require 'luci.jsonc'
  local runtime=json.parse(require('luci.sys').exec('/usr/bin/fastacl251 status')) or {}
  local job=nixio.fs.readfile('/tmp/fastacl251/apply.result')
  local subscriptions={}
  u:foreach('fastacl251','subscription',function(s)
    subscriptions[#subscriptions+1]={id=s['.name'],name=s.name or s['.name'],enabled=s.enabled~='0',interval_hours=tonumber(s.interval_hours or '24'),status=json.parse(nixio.fs.readfile('/tmp/fastacl251/sub-'..s['.name']..'.json') or '') or {}}
  end)
  reply({ok=true,version='2.5.1-dev.1',enabled=c.enabled,devices=env.inventory(c,u),nodes=nodes,subscriptions=subscriptions,dns_policy=c.dns_policy,network=c.network,router_ip=c.router_ip,runtime=runtime,job=job,subscription_running=nixio.fs.access('/tmp/fastacl251-subscribe.lock') or false})
end
function save()
  local h=require 'luci.http'; local json=require 'luci.jsonc'; local fs=require 'nixio.fs'
  local util=require 'luci.util'; local sys=require 'luci.sys'; local policy=require 'fastacl251'; local env=require 'fastacl251_env'
  local raw=h.formvalue('data') or ''; if #raw>65536 then reply({ok=false,error='Request too large'}); return end
  local request=json.parse(raw); if type(request)~='table' then reply({ok=false,error='Invalid request'}); return end
  if not fs.mkdir('/tmp/fastacl251-edit.lock') then reply({ok=false,error='操作正在进行，请稍后重试'}); return end
  local u=require('uci').cursor(); local oldcfg=fs.readfile('/etc/config/fastacl251'); local olddhcp=fs.readfile('/etc/config/dhcp')
  local committed=false
  local ok,err=pcall(function()
    for _,cfg in ipairs({'fastacl251','dhcp'}) do local changes=u:changes(cfg); assert(not changes or not next(changes),'请先保存或撤销未提交配置') end
    local c=env.read(u)
    if request.dns_policy then assert(request.dns_policy=='direct' or request.dns_policy=='private','Invalid DNS policy'); c.dns_policy=request.dns_policy end
    local updates=request.devices or {}; assert(type(updates)=='table' and #updates<=256,'Too many devices')
    local existing={}; for _,d in ipairs(c.devices) do existing[d.mac]=d end
    local changed={}
    for _,d in ipairs(updates) do
      local mac=assert(policy.mac(d.mac),'Invalid MAC'); assert(not changed[mac],'Duplicate update'); changed[mac]=true
      if d.remove==true then existing[mac]=nil
      else
        assert(type(d.name or '')=='string' and #(d.name or '')<=80,'Invalid device name')
        existing[mac]={id='d_'..mac:gsub(':',''),mac=mac,ip=d.ip,name=d.name or '',mode=d.mode,node=d.node,preproxy=d.preproxy or ''}
      end
    end
    c.devices={}; for _,d in pairs(existing) do c.devices[#c.devices+1]=d end; policy.validate(c)
    -- Reject duplicate reservations and currently leased addresses owned by another MAC.
    local inventory=env.inventory(c,u)
    for _,d in ipairs(c.devices) do
      u:foreach('dhcp','host',function(s)
        if s['.name']~='jfa25_'..d.id and s.ip==d.ip then
          local same=false; local list=type(s.mac)=='table' and s.mac or {s.mac or ''}
          for _,v in ipairs(list) do for x in v:gmatch('%S+') do if policy.mac(x)==d.mac then same=true end end end
          assert(same,'IP 已被其他静态租约使用')
        end
      end)
      for _,r in ipairs(inventory) do assert(r.mac==d.mac or r.ip~=d.ip,'IP 已由其他设备使用') end
    end
    u:set('fastacl251','main','dns_policy',c.dns_policy)
    for mac in pairs(changed) do
      local id='d_'..mac:gsub(':',''); local host='jfa25_'..id
      u:delete('fastacl251',id); u:delete('dhcp',host)
      local d=existing[mac]
      if d then
        -- Existing user-managed MAC reservations must already agree; do not alter them.
        local reserved=false
        u:foreach('dhcp','host',function(s)
          local list=type(s.mac)=='table' and s.mac or {s.mac or ''}
          for _,v in ipairs(list) do for x in v:gmatch('%S+') do if policy.mac(x)==mac then assert(s.ip==d.ip,'此 MAC 已有其他固定 IP，请先调整原静态租约'); reserved=true end end end
        end)
        u:section('fastacl251','device',id,{mac=mac,ip=d.ip,name=d.name,mode=d.mode,node=d.node or '',preproxy=d.preproxy})
        if not reserved then u:section('dhcp','host',host,{mac=mac,ip=d.ip,leasetime='infinite',jfa25='1'}) end
      end
    end
    assert(u:commit('fastacl251'),'保存设备配置失败'); committed=true; assert(u:commit('dhcp'),'保存 DHCP 配置失败')
    fs.chmod('/etc/config/fastacl251',384)
    sys.call('/etc/init.d/dnsmasq reload >/dev/null 2>&1')
    if c.enabled then
      fs.mkdir('/tmp/fastacl251'); fs.writefile('/tmp/fastacl251/apply.result','pending')
      sys.call("( /usr/bin/fastacl251 apply > /tmp/fastacl251/apply.log 2>&1; rc=$?; echo $rc > /tmp/fastacl251/apply.result ) </dev/null >/dev/null 2>&1 &")
    end
  end)
  if not ok then
    u:revert('fastacl251'); u:revert('dhcp')
    if committed then fs.writefile('/etc/config/fastacl251',oldcfg or ''); fs.writefile('/etc/config/dhcp',olddhcp or '') end
  end
  fs.rmdir('/tmp/fastacl251-edit.lock')
  reply(ok and {ok=true,message='已保存。固定 IP 改变后，请重新连接 WiFi 获取地址。'} or {ok=false,error=tostring(err)})
end
function import_nodes()
  local h=require 'luci.http'; local fs=require 'nixio.fs'; local sys=require 'luci.sys'
  local links=h.formvalue('links') or ''
  if #links<1 or #links>524288 then reply({ok=false,error='导入内容为空或超过 512KB'}); return end
  if not fs.mkdir('/tmp/fastacl251-edit.lock') then reply({ok=false,error='配置正在保存，请稍后重试'}); return end
  local u=require('uci').cursor(); local original=fs.readfile('/etc/config/fastacl251')
  local count=0
  local ok,err=pcall(function()
    local pending=u:changes('fastacl251'); assert(not pending or not next(pending),'请先保存未提交配置')
    local nodes=require('fastacl251_import').batch(links)
    local manager=require 'fastacl251_nodes'; manager.check(nodes); manager.add(u,nodes); assert(u:commit('fastacl251'),'保存节点失败'); count=#nodes
  end)
  if not ok then u:revert('fastacl251'); if original then fs.writefile('/etc/config/fastacl251',original) end end
  fs.chmod('/etc/config/fastacl251',384)
  fs.rmdir('/tmp/fastacl251-edit.lock'); reply({ok=ok,count=count,error=not ok and tostring(err) or nil})
end
function subscription()
  local h=require 'luci.http'; local fs=require 'nixio.fs'; local policy=require 'fastacl251'; local sys=require 'luci.sys'
  local data=require('luci.jsonc').parse(h.formvalue('data') or '')
  if type(data)~='table' then reply({ok=false,error='Invalid subscription request'}); return end
  local u=require('uci').cursor()
  if data.action=='update' then
    local id=data.id or 'all'
    if id~='all' and (not policy.id(id) or u:get('fastacl251',id)~='subscription') then reply({ok=false,error='Invalid subscription ID'}); return end
    if fs.access('/tmp/fastacl251-subscribe.lock') then reply({ok=false,error='订阅正在更新'}); return end
    sys.call('lua /usr/libexec/fastacl251-subscribe.lua '..id..' >/tmp/fastacl251-subscribe.log 2>&1 </dev/null &')
    reply({ok=true,message='订阅更新已开始'}); return
  end
  if not fs.mkdir('/tmp/fastacl251-edit.lock') then reply({ok=false,error='配置正在保存'}); return end
  local original=fs.readfile('/etc/config/fastacl251')
  local ok,err=pcall(function()
    local pending=u:changes('fastacl251'); assert(not pending or not next(pending),'请先保存未提交配置')
    local id=data.id
    if id then assert(policy.id(id) and u:get('fastacl251',id)=='subscription','Invalid subscription ID') end
    if data.action=='remove' then
      assert(id,'Missing subscription ID'); local owned,remove={},{}
      u:foreach('fastacl251','node',function(n) if n.owner==id then owned[n['.name']]=true; remove[#remove+1]=n['.name'] end end)
      u:foreach('fastacl251','device',function(d) assert(not owned[d.node] and not owned[d.preproxy],'订阅仍有设备绑定，请先解除绑定') end)
      for _,n in ipairs(remove) do u:delete('fastacl251',n) end; u:delete('fastacl251',id)
    else
      assert(data.action=='save','Invalid action')
      local hours=tonumber(data.interval_hours or 24); assert(hours and hours>=1 and hours<=168 and hours%1==0,'更新周期须为 1–168 小时')
      local name=data.name or ''; assert(type(name)=='string' and #name>0 and #name<=80,'Invalid subscription name')
      local url=data.url
      if not url or url=='' then url=id and u:get('fastacl251',id,'url') end
      assert(type(url)=='string' and #url<=4096 and url:match('^https://') and not url:find('[%c"\\]'),'订阅须使用 HTTPS')
      if not id then
        local count=0; u:foreach('fastacl251','subscription',function() count=count+1 end); assert(count<32,'最多 32 个订阅')
        id=u:add('fastacl251','subscription')
      end
      u:set('fastacl251',id,'name',name); u:set('fastacl251',id,'url',url); u:set('fastacl251',id,'interval_hours',tostring(hours)); u:set('fastacl251',id,'enabled',data.enabled==false and '0' or '1')
    end
    assert(u:commit('fastacl251'),'保存订阅失败'); fs.chmod('/etc/config/fastacl251',384)
  end)
  if not ok then u:revert('fastacl251'); if original then fs.writefile('/etc/config/fastacl251',original) end end
  fs.rmdir('/tmp/fastacl251-edit.lock'); reply({ok=ok,error=not ok and tostring(err) or nil})
end
function delete_node()
  local fs=require 'nixio.fs'; local id=require('luci.http').formvalue('id'); local policy=require 'fastacl251'
  if not policy.id(id) then reply({ok=false,error='Invalid node ID'}); return end
  if not fs.mkdir('/tmp/fastacl251-edit.lock') then reply({ok=false,error='配置正在保存'}); return end
  local u=require('uci').cursor(); local ok,err=pcall(function()
    local pending=u:changes('fastacl251'); assert(not pending or not next(pending),'请先保存配置')
    assert(u:get('fastacl251',id)=='node','Node not found')
    u:foreach('fastacl251','device',function(d) assert(d.node~=id and d.preproxy~=id,'节点仍被设备使用，请先解除绑定') end)
    u:delete('fastacl251',id); u:commit('fastacl251')
  end)
  if not ok then u:revert('fastacl251') end
  fs.rmdir('/tmp/fastacl251-edit.lock'); reply({ok=ok,error=not ok and tostring(err) or nil})
end
