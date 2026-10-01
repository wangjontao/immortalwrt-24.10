#!/bin/sh
set -eu
VERSION="2.2.3-hotfix"
TMP="/tmp/jfa-v223-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

extract_embedded(){
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
echo " fix: AP probe success but client still follows main PassWall2"
echo "=================================================="

extract_embedded ENGINE "$TMP/juliang-fastacl"
extract_embedded CONTROLLER "$TMP/juliang_fastacl.lua"
sh -n "$TMP/juliang-fastacl"
lua -e 'assert(loadfile("'"$TMP"'/juliang_fastacl.lua"))'

cp -af /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl.pre-v223 2>/dev/null || true
cp -af /usr/lib/lua/luci/controller/juliang_fastacl.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua.pre-v223 2>/dev/null || true
cp -af "$TMP/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP/juliang_fastacl.lua" /usr/lib/lua/luci/controller/juliang_fastacl.lua
chmod 0755 /usr/bin/juliang-fastacl
chmod 0644 /usr/lib/lua/luci/controller/juliang_fastacl.lua

# PassWall2 stays only as node database/UI. Disable its transparent dataplane.
uci -q set passwall2.@global[0].enabled=0
uci -q set passwall2.@global[0].acl_enable=0
uci -q set passwall2.@global[0].socks_enabled=0
uci commit passwall2

echo "[INFO] repairing FastACL dataplane..."
if /usr/bin/juliang-fastacl repair >/tmp/juliang-fastacl/v223-repair.log 2>&1; then
  echo "[OK] FastACL dataplane repaired"
else
  echo "[ERROR] FastACL dataplane repair failed"
  cat /tmp/juliang-fastacl/v223-repair.log 2>/dev/null || true
  exit 1
fi

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "===== FastACL status ====="
/usr/bin/juliang-fastacl status
echo "===== AP1 local relay exit ====="
/usr/bin/juliang-fastacl probe AP1 2>/dev/null || true
echo "===== stale PassWall2 dataplane ====="
nft list table inet passwall2 >/dev/null 2>&1 && echo "WARNING: inet passwall2 still exists" || echo "OK: inet passwall2 removed"
pgrep -af "/tmp/etc/passwall2/acl/default/global.json" 2>/dev/null || echo "OK: old global proxy process absent"
echo "===== FastACL policy ====="
ip rule show | grep -E "0x66|0x1" || true
ip route show table 100 || true
echo "[OK] every node switch now also verifies/repairs router+nft+policy dataplane"
echo "[OK] LuCI FastACL status now checks real dataplane, not only PID"
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

has_tcp_listener(){
  local port="$1"
  ss -lnt 2>/dev/null | grep -q ":$port " && return 0
  netstat -lnt 2>/dev/null | grep -q ":$port " && return 0
  return 1
}

has_any_listener(){
  local port="$1"
  ss -lnt 2>/dev/null | grep -q ":$port " && return 0
  ss -lnu 2>/dev/null | grep -q ":$port " && return 0
  netstat -lnt 2>/dev/null | grep -q ":$port " && return 0
  netstat -lnu 2>/dev/null | grep -q ":$port " && return 0
  return 1
}

ap_count(){
  local c
  c="$(uci -q get $CFG.main.ap_count 2>/dev/null || echo 0)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  echo "$c"
}

ap_num(){
  local n
  case "$1" in
    AP[0-9]*) n="${1#AP}" ;;
    *) return 1 ;;
  esac
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -ge 1 ] 2>/dev/null || return 1
  [ "$(uci -q get $CFG.ap$n 2>/dev/null || true)" = "ap" ] || return 1
  echo "$n"
}

find_acl_section(){
  local n="$1" subnet
  subnet="$(uci -q get $CFG.ap$n.subnet 2>/dev/null || true)"
  [ -n "$subnet" ] || return 0
  uci -q show "$APP" | awk -F'[.=]' -v S="$subnet" '
    /\.sources=/{gsub("\047", "", $0); if ($0 ~ "=" S "$") print $2}
  ' | head -n1
}

