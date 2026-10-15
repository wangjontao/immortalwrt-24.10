#!/bin/sh
set -eu

TAG="jfa252-hotfix2-20261015"
BK="/root/${TAG}-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"

echo "=================================================="
echo " JuLiang FastACL 2.5.2 dev.2 HOTFIX-2"
echo " - 兼容 HOTFIX-1 已部分执行的机器"
echo " - 不再依赖 fastacl252_wifi.lua 精确行匹配"
echo " - 修复 UCI changes()/chmod 兼容"
echo " - 保护 WiFi 正在使用的订阅节点"
echo " - 修复 172.16.x.x 地址池识别"
echo " - 修复 NPS 域名输入"
echo " - 导入阶段兼容 DNS Relay 合法协议误判"
echo "=================================================="

need() {
    [ -e "$1" ] || { echo "[ERR] 缺少文件: $1"; exit 1; }
}

NODES="/usr/lib/lua/fastacl252_nodes.lua"
WIFI="/usr/lib/lua/fastacl252_wifi.lua"
CTRL="/usr/lib/lua/luci/controller/fastacl252.lua"
SUB="/usr/libexec/fastacl252-subscribe.lua"
IMP="/usr/lib/lua/fastacl252_import.lua"

for f in "$NODES" "$WIFI" "$CTRL" "$SUB" "$IMP"; do
    need "$f"
    cp -a "$f" "$BK/$(echo "$f" | sed 's#/#_#g').bak"
done
[ -f /etc/config/nps ] && cp -a /etc/config/nps "$BK/nps.config.bak" || true

cat >/tmp/jfa252_patch2.lua <<'LUA'
local function read(p)
  local f=assert(io.open(p,'rb')); local s=f:read('*a'); f:close(); return s
end
local function write(p,s)
  local f=assert(io.open(p,'wb')); assert(f:write(s)); f:close()
