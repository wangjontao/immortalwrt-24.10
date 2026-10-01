#!/bin/sh
set -eu

VERSION="2.2.6-guardian"
TMP="/tmp/jfa-v226-$$"
STATE="/etc/juliang-fastacl"
mkdir -p "$TMP" "$STATE/last-good" /tmp/juliang-fastacl
trap 'rm -rf "$TMP"' EXIT INT TERM

extract_embedded(){
  tag="$1"; dst="$2"
  awk -v b="__JFA_BEGIN_${tag}__" -v e="__JFA_END_${tag}__" '
    $0 == b { on=1; next }
    $0 == e { found=1; exit }
    on { print }
    END { if (!found) exit 2 }
  ' "$0" > "$dst"
  [ -s "$dst" ]
}

echo "=================================================="
echo " JuLiang FastACL $VERSION"
echo " boot protection + watchdog + last-good persistence"
echo "=================================================="

[ "$(id -u)" = "0" ] || { echo "[ERROR] run as root"; exit 1; }

extract_embedded ENGINE "$TMP/juliang-fastacl"
extract_embedded DISCOVER "$TMP/juliang-fastacl-discover.lua"
extract_embedded GUARD "$TMP/juliang-fastacl-guard"
extract_embedded INIT "$TMP/juliang-fastacl.init"
extract_embedded ROUTER "$TMP/juliang-fastacl-router.lua"

sh -n "$TMP/juliang-fastacl"
sh -n "$TMP/juliang-fastacl-guard"
sh -n "$TMP/juliang-fastacl.init"
lua -e 'assert(loadfile("'"$TMP"'/juliang-fastacl-discover.lua"))'
lua -e 'assert(loadfile("'"$TMP"'/juliang-fastacl-router.lua"))'

# Save current working hot configuration before touching runtime.
if [ -s /etc/config/juliang_fastacl ]; then
  cp -af /etc/config/juliang_fastacl "$STATE/last-good/juliang_fastacl"
  cp -af /etc/config/juliang_fastacl "$STATE/pre-v226-juliang_fastacl"
  echo "[OK] current bindings/DNS saved as last-good"
fi

# PassWall2 remains only the node database/UI. Its S99 startup can interfere
# with FastACL local relay children, so remove it from boot order.
uci -q set passwall2.@global[0].enabled=0
uci -q set passwall2.@global[0].acl_enable=0
uci -q set passwall2.@global[0].socks_enabled=0
uci commit passwall2
/etc/init.d/passwall2 disable >/dev/null 2>&1 || true
echo "[OK] PassWall2 transparent runtime autostart disabled"

# Stop old FastACL runtime once, replace runtime files, then immediately repair.
if [ -x /usr/bin/juliang-fastacl ]; then
  /usr/bin/juliang-fastacl stop >/dev/null 2>&1 || true
  cp -af /usr/bin/juliang-fastacl "$STATE/juliang-fastacl.pre-v226" 2>/dev/null || true
fi
cp -af /etc/init.d/juliang-fastacl "$STATE/juliang-fastacl.init.pre-v226" 2>/dev/null || true

cp -af "$TMP/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP/juliang-fastacl-guard" /usr/bin/juliang-fastacl-guard
cp -af "$TMP/juliang-fastacl-discover.lua" /usr/libexec/juliang-fastacl-discover.lua
cp -af "$TMP/juliang-fastacl-router.lua" /usr/libexec/juliang-fastacl-router.lua
cp -af "$TMP/juliang-fastacl.init" /etc/init.d/juliang-fastacl

chmod 0755 /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl-guard /etc/init.d/juliang-fastacl
chmod 0644 /usr/libexec/juliang-fastacl-discover.lua /usr/libexec/juliang-fastacl-router.lua

uci -q set juliang_fastacl.main.enabled=1
uci commit juliang_fastacl

# Rebuild current dataplane immediately.
echo "[INFO] repairing current FastACL runtime..."
if ! /usr/bin/juliang-fastacl repair >/tmp/juliang-fastacl/v226-repair.log 2>&1; then
  cat /tmp/juliang-fastacl/v226-repair.log 2>/dev/null || true
  echo "[ERROR] FastACL repair failed"
  exit 1
fi
/usr/bin/juliang-fastacl save-state >/dev/null 2>&1 || true

# Replace old rc.d links with procd guardian service.
 /etc/init.d/juliang-fastacl disable >/dev/null 2>&1 || true
 /etc/init.d/juliang-fastacl enable >/dev/null 2>&1
 /etc/init.d/juliang-fastacl start >/dev/null 2>&1 || true

echo "===== FastACL status ====="
/usr/bin/juliang-fastacl status

