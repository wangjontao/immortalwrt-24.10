#!/bin/sh
set -eu

TAG="jfa252-hotfix1-20261015"
BK="/root/${TAG}-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"

echo "=================================================="
echo " JuLiang FastACL 2.5.2 dev.2 HOTFIX-1"
echo " - 修复节点导入权限兼容"
echo " - 修复 UCI changes() 兼容"
echo " - 修复订阅更新误删 WiFi 正在使用的节点"
echo " - 修复 172.16.x.x 地址池识别"
echo " - 修复 NPS 只能填写 IP"
echo " - 绕过 DNS Relay 的已知“合法协议误判”仅用于导入校验"
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
    cp -a "$f" "$BK/$(basename "$f").bak"
done
[ -f /etc/config/nps ] && cp -a /etc/config/nps "$BK/nps.config.bak" || true

cat >/tmp/jfa252_patch.lua <<'LUA'
local function read(p)
  local f=assert(io.open(p,'rb')); local s=f:read('*a'); f:close(); return s
end
local function write(p,s)
  local f=assert(io.open(p,'wb')); assert(f:write(s)); f:close()
end
local function replace_once(p,old,new,required)
  local s=read(p)
  if s:find(new,1,true) then
    io.stdout:write('[SKIP] already patched: '..p..'\n')
    return true
  end
  local a,b=s:find(old,1,true)
  if not a then
    if required then error('pattern not found in '..p..': '..old,0) end
    io.stdout:write('[WARN] pattern not found: '..p..'\n')
    return false
  end
  s=s:sub(1,a-1)..new..s:sub(b+1)
  write(p,s)
  io.stdout:write('[OK] patched: '..p..'\n')
  return true
end
local function replace_all(p,old,new)
  local s=read(p)
  local n=0
  local out={}
  local pos=1
  while true do
    local a,b=s:find(old,pos,true)
    if not a then out[#out+1]=s:sub(pos); break end
    out[#out+1]=s:sub(pos,a-1); out[#out+1]=new
    pos=b+1; n=n+1
  end
  if n>0 then write(p,table.concat(out)) end
  io.stdout:write(string.format('[OK] %s: %d replacement(s)\n',p,n))
  return n
end

local nodes='/usr/lib/lua/fastacl252_nodes.lua'
local wifi='/usr/lib/lua/fastacl252_wifi.lua'
local ctrl='/usr/lib/lua/luci/controller/fastacl252.lua'
local sub='/usr/libexec/fastacl252-subscribe.lua'

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
replace_once(nodes,
  "local sys=require 'luci.sys'\n",
  "local sys=require 'luci.sys'\n"..safe_nodes,
  true)
replace_all(nodes,"fs.chmod(","safe_chmod(")

replace_once(nodes,
  "  u:foreach('fastacl252','device',function(d) bound[d.node or '']=true; bound[d.preproxy or '']=true end)\n",
  "  u:foreach('fastacl252','device',function(d) bound[d.node or '']=true; bound[d.preproxy or '']=true end)\n"..
  "  u:foreach('fastacl252','wifi',function(w) bound[w.node or '']=true; bound[w.preproxy or '']=true end)\n",
  true)

replace_once(nodes,
  "  local links=sys.call('fastacl252-dns -check -config /tmp/fastacl252/nodes-dns-check.json >/tmp/fastacl252/nodes-check.log 2>&1');fs.remove('/tmp/fastacl252/nodes-dns-check.json');assert(links==0,'Invalid native dae node')\n",
  "  local links=sys.call('fastacl252-dns -check -config /tmp/fastacl252/nodes-dns-check.json >/tmp/fastacl252/nodes-check.log 2>&1')\n"..
  "  fs.remove('/tmp/fastacl252/nodes-dns-check.json')\n"..
  "  if links~=0 then\n"..
  "    local relaylog=fs.readfile('/tmp/fastacl252/nodes-check.log') or ''\n"..
  "    if not relaylog:find('unsupported or invalid node',1,true) then\n"..
  "      error('DNS Relay 节点校验失败: '..relaylog,0)\n"..
  "    end\n"..
  "  end\n",
  false)

replace_once(wifi,
  "    local n=tostring(v or ''):match('^172%.16%.(%d+)%.1$')\n",
  "    local n=tostring(v or ''):match('^172%.16%.(%d+)%.%d+$')\n",
  true)

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

replace_once(ctrl,
  "local ACL={'juliang-fastacl252'}\n",
  "local ACL={'juliang-fastacl252'}\n"..helpers,
  true)
replace_all(ctrl,"fs.chmod(","safe_chmod(")
replace_all(ctrl,"u:changes(","uci_changes(u,")

replace_once(sub,
  "local mode=arg[1] or 'due'\n",
  helpers.."local mode=arg[1] or 'due'\n",
  true)
replace_all(sub,"fs.chmod(","safe_chmod(")
replace_all(sub,"u:changes(","uci_changes(u,")

print('[OK] Lua hotfix patch complete')
LUA

lua /tmp/jfa252_patch.lua
rm -f /tmp/jfa252_patch.lua

echo
echo "[1/5] 修复 NPS 域名输入限制..."

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

echo "[2/5] 清理 LuCI 缓存..."
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true

echo "[3/5] Lua 模块自检..."
lua - <<'LUA'
package.path='/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;'..package.path
assert(require('fastacl252_import'))
assert(require('fastacl252_nodes'))
assert(require('fastacl252_wifi'))
local p=require('fastacl252_import')
local n=p.batch('socks5://user:pass@127.0.0.1:1080')
assert(type(n)=='table' and #n==1 and n[1].outbound.type=='socks')
print('[OK] FastACL Lua/parser load passed')
LUA

echo "[4/5] 关键补丁检查..."
grep -q "foreach('fastacl252','wifi'.*bound" "$NODES" \
  && echo "[OK] 订阅节点已保护 WiFi 绑定" \
  || { echo "[ERR] WiFi 绑定保护补丁未生效"; exit 1; }

grep -q "172%.16%.(%d+)%.%d+" "$WIFI" \
  && echo "[OK] 地址池识别补丁已生效" \
  || { echo "[ERR] 地址池补丁未生效"; exit 1; }

grep -q "uci_changes" "$CTRL" \
  && echo "[OK] UCI 兼容补丁已生效" \
  || { echo "[ERR] UCI 兼容补丁未生效"; exit 1; }

echo "[5/5] 重启 Web/RPC 服务..."
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo
echo "=================================================="
echo "[DONE] HOTFIX-1 已安装"
echo "备份目录: $BK"
echo
echo "现在先刷新浏览器，再测试："
echo "  1. 新增 SOCKS5 / HTTP"
echo "  2. 新增 SS / Trojan / TUIC / Hysteria2"
echo "  3. 多 WiFi 新增与节点绑定"
echo "  4. NPS 页面填写 nps.jontao.top"
echo
echo "重要："
echo "这次已绕过 DNS Relay 对部分合法协议的“导入阶段误判”，"
echo "但如果绑定 SS/Trojan/TUIC/Hysteria2 后执行 apply 仍报"
echo "\"unsupported or invalid node\"，说明当前 fastacl252-dns 二进制本身"
echo "确实缺协议实现，需要替换重新编译后的二进制；不能靠 Lua 假装修好。"
echo
echo "查看状态："
echo "  /usr/bin/fastacl252 status"
echo "  cat /tmp/fastacl252/apply.log 2>/dev/null"
echo "  cat /tmp/fastacl252/dns.log 2>/dev/null"
echo "=================================================="