ensure_socks_section(){
  local n="$1" node="${2:-}" sec port type
  sec="jfa_ap$n"; port="$(uci -q get $CFG.ap$n.socks_port 2>/dev/null || echo $((13100+n)))"
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
  local n="$1" node="${2:-}" sec port type
  sec="jfa_pre$n"; port="$(uci -q get $CFG.ap$n.preproxy_port 2>/dev/null || echo $((14100+n)))"
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
  local n="$1" pre="$2" sec port plog i
  sec="jfa_pre$n"; port="$(uci -q get $CFG.ap$n.preproxy_port 2>/dev/null || echo $((14100+n)))"
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
  # PassWall2 socks_node_switch may return non-zero when its transparent
  # runtime cache (USE_TABLES) is absent, even if the local relay was started.
  # FastACL therefore verifies the actual listening port instead of trusting
  # the helper's shell return code.
  /usr/share/passwall2/app.sh socks_node_switch flag="$sec" new_node="$pre" >"$plog" 2>&1 || true

  i=0
  while [ "$i" -lt 6 ]; do
    has_tcp_listener "$port" && return 0
    sleep 1
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
  local n="$1" sec psec pidf flag
  sec="jfa_ap$n"; psec="jfa_pre$n"
  pidf="$RUN_DIR/ap$n.pid"
  if [ -s "$pidf" ]; then kill "$(cat "$pidf")" >/dev/null 2>&1 || true; rm -f "$pidf"; fi
  for flag in "$sec" "$psec"; do
    pgrep -af '/tmp/etc/passwall2/bin' 2>/dev/null | awk -v P="$flag" '$0 ~ P {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
    pgrep -af "SOCKS_${flag}" 2>/dev/null | awk '!/pgrep/{print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
  done
  rm -f "$RUN_DIR/ap$n-direct.json" "$RUN_DIR/ap$n-preproxy-error.log" "$RUN_DIR/ap$n-preproxy-switch.log"
}

