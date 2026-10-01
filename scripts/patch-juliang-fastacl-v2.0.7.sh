#!/bin/sh
set -eu
VERSION="2.0.7-hotfix"

TMP="/tmp/jfa-hotfix-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

extract_embedded() {
    tag="$1"
    dst="$2"
    awk -v b="__JFA_BEGIN_${tag}__" -v e="__JFA_END_${tag}__" '
        $0 == b { on=1; next }
        $0 == e { found=1; exit }
        on { print }
        END { if (!found) exit 2 }
    ' "$0" > "$dst"
}

echo "=================================================="
echo " JuLiang FastACL $VERSION"
echo " unique binding: transactional MOVE + diagnostics"
echo "=================================================="

extract_embedded ENGINE "$TMP/juliang-fastacl"
extract_embedded CONTROLLER "$TMP/juliang_fastacl.lua"

[ "$(head -n1 "$TMP/juliang-fastacl")" = "#!/bin/sh" ]
sh -n "$TMP/juliang-fastacl"
lua -e 'assert(loadfile("'"$TMP"'/juliang_fastacl.lua"))'

cp -af /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl.pre-v207 2>/dev/null || true
cp -af /usr/lib/lua/luci/controller/juliang_fastacl.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua.pre-v207 2>/dev/null || true

cp -af "$TMP/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP/juliang_fastacl.lua" /usr/lib/lua/luci/controller/juliang_fastacl.lua
chmod 0755 /usr/bin/juliang-fastacl
chmod 0644 /usr/lib/lua/luci/controller/juliang_fastacl.lua

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "[OK] FastACL $VERSION installed"
echo "[OK] no nftables rebuild / no dnsmasq restart / no PassWall2 restart"
echo "[OK] unique binding now MOVE: old AP stops first; target starts; failure restores old AP"
exit 0

__JFA_BEGIN_ENGINE__
#!/bin/sh
set -u
CFG="juliang_fastacl"
APP="passwall2"
STATE_DIR="/etc/juliang-fastacl"
RUN_DIR="/tmp/juliang-fastacl"
ROUTER_CFG="$STATE_DIR/router.json"
MARK_HEX="0x66"
ROUTE_TABLE="100"
mkdir -p "$STATE_DIR" "$RUN_DIR" /tmp/etc/passwall2/bin /tmp/etc/passwall2/script_func /tmp/etc/passwall2/acl /tmp/etc/passwall2/route /tmp/etc/passwall2/iface /tmp/log /tmp/lock 2>/dev/null || true
touch /tmp/etc/passwall2/var

log(){ echo "[JFA] $*"; }

ap_num(){
  case "$1" in
    AP[1-9]) echo "${1#AP}" ;;
    AP1[0-9]|AP20) echo "${1#AP}" ;;
    *) return 1 ;;
  esac
}

find_acl_section(){
  n="$1"; subnet="172.16.$n.0/24"
  uci -q show "$APP" | awk -F'[.=]' -v A="AP$n" -v S="$subnet" '
    /\.remarks=/{gsub("\047", "", $0); if ($0 ~ "=" A "$") print $2}
    /\.sources=/{gsub("\047", "", $0); if ($0 ~ "=" S "$") print $2}
  ' | head -n1
}

ensure_socks_section(){
  n="$1"; node="${2:-}"; sec="jfa_ap$n"; port=$((13100+n))
  type="$(uci -q get $APP.$sec 2>/dev/null || true)"
  [ "$type" = "socks" ] || { uci -q delete $APP.$sec; uci set $APP.$sec='socks'; }
  uci set $APP.$sec.enabled='0'
  uci set $APP.$sec.bind_local='1'
  uci set $APP.$sec.port="$port"
  uci set $APP.$sec.http_port='0'
  uci set $APP.$sec.log='1'
  uci set $APP.$sec.enable_autoswitch='0'
  [ -n "$node" ] && uci set $APP.$sec.node="$node" || true
}

kill_ap(){
  n="$1"; sec="jfa_ap$n"
  pidf="$RUN_DIR/ap$n.pid"
  if [ -s "$pidf" ]; then kill "$(cat "$pidf")" >/dev/null 2>&1 || true; rm -f "$pidf"; fi
  pgrep -af '/tmp/etc/passwall2/bin' 2>/dev/null | awk -v P="$sec" '$0 ~ P {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
  pgrep -af "SOCKS_${sec}" 2>/dev/null | awk '!/pgrep/{print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
  rm -f "$RUN_DIR/ap$n-direct.json"
}

