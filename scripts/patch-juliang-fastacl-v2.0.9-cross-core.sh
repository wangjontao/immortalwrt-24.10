#!/bin/sh
set -eu
VERSION="2.0.9-hotfix"

TMP="/tmp/jfa-v209-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

extract_embedded() {
    tag="$1"; dst="$2"
    awk -v b="__JFA_BEGIN_${tag}__" -v e="__JFA_END_${tag}__" '
        $0 == b { on=1; next }
        $0 == e { found=1; exit }
        on { print }
        END { if (!found) exit 2 }
    ' "$0" > "$dst"
}

echo "=================================================="
echo " JuLiang FastACL $VERSION"
echo " cross-core chain: Xray/VLESS -> sing-box/SOCKS5"
echo "=================================================="

extract_embedded ENGINE "$TMP/juliang-fastacl"
extract_embedded RELAY "$TMP/juliang-fastacl-relay.lua"
extract_embedded CONTROLLER "$TMP/juliang_fastacl.lua"
extract_embedded LUCI_INSTALL "$TMP/juliang-fastacl-luci-install"

[ "$(head -n1 "$TMP/juliang-fastacl")" = "#!/bin/sh" ]
sh -n "$TMP/juliang-fastacl"
lua -e 'assert(loadfile("'"$TMP"'/juliang-fastacl-relay.lua"))'
lua -e 'assert(loadfile("'"$TMP"'/juliang_fastacl.lua"))'
sh -n "$TMP/juliang-fastacl-luci-install"

cp -af /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl.pre-v209 2>/dev/null || true
cp -af /usr/libexec/juliang-fastacl-relay.lua /usr/libexec/juliang-fastacl-relay.lua.pre-v209 2>/dev/null || true
cp -af /usr/lib/lua/luci/controller/juliang_fastacl.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua.pre-v209 2>/dev/null || true
cp -af /usr/bin/juliang-fastacl-luci-install /usr/bin/juliang-fastacl-luci-install.pre-v209 2>/dev/null || true

cp -af "$TMP/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP/juliang-fastacl-relay.lua" /usr/libexec/juliang-fastacl-relay.lua
cp -af "$TMP/juliang_fastacl.lua" /usr/lib/lua/luci/controller/juliang_fastacl.lua
cp -af "$TMP/juliang-fastacl-luci-install" /usr/bin/juliang-fastacl-luci-install
chmod 0755 /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl-luci-install
chmod 0644 /usr/libexec/juliang-fastacl-relay.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua

/usr/bin/juliang-fastacl-luci-install

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "[OK] FastACL $VERSION installed"
echo "[OK] Xray/VLESS preproxy can feed sing-box SOCKS/HTTP landing through local SOCKS 14101-14120"
echo "[OK] AP traffic still uses fixed 13101-13120; nftables and system DNS are untouched"
echo "[OK] Re-open PassWall2 -> 节点列表 -> 快速前置代理"
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

ensure_pre_section(){
  n="$1"; node="${2:-}"; sec="jfa_pre$n"; port=$((14100+n))
  type="$(uci -q get $APP.$sec 2>/dev/null || true)"
  [ "$type" = "socks" ] || { uci -q delete $APP.$sec >/dev/null 2>&1 || true; uci set $APP.$sec='socks'; }
  uci set $APP.$sec.enabled='0'
  uci set $APP.$sec.bind_local='1'
  uci set $APP.$sec.port="$port"
  uci set $APP.$sec.http_port='0'
  uci set $APP.$sec.log='1'
  uci set $APP.$sec.enable_autoswitch='0'
  [ -n "$node" ] && uci set $APP.$sec.node="$node" || true
}