start_ap(){
  local n="$1" landing_node type proto port chain pre preport cfg swlog i
  landing_node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
  [ -n "$landing_node" ] || { kill_ap "$n"; return 0; }
  [ "$(uci -q get $APP.$landing_node 2>/dev/null || true)" = "nodes" ] || { log "AP$n 节点不存在: $landing_node"; return 1; }
  ensure_socks_section "$n" "$landing_node"
  uci commit "$APP"
  kill_ap "$n"
  type="$(uci -q get $APP.$landing_node.type 2>/dev/null | tr 'A-Z' 'a-z')"
  proto="$(uci -q get $APP.$landing_node.protocol 2>/dev/null | tr 'A-Z' 'a-z')"
  [ -n "$proto" ] || proto="$type"
  port="$(uci -q get $CFG.ap$n.socks_port 2>/dev/null || echo $((13100+n)))"
  chain="$(uci -q get $APP.$landing_node.chain_proxy 2>/dev/null || true)"
  pre="$(uci -q get $APP.$landing_node.preproxy_node 2>/dev/null || true)"

  # SOCKS/HTTP landing nodes get a deterministic cross-core bridge:
  # native preproxy core (Xray or sing-box) -> local SOCKS 141xx ->
  # sing-box landing SOCKS/HTTP -> local SOCKS 131xx.
  if [ "$proto" = "socks" ] || [ "$proto" = "http" ]; then
    preport="0"
    if [ "$chain" = "1" ] && [ -n "$pre" ]; then
      start_preproxy "$n" "$pre" || return 1
      preport="$(uci -q get $CFG.ap$n.preproxy_port 2>/dev/null || echo $((14100+n)))"
    fi
    cfg="$RUN_DIR/ap$n-direct.json"
    lua /usr/libexec/juliang-fastacl-relay.lua "$landing_node" "$port" "$cfg" "$preport" || return 1
    sing-box check -c "$cfg" >"$RUN_DIR/ap$n-relay-check.log" 2>&1 || {
      log "AP$n SOCKS/HTTP 桥接配置检查失败"
      return 1
    }
    sing-box run -c "$cfg" >"$RUN_DIR/ap$n.log" 2>&1 &
    echo $! > "$RUN_DIR/ap$n.pid"
  else
    swlog="$RUN_DIR/ap$n-switch.log"
    : > "$swlog"
    # The helper can return 1 after PassWall2 handover simply because its
    # USE_TABLES cache is empty. Do not fail on the return code; the local
    # SOCKS listener below is the authoritative health check.
    /usr/share/passwall2/app.sh socks_node_switch flag="jfa_ap$n" new_node="$landing_node" >"$swlog" 2>&1 || true
  fi
  i=0
  while [ "$i" -lt 5 ]; do
    has_tcp_listener "$port" && return 0
    sleep 1; i=$((i+1))
  done
  {
    echo "AP$n local SOCKS port $port not ready"
    echo "node=$landing_node type=$type protocol=$proto chain=$chain preproxy=$pre"
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
  n="$1"; port="$(uci -q get $CFG.ap$n.socks_port 2>/dev/null || echo $((13100+n)))"
  ip="$(curl -4 -fsS --connect-timeout 3 --max-time 6 --socks5-hostname "127.0.0.1:$port" https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="-"
  echo "$ip"
}

write_router(){
  lua /usr/libexec/juliang-fastacl-router.lua > "$ROUTER_CFG" || return 1
  sing-box check -c "$ROUTER_CFG" >/tmp/jfa-router-check.log 2>&1 || { cat /tmp/jfa-router-check.log; return 1; }
}

remove_fw4_accept(){
  local h
  nft list chain inet fw4 input >/dev/null 2>&1 || return 0
  for h in $(nft -a list chain inet fw4 input 2>/dev/null | awk '/comment "juliang-fastacl-tproxy"/ {for(i=1;i<=NF;i++) if($i=="handle") print $(i+1)}'); do
    nft delete rule inet fw4 input handle "$h" >/dev/null 2>&1 || true
  done
}

install_fw4_accept(){
  nft list chain inet fw4 input >/dev/null 2>&1 || {
    log "warning: fw4 input chain not found; cannot install TProxy input accept rule"
    return 0
  }
  remove_fw4_accept
  nft insert rule inet fw4 input meta mark $MARK_HEX counter accept comment "juliang-fastacl-tproxy" >/dev/null 2>&1 || {
    log "failed to install fw4 TProxy input accept rule"
    return 1
  }
}

ap_sources_csv(){
  local n count subnet out
  count="$(ap_count)"
  out=""
  n=1
  while [ "$n" -le "$count" ]; do
    subnet="$(uci -q get $CFG.ap$n.subnet 2>/dev/null || true)"
    if [ -n "$subnet" ]; then
      [ -n "$out" ] && out="$out, "
      out="$out$subnet"
    fi
    n=$((n+1))
  done
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

firewall(){
  TPROXY_PORT="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  AP_SOURCES="$(ap_sources_csv)" || { log "no AP subnets discovered"; return 1; }
  nft list table inet juliang_fastacl >/dev/null 2>&1 && nft delete table inet juliang_fastacl >/dev/null 2>&1 || true
  cat > "$RUN_DIR/rules.nft" <<EOF
 table inet juliang_fastacl {
   set ap_sources {
     type ipv4_addr
     flags interval
     elements = { $AP_SOURCES }
   }
   set local_dst {
     type ipv4_addr
     flags interval
     elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
   }
   chain prerouting {
     type filter hook prerouting priority mangle; policy accept;
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 counter tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst counter return
     ip saddr @ap_sources meta l4proto { tcp, udp } counter tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
   }
 }
EOF
  nft -c -f "$RUN_DIR/rules.nft" || return 1
  nft -f "$RUN_DIR/rules.nft" || return 1
  install_fw4_accept || return 1
  ip rule del fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000 >/dev/null 2>&1 || true
  ip rule add fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000
  ip route replace local 0.0.0.0/0 dev lo table "$ROUTE_TABLE"
}

firewall_check(){
  TPROXY_PORT="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  AP_SOURCES="$(ap_sources_csv)" || { log "no AP subnets discovered"; return 1; }
  cat > "$RUN_DIR/rules-check.nft" <<EOF
 table inet juliang_fastacl_check {
   set ap_sources {
     type ipv4_addr
     flags interval
     elements = { $AP_SOURCES }
   }
   set local_dst {
     type ipv4_addr
     flags interval
     elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
   }
   chain prerouting {
     type filter hook prerouting priority mangle; policy accept;
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 counter tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst counter return
     ip saddr @ap_sources meta l4proto { tcp, udp } counter tproxy ip to :$TPROXY_PORT meta mark set $MARK_HEX accept
   }
 }
EOF
  nft -c -f "$RUN_DIR/rules-check.nft"
}

start_router(){
  local pid i tport
  write_router || return 1
  [ -s "$RUN_DIR/router.pid" ] && kill "$(cat "$RUN_DIR/router.pid")" >/dev/null 2>&1 || true
  sing-box run -c "$ROUTER_CFG" >"$RUN_DIR/router.log" 2>&1 &
  pid=$!
  echo "$pid" > "$RUN_DIR/router.pid"
  tport="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  i=0
  while [ "$i" -lt 5 ]; do
    kill -0 "$pid" >/dev/null 2>&1 || { cat "$RUN_DIR/router.log"; return 1; }
    if has_any_listener "$tport"; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  log "FastACL router process exists but TProxy port $tport is not listening"
  cat "$RUN_DIR/router.log" 2>/dev/null || true
  return 1
}

stop_router(){
  if [ -s "$RUN_DIR/router.pid" ]; then kill "$(cat "$RUN_DIR/router.pid")" >/dev/null 2>&1 || true; rm -f "$RUN_DIR/router.pid"; fi
}

cleanup_old_passwall2_dataplane(){
  # FastACL keeps PassWall2 only as node DB/UI. Any old transparent proxy
  # dataplane must not intercept AP traffic before our dedicated table.
  if [ "$(uci -q get passwall2.@global[0].enabled 2>/dev/null || echo 0)" = "0" ]; then
    nft list table inet passwall2 >/dev/null 2>&1 && nft delete table inet passwall2 >/dev/null 2>&1 || true
    pgrep -af '/tmp/etc/passwall2/acl/default/global.json' 2>/dev/null | awk '!/pgrep|awk/ {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true
    ip rule del fwmark 0x1 table 100 priority 9999 >/dev/null 2>&1 || true
  fi
}

router_healthy(){
  local tport pid
  tport="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  [ -s "$RUN_DIR/router.pid" ] || return 1
  pid="$(cat "$RUN_DIR/router.pid" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1 || return 1
  has_any_listener "$tport"
}

dataplane_healthy(){
  router_healthy || return 1
  nft list table inet juliang_fastacl >/dev/null 2>&1 || return 1
  ip rule show 2>/dev/null | grep -q 'fwmark 0x66/0xff.*lookup 100' || return 1
  ip route show table "$ROUTE_TABLE" 2>/dev/null | grep -q '^local default dev lo' || return 1
  return 0
}

ensure_dataplane(){
  cleanup_old_passwall2_dataplane
  if ! router_healthy; then
    log "FastACL 主 TProxy 未运行，自动恢复..."
    start_router || return 1
  fi
  if ! nft list table inet juliang_fastacl >/dev/null 2>&1; then
    log "FastACL nftables 表缺失，自动恢复..."
    firewall || return 1
  else
    install_fw4_accept || return 1
    if ! ip rule show 2>/dev/null | grep -q 'fwmark 0x66/0xff.*lookup 100'; then
      ip rule del fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000 >/dev/null 2>&1 || true
      ip rule add fwmark "$MARK_HEX/0xff" table "$ROUTE_TABLE" priority 10000 || return 1
    fi
    ip route replace local 0.0.0.0/0 dev lo table "$ROUTE_TABLE" || return 1
  fi
  dataplane_healthy
}

repair_all(){
  lua /usr/libexec/juliang-fastacl-discover.lua >"$RUN_DIR/repair-discover.json" 2>"$RUN_DIR/repair-discover.log" || true
  cleanup_old_passwall2_dataplane
  start_all
}

start_all(){
  local n node failed count
  failed=0
  count="$(ap_count)"
  [ "$count" -gt 0 ] || { log "no discovered APs"; return 1; }
  n=1
  while [ "$n" -le "$count" ]; do
    node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
    if [ -n "$node" ]; then
      if [ "$(uci -q get $APP.$node 2>/dev/null || true)" != "nodes" ]; then
        log "AP$n stale mapping cleared: node '$node' no longer exists"
        clear_ap "AP$n" >/dev/null 2>&1 || true
      else
        start_ap "$n" || failed=$((failed+1))
      fi
    else
      kill_ap "$n"
    fi
    n=$((n+1))
  done
  [ "$failed" -eq 0 ] || {
    log "$failed assigned AP relay(s) failed to start"
    return 1
  }
  cleanup_old_passwall2_dataplane
  start_router || return 1
  firewall || return 1
}

stop_all(){
  local n count
  count="$(ap_count)"
  n=1; while [ "$n" -le "$count" ]; do kill_ap "$n"; n=$((n+1)); done
  stop_router
  nft list table inet juliang_fastacl >/dev/null 2>&1 && nft delete table inet juliang_fastacl >/dev/null 2>&1 || true
  remove_fw4_accept
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
  if start_ap "$n" && ensure_dataplane; then
    ip="$(probe_ap "$n")"
    printf '%s\n' "$ip" > "$RUN_DIR/ap$n.ip"
    t1="$(date +%s)"; sec=$((t1-t0))
    remark="$(uci -q get $APP.$node.remarks 2>/dev/null || echo "$node")"
    printf '{"ok":true,"ap":"AP%s","node":"%s","remark":"%s","ip":"%s","seconds":%s,"dataplane":"running"}\n' "$n" "$node" "$(echo "$remark" | sed 's/"/\\"/g')" "$ip" "$sec"
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
  count="$(ap_count)"
  i=1
  while [ "$i" -le "$count" ]; do
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
  local tport router_state count
  echo "JuLiang FastACL"
  tport="$(uci -q get $CFG.main.tproxy_port 2>/dev/null || echo 12345)"
  router_state="stopped"
  if router_healthy; then
    router_state="running"
  elif [ -s "$RUN_DIR/router.pid" ] && kill -0 "$(cat "$RUN_DIR/router.pid")" 2>/dev/null; then
    router_state="broken(no-listener:$tport)"
  fi
  echo "router: $router_state"
  nft list table inet juliang_fastacl >/dev/null 2>&1 && echo "nftables: loaded" || echo "nftables: missing"
  count="$(ap_count)"
  echo "wireless: $count discovered"
  n=1; while [ "$n" -le "$count" ]; do
    node="$(uci -q get $CFG.ap$n.node 2>/dev/null || true)"
    port="$(uci -q get $CFG.ap$n.socks_port 2>/dev/null || echo $((13100+n)))"
    ssid="$(uci -q get $CFG.ap$n.ssid 2>/dev/null || echo "AP$n")"
    net="$(uci -q get $CFG.ap$n.network 2>/dev/null || true)"
    subnet="$(uci -q get $CFG.ap$n.subnet 2>/dev/null || true)"
    if [ -n "$node" ]; then
      remark="$(uci -q get $APP.$node.remarks 2>/dev/null || echo "$node")"
      listen="no"; has_tcp_listener "$port" && listen="yes"
      echo "AP$n [$ssid | $net | $subnet] -> $remark | socks:$port listen:$listen"
    else
      echo "AP$n [$ssid | $net | $subnet] -> unassigned"
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
  discover) lua /usr/libexec/juliang-fastacl-discover.lua ;;
  repair) repair_all ;;
  *) echo "Usage: juliang-fastacl {start|stop|restart|repair|discover|firewall|firewall-check|switch AP1 nodeid|move AP1 nodeid|clear AP1|probe AP1|status}"; exit 1 ;;
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

