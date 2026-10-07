module('luci.controller.juliangtk_nps',package.seeall)
function index()
 if not nixio.fs.access('/etc/config/nps') then return end
 local p=entry({'admin','juliangtk_nps'},template('juliangtk/nps'),_('NPS 管理'),40);p.leaf=true;p.acl_depends={'luci-app-nps'}
 local s=entry({'admin','juliangtk_nps_status'},call('status'),nil);s.leaf=true;s.acl_depends={'luci-app-nps'}
 local a=entry({'admin','juliangtk_nps_save'},post('save'),nil);a.leaf=true;a.acl_depends={'luci-app-nps'}
end
local function reply(v) local h=require 'luci.http';h.prepare_content('application/json');h.write(require('luci.jsonc').stringify(v)) end
local function root_only()
 if (require('luci.dispatcher').context or {}).authuser~='root' then require('luci.http').status(403,'Forbidden');reply({ok=false,error='仅 root 可管理 NPS'});return false end
 return true
end
local function section(u)
 local id;u:foreach('nps','nps',function(s) if not id then id=s['.name'] end end);return id
end
function status()
 if not root_only() then return end
 local u=require('luci.model.uci').cursor();local id=section(u);local c=id and u:get_all('nps',id) or {}
 local data={};for _,key in ipairs({'enabled','server_addr','server_port','protocol','compress','crypt','log_level'}) do data[key]=c[key] end
 data.key_configured=c.vkey~=nil and c.vkey~=''
 reply({ok=true,config=data,running=require('luci.sys').call('pgrep -x npc >/dev/null 2>&1')==0})
end
function save()
 if not root_only() then return end
 local h=require 'luci.http';local json=require 'luci.jsonc';local fs=require 'nixio.fs';local sys=require 'luci.sys'
 local raw=h.formvalue('data') or '';if #raw>8192 then reply({ok=false,error='Request too large'});return end
 local d=json.parse(raw);if type(d)~='table' then reply({ok=false,error='Invalid request'});return end
 if not fs.mkdir('/tmp/juliangtk-nps.lock') then reply({ok=false,error='NPS 配置正在保存'});return end
 local u=require('luci.model.uci').cursor()
 local ok,err=pcall(function()
  local changes=u:changes('nps');assert(not changes or not next(changes),'请先保存或撤销原 NPS 未提交配置')
  local id=assert(section(u),'NPS configuration missing')
  assert(type(d.server_addr)=='string' and #d.server_addr>0 and #d.server_addr<=253 and d.server_addr:match('^[%w.-]+$'),'服务器地址无效')
  local port=tonumber(d.server_port);assert(port and port>=1 and port<=65535 and port%1==0,'端口无效')
  assert(d.protocol=='tcp' or d.protocol=='kcp','协议无效')
  for _,key in ipairs({'enabled','compress','crypt'}) do assert(type(d[key])=='boolean','Invalid flag');u:set('nps',id,key,d[key] and '1' or '0') end
  if d.vkey and d.vkey~='' then assert(type(d.vkey)=='string' and #d.vkey<=512 and not d.vkey:find('[%c%s]'),'VKey 无效');u:set('nps',id,'vkey',d.vkey) end
  assert((u:get('nps',id,'vkey') or '')~='','请填写 VKey')
  u:set('nps',id,'server_addr',d.server_addr);u:set('nps',id,'server_port',tostring(port));u:set('nps',id,'protocol',d.protocol)
  assert(u:commit('nps'),'NPS 保存失败');fs.chmod('/etc/config/nps','600')
  sys.call('( /etc/init.d/nps restart >/tmp/juliangtk-nps-apply.log 2>&1 ) </dev/null >/dev/null 2>&1 &')
 end)
 if not ok then u:revert('nps') end
 fs.rmdir('/tmp/juliangtk-nps.lock');reply({ok=ok,error=not ok and tostring(err) or nil})
end