start_preproxy(){
  n="$1"; pre="$2"; sec="jfa_pre$n"; port=$((14100+n))
  [ -n "$pre" ] || return 0
  [ "$(uci -q get $APP.$pre 2>/dev/null || true)" = "nodes" ] || {
    log "AP$n 前置节点不存在: $pre"
    return 1
  }

  ensure_pre_section "$n" "$pre"
  uci commit "$APP"

  pgrep -af '/tmp/etc/passwall2/bin' 2>/dev/null | awk -v P="$sec" '$0 ~ P {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
  pgrep -af "SOCKS_${sec}" 2>/dev/null | awk '!/pgrep/{print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true

  plog="$RUN_DIR/ap$n-preproxy-switch.log"
  : > "$plog"
  /usr/share/passwall2/app.sh socks_node_switch flag="$sec" new_node="$pre" >"$plog" 2>&1 || {
    log "AP$n 前置代理启动命令失败"
    return 1
  }

  i=0
  while [ "$i" -lt 60 ]; do
    (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && return 0
    sleep 0.1
    i=$((i+1))
  done

  {
    echo "AP$n preproxy SOCKS port $port not ready"
    echo "preproxy=$pre"
    echo "===== switch log ====="
    cat "$plog" 2>/dev/null || true
    echo "===== passwall2 socks log ====="
    cat "/tmp/etc/passwall2/SOCKS_${sec}.log" 2>/dev/null || true
    echo "===== generated config ====="
    cat "/tmp/etc/passwall2/SOCKS_${sec}.json" 2>/dev/null || true
  } > "$RUN_DIR/ap$n-preproxy-error.log"
  log "AP$n 前置代理端口 $port 未就绪，诊断：$RUN_DIR/ap$n-preproxy-error.log"
  return 1
}

kill_ap(){
  n="$1"; sec="jfa_ap$n"; psec="jfa_pre$n"
  pidf="$RUN_DIR/ap$n.pid"
  if [ -s "$pidf" ]; then kill "$(cat "$pidf")" >/dev/null 2>&1 || true; rm -f "$pidf"; fi
  for flag in "$sec" "$psec"; do
    pgrep -af '/tmp/etc/passwall2/bin' 2>/dev/null | awk -v P="$flag" '$0 ~ P {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
    pgrep -af "SOCKS_${flag}" 2>/dev/null | awk '!/pgrep/{print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
  done
  rm -f "$RUN_DIR/ap$n-direct.json" "$RUN_DIR/ap$n-preproxy-error.log" "$RUN_DIR/ap$n-preproxy-switch.log"
}

start_ap(){
  n="$1"; node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
  [ -n "$node" ] || { kill_ap "$n"; return 0; }
  [ "$(uci -q get $APP.$node 2>/dev/null || true)" = "nodes" ] || { log "AP$n 节点不存在: $node"; return 1; }
  ensure_socks_section "$n" "$node"
  uci commit "$APP"
  kill_ap "$n"
  type="$(uci -q get $APP.$node.type 2>/dev/null | tr 'A-Z' 'a-z')"
  proto="$(uci -q get $APP.$node.protocol 2>/dev/null | tr 'A-Z' 'a-z')"
  [ -n "$proto" ] || proto="$type"
  port=$((13100+n))
  chain="$(uci -q get $APP.$node.chain_proxy 2>/dev/null || true)"
  pre="$(uci -q get $APP.$node.preproxy_node 2>/dev/null || true)"

  # SOCKS/HTTP landing nodes get a deterministic cross-core bridge:
  # native preproxy core (Xray or sing-box) -> local SOCKS 141xx ->
  # sing-box landing SOCKS/HTTP -> local SOCKS 131xx.
  if [ "$proto" = "socks" ] || [ "$proto" = "http" ]; then
    preport="0"
    if [ "$chain" = "1" ] && [ -n "$pre" ]; then
      start_preproxy "$n" "$pre" || return 1
      preport=$((14100+n))
    fi
    cfg="$RUN_DIR/ap$n-direct.json"
    lua /usr/libexec/juliang-fastacl-relay.lua "$node" "$port" "$cfg" "$preport" || return 1
    sing-box check -c "$cfg" >"$RUN_DIR/ap$n-relay-check.log" 2>&1 || {
      log "AP$n SOCKS/HTTP 桥接配置检查失败"
      return 1
    }
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
    echo "node=$node type=$type protocol=$proto chain=$chain preproxy=$pre"
    echo "===== preproxy error ====="
    cat "$RUN_DIR/ap$n-preproxy-error.log" 2>/dev/null || true
    echo "===== relay check ====="
    cat "$RUN_DIR/ap$n-relay-check.log" 2>/dev/null || true
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
__JFA_BEGIN_RELAY__
local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local node = arg[1] or ""
local port = tonumber(arg[2] or "0")
local outfile = arg[3] or ""
local preproxy_port = tonumber(arg[4] or "0")
if node == "" or port == 0 or outfile == "" then os.exit(2) end
local n = uci:get_all("passwall2", node)
if not n then os.exit(3) end
local t = string.lower(n.protocol or n.type or "")
local out
if t == "socks" then
  out = {
    type = "socks", tag = "proxy", server = n.address, server_port = tonumber(n.port), version = "5",
    username = n.username, password = n.password
  }
elseif t == "http" then
  out = {
    type = "http", tag = "proxy", server = n.address, server_port = tonumber(n.port),
    username = n.username, password = n.password
  }
else
  os.exit(4)
end
local outbounds = {}
if preproxy_port and preproxy_port > 0 then
  outbounds[#outbounds + 1] = {
    type = "socks",
    tag = "preproxy",
    server = "127.0.0.1",
    server_port = preproxy_port,
    version = "5"
  }
  out.detour = "preproxy"
end
outbounds[#outbounds + 1] = out

local conf = {
  log = { level = "error" },
  inbounds = { { type = "socks", tag = "in", listen = "127.0.0.1", listen_port = port } },
  outbounds = outbounds,
  route = { final = "proxy" }
}
local f = assert(io.open(outfile, "w"))
f:write(jsonc.stringify(conf, true))
f:close()

__JFA_END_RELAY__
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

local function is_special_protocol(p)
    return p == "_shunt" or p == "_balancing" or p == "_urltest" or p == "_iface"
end

local function preproxy_options(uci, current)
    local out = {}
    uci:foreach("passwall2", "nodes", function(s)
        local id = s[".name"] or ""
        local proto = s.protocol or ""
        local chained = s.chain_proxy or ""
        if id ~= "" and id ~= current and not is_special_protocol(proto) and chained == "" then
            out[#out + 1] = {
                id = id,
                remarks = s.remarks or id,
                type = s.type or "",
                protocol = proto
            }
        end
    end)
    table.sort(out, function(a, b)
        return (a.remarks or "") < (b.remarks or "")
    end)
    return out
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

        local preproxy = {}
        uci:foreach("passwall2", "nodes", function(s)
            local id = s[".name"] or ""
            if id ~= "" then
                local pp = s.preproxy_node or ""
                preproxy[id] = {
                    enabled = (s.chain_proxy == "1" and pp ~= ""),
                    id = pp,
                    remarks = pp ~= "" and (uci:get("passwall2", pp, "remarks") or pp) or ""
                }
            end
        end)

        write_json({
            ok = true,
            engine = runtime_status(),
            map = map,
            ap_to_node = ap_to_node,
            wireless_labels = labels,
            ips = ips,
            preproxy = preproxy
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

    if action == "preproxy_options" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end
        write_json({
            ok = true,
            current = node_cfg.preproxy_node or "",
            enabled = node_cfg.chain_proxy == "1",
            options = preproxy_options(uci, node)
        })
        return
    end

    if action == "set_preproxy" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local pre = http.formvalue("preproxy") or ""
        if pre == node then
            write_json({ ok = false, error = "PREPROXY_SELF" })
            return
        end

        if pre ~= "" then
            local p = uci:get_all("passwall2", pre)
            if not p or p[".type"] ~= "nodes" or is_special_protocol(p.protocol or "") then
                write_json({ ok = false, error = "BAD_PREPROXY" })
                return
            end
            if (p.chain_proxy or "") ~= "" then
                write_json({ ok = false, error = "PREPROXY_ALREADY_CHAINED" })
                return
            end
        end

        local old_chain = node_cfg.chain_proxy or ""
        local old_pre = node_cfg.preproxy_node or ""

        if pre == "" then
            uci:delete("passwall2", node, "chain_proxy")
            uci:delete("passwall2", node, "preproxy_node")
        else
            uci:set("passwall2", node, "chain_proxy", "1")
            uci:set("passwall2", node, "preproxy_node", pre)
        end
        uci:commit("passwall2")

        local affected = {}
        local failed = nil
        for i = 1, 20 do
            if (uci:get("juliang_fastacl", "ap" .. i, "node") or "") == node then
                local ap = "AP" .. i
                local r = exec_json("/usr/bin/juliang-fastacl switch " .. ap .. " " .. util.shellquote(node))
                if not r.ok then
                    failed = r
                    break
                end
                affected[#affected + 1] = ap
            end
        end

        if failed then
            if old_chain == "" then
                uci:delete("passwall2", node, "chain_proxy")
            else
                uci:set("passwall2", node, "chain_proxy", old_chain)
            end
            if old_pre == "" then
                uci:delete("passwall2", node, "preproxy_node")
            else
                uci:set("passwall2", node, "preproxy_node", old_pre)
            end
            uci:commit("passwall2")
            for _, ap in ipairs(affected) do
                exec_json("/usr/bin/juliang-fastacl switch " .. ap .. " " .. util.shellquote(node))
            end
            write_json({
                ok = false,
                error = "PREPROXY_START_FAILED",
                detail = failed,
                rolled_back = true
            })
            return
        end

        local ip = ""
        if #affected > 0 then
            local sys = require "luci.sys"
            ip = (sys.exec("/usr/bin/juliang-fastacl probe " .. affected[1] .. " 2>/dev/null") or ""):gsub("%s+", "")
        end

        write_json({
            ok = true,
            action = "set_preproxy",
            node = node,
            preproxy = pre,
            preproxy_remarks = pre ~= "" and (uci:get("passwall2", pre, "remarks") or pre) or "",
            affected = affected,
            ip = ip
        })
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
__JFA_BEGIN_LUCI_INSTALL__
#!/bin/sh
set -eu

FILE="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"
CTRL="/usr/lib/lua/luci/controller/juliang_fastacl.lua"
MARKER="JULIANG_FASTACL_V209"

[ -f "$FILE" ] || {
    echo "[ERROR] PassWall2 node_list.htm not found: $FILE"
    exit 1
}
[ -f "$CTRL" ] || {
    echo "[ERROR] FastACL LuCI controller not found: $CTRL"
    exit 1
}

# Remove the old Quick-ACL UI cleanly. Its backup is the original PassWall2
# node list from before the experimental v1 patch.
if [ -f "$FILE.quick-acl.bak" ]; then
    cp -af "$FILE.quick-acl.bak" "$FILE"
    echo "[INFO] restored original PassWall2 node list from Quick-ACL backup"
fi

if grep -q "$MARKER" "$FILE"; then
    echo "[OK] FastACL v2 LuCI already installed"
    exit 0
fi

[ -f "$FILE.jfa-v2.bak" ] || cp -a "$FILE" "$FILE.jfa-v2.bak"

FILE="$FILE" lua <<'LUA_PATCH'
local file = assert(os.getenv("FILE"))
local f = assert(io.open(file, "r"))
local text = f:read("*a")
f:close()

local function replace_once(src, needle, repl, label)
    local s, e = src:find(needle, 1, true)
    assert(s, (label or "anchor") .. " missing")
    return src:sub(1, s - 1) .. repl .. src:sub(e + 1)
end

local top_old = 'local appname = api.appname\n'
local top_new = 'local appname = api.appname\nlocal jfa_url = require("luci.dispatcher").build_url("admin", "services", "juliang_fastacl")\n'
text = replace_once(text, top_old, top_new, "top anchor")

local js_anchor = '\n\tfunction to_edit_node(cbi_id) {'
local js = [=[

    // JULIANG_FASTACL_V209
    var jfaNode = "";
    var jfaMap = {};
    var jfaLabels = {};
    var jfaIps = {};
    var jfaEngine = "unknown";
    var jfaPreproxy = {};

    function jfa_label(ap) {
        return jfaLabels[ap] || ("无线" + ap);
    }

    function jfa_assignments(node) {
        return jfaMap[node] || [];
    }

    function jfa_update_buttons() {
        var buttons = document.getElementsByClassName("jfa-btn");
        for (var i = 0; i < buttons.length; i++) {
            var node = buttons[i].getAttribute("data-node-id");
            var aps = jfa_assignments(node);
            var labels = [];
            var ips = [];

            for (var j = 0; j < aps.length; j++) {
                labels.push(jfa_label(aps[j]));
                if (jfaIps[aps[j]])
                    ips.push(jfaIps[aps[j]]);
            }

            buttons[i].value = labels.length ? labels.join(",") : "分配无线";
            buttons[i].title = labels.length
                ? ("FastACL 已绑定：" + labels.join(", ") + (ips.length ? "\n出口 IP：" + ips.join(", ") : ""))
                : "FastACL：点击即时分配到无线 AP";

            var ipNode = document.getElementById("jfa_ip_" + node);
            if (ipNode) {
                ipNode.textContent = ips.join(" / ");
                ipNode.style.display = ips.length ? "inline-block" : "none";
            }
        }
    }

    function jfa_refresh_select() {
        var sel = document.getElementById("jfa_select");
        if (!sel) return;

        for (var i = 0; i < sel.options.length; i++) {
            var ap = sel.options[i].value;
            if (/^AP([1-9]|1[0-9]|20)$/.test(ap)) {
                var n = ap.replace("AP", "");
                sel.options[i].text = jfa_label(ap) + " · 172.16." + n + ".0/24";
            }
        }
    }

    function jfa_load_status(done) {
        XHR.get('<%=jfa_url%>', { action: 'status' }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                jfaMap = result.map || {};
                jfaLabels = result.wireless_labels || {};
                jfaIps = result.ips || {};
                jfaEngine = result.engine || "unknown";
                jfaPreproxy = result.preproxy || {};
                jfa_refresh_select();
                jfa_update_buttons();
            }
            if (done) done(result || {});
        });
    }

    function jfa_preproxy_current(node) {
        var p = jfaPreproxy[node] || {};
        return (p.enabled && p.remarks) ? p.remarks : "不使用";
    }

    function jfa_load_preproxy_options(node, done) {
        XHR.get('<%=jfa_url%>', {
            action: 'preproxy_options',
            node: node
        }, function(x, result) {
            var sel = document.getElementById("jfa_preproxy_select");
            if (sel) {
                while (sel.options.length) sel.remove(0);
                var o0 = document.createElement("option");
                o0.value = "";
                o0.text = "不使用前置代理（直连落地）";
                sel.add(o0);

                if (x && x.status == 200 && result && result.ok) {
                    var opts = result.options || [];
                    for (var i = 0; i < opts.length; i++) {
                        var o = document.createElement("option");
                        o.value = opts[i].id;
                        var core = opts[i].type || "";
                        var proto = opts[i].protocol || "";
                        var suffix = "";
                        if (core || proto)
                            suffix = " · " + core + (proto && proto.toLowerCase() != core.toLowerCase() ? ("/" + proto) : "");
                        o.text = opts[i].remarks + suffix;
                        sel.add(o);
                    }
                    sel.value = result.enabled ? (result.current || "") : "";
                }
            }
            if (done) done(result || {});
        });
    }

    function jfa_apply_preproxy() {
        if (!jfaNode) return;

        var sel = document.getElementById("jfa_preproxy_select");
        var pre = sel ? sel.value : "";
        var status = document.getElementById("jfa_preproxy_status");
        status.innerText = pre ? "正在切换前置代理…" : "正在关闭前置代理…";
        status.style.color = "#606266";

        XHR.get('<%=jfa_url%>', {
            action: 'set_preproxy',
            node: jfaNode,
            preproxy: pre
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                var msg = pre ? ("✓ 前置已切换：" + (result.preproxy_remarks || pre)) : "✓ 已关闭前置代理";
                if (result.affected && result.affected.length)
                    msg += "；即时刷新 " + result.affected.join(",");
                if (result.ip && result.ip != "-")
                    msg += "；出口 IP " + result.ip;
                status.innerText = msg;
                status.style.color = "#159957";
                jfa_load_status(function() {
                    document.getElementById("jfa_preproxy_current").innerText = jfa_preproxy_current(jfaNode);
                });
            } else {
                status.innerText = "前置切换失败：" + ((result && result.error) || "ERROR");
                status.style.color = "#e43f3b";
            }
        });
    }

    function jfa_open(cbi_id) {
        jfaNode = cbi_id;
        var remarks = (document.getElementById("cbid.<%=appname%>." + cbi_id + ".remarks") || {}).value || cbi_id;
        document.getElementById("jfa_node_name").innerText = remarks;
        document.getElementById("jfa_div").style.display = "block";
        document.getElementById("jfa_status").innerText = "";

        jfa_load_status(function() {
            var aps = jfa_assignments(cbi_id);
            var labels = [];
            for (var i = 0; i < aps.length; i++) labels.push(jfa_label(aps[i]));

            document.getElementById("jfa_current").innerText = labels.length ? labels.join(", ") : "未分配";
            document.getElementById("jfa_engine").innerText =
                jfaEngine == "running" ? "FastACL：运行中" : "FastACL：未运行";
            document.getElementById("jfa_engine").style.color =
                jfaEngine == "running" ? "#159957" : "#e43f3b";
            document.getElementById("jfa_preproxy_current").innerText = jfa_preproxy_current(cbi_id);
            document.getElementById("jfa_preproxy_status").innerText = "";
            jfa_load_preproxy_options(cbi_id);

            if (aps.length && /^AP([1-9]|1[0-9]|20)$/.test(aps[0]))
                document.getElementById("jfa_select").value = aps[0];
        });
    }

    function jfa_close() {
        document.getElementById("jfa_div").style.display = "none";
        jfaNode = "";
    }

    function jfa_assign() {
        if (!jfaNode) return;

        var ap = document.getElementById("jfa_select").value;
        if (!ap) {
            alert("请选择无线 AP");
            return;
        }

        var exclusive = document.getElementById("jfa_exclusive").checked ? "1" : "0";
        var status = document.getElementById("jfa_status");
        status.innerText = "正在即时切换 " + jfa_label(ap) + "…";

        XHR.get('<%=jfa_url%>', {
            action: 'assign',
            node: jfaNode,
            ap: ap,
            exclusive: exclusive
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                var msg = "✓ " + jfa_label(ap) + " 已切换";
                if (result.ip && result.ip != "-")
                    msg += "；出口 IP " + result.ip;
                if (result.seconds != null)
                    msg += "；耗时 " + result.seconds + "s";
                status.innerText = msg;
                status.style.color = "#159957";

                jfa_load_status(function() {
                    var aps = jfa_assignments(jfaNode);
                    var labels = [];
                    for (var i = 0; i < aps.length; i++) labels.push(jfa_label(aps[i]));
                    document.getElementById("jfa_current").innerText = labels.length ? labels.join(", ") : "未分配";
                });
            } else {
                status.innerText = "切换失败：" + ((result && result.error) || "ERROR");
                status.style.color = "#e43f3b";
            }
        });
    }

    function jfa_clear() {
        if (!jfaNode) return;
        if (!confirm("解除这个节点当前绑定的无线 AP？")) return;

        var status = document.getElementById("jfa_status");
        status.innerText = "正在解除…";

        XHR.get('<%=jfa_url%>', {
            action: 'clear_node',
            node: jfaNode
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                status.innerText = "✓ 已解除绑定";
                status.style.color = "#159957";
                jfa_load_status(function() {
                    document.getElementById("jfa_current").innerText = "未分配";
                });
            } else {
                status.innerText = "解除失败：" + ((result && result.error) || "ERROR");
                status.style.color = "#e43f3b";
            }
        });
    }
]=]
text = replace_once(text, js_anchor, js .. js_anchor, "JS anchor")

local copy_anchor = '\n\t\t\t\t<input class="btn cbi-button cbi-button-add" type="button" value="<%:Copy%>" onclick="copy_node(\'{{id}}\')"/>'
local button = [=[
				<input class="btn cbi-button cbi-button-edit jfa-btn" type="button" id="jfa_{{id}}" data-node-id="{{id}}" value="分配无线" onclick="jfa_open('{{id}}')" title="FastACL 即时分配无线"/>
				<span id="jfa_ip_{{id}}" style="display:none;margin-left:5px;color:#159957;font-weight:600;font-size:12px;white-space:nowrap;"></span>
]=]
text = replace_once(text, copy_anchor, "\n" .. button .. copy_anchor, "button anchor")

local ping_call = '\n\t\t\tpingAllNodes();'
text = replace_once(text, ping_call, ping_call .. '\n\t\t\tjfa_load_status();', "load-status anchor")

local modal = [=[

<div id="jfa_div" style="display:none;width:35rem;max-width:94vw;position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);z-index:220;padding:22px;text-align:center;background:var(--main-bg-color,#fff);border-radius:12px;box-shadow:0 12px 42px rgba(0,0,0,.38);">
    <div style="font-size:17px;font-weight:700;margin-bottom:7px;">FastACL 即时分配无线</div>
    <div style="font-size:12px;opacity:.72;margin-bottom:13px;">不重建 nftables · 不重启系统 DNS · 只切换当前 AP 节点</div>
    <div style="margin:7px 0;">节点：<strong id="jfa_node_name" style="color:#159957"></strong></div>
    <div style="margin:7px 0;">当前：<strong id="jfa_current" style="color:#e6a23c">读取中…</strong></div>
    <div id="jfa_engine" style="margin:7px 0;font-weight:600;">FastACL：检测中…</div>
    <div style="margin:13px 0;">
        <select id="jfa_select" class="cbi-input-select" style="min-width:240px;">
            <option value="">请选择无线 AP</option>
            <option value="AP1">无线AP1 · 172.16.1.0/24</option>
            <option value="AP2">无线AP2 · 172.16.2.0/24</option>
            <option value="AP3">无线AP3 · 172.16.3.0/24</option>
            <option value="AP4">无线AP4 · 172.16.4.0/24</option>
            <option value="AP5">无线AP5 · 172.16.5.0/24</option>
            <option value="AP6">无线AP6 · 172.16.6.0/24</option>
            <option value="AP7">无线AP7 · 172.16.7.0/24</option>
            <option value="AP8">无线AP8 · 172.16.8.0/24</option>
            <option value="AP9">无线AP9 · 172.16.9.0/24</option>
            <option value="AP10">无线AP10 · 172.16.10.0/24</option>
            <option value="AP11">无线AP11 · 172.16.11.0/24</option>
            <option value="AP12">无线AP12 · 172.16.12.0/24</option>
            <option value="AP13">无线AP13 · 172.16.13.0/24</option>
            <option value="AP14">无线AP14 · 172.16.14.0/24</option>
            <option value="AP15">无线AP15 · 172.16.15.0/24</option>
            <option value="AP16">无线AP16 · 172.16.16.0/24</option>
            <option value="AP17">无线AP17 · 172.16.17.0/24</option>
            <option value="AP18">无线AP18 · 172.16.18.0/24</option>
            <option value="AP19">无线AP19 · 172.16.19.0/24</option>
            <option value="AP20">无线AP20 · 172.16.20.0/24</option>
        </select>
    </div>
    <div style="margin:16px 0 8px;padding:12px;border-top:1px solid rgba(128,128,128,.22);">
        <div style="font-weight:700;margin-bottom:8px;">快速前置代理</div>
        <div style="font-size:12px;opacity:.72;margin-bottom:9px;">支持跨内核：Xray/VLESS 前置 → sing-box/SOCKS5 落地；只切当前 AP，本地桥接端口 141xx</div>
        <div style="margin:6px 0;">当前前置：<strong id="jfa_preproxy_current" style="color:#e6a23c">读取中…</strong></div>
        <div style="display:flex;justify-content:center;gap:8px;flex-wrap:wrap;align-items:center;">
            <select id="jfa_preproxy_select" class="cbi-input-select" style="min-width:260px;">
                <option value="">不使用前置代理（直连落地）</option>
            </select>
            <input class="btn cbi-button cbi-button-apply" type="button" value="应用前置" onclick="jfa_apply_preproxy()"/>
        </div>
        <div id="jfa_preproxy_status" style="min-height:22px;margin-top:8px;font-weight:600;"></div>
    </div>
    <label style="display:block;margin:10px 0;">
        <input id="jfa_exclusive" type="checkbox" checked="checked"/>
        唯一绑定：同一个节点只分配给一个无线 AP
    </label>
    <div id="jfa_status" style="min-height:24px;margin:9px 0;font-weight:600;color:#159957;"></div>
    <div style="display:flex;justify-content:center;gap:8px;flex-wrap:wrap;">
        <input class="btn cbi-button cbi-button-apply" type="button" value="立即切换" onclick="jfa_assign()"/>
        <input class="btn cbi-button cbi-button-remove" type="button" value="解除绑定" onclick="jfa_clear()"/>
        <input class="btn cbi-button cbi-button-edit" type="button" value="关闭" onclick="jfa_close()"/>
    </div>
</div>
]=]

text = text .. modal

local out = assert(io.open(file .. ".new", "w"))
out:write(text)
out:close()
os.rename(file .. ".new", file)
LUA_PATCH

grep -q "$MARKER" "$FILE"
grep -q 'jfa-btn' "$FILE"
grep -q 'FastACL 即时分配无线' "$FILE"
grep -q '快速前置代理' "$FILE"

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "[OK] FastACL v2 LuCI installed"
echo "PassWall2 -> 节点列表：支持即时分配无线 + 跨内核快速前置（Xray/VLESS -> sing-box/SOCKS5），并显示出口 IP。"

__JFA_END_LUCI_INSTALL__