local function ap_sections(uci)
    local out = {}
    uci:foreach("juliang_fastacl", "ap", function(s)
        local n = tonumber(s.slot or (s[".name"] or ""):match("^ap(%d+)$"))
        if n then
            out[#out + 1] = {
                n = n,
                ap = "AP" .. n,
                section = s[".name"] or ("ap" .. n),
                ssid = s.ssid or ("AP" .. n),
                network = s.network or "",
                subnet = s.subnet or "",
                router_ip = s.router_ip or "",
                socks_port = tonumber(s.socks_port or "") or (13100 + n),
                preproxy_port = tonumber(s.preproxy_port or "") or (14100 + n),
                node = s.node or ""
            }
        end
    end)
    table.sort(out, function(a,b) return a.n < b.n end)
    return out
end

local function ap_number(uci, v)
    local n = tonumber((v or ""):match("^AP(%d+)$"))
    if not n or n < 1 then return nil end
    if uci:get("juliang_fastacl", "ap" .. n) ~= "ap" then return nil end
    return n
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
    if sys.call("kill -0 " .. pid .. " >/dev/null 2>&1") ~= 0 then return "stopped" end
    local port = tonumber(require("luci.model.uci").cursor():get("juliang_fastacl", "main", "tproxy_port") or "12345")
    local cmd = "(ss -lnt 2>/dev/null; ss -lnu 2>/dev/null; netstat -lnt 2>/dev/null; netstat -lnu 2>/dev/null) | grep -q ':" .. port .. " '"
    local listener = sys.call(cmd) == 0
    local nft = sys.call("nft list table inet juliang_fastacl >/dev/null 2>&1") == 0
    local rule = sys.call("ip rule show 2>/dev/null | grep -q 'fwmark 0x66/0xff.*lookup 100'") == 0
    return (listener and nft and rule) and "running" or "broken"