start_ap(){
  n="$1"; node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
  [ -n "$node" ] || { kill_ap "$n"; return 0; }
  [ "$(uci -q get $APP.$node 2>/dev/null || true)" = "nodes" ] || { log "AP$n 节点不存在: $node"; return 1; }
  ensure_socks_section "$n" "$node"
  uci commit "$APP"
  kill_ap "$n"
  type="$(uci -q get $APP.$node.type 2>/dev/null | tr 'A-Z' 'a-z')"
  port=$((13100+n))
  if [ "$type" = "socks" ] || [ "$type" = "http" ]; then
    cfg="$RUN_DIR/ap$n-direct.json"
    lua /usr/libexec/juliang-fastacl-relay.lua "$node" "$port" "$cfg" || return 1
    sing-box check -c "$cfg" >/dev/null 2>&1 || { log "AP$n 直连代理配置检查失败"; return 1; }
    sing-box run -c "$cfg" >"$RUN_DIR/ap$n.log" 2>&1 &
    echo $! > "$RUN_DIR/ap$n.pid"
  else
    swlog="$RUN_DIR/ap$n-switch.log"
    : > "$swlog"
    /usr/share/passwall2/app.sh socks_node_switch flag="jfa_ap$n" new_node="$node" >"$swlog" 2>&1 || {
      log "AP$n PassWall2 socks_node_switch 返回失败"
      return 1
    }
  fi
  i=0
  while [ "$i" -lt 50 ]; do
    (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && return 0
    sleep 0.1; i=$((i+1))
  done
  {
    echo "AP$n local SOCKS port $port not ready"
    echo "node=$node type=$type"
    echo "===== switch log ====="
    cat "$RUN_DIR/ap$n-switch.log" 2>/dev/null || true
    echo "===== passwall2 socks log ====="
    cat "/tmp/etc/passwall2/SOCKS_jfa_ap$n.log" 2>/dev/null || true
    echo "===== generated config ====="
    cat "/tmp/etc/passwall2/SOCKS_jfa_ap$n.json" 2>/dev/null || true
  } > "$RUN_DIR/ap$n-start-error.log"
  log "AP$n 本地 SOCKS 端口 $port 未就绪，诊断：$RUN_DIR/ap$n-start-error.log"
  return 1
}

probe_ap(){
  n="$1"; port=$((13100+n))
  ip="$(curl -4 -fsS --connect-timeout 3 --max-time 6 --socks5-hostname "127.0.0.1:$port" https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="-"
  echo "$ip"
}

write_router(){
  lua /usr/libexec/juliang-fastacl-router.lua > "$ROUTER_CFG" || return 1
  sing-box check -c "$ROUTER_CFG" >/tmp/jfa-router-check.log 2>&1 || { cat /tmp/jfa-router-check.log; return 1; }
}

firewall(){
  TPROXY_PORT="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  nft list table inet juliang_fastacl >/dev/null 2>&1 && nft delete table inet juliang_fastacl >/dev/null 2>&1 || true
  cat > "$RUN_DIR/rules.nft" <<EOF
 table inet juliang_fastacl {
   set ap_sources {
     type ipv4_addr
     flags interval
     elements = { 172.16.1.0/24, 172.16.2.0/24, 172.16.3.0/24, 172.16.4.0/24, 172.16.5.0/24, 172.16.6.0/24, 172.16.7.0/24, 172.16.8.0/24, 172.16.9.0/24, 172.16.10.0/24, 172.16.11.0/24, 172.16.12.0/24, 172.16.13.0/24, 172.16.14.0/24, 172.16.15.0/24, 172.16.16.0/24, 172.16.17.0/24, 172.16.18.0/24, 172.16.19.0/24, 172.16.20.0/24 }
   }
   set local_dst {
     type ipv4_addr
     flags interval
     elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
   }
   chain prerouting {
     type filter hook prerouting priority mangle; policy accept;
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst return
     ip saddr @ap_sources meta l4proto { tcp, udp } tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
   }
 }
EOF
  nft -c -f "$RUN_DIR/rules.nft" || return 1
  nft -f "$RUN_DIR/rules.nft" || return 1
  ip rule del fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000 >/dev/null 2>&1 || true
  ip rule add fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000
  ip route replace local 0.0.0.0/0 dev lo table "$ROUTE_TABLE"
}

firewall_check(){
  TPROXY_PORT="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  cat > "$RUN_DIR/rules-check.nft" <<EOF
 table inet juliang_fastacl_check {
   set ap_sources {
     type ipv4_addr
     flags interval
     elements = { 172.16.1.0/24, 172.16.2.0/24, 172.16.3.0/24, 172.16.4.0/24, 172.16.5.0/24, 172.16.6.0/24, 172.16.7.0/24, 172.16.8.0/24, 172.16.9.0/24, 172.16.10.0/24, 172.16.11.0/24, 172.16.12.0/24, 172.16.13.0/24, 172.16.14.0/24, 172.16.15.0/24, 172.16.16.0/24, 172.16.17.0/24, 172.16.18.0/24, 172.16.19.0/24, 172.16.20.0/24 }
   }
   set local_dst {
     type ipv4_addr
     flags interval
     elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
   }
   chain prerouting {
     type filter hook prerouting priority mangle; policy accept;
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst return
     ip saddr @ap_sources meta l4proto { tcp, udp } tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
   }
 }
EOF
  nft -c -f "$RUN_DIR/rules-check.nft"
}

start_router(){
  write_router || return 1
  [ -s "$RUN_DIR/router.pid" ] && kill "$(cat "$RUN_DIR/router.pid")" >/dev/null 2>&1 || true
  sing-box run -c "$ROUTER_CFG" >"$RUN_DIR/router.log" 2>&1 &
  echo $! > "$RUN_DIR/router.pid"
  sleep 0.3
  kill -0 "$(cat "$RUN_DIR/router.pid")" >/dev/null 2>&1 || { cat "$RUN_DIR/router.log"; return 1; }
}

stop_router(){
  if [ -s "$RUN_DIR/router.pid" ]; then kill "$(cat "$RUN_DIR/router.pid")" >/dev/null 2>&1 || true; rm -f "$RUN_DIR/router.pid"; fi
}

start_all(){
  n=1; while [ "$n" -le 20 ]; do start_ap "$n" || true; n=$((n+1)); done
  start_router || return 1
  firewall || return 1
}

stop_all(){
  n=1; while [ "$n" -le 20 ]; do kill_ap "$n"; n=$((n+1)); done
  stop_router
  nft list table inet juliang_fastacl >/dev/null 2>&1 && nft delete table inet juliang_fastacl >/dev/null 2>&1 || true
  ip rule del fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000 >/dev/null 2>&1 || true
  ip route flush table "$ROUTE_TABLE" >/dev/null 2>&1 || true
}

switch_node(){
  ap="$1"; node="$2"; n="$(ap_num "$ap")" || { echo '{"ok":false,"error":"BAD_AP"}'; return 2; }
  [ "$(uci -q get $APP.$node 2>/dev/null || true)" = "nodes" ] || { echo '{"ok":false,"error":"BAD_NODE"}'; return 3; }

  old="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
  acl="$(find_acl_section "$n")"
  old_acl_node=""
  [ -n "$acl" ] && old_acl_node="$(uci -q get $APP.$acl.node 2>/dev/null || true)"

  uci set $CFG.ap$n.node="$node"
  ensure_socks_section "$n" "$node"
  [ -n "$acl" ] && { uci set $APP.$acl.node="$node"; uci set $APP.$acl.enabled='1'; }
  uci commit "$CFG"; uci commit "$APP"

  t0="$(date +%s)"
  if start_ap "$n"; then
    ip="$(probe_ap "$n")"
    printf '%s\n' "$ip" > "$RUN_DIR/ap$n.ip"
    t1="$(date +%s)"; sec=$((t1-t0))
    remark="$(uci -q get $APP.$node.remarks 2>/dev/null || echo "$node")"
    printf '{"ok":true,"ap":"AP%s","node":"%s","remark":"%s","ip":"%s","seconds":%s}\n' "$n" "$node" "$(echo "$remark" | sed 's/"/\\"/g')" "$ip" "$sec"
  else
    if [ -n "$old" ]; then
      uci set $CFG.ap$n.node="$old"
      ensure_socks_section "$n" "$old"
    else
      uci -q delete $CFG.ap$n.node
      uci -q delete $APP.jfa_ap$n.node
    fi
    if [ -n "$acl" ]; then
      if [ -n "$old_acl_node" ]; then uci set $APP.$acl.node="$old_acl_node"; else uci -q delete $APP.$acl.node; fi
    fi
    uci commit "$CFG"; uci commit "$APP"
    [ -n "$old" ] && start_ap "$n" >/dev/null 2>&1 || kill_ap "$n"
    printf '{"ok":false,"ap":"AP%s","node":"%s","error":"NODE_START_FAILED","rolled_back":true}\n' "$n" "$node"
    return 4
  fi
}

move_node(){
  ap="$1"; node="$2"; n="$(ap_num "$ap")" || { echo '{"ok":false,"error":"BAD_AP"}'; return 2; }
  [ "$(uci -q get $APP.$node 2>/dev/null || true)" = "nodes" ] || { echo '{"ok":false,"error":"BAD_NODE"}'; return 3; }

  sources=""
  i=1
  while [ "$i" -le 20 ]; do
    if [ "$i" -ne "$n" ] && [ "$(uci -q get $CFG.ap$i.node 2>/dev/null || true)" = "$node" ]; then
      sources="$sources $i"
    fi
    i=$((i+1))
  done

  # Unique-binding means MOVE, not duplicate-then-delete. Stop old AP relay(s)
  # first to avoid protocol/plugin/shared-resource collisions, but keep UCI
  # mappings until the target is confirmed healthy so rollback is possible.
  for i in $sources; do
    kill_ap "$i"
  done

  if result="$(switch_node "$ap" "$node")"; then
    for i in $sources; do
      uci -q delete $CFG.ap$i.node
      uci -q delete $APP.jfa_ap$i.node
      old_acl="$(find_acl_section "$i")"
      [ -n "$old_acl" ] && uci -q delete $APP.$old_acl.node
      rm -f "$RUN_DIR/ap$i.ip"
    done
    uci commit "$CFG"
    uci commit "$APP"
    printf '%s\n' "$result"
    return 0
  fi

  # Target failed: source UCI mappings were intentionally left intact; restart
  # them so the previous working wireless AP is restored.
  for i in $sources; do
    start_ap "$i" >/dev/null 2>&1 || true
  done
  printf '{"ok":false,"ap":"%s","node":"%s","error":"NODE_START_FAILED","rolled_back_sources":true,"diagnostic":"%s"}\n' "$ap" "$node" "$RUN_DIR/ap$n-start-error.log"
  return 4
}

clear_ap(){
  ap="$1"; n="$(ap_num "$ap")" || { echo '{"ok":false,"error":"BAD_AP"}'; return 2; }
  old="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
  uci -q delete $CFG.ap$n.node
  ensure_socks_section "$n" ""
  uci -q delete $APP.jfa_ap$n.node
  acl="$(find_acl_section "$n")"
  [ -n "$acl" ] && uci -q delete $APP.$acl.node
  uci commit "$CFG"; uci commit "$APP"
  kill_ap "$n"
  rm -f "$RUN_DIR/ap$n.ip"
  printf '{"ok":true,"ap":"AP%s","old_node":"%s"}\n' "$n" "$old"
}

status(){
  echo "JuLiang FastACL"
  echo "router: $([ -s "$RUN_DIR/router.pid" ] && kill -0 "$(cat "$RUN_DIR/router.pid")" 2>/dev/null && echo running || echo stopped)"
  nft list table inet juliang_fastacl >/dev/null 2>&1 && echo "nftables: loaded" || echo "nftables: missing"
  n=1; while [ "$n" -le 20 ]; do
    node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"; port=$((13100+n))
    if [ -n "$node" ]; then
      remark="$(uci -q get $APP.$node.remarks 2>/dev/null || echo "$node")"
      listen="no"; (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && listen="yes"
      echo "AP$n -> $remark | socks:$port listen:$listen"
    fi
    n=$((n+1))
  done
}

case "${1:-}" in
  start) start_all ;;
  stop) stop_all ;;
  restart) stop_all; start_all ;;
  firewall) firewall ;;
  firewall-check) firewall_check ;;
  switch) [ $# -eq 3 ] || exit 2; switch_node "$2" "$3" ;;
  move) [ $# -eq 3 ] || exit 2; move_node "$2" "$3" ;;
  clear) [ $# -eq 2 ] || exit 2; clear_ap "$2" ;;
  probe) n="$(ap_num "$2")" || exit 2; probe_ap "$n" ;;
  status) status ;;
  *) echo "Usage: juliang-fastacl {start|stop|restart|firewall|firewall-check|switch AP1 nodeid|move AP1 nodeid|clear AP1|probe AP1|status}"; exit 1 ;;
