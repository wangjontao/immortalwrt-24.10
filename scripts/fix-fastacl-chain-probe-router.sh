#!/bin/sh
set -eu

CTRL=/usr/lib/lua/luci/controller/fastacl252.lua
VIEW=/usr/lib/lua/luci/view/fastacl252/console.htm
MARKER=FASTACL_CHAIN_PROBE_V1

[ -f "$CTRL" ] || { echo "Missing $CTRL" >&2; exit 1; }
[ -f "$VIEW" ] || { echo "Missing $VIEW" >&2; exit 1; }
command -v lua >/dev/null 2>&1 || { echo "Missing lua" >&2; exit 1; }

if grep -q "$MARKER" "$CTRL" && grep -q "$MARKER" "$VIEW"; then
	echo "FastACL chained node probe fix is already installed."
	exit 0
fi

stamp=$(date +%Y%m%d-%H%M%S)
backup="/root/fastacl-chain-probe-backup-$stamp"
ctrl_tmp="$CTRL.chain-probe.$$"
view_tmp="$VIEW.chain-probe.$$"

cleanup() {
	rm -f "$ctrl_tmp" "$view_tmp"
}
trap cleanup EXIT INT TERM

mkdir -m 700 "$backup"
cp -p "$CTRL" "$backup/controller-fastacl252.lua"
cp -p "$VIEW" "$backup/console.htm"

lua - "$CTRL" "$ctrl_tmp" "$VIEW" "$view_tmp" <<'LUA'
local ctrl_path, ctrl_tmp, view_path, view_tmp = ...

local function read(path)
	local f = assert(io.open(path, 'rb'))
	local value = f:read('*a')
	f:close()
	return value
end

local function write(path, value)
	local f = assert(io.open(path, 'wb'))
	assert(f:write(value))
	f:close()
end