end

local function exec_json(cmd)
    local sys = require "luci.sys"
    local jsonc = require "luci.jsonc"
    local raw = sys.exec(cmd .. " 2>/tmp/juliang-fastacl/luci-error.log")
    local ok, data = pcall(jsonc.parse, raw or "")
    if ok and type(data) == "table" then return data end
    return { ok = false, error = "ENGINE_ERROR", detail = raw or "" }
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
    table.sort(out, function(a,b) return (a.remarks or "") < (b.remarks or "") end)
    return out
end

function handle()
    local http = require "luci.http"
    local util = require "luci.util"
    local uci = require("luci.model.uci").cursor()
    local action = http.formvalue("action") or "status"
    local aps = ap_sections(uci)

    if action == "status" then
        local map, ap_to_node, ips, labels = {}, {}, {}, {}
        local ap_meta = {}

        for _, a in ipairs(aps) do
            local node = uci:get("juliang_fastacl", a.section, "node") or ""
            ap_to_node[a.ap] = node
            ips[a.ap] = read_ip(a.n)
            labels[a.ap] = a.ssid
            ap_meta[#ap_meta + 1] = {
                ap = a.ap,
                slot = a.n,
                ssid = a.ssid,
                network = a.network,
                subnet = a.subnet,
                router_ip = a.router_ip,
                socks_port = a.socks_port
            }
            if node ~= "" then
                map[node] = map[node] or {}
                map[node][#map[node] + 1] = a.ap
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
            count = #aps,
            aps = ap_meta,
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
        local n = ap_number(uci, ap)
        if not n then write_json({ok=false,error="BAD_AP"}); return end
        if not node_cfg or node_cfg[".type"] ~= "nodes" then write_json({ok=false,error="BAD_NODE"}); return end
        local exclusive = http.formvalue("exclusive") ~= "0"
        local verb = exclusive and "move" or "switch"
        write_json(exec_json("/usr/bin/juliang-fastacl " .. verb .. " " .. ap .. " " .. util.shellquote(node)))
        return
    end

    if action == "preproxy_options" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then write_json({ok=false,error="BAD_NODE"}); return end
        write_json({
            ok = true,
            current = node_cfg.preproxy_node or "",
            enabled = node_cfg.chain_proxy == "1",
            options = preproxy_options(uci, node)
        })
        return
    end

    if action == "set_preproxy" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then write_json({ok=false,error="BAD_NODE"}); return end
        local pre = http.formvalue("preproxy") or ""
        if pre == node then write_json({ok=false,error="PREPROXY_SELF"}); return end

        if pre ~= "" then
            local p = uci:get_all("passwall2", pre)
            if not p or p[".type"] ~= "nodes" or is_special_protocol(p.protocol or "") then
                write_json({ok=false,error="BAD_PREPROXY"}); return
            end
            if (p.chain_proxy or "") ~= "" then
                write_json({ok=false,error="PREPROXY_ALREADY_CHAINED"}); return
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

        local affected, failed = {}, nil
        for _, a in ipairs(aps) do
            if (uci:get("juliang_fastacl", a.section, "node") or "") == node then
                local rr = exec_json("/usr/bin/juliang-fastacl switch " .. a.ap .. " " .. util.shellquote(node))
                if not rr.ok then failed = rr; break end
                affected[#affected + 1] = a.ap
            end
        end

        if failed then
            if old_chain == "" then uci:delete("passwall2", node, "chain_proxy")
            else uci:set("passwall2", node, "chain_proxy", old_chain) end
            if old_pre == "" then uci:delete("passwall2", node, "preproxy_node")
            else uci:set("passwall2", node, "preproxy_node", old_pre) end
            uci:commit("passwall2")
            for _, ap in ipairs(affected) do
                exec_json("/usr/bin/juliang-fastacl switch " .. ap .. " " .. util.shellquote(node))
            end
            write_json({ok=false,error="PREPROXY_START_FAILED",detail=failed,rolled_back=true})
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
        if not node_cfg or node_cfg[".type"] ~= "nodes" then write_json({ok=false,error="BAD_NODE"}); return end
        local cleared = {}
        for _, a in ipairs(aps) do
            if (uci:get("juliang_fastacl", a.section, "node") or "") == node then
                local rr = exec_json("/usr/bin/juliang-fastacl clear " .. a.ap)
                if rr.ok then cleared[#cleared + 1] = a.ap end
            end
        end
        write_json({ok=true,action="clear_node",node=node,cleared=cleared})
        return
    end

    if action == "probe" then
        local ap = http.formvalue("ap") or ""
        local n = ap_number(uci, ap)
        if not n then write_json({ok=false,error="BAD_AP"}); return end
        local sys = require "luci.sys"
        local ip = (sys.exec("/usr/bin/juliang-fastacl probe " .. ap .. " 2>/dev/null") or ""):gsub("%s+", "")
        write_json({ok = ip ~= "" and ip ~= "-", ap=ap, ip=ip})
        return
    end

    if action == "rediscover" then
        local rr = exec_json("/usr/bin/juliang-fastacl discover")
        write_json(rr)
        return
    end

    write_json({ok=false,error="BAD_ACTION"})
end

__JFA_END_CONTROLLER__