esac
__JFA_END_ENGINE__
__JFA_BEGIN_CONTROLLER__
module("luci.controller.juliang_fastacl", package.seeall)

function index()
    local page = entry({"admin", "services", "juliang_fastacl"}, call("handle"), nil)
    page.leaf = true
    page.dependent = false
end

local function write_json(t)
    local http = require "luci.http"
    local jsonc = require "luci.jsonc"
    http.prepare_content("application/json")
    http.write(jsonc.stringify(t))
end

local function ap_number(v)
    local n = tonumber((v or ""):match("^AP(%d+)$"))
    if n and n >= 1 and n <= 20 then return n end
    return nil
end

local function wireless_labels(uci)
    local labels = {}
    for i = 1, 20 do
        labels["AP" .. i] = "无线AP" .. i
    end

    uci:foreach("wireless", "wifi-iface", function(s)
        local network = s.network or ""
        local ssid = s.ssid or ""
        if ssid ~= "" then
            for i = 1, 20 do
                local tk = "tk" .. i
                if (" " .. network .. " "):find(" " .. tk .. " ", 1, true) then
                    labels["AP" .. i] = "无线" .. ssid
                end
            end
        end
    end)

    return labels
end

local function read_ip(n)
    local f = io.open("/tmp/juliang-fastacl/ap" .. n .. ".ip", "r")
    if not f then return "" end
    local ip = (f:read("*l") or ""):gsub("%s+", "")
    f:close()
    return ip