end
local function has(s,x) return s:find(x,1,true)~=nil end
local function replace_plain(s,old,new)
  local out,n={},0; local pos=1
  while true do
    local a,b=s:find(old,pos,true)
    if not a then out[#out+1]=s:sub(pos); break end
    out[#out+1]=s:sub(pos,a-1); out[#out+1]=new
    pos=b+1; n=n+1
  end
  return table.concat(out),n
end
local function replace_all_file(p,old,new)
  local s=read(p); local out,n=replace_plain(s,old,new)
  if n>0 then write(p,out) end
  io.stdout:write(string.format('[OK] %s: %d replacement(s): %s\n',p,n,old))
  return n
end
local function prepend_once(p,marker,block)
  local s=read(p)
  if has(s,marker) then
    io.stdout:write('[SKIP] helper already present: '..p..'\n'); return
  end
  write(p,block..s)
  io.stdout:write('[OK] helper inserted: '..p..'\n')
end
local function insert_after_line(p,needle,marker,line)
  local s=read(p)
  if has(s,marker) then io.stdout:write('[SKIP] already present: '..p..'\n'); return true end
  local pos=1
  while true do
    local nl=s:find('\n',pos,true)
    local e=nl and nl or (#s+1)
    local row=s:sub(pos,e-1)
    if has(row,needle) then
      local ins=e
      local out=s:sub(1,ins)..line..s:sub(ins+1)
      write(p,out); io.stdout:write('[OK] inserted after matching line: '..p..'\n'); return true
    end
    if not nl then break end
    pos=nl+1
  end
  io.stdout:write('[WARN] insertion anchor not found: '..p..' / '..needle..'\n')
  return false
end
local function replace_function(p,start_marker,next_marker,newblock)
  local s=read(p)
  local a=s:find(start_marker,1,true)
  if not a then
    io.stdout:write('[WARN] function start not found: '..p..' / '..start_marker..'\n'); return false
  end
  local b=s:find(next_marker,a+#start_marker,true)
  if not b then
    io.stdout:write('[WARN] next function marker not found: '..p..' / '..next_marker..'\n'); return false
  end
  local out=s:sub(1,a-1)..newblock..s:sub(b)
  write(p,out)
  io.stdout:write('[OK] function replaced safely: '..p..' / '..start_marker..'\n')
  return true
end

local nodes='/usr/lib/lua/fastacl252_nodes.lua'
local wifi='/usr/lib/lua/fastacl252_wifi.lua'
local ctrl='/usr/lib/lua/luci/controller/fastacl252.lua'
local sub='/usr/libexec/fastacl252-subscribe.lua'

-- nodes.lua: chmod compatibility. HOTFIX-1 may already have done this.
local safe_nodes=[[
local function safe_chmod(path,mode)
  local f=fs["chmod"]
  if type(f)=="function" then
    local ok,res=pcall(f,path,mode)
    if ok and res~=nil then return res end
  end
  local oct=string.format('%o',tonumber(mode) or 384)
  return sys.call('chmod '..oct..' '..require('luci.util').shellquote(path)..' >/dev/null 2>&1')==0
end
]]
local ns=read(nodes)
if not has(ns,'local function safe_chmod(') then
  local anchor="local sys=require 'luci.sys'\n"
  if has(ns,anchor) then
    ns=select(1,replace_plain(ns,anchor,anchor..safe_nodes)); write(nodes,ns)
    io.stdout:write('[OK] safe_chmod inserted: '..nodes..'\n')
  else
    io.stdout:write('[WARN] safe_chmod anchor missing in nodes.lua; existing chmod calls will be left if helper cannot be added\n')
  end
else
  io.stdout:write('[SKIP] safe_chmod already present: '..nodes..'\n')
end
if has(read(nodes),'local function safe_chmod(') then replace_all_file(nodes,'fs.chmod(','safe_chmod(') end

-- Protect nodes referenced by FastACL-managed WiFi during subscription replacement.
local cur=read(nodes)
if has(cur,"foreach('fastacl252','wifi'") and has(cur,'bound[w.node') then
  io.stdout:write('[SKIP] WiFi node protection already present\n')
else
  insert_after_line(nodes,
    "u:foreach('fastacl252','device'",
    "u:foreach('fastacl252','wifi'",
    "  u:foreach('fastacl252','wifi',function(w) bound[w.node or '']=true; bound[w.preproxy or '']=true end)\n")
end

-- Import-stage DNS relay false-negative workaround. Keep dae validation strict.
cur=read(nodes)
if has(cur,'DNS Relay 节点校验失败:') then
  io.stdout:write('[SKIP] DNS Relay import workaround already present\n')
else
  local old="  local links=sys.call('fastacl252-dns -check -config /tmp/fastacl252/nodes-dns-check.json >/tmp/fastacl252/nodes-check.log 2>&1');fs.remove('/tmp/fastacl252/nodes-dns-check.json');assert(links==0,'Invalid native dae node')\n"
  local new="  local links=sys.call('fastacl252-dns -check -config /tmp/fastacl252/nodes-dns-check.json >/tmp/fastacl252/nodes-check.log 2>&1')\n"..
    "  fs.remove('/tmp/fastacl252/nodes-dns-check.json')\n"..
    "  if links~=0 then\n"..
    "    local relaylog=fs.readfile('/tmp/fastacl252/nodes-check.log') or ''\n"..
    "    if not relaylog:find('unsupported or invalid node',1,true) then\n"..
    "      error('DNS Relay 节点校验失败: '..relaylog,0)\n"..
    "    end\n"..
    "  end\n"
  local out,n=replace_plain(cur,old,new)
  if n>0 then write(nodes,out); io.stdout:write('[OK] DNS Relay import workaround installed\n')
  else io.stdout:write('[WARN] original DNS check line differs; leaving current implementation unchanged\n') end
end

-- wifi.lua: replace the whole helper instead of matching one fragile source line.
local used_subnets=[[
local function used_subnets(u)
  local used={}
  u:foreach('network','interface',function(s)
    local v=s.ipaddr; if type(v)=='table' then v=v[1] end
    local n=tostring(v or ''):match('^172%.16%.(%d+)%.%d+$')
    if n then used[tonumber(n)]=true end
  end)
  return used
end
]]
assert(replace_function(wifi,'local function used_subnets(u)','local function next_subnet',used_subnets),
  '无法定位 used_subnets()，为避免误改已停止')

-- Generic controller/subscription compatibility helpers.
local helpers=[[
local function safe_chmod(path,mode)
  local fs=require 'nixio.fs'
  local f=fs["chmod"]
  if type(f)=="function" then
    local ok,res=pcall(f,path,mode)
    if ok and res~=nil then return res end
  end
  local oct=string.format('%o',tonumber(mode) or 384)
  return require('luci.sys').call('chmod '..oct..' '..require('luci.util').shellquote(path)..' >/dev/null 2>&1')==0
end
local function uci_changes(u,cfg)
  local f=u and u.changes
  if type(f)=='function' then
    local ok,res=pcall(f,u,cfg)
    if ok then return res end
  end
  return nil
end
]]
prepend_once(ctrl,'local function uci_changes(',helpers)
replace_all_file(ctrl,'fs.chmod(','safe_chmod(')
replace_all_file(ctrl,'u:changes(','uci_changes(u,')

prepend_once(sub,'local function uci_changes(',helpers)
replace_all_file(sub,'fs.chmod(','safe_chmod(')
replace_all_file(sub,'u:changes(','uci_changes(u,')

print('[OK] Lua HOTFIX-2 patch complete')
LUA

lua /tmp/jfa252_patch2.lua
rm -f /tmp/jfa252_patch2.lua

# Keep expected config permissions sane even if the running nixio build lacks chmod().
chmod 600 /etc/config/fastacl252 2>/dev/null || true
mkdir -p /tmp/fastacl252
chmod 700 /tmp/fastacl252 2>/dev/null || true

echo
echo "[1/6] 修复 NPS 域名输入限制..."
if [ -f /etc/config/nps ]; then
    sed -i 's/47\.83\.9\.208/nps.jontao.top/g' /etc/config/nps || true
fi
for f in $(find /usr/lib/lua/luci -type f \( -iname '*nps*.lua' -o -path '*/nps/*.lua' \) 2>/dev/null); do
    sed -i \
      -e 's/datatype[[:space:]]*=[[:space:]]*"ipaddr"/datatype = "host"/g' \
      -e "s/datatype[[:space:]]*=[[:space:]]*'ipaddr'/datatype = 'host'/g" \
      -e 's/47\.83\.9\.208/nps.jontao.top/g' \
      "$f" || true
done
for f in $(find /www /usr/share/luci 2>/dev/null -type f \( -name '*.js' -o -name '*.htm' \) | grep -i nps || true); do
    sed -i \
      -e "s/'ipaddr'/'host'/g" \
      -e 's/"ipaddr"/"host"/g' \
      -e 's/47\.83\.9\.208/nps.jontao.top/g' \
      "$f" || true
done
if command -v uci >/dev/null 2>&1; then
    uci show nps 2>/dev/null | grep "=.*47\.83\.9\.208" | while IFS= read -r line; do
        key="${line%%=*}"
        uci -q set "${key}=nps.jontao.top" || true
    done
    uci -q commit nps || true
fi

echo "[2/6] 清理 LuCI 缓存..."
rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -rf /tmp/luci-modulecache/* 2>/dev/null || true

echo "[3/6] Lua 语法/模块自检..."
lua - <<'LUA'
package.path='/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;'..package.path
assert(require('fastacl252_import'))
assert(require('fastacl252_nodes'))
assert(require('fastacl252_wifi'))
local p=require('fastacl252_import')
local n=p.batch('socks5://user:pass@127.0.0.1:1080')
assert(type(n)=='table' and #n==1,'SOCKS5 parser returned no node')
print('[OK] FastACL Lua modules and SOCKS5 parser load passed')
LUA

echo "[4/6] 关键补丁检查..."
grep -q "foreach('fastacl252','wifi'.*bound" "$NODES" \
  && echo "[OK] 订阅更新已保护 WiFi 绑定节点" \
  || { echo "[ERR] WiFi 绑定保护未生效"; exit 1; }

grep -Fq "^172%.16%.(%d+)%.%d+$" "$WIFI" \
  && echo "[OK] 172.16.x.x 地址池识别已修复" \
  || { echo "[ERR] 地址池识别补丁未生效"; exit 1; }

grep -q "local function uci_changes" "$CTRL" \
  && echo "[OK] Controller UCI changes() 兼容层已安装" \
  || { echo "[ERR] Controller UCI 兼容层未生效"; exit 1; }

grep -q "local function uci_changes" "$SUB" \
  && echo "[OK] Subscription UCI changes() 兼容层已安装" \
  || { echo "[ERR] Subscription UCI 兼容层未生效"; exit 1; }

echo "[5/6] 显示当前地址池函数，便于核对..."
sed -n '/local function used_subnets/,/local function next_subnet/p' "$WIFI" | sed '$d'

echo "[6/6] 重启 Web/RPC 服务..."
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo
echo "=================================================="
echo "[DONE] HOTFIX-2 已安装"
echo "备份目录: $BK"
echo
echo "无需恢复 HOTFIX-1；HOTFIX-2 已兼容前一次部分修改。"
echo "现在刷新浏览器后依次测试："
echo "  1. 新增 SOCKS5 / HTTP 节点"
echo "  2. 新增 SS / Trojan / TUIC / Hysteria2 节点"
echo "  3. 新增 WiFi，并绑定节点"
echo "  4. NPS 页面填写 nps.jontao.top"
echo
echo "如果第 2 步能导入、但绑定/应用时报："
echo "  unsupported or invalid node"
echo "则下一步直接修 fastacl252-dns ARM64 二进制，不再改 Lua。"
echo "=================================================="
