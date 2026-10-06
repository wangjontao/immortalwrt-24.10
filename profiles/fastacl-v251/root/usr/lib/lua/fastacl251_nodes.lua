local M={}
local fs=require 'nixio.fs'
local json=require 'luci.jsonc'
local sys=require 'luci.sys'
local policy=require 'fastacl251'
local parser=require 'fastacl251_import'
function M.check(nodes)
  local c={network='lan',interface='br-lan',router_ip='192.168.7.1',netmask='255.255.0.0',port=12525,default_mode='direct',dns_policy='direct',dns_server='223.5.5.5',dns_name='dns.alidns.com',private_dns_server='9.9.9.9',private_dns_name='dns.quad9.net',nodes={},devices={}}
  for i,n in ipairs(nodes) do
    local id='check'..i; c.nodes[id]=n
    c.devices[#c.devices+1]={mac=string.format('02:00:00:00:%02X:%02X',math.floor(i/256),i%256),ip='192.168.'..(8+math.floor(i/254))..'.'..(i%254+1),mode='proxy',node=id}
  end
  local conf=policy.compile(c)
  fs.mkdir('/tmp/fastacl251')
  fs.chmod('/tmp/fastacl251',448)
  assert(fs.writefile('/tmp/fastacl251/nodes-check.json',json.stringify(conf,true)),'Cannot stage node check')
  fs.chmod('/tmp/fastacl251/nodes-check.json',384)
  local rc=sys.call('mihomo -t -d /tmp/fastacl251 -f /tmp/fastacl251/nodes-check.json >/tmp/fastacl251/nodes-check.log 2>&1')
  fs.remove('/tmp/fastacl251/nodes-check.json'); assert(rc==0,'节点包含核心不支持的参数，请检查节点格式')
end
local function hash(s)
  local h=0; for i=1,#s do h=(h*131+s:byte(i))%2147483647 end; return string.format('%08x',h)
end
function M.replace(u,nodes,owner)
  local counts,active={},{}; local bound={}
  u:foreach('fastacl251','device',function(d) bound[d.node or '']=true; bound[d.preproxy or '']=true end)
  for _,n in ipairs(nodes) do
    local identity=n.protocol..'\n'..n.name; counts[identity]=(counts[identity] or 0)+1
    identity=identity..'\n'..counts[identity]
    local id='n_'..hash(owner..'\n'..identity); local tries=0
    while u:get('fastacl251',id) and (u:get('fastacl251',id,'owner')~=owner or u:get('fastacl251',id,'identity')~=identity) do tries=tries+1; assert(tries<100,'Node identity collision'); id='n_'..hash(owner..'\n'..identity..'\n'..tries) end
    u:section('fastacl251','node',id,{name=n.name,protocol=n.protocol,outbound=json.stringify(n.outbound),owner=owner,identity=identity,retired='0'})
    active[id]=true
  end
  local remove={}; u:foreach('fastacl251','node',function(n)
    if n.owner==owner and not active[n['.name']] then
      if bound[n['.name']] then u:set('fastacl251',n['.name'],'retired','1') else remove[#remove+1]=n['.name'] end
    end
  end)
  for _,id in ipairs(remove) do u:delete('fastacl251',id) end
end
function M.add(u,nodes)
  local index=tonumber(u:get('fastacl251','main','import_index') or '0')+1
  M.replace(u,nodes,'manual'..index); u:set('fastacl251','main','import_index',tostring(index))
end
return M