echo "===== boot protection ====="
ls -l /etc/rc.d/*juliang-fastacl* 2>/dev/null || true
ls -l /etc/rc.d/*passwall2* 2>/dev/null || echo "OK: PassWall2 has no boot link"

echo "===== guardian ====="
pgrep -af juliang-fastacl-guard 2>/dev/null || echo "guardian will be started by procd"

echo "===== last-good ====="
ls -l "$STATE/last-good/juliang_fastacl" 2>/dev/null || true

echo "[OK] FastACL $VERSION installed"
echo "[OK] guardian checks dataplane/relays every 20s"
echo "[OK] failed early-boot WiFi discovery can no longer erase bindings"
echo "[OK] last-good snapshot protects AP bindings and DNS settings"
echo "[INFO] after reboot: wait 20s, then run /usr/bin/juliang-fastacl status"
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

save_state(){
  local dir tmp
  dir="$STATE_DIR/last-good"
  tmp="$dir/juliang_fastacl.tmp"
  mkdir -p "$dir" || return 0
  cp -af /etc/config/juliang_fastacl "$tmp" 2>/dev/null || return 0
  mv -f "$tmp" "$dir/juliang_fastacl" 2>/dev/null || true
}

restore_state(){
  local src
  src="$STATE_DIR/last-good/juliang_fastacl"
  [ -s "$src" ] || return 1
  cp -af "$src" /etc/config/juliang_fastacl || return 1
  log "restored FastACL last-good persistent config"
  return 0
}

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
    for pref in $(ip rule show 2>/dev/null | awk '/fwmark 0x1/ && /lookup 100/ {gsub(":", "", $1); print $1}'); do
      ip rule del priority "$pref" >/dev/null 2>&1 || true
    done
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

heal_other_aps(){
  local skip="${1:-0}" count i node port failed
  count="$(ap_count)"
  failed=0
  i=1
  while [ "$i" -le "$count" ]; do
    if [ "$i" -ne "$skip" ]; then
      node="$(uci -q get $CFG.ap$i.node 2>/dev/null || true)"
      if [ -n "$node" ] && [ "$(uci -q get $APP.$node 2>/dev/null || true)" = "nodes" ]; then
        port="$(uci -q get $CFG.ap$i.socks_port 2>/dev/null || echo $((13100+i)))"
        if ! has_tcp_listener "$port"; then
          log "AP$i 已绑定但 SOCKS:$port 掉线，自动恢复..."
          if start_ap "$i"; then
            log "AP$i 已恢复"
          else
            log "AP$i 自动恢复失败"
            failed=$((failed+1))
          fi
        fi
      fi
    fi
    i=$((i+1))
  done
  [ "$failed" -eq 0 ]
}

reload_router(){
  start_router || return 1
  firewall || return 1
}

set_dns_mode(){
  local ap="$1" mode="$2" n
  n="$(ap_num "$ap")" || { echo '{"ok":false,"error":"BAD_AP"}'; return 2; }
  case "$mode" in
    doh)
      uci set $CFG.ap$n.dns_mode='doh'
      ;;
    tcp)
      uci set $CFG.ap$n.dns_mode='tcp'
      ;;
    auto)
      uci -q delete $CFG.ap$n.dns_mode
      ;;
    *)
      echo '{"ok":false,"error":"BAD_DNS_MODE"}'
      return 2
      ;;
  esac
  uci commit "$CFG"
  save_state
  if reload_router; then
    printf '{"ok":true,"ap":"AP%s","dns_mode":"%s"}\n' "$n" "$mode"
  else
    printf '{"ok":false,"ap":"AP%s","error":"ROUTER_RELOAD_FAILED"}\n' "$n"
    return 1
  fi
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
  save_state
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
    # Starting a new local relay must never leave an already assigned AP dead.
    # Heal only missing listeners; healthy AP relays are untouched.
    heal_other_aps "$n" >/dev/null 2>&1 || true
    ensure_dataplane || true
    ip="$(probe_ap "$n")"
    printf '%s\n' "$ip" > "$RUN_DIR/ap$n.ip"
    t1="$(date +%s)"; sec=$((t1-t0))
    remark="$(uci -q get $APP.$node.remarks 2>/dev/null || echo "$node")"
    save_state
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
    save_state
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
  save_state
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
  heal) heal_other_aps 0 ;;
  ensure) ensure_dataplane ;;
  save-state) save_state ;;
  restore-state) restore_state ;;
  router-reload) reload_router ;;
  dns) [ $# -eq 3 ] || exit 2; set_dns_mode "$2" "$3" ;;
  *) echo "Usage: juliang-fastacl {start|stop|restart|repair|heal|ensure|save-state|restore-state|router-reload|dns AP1 doh|dns AP1 tcp|dns AP1 auto|discover|firewall|firewall-check|switch AP1 nodeid|move AP1 nodeid|clear AP1|probe AP1|status}"; exit 1 ;;
esac
__JFA_END_ENGINE__

__JFA_BEGIN_DISCOVER__
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local uci = require("luci.model.uci").cursor()

local function split_words(v)
  local out = {}
  if type(v) == "table" then
    for _, x in ipairs(v) do
      if x and x ~= "" then out[#out + 1] = x end
    end
  elseif type(v) == "string" then
    for x in v:gmatch("%S+") do out[#out + 1] = x end
  end
  return out
end

local function ip_to_num(ip)
  local a,b,c,d = tostring(ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if not a or a>255 or b>255 or c>255 or d>255 then return nil end
  return ((a*256+b)*256+c)*256+d
end

local function num_to_ip(n)
  local a = math.floor(n / 16777216) % 256
  local b = math.floor(n / 65536) % 256
  local c = math.floor(n / 256) % 256
  local d = n % 256
  return string.format("%d.%d.%d.%d", a,b,c,d)
end

local function mask_to_prefix(mask)
  if not mask or mask == "" then return 24 end
  local p = tonumber(mask)
  if p and p >= 0 and p <= 32 then return p end
  local n = ip_to_num(mask)
  if not n then return nil end
  local bits = 0
  local seen_zero = false
  for i = 31, 0, -1 do
    local bit = math.floor(n / (2^i)) % 2
    if bit == 1 then
      if seen_zero then return nil end
      bits = bits + 1
    else
      seen_zero = true
    end
  end
  return bits
end

local function cidr_from(ip, mask)
  if not ip or ip == "" then return nil end
  local bare, slash = tostring(ip):match("^([^/]+)/(%d+)$")
  if bare then
    ip = bare
    mask = slash
  end
  local n = ip_to_num(ip)
  local p = mask_to_prefix(mask)
  if not n or not p then return nil end
  local block = 2^(32-p)
  local net = math.floor(n / block) * block
  return num_to_ip(net) .. "/" .. tostring(p)
end

local function network_ipv4(net)
  local ip = uci:get("network", net, "ipaddr")
  local mask = uci:get("network", net, "netmask")
  if type(ip) == "table" then ip = ip[1] end
  local cidr = cidr_from(ip, mask)
  if cidr then return cidr, tostring(ip):match("^([^/]+)") end

  local raw = sys.exec("ubus call network.interface." .. string.format("%q", net) .. " status 2>/dev/null")
  if raw and raw ~= "" then
    local ok, st = pcall(jsonc.parse, raw)
    if ok and type(st) == "table" and type(st["ipv4-address"]) == "table" then
      local a = st["ipv4-address"][1]
      if a and a.address and a.mask then
        return cidr_from(a.address, a.mask), a.address
      end
    end
  end
  return nil
end

local lan_cidr = nil
do
  local ip = uci:get("network", "lan", "ipaddr")
  local mask = uci:get("network", "lan", "netmask")
  if type(ip) == "table" then ip = ip[1] end
  lan_cidr = cidr_from(ip, mask)
end

local ignore = {
  lan=true, wan=true, wan6=true, loopback=true, wwan=true
}

local by_net = {}
uci:foreach("wireless", "wifi-iface", function(s)
  if tostring(s.disabled or "0") ~= "1" and tostring(s.mode or "ap") == "ap" then
    local ssid = s.ssid or s[".name"] or "WiFi"
    for _, net in ipairs(split_words(s.network)) do
      if not ignore[net] then
        local cidr, router_ip = network_ipv4(net)
        if cidr and cidr ~= lan_cidr then
          local item = by_net[net]
          if not item then
            item = {
              network = net,
              subnet = cidr,
              router_ip = router_ip or "",
              ssids = {}
            }
            by_net[net] = item
          end
          local found=false
          for _,v in ipairs(item.ssids) do if v == ssid then found=true break end end
          if not found then item.ssids[#item.ssids+1]=ssid end
        end
      end
    end
  end
end)

local items = {}
for _, item in pairs(by_net) do
  item.ssid = table.concat(item.ssids, " / ")
  item._sort = ip_to_num((item.subnet or ""):match("^([^/]+)$") or (item.subnet or ""):match("^([^/]+)/")) or 0
  items[#items+1] = item
end

table.sort(items, function(a,b)
  if a._sort == b._sort then return a.network < b.network end
  return a._sort < b._sort
end)

local old = {}
uci:foreach("juliang_fastacl", "ap", function(s)
  local data = {
    node = s.node,
    dns_mode = s.dns_mode,
    dns_server = s.dns_server,
    dns_tls_server_name = s.dns_tls_server_name,
    dns_path = s.dns_path
  }
  if s.network and s.network ~= "" then old["net:" .. s.network] = data end
  if s.subnet and s.subnet ~= "" then old["subnet:" .. s.subnet] = data end
end)

-- Discovery must be transactional. During early boot WiFi/netifd may not be
-- ready yet. Never erase a working persistent FastACL topology on a 0-result scan.
if #items == 0 then
  io.write(jsonc.stringify({ ok = false, count = 0, aps = {}, preserved = true, error = "NO_AP_READY" }, true))
  os.exit(2)
end

-- Remove only AP slot sections after we already have a valid replacement set.
local dels = {}
uci:foreach("juliang_fastacl", "ap", function(s) dels[#dels+1]=s[".name"] end)
for _,name in ipairs(dels) do uci:delete("juliang_fastacl", name) end

for i,item in ipairs(items) do
  local sec = "ap" .. i
  uci:section("juliang_fastacl", "ap", sec, {
    slot = tostring(i),
    network = item.network,
    ssid = item.ssid,
    subnet = item.subnet,
    router_ip = item.router_ip or "",
    socks_port = tostring(13100+i),
    preproxy_port = tostring(14100+i)
  })
  local prev = old["net:"..item.network] or old["subnet:"..item.subnet]
  if prev then
    if prev.node and prev.node ~= "" then uci:set("juliang_fastacl", sec, "node", prev.node) end
    if prev.dns_mode and prev.dns_mode ~= "" then uci:set("juliang_fastacl", sec, "dns_mode", prev.dns_mode) end
    if prev.dns_server and prev.dns_server ~= "" then uci:set("juliang_fastacl", sec, "dns_server", prev.dns_server) end
    if prev.dns_tls_server_name and prev.dns_tls_server_name ~= "" then uci:set("juliang_fastacl", sec, "dns_tls_server_name", prev.dns_tls_server_name) end
    if prev.dns_path and prev.dns_path ~= "" then uci:set("juliang_fastacl", sec, "dns_path", prev.dns_path) end
  end
end
uci:set("juliang_fastacl", "main", "ap_count", tostring(#items))
uci:commit("juliang_fastacl")

io.write(jsonc.stringify({ ok = (#items > 0), count = #items, aps = items }, true))

__JFA_END_DISCOVER__

__JFA_BEGIN_GUARD__
#!/bin/sh
set -u

LOG="/tmp/juliang-fastacl/guard.log"
mkdir -p /tmp/juliang-fastacl

log(){
  echo "$(date '+%Y-%m-%d %H:%M:%S') [GUARD] $*" >> "$LOG"
}

disable_passwall2_runtime(){
  local changed=0
  [ "$(uci -q get passwall2.@global[0].enabled 2>/dev/null || echo 0)" = "0" ] || { uci -q set passwall2.@global[0].enabled=0; changed=1; }
  [ "$(uci -q get passwall2.@global[0].acl_enable 2>/dev/null || echo 0)" = "0" ] || { uci -q set passwall2.@global[0].acl_enable=0; changed=1; }
  [ "$(uci -q get passwall2.@global[0].socks_enabled 2>/dev/null || echo 0)" = "0" ] || { uci -q set passwall2.@global[0].socks_enabled=0; changed=1; }
  [ "$changed" -eq 0 ] || uci commit passwall2
}

# Wait for network/wireless services. Persistent UCI bindings are kept intact
# while we wait; discovery itself is transactional and cannot erase them.
sleep 12

while true; do
  if [ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null || echo 0)" != "1" ]; then
    sleep 30
    continue
  fi

  disable_passwall2_runtime

  # If persistent topology is unexpectedly missing, first attempt
  # discovery. If boot services are not ready yet, restore last-good state.
  count="$(uci -q get juliang_fastacl.main.ap_count 2>/dev/null || echo 0)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  if [ "$count" -eq 0 ]; then
    if lua /usr/libexec/juliang-fastacl-discover.lua >/tmp/juliang-fastacl/guard-discover.json 2>/tmp/juliang-fastacl/guard-discover.log; then
      log "wireless topology discovered"
    elif /usr/bin/juliang-fastacl restore-state >/tmp/juliang-fastacl/guard-restore.log 2>&1; then
      log "persistent config restored from last-good snapshot"
    else
      log "wireless not ready and no last-good snapshot; retrying"
      sleep 15
      continue
    fi
  fi

  if ! /usr/bin/juliang-fastacl ensure >/tmp/juliang-fastacl/guard-ensure.log 2>&1; then
    log "dataplane unhealthy; full repair"
    if /usr/bin/juliang-fastacl repair >/tmp/juliang-fastacl/guard-repair.log 2>&1; then
      log "dataplane repaired"
    else
      log "dataplane repair failed"
    fi
  fi

  if ! /usr/bin/juliang-fastacl heal >/tmp/juliang-fastacl/guard-heal.log 2>&1; then
    log "one or more AP relays were missing; heal attempted"
  fi

  sleep 20
done

__JFA_END_GUARD__

__JFA_BEGIN_INIT__
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95
STOP=10

start_service() {
    [ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null)" = "1" ] || return 0

    # PassWall2 is retained only as the node database/UI. Its late S99 start
    # would otherwise see FastACL's /tmp/etc/passwall2/bin children and stop
    # them. Keep its service disabled permanently while FastACL owns dataplane.
    /etc/init.d/passwall2 disable >/dev/null 2>&1 || true

    mkdir -p /tmp/juliang-fastacl

    procd_open_instance
    procd_set_param command /usr/bin/juliang-fastacl-guard
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    /usr/bin/juliang-fastacl stop >/dev/null 2>&1 || true
}

service_triggers() {
    procd_add_reload_trigger juliang_fastacl
}

__JFA_END_INIT__

__JFA_BEGIN_ROUTER__
local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local cfg = "juliang_fastacl"
local port = tonumber(uci:get(cfg, "main", "tproxy_port") or "12345")
local dns_mode = uci:get(cfg, "main", "dns_mode") or "doh"
local dns_addr = uci:get(cfg, "main", "dns_server") or "1.1.1.1"
local dns_tls_name = uci:get(cfg, "main", "dns_tls_server_name") or "cloudflare-dns.com"
local dns_path = uci:get(cfg, "main", "dns_path") or "/dns-query"

local aps = {}
uci:foreach(cfg, "ap", function(s)
  local slot = tonumber(s.slot or (s[".name"] or ""):match("^ap(%d+)$"))
  local subnet = s.subnet
  local sport = tonumber(s.socks_port)
  if slot and subnet and subnet ~= "" and sport then
    aps[#aps + 1] = {
      slot = slot,
      subnet = subnet,
      sport = sport,
      name = s[".name"] or ("ap" .. slot),
      dns_mode = s.dns_mode or dns_mode,
      dns_server = s.dns_server or dns_addr,
      dns_tls_server_name = s.dns_tls_server_name or dns_tls_name,
      dns_path = s.dns_path or dns_path
    }
  end
end)
table.sort(aps, function(a,b) return a.slot < b.slot end)

if #aps == 0 then
  io.stderr:write("FastACL: no discovered AP networks\n")
  os.exit(2)
end

local outbounds = { { type = "direct", tag = "direct" } }
local route_rules = {}
local dns_servers = {}
local dns_rules = {}

for _, a in ipairs(aps) do
  local tag = "ap" .. a.slot
  outbounds[#outbounds + 1] = {
    type = "socks",
    tag = tag,
    server = "127.0.0.1",
    server_port = a.sport,
    version = "5"
  }
  local dns_server
  if a.dns_mode == "tcp" then
    dns_server = {
      type = "tcp",
      tag = "dns-" .. tag,
      server = a.dns_server,
      server_port = 53,
      detour = tag
    }
  else
    dns_server = {
      type = "https",
      tag = "dns-" .. tag,
      server = a.dns_server,
      server_port = 443,
      path = a.dns_path,
      tls = {
        enabled = true,
        server_name = a.dns_tls_server_name
      },
      detour = tag
    }
  end
  dns_servers[#dns_servers + 1] = dns_server
  dns_rules[#dns_rules + 1] = {
    source_ip_cidr = { a.subnet },
    action = "route",
    server = "dns-" .. tag
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { a.subnet },
    port = { 53 },
    action = "hijack-dns"
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { a.subnet },
    action = "route",
    outbound = tag
  }
end

local conf = {
  log = { level = "warn", timestamp = true },
  dns = {
    servers = dns_servers,
    rules = dns_rules,
    final = dns_servers[1] and dns_servers[1].tag or nil
  },
  inbounds = {
    {
      type = "tproxy",
      tag = "jfa-tproxy",
      listen = "0.0.0.0",
      listen_port = port
    }
  },
  outbounds = outbounds,
  route = {
    rules = route_rules,
    final = "direct"
  }
}

io.write(jsonc.stringify(conf, true))

__JFA_END_ROUTER__