local controller = read(ctrl_path)
if not controller:find('FASTACL_CHAIN_PROBE_V1', 1, true) then
	local start = controller:find('-- Read-only saved-node/assigned-exit probe', 1, true)
	local stop = start and controller:find('\nfunction wireless_status()', start, true)
	assert(start and stop, 'Unsupported controller probe block')
	local replacement = [=[-- FASTACL_CHAIN_PROBE_V1
function probe_fronts(c,id)
 local fronts={};local seen={}
 local function add(value)
  if value and value~='' and not seen[value] then seen[value]=true;fronts[#fronts+1]=value end
 end
 for _,d in ipairs(c.devices or {}) do if d.node==id then add(d.preproxy) end end
 for _,w in ipairs(c.wifis or {}) do if w.node==id then add(w.preproxy) end end
 local lan=c.lan_default or {};if lan.node==id then add(lan.preproxy) end
 return fronts[1],#fronts
end

-- Read-only saved-node/assigned-exit probe. Never changes client bindings.
function probe()
 local h=require'luci.http'; local fs=require'nixio.fs'; local sys=require'luci.sys';local json=require'luci.jsonc'
 if not fs.mkdir('/tmp/fastacl252-probe.lock') then reply({ok=false,error='已有出口检测正在进行，请稍后重试'});return end
 local result
 local ok,err=pcall(function()
  local c=require('fastacl252_env').read();local kind=h.formvalue('kind');local target=h.formvalue('id');local x;local mode='proxy'
  if kind=='node' then
   assert(require('fastacl252').id(target) and c.nodes[target],'节点不存在')
   local pre=h.formvalue('preproxy') or ''
   if pre=='' then
    local inferred,count=probe_fronts(c,target)
    assert(count<=1,'该节点存在多个不同前置链路，请在对应设备或 WiFi 行检测出口')
    pre=inferred or ''
   end
   assert(pre=='' or c.nodes[pre],'前置节点不存在')
   assert(pre=='' or pre~=target,'前置节点不能与出口节点相同')
   x={node=target,preproxy=pre}
  elseif kind=='device' then
   local mac=assert(require('fastacl252').mac(target),'设备 MAC 无效')
   for _,d in ipairs(c.devices) do if d.mac==mac then x=d;mode=d.mode;break end end
   if not x then x={};mode='direct' end
  else error('检测类型无效') end
  local link=''
  if mode=='proxy' then
   local relay_ok,compiler=pcall(require,'fastacl252_relay')
   if not relay_ok then compiler=require'fastacl252_dae' end
   link=compiler.link(assert(c.nodes[x.node],'绑定节点不存在'))
   if x.preproxy and x.preproxy~='' then link=link..' -> '..compiler.link(assert(c.nodes[x.preproxy],'前置节点不存在')) end
  end
  assert(fs.writefile('/tmp/fastacl252-probe.lock/spec.json',json.stringify({link=link})),'写入检测配置失败');fs.chmod('/tmp/fastacl252-probe.lock/spec.json','600')
  local data=sys.exec('/usr/libexec/fastacl252-exit-probe -probe-file /tmp/fastacl252-probe.lock/spec.json 2>/dev/null')
  result=json.parse(data);assert(type(result)=='table','检测程序未返回结果')
  result.kind=kind;result.mode=mode;result.scope='saved_exit';result.preproxy=x.preproxy or ''
  if result.preproxy~='' and c.nodes[result.preproxy] then result.preproxy_name=c.nodes[result.preproxy].name or result.preproxy end
  result.note=kind=='device' and '路由器侧检测已保存的绑定出口，不代表手机实机连通性' or '路由器侧节点出口检测'
 end)
 fs.remove('/tmp/fastacl252-probe.lock/spec.json');fs.rmdir('/tmp/fastacl252-probe.lock')
 if ok then reply(result) else reply({ok=false,error='出口检测失败：'..tostring(err)}) end
end

]=]
	controller = controller:sub(1, start - 1) .. replacement .. controller:sub(stop + 1)
	write(ctrl_tmp, controller)
end

local view = read(view_path)
if not view:find('FASTACL_CHAIN_PROBE_V1', 1, true) then
	local start = view:find('async function probeExit(kind,id,button,result)', 1, true)
	local stop = start and view:find('\n', start, true)
	assert(start and stop, 'Unsupported console probe function')
	local replacement = [=[/* FASTACL_CHAIN_PROBE_V1 */async function probeExit(kind,id,button,result){if(probing)return msg('已有出口检测正在进行，请稍后重试',true);probing=true;button.disabled=true;result.className='probe-result note';result.textContent='正在通过已保存出口查询…';try{const j=await api('probe',{kind,id});result.className='probe-result good';result.textContent=(j.proxy?'代理出口：':'直连出口：')+j.ip+' · '+(j.location||j.country||'归属地未知')+' · '+j.elapsed_ms+'ms'+(j.source?' · '+j.source:'')+(j.preproxy_name?' · 经前置 '+j.preproxy_name:'');result.title=j.note||'';if(kind==='device')result.append(el('span','meta','（绑定出口检测，非手机实机检测）'));}catch(e){result.className='probe-result bad';result.textContent=e.message;}finally{button.disabled=false;probing=false}}]=]
	view = view:sub(1, start - 1) .. replacement .. view:sub(stop)
	write(view_tmp, view)
end
LUA

if [ -s "$ctrl_tmp" ]; then
	if command -v luac >/dev/null 2>&1; then
		luac -p "$ctrl_tmp" || {
			echo "Generated controller failed syntax validation" >&2
			exit 1
		}
	fi
	chmod 644 "$ctrl_tmp"
	mv -f "$ctrl_tmp" "$CTRL"
fi

if [ -s "$view_tmp" ]; then
	grep -q "$MARKER" "$view_tmp" || {
		echo "Generated console is missing its patch marker" >&2
		exit 1
	}
	chmod 644 "$view_tmp"
	mv -f "$view_tmp" "$VIEW"
fi

rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache

echo "FastACL chained node probe fix applied."
echo "Backup: $backup"
echo "Reload LuCI and test a chained SOCKS exit node."