end

local function runtime_status()
    local f = io.open("/tmp/juliang-fastacl/router.pid", "r")
    if not f then return "stopped" end
    local pid = tonumber(f:read("*l") or "")
    f:close()
    if not pid then return "stopped" end
    local sys = require "luci.sys"
    return sys.call("kill -0 " .. pid .. " >/dev/null 2>&1") == 0 and "running" or "stopped"
end

local function exec_json(cmd)
    local sys = require "luci.sys"
    local jsonc = require "luci.jsonc"
    local raw = sys.exec(cmd .. " 2>/tmp/juliang-fastacl/luci-error.log")
    local ok, data = pcall(jsonc.parse, raw or "")
    if ok and type(data) == "table" then
        return data
    end
    return {
        ok = false,
        error = "ENGINE_ERROR",
        detail = raw or ""
    }
end

function handle()
    local http = require "luci.http"
    local util = require "luci.util"
    local uci = require("luci.model.uci").cursor()

    local action = http.formvalue("action") or "status"

    if action == "status" then
        local map = {}
        local ap_to_node = {}
        local ips = {}
        local labels = wireless_labels(uci)

        for i = 1, 20 do
            local ap = "AP" .. i
            local node = uci:get("juliang_fastacl", "ap" .. i, "node") or ""
            ap_to_node[ap] = node
            ips[ap] = read_ip(i)
            if node ~= "" then
                map[node] = map[node] or {}
                map[node][#map[node] + 1] = ap
            end
        end

        write_json({
            ok = true,
            engine = runtime_status(),
            map = map,
            ap_to_node = ap_to_node,
            wireless_labels = labels,
            ips = ips
        })
        return
    end

    local node = http.formvalue("node") or ""
    local node_cfg = node ~= "" and uci:get_all("passwall2", node) or nil

    if action == "assign" then
        local ap = http.formvalue("ap") or ""
        local n = ap_number(ap)
        if not n then
            write_json({ ok = false, error = "BAD_AP" })
            return
        end
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local exclusive = http.formvalue("exclusive") ~= "0"
        local verb = exclusive and "move" or "switch"
        local result = exec_json(
            "/usr/bin/juliang-fastacl " .. verb .. " " ..
            ap .. " " .. util.shellquote(node)
        )
        write_json(result)
        return
    end

    if action == "clear_node" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local cleared = {}
        for i = 1, 20 do
            if (uci:get("juliang_fastacl", "ap" .. i, "node") or "") == node then
                local ap = "AP" .. i
                local r = exec_json("/usr/bin/juliang-fastacl clear " .. ap)
                if r.ok then cleared[#cleared + 1] = ap end
            end
        end

        write_json({ ok = true, action = "clear_node", node = node, cleared = cleared })
        return
    end

    if action == "probe" then
        local ap = http.formvalue("ap") or ""
        local n = ap_number(ap)
        if not n then
            write_json({ ok = false, error = "BAD_AP" })
            return
        end
        local sys = require "luci.sys"
        local ip = (sys.exec("/usr/bin/juliang-fastacl probe " .. ap .. " 2>/dev/null") or ""):gsub("%s+", "")
        write_json({ ok = ip ~= "" and ip ~= "-", ap = ap, ip = ip })
        return
    end

    write_json({ ok = false, error = "BAD_ACTION" })
end

__JFA_END_CONTROLLER__
