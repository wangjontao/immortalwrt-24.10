#!/bin/sh
set -eu

VERSION="2.2.1-adaptive"
TMP_DIR="/tmp/juliang-fastacl-v220-$$"
BACKUP_DIR="/etc/juliang-fastacl/backup"
NODE_LIST="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"

log(){ echo "[JFA-V220] $*"; }
fail(){ echo "[JFA-V220][ERROR] $*" >&2; exit 1; }
cleanup(){ rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

extract_embedded(){
    tag="$1"; dst="$2"
    mkdir -p "$(dirname "$dst")"
    awk -v b="__JFA_BEGIN_${tag}__" -v e="__JFA_END_${tag}__" '
        $0 == b { on=1; next }
        $0 == e { found=1; exit }
        on { print }
        END { if (!found) exit 2 }
    ' "$0" > "$dst" || fail "embedded payload missing/corrupt: $tag"
    [ -s "$dst" ] || fail "embedded payload empty: $tag"
}

find_acl_by_subnet(){
    subnet="$1"
    uci -q show passwall2 | awk -F'[.=]' -v S="$subnet" '
        /\.sources=/{gsub("\047", "", $0); if ($0 ~ "=" S "$") print $2}
    ' | head -n1
}

echo "=================================================="
echo " JuLiang FastACL $VERSION"
echo " Adaptive WiFi / network / subnet discovery"
echo " Fast switch + Xray->sing-box cross-core preproxy"
echo "=================================================="

[ "$(id -u)" = "0" ] || fail "run as root"
[ -f /etc/config/passwall2 ] || fail "PassWall2 config not found"
[ -f /usr/share/passwall2/app.sh ] || fail "PassWall2 runtime not found"
[ -f "$NODE_LIST" ] || fail "PassWall2 node list UI not found"

for cmd in uci nft ip lua sing-box curl awk; do
    command -v "$cmd" >/dev/null 2>&1 || fail "missing command: $cmd"
done

mkdir -p "$TMP_DIR" "$BACKUP_DIR"
cp -af /etc/config/passwall2 "$TMP_DIR/passwall2.current"
[ -f /etc/config/juliang_fastacl ] && cp -af /etc/config/juliang_fastacl "$TMP_DIR/juliang_fastacl.current" || true

if [ ! -f "$BACKUP_DIR/passwall2" ]; then
    cp -af /etc/config/passwall2 "$BACKUP_DIR/passwall2"
fi
if [ ! -f "$BACKUP_DIR/original-flags" ]; then
    PW2_ENABLED="$(uci -q get passwall2.@global[0].enabled 2>/dev/null || echo 0)"
    PW2_ACL_ENABLE="$(uci -q get passwall2.@global[0].acl_enable 2>/dev/null || echo 0)"
    PW2_SOCKS_ENABLED="$(uci -q get passwall2.@global[0].socks_enabled 2>/dev/null || echo 0)"
    {
        echo "PW2_ENABLED='$PW2_ENABLED'"
        echo "PW2_ACL_ENABLE='$PW2_ACL_ENABLE'"
        echo "PW2_SOCKS_ENABLED='$PW2_SOCKS_ENABLED'"
    } > "$BACKUP_DIR/original-flags"
fi
if [ ! -f "$BACKUP_DIR/node_list.htm" ]; then
    if [ -f "$NODE_LIST.quick-acl.bak" ]; then
        cp -af "$NODE_LIST.quick-acl.bak" "$BACKUP_DIR/node_list.htm"
    elif [ -f "$NODE_LIST.jfa-v2.bak" ]; then
        cp -af "$NODE_LIST.jfa-v2.bak" "$BACKUP_DIR/node_list.htm"
    else
        cp -af "$NODE_LIST" "$BACKUP_DIR/node_list.htm"
    fi
fi

log "Extracting embedded runtime..."
extract_embedded BIN_FASTACL "$TMP_DIR/juliang-fastacl"
extract_embedded BIN_LUCI_INSTALL "$TMP_DIR/juliang-fastacl-luci-install"
extract_embedded BIN_UNINSTALL "$TMP_DIR/uninstall-juliang-fastacl"
extract_embedded LUA_ROUTER "$TMP_DIR/juliang-fastacl-router.lua"
extract_embedded LUA_RELAY "$TMP_DIR/juliang-fastacl-relay.lua"
extract_embedded LUA_DISCOVER "$TMP_DIR/juliang-fastacl-discover.lua"
extract_embedded LUA_CONTROLLER "$TMP_DIR/juliang_fastacl.lua"
extract_embedded INIT_FASTACL "$TMP_DIR/juliang-fastacl.init"
extract_embedded HOTPLUG_FASTACL "$TMP_DIR/99-juliang-fastacl"

sh -n "$TMP_DIR/juliang-fastacl"
sh -n "$TMP_DIR/juliang-fastacl-luci-install"
sh -n "$TMP_DIR/uninstall-juliang-fastacl"
lua -e 'assert(loadfile("'"$TMP_DIR"'/juliang-fastacl-router.lua"))'
lua -e 'assert(loadfile("'"$TMP_DIR"'/juliang-fastacl-relay.lua"))'
lua -e 'assert(loadfile("'"$TMP_DIR"'/juliang-fastacl-discover.lua"))'
lua -e 'assert(loadfile("'"$TMP_DIR"'/juliang_fastacl.lua"))'
chmod 0755 "$TMP_DIR/juliang-fastacl" "$TMP_DIR/juliang-fastacl-luci-install" "$TMP_DIR/uninstall-juliang-fastacl" "$TMP_DIR/juliang-fastacl.init" "$TMP_DIR/99-juliang-fastacl"
log "Embedded payload verified."

# Prepare main config while preserving existing AP assignments for discovery.
touch /etc/config/juliang_fastacl
[ "$(uci -q get juliang_fastacl.main 2>/dev/null || true)" = "main" ] || uci set juliang_fastacl.main='main'
uci set juliang_fastacl.main.enabled='1'
uci set juliang_fastacl.main.app='passwall2'
uci set juliang_fastacl.main.tproxy_port='12345'
uci set juliang_fastacl.main.mark='102'
uci set juliang_fastacl.main.route_table='100'
uci set juliang_fastacl.main.dns_server='1.1.1.1'
uci commit juliang_fastacl

log "Discovering enabled WiFi APs and their real network/subnet..."
DISCOVERY="$(lua "$TMP_DIR/juliang-fastacl-discover.lua" 2>"$TMP_DIR/discover.err")" || {
    cat "$TMP_DIR/discover.err" 2>/dev/null || true
    fail "wireless discovery failed"
}
COUNT="$(uci -q get juliang_fastacl.main.ap_count 2>/dev/null || echo 0)"
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
[ "$COUNT" -gt 0 ] || {
    echo "$DISCOVERY"
    fail "no eligible AP WiFi network with IPv4 subnet was discovered"
}
echo "$DISCOVERY"
log "Detected $COUNT proxy WiFi network(s)."

# On a clean install, migrate matching legacy PassWall2 ACL assignments by
# the real source subnet. Existing FastACL assignments were already preserved
# by the discovery helper using network/subnet identity.
n=1
while [ "$n" -le "$COUNT" ]; do
    node="$(uci -q get juliang_fastacl.ap$n.node 2>/dev/null || true)"
    subnet="$(uci -q get juliang_fastacl.ap$n.subnet 2>/dev/null || true)"
    if [ -z "$node" ] && [ -n "$subnet" ]; then
        acl="$(find_acl_by_subnet "$subnet")"
        if [ -n "$acl" ]; then
            cand="$(uci -q get passwall2.$acl.node 2>/dev/null || true)"
            if [ -n "$cand" ] && [ "$(uci -q get passwall2.$cand 2>/dev/null || true)" = "nodes" ]; then
                uci set juliang_fastacl.ap$n.node="$cand"
            fi
        fi
    fi
    n=$((n+1))
done
uci commit juliang_fastacl

# Preflight the new router config and dynamic nft syntax before takeover.
cp -af "$TMP_DIR/juliang-fastacl-router.lua" /tmp/jfa-v220-router.lua
lua /tmp/jfa-v220-router.lua > "$TMP_DIR/router-preflight.json"
sing-box check -c "$TMP_DIR/router-preflight.json" >"$TMP_DIR/router-preflight.log" 2>&1 || {
    cat "$TMP_DIR/router-preflight.log"
    fail "sing-box adaptive router preflight failed"
}
sh "$TMP_DIR/juliang-fastacl" firewall-check >"$TMP_DIR/nft-preflight.log" 2>&1 || {
    cat "$TMP_DIR/nft-preflight.log"
    fail "dynamic nftables preflight failed"
}
log "Adaptive router/nft preflight OK."

# Stop any previous FastACL generation before replacing runtime.
if [ -x /usr/bin/juliang-fastacl ]; then
    /usr/bin/juliang-fastacl stop >/dev/null 2>&1 || true
fi

mkdir -p /usr/libexec /usr/lib/lua/luci/controller /etc/hotplug.d/iface
cp -af "$TMP_DIR/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP_DIR/juliang-fastacl-luci-install" /usr/bin/juliang-fastacl-luci-install
cp -af "$TMP_DIR/uninstall-juliang-fastacl" /usr/bin/uninstall-juliang-fastacl
cp -af "$TMP_DIR/juliang-fastacl-router.lua" /usr/libexec/juliang-fastacl-router.lua
cp -af "$TMP_DIR/juliang-fastacl-relay.lua" /usr/libexec/juliang-fastacl-relay.lua
cp -af "$TMP_DIR/juliang-fastacl-discover.lua" /usr/libexec/juliang-fastacl-discover.lua
cp -af "$TMP_DIR/juliang_fastacl.lua" /usr/lib/lua/luci/controller/juliang_fastacl.lua
cp -af "$TMP_DIR/juliang-fastacl.init" /etc/init.d/juliang-fastacl
cp -af "$TMP_DIR/99-juliang-fastacl" /etc/hotplug.d/iface/99-juliang-fastacl

chmod 0755 /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl-luci-install /usr/bin/uninstall-juliang-fastacl
chmod 0755 /etc/init.d/juliang-fastacl /etc/hotplug.d/iface/99-juliang-fastacl
chmod 0644 /usr/libexec/juliang-fastacl-router.lua /usr/libexec/juliang-fastacl-relay.lua /usr/libexec/juliang-fastacl-discover.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua

# Delete stale shadow holder configs outside the discovered range.
n=$((COUNT+1))
while [ "$n" -le 64 ]; do
    uci -q delete passwall2.jfa_ap$n >/dev/null 2>&1 || true
    uci -q delete passwall2.jfa_pre$n >/dev/null 2>&1 || true
    n=$((n+1))
done
uci commit passwall2

# PassWall2 stays as node DB/UI; FastACL owns interception.
if [ "$(uci -q get passwall2.@global[0].enabled 2>/dev/null || echo 0)" != "0" ]; then
    log "One-time handover: stopping PassWall2 transparent proxy runtime..."
    /etc/init.d/passwall2 stop >/tmp/juliang-fastacl-passwall2-handover.log 2>&1 || true
fi
uci -q set passwall2.@global[0].enabled='0'
uci -q set passwall2.@global[0].acl_enable='0'
uci -q set passwall2.@global[0].socks_enabled='0'
uci commit passwall2

# Clear a stale old global process if PassWall2 is disabled but the process survived.
pgrep -af '/tmp/etc/passwall2/acl/default/global.json' 2>/dev/null | awk '!/pgrep|awk/ {print $1}' | xargs -r kill -9 >/dev/null 2>&1 || true

mkdir -p /tmp/juliang-fastacl
log "Starting FastACL adaptive dataplane..."
if ! /usr/bin/juliang-fastacl start >/tmp/juliang-fastacl/v220-start.log 2>&1; then
    cat /tmp/juliang-fastacl/v220-start.log 2>/dev/null || true
    fail "FastACL v2.2 start failed"
fi

/usr/bin/juliang-fastacl-luci-install
/etc/init.d/juliang-fastacl enable >/dev/null 2>&1 || true

echo
echo "================== FastACL status =================="
/usr/bin/juliang-fastacl status
echo
echo "================ discovered WiFi ===================="
n=1
while [ "$n" -le "$COUNT" ]; do
    ssid="$(uci -q get juliang_fastacl.ap$n.ssid 2>/dev/null || echo AP$n)"
    net="$(uci -q get juliang_fastacl.ap$n.network 2>/dev/null || true)"
    subnet="$(uci -q get juliang_fastacl.ap$n.subnet 2>/dev/null || true)"
    echo "AP$n -> SSID: $ssid | network: $net | subnet: $subnet"
    n=$((n+1))
done
echo
echo "[OK] FastACL $VERSION installed"
echo "[OK] WiFi selector is dynamic: only discovered AP networks are shown"
echo "[OK] nftables source set uses only discovered real subnets"
echo "[OK] fw4 input explicitly accepts FastACL mark 0x66 for TProxy client traffic"
echo "[OK] BusyBox integer sleeps / stale mapping cleanup / cross-core preproxy included"
echo "[INFO] Browser: Ctrl+F5 -> PassWall2 -> 节点列表"
echo "[INFO] Rollback: /usr/bin/uninstall-juliang-fastacl"

__JFA_BEGIN_BIN_FASTACL__
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
  /usr/share/passwall2/app.sh socks_node_switch flag="$sec" new_node="$pre" >"$plog" 2>&1 || {
    log "AP$n 前置代理启动命令失败"
    return 1
  }

  i=0
  while [ "$i" -lt 6 ]; do
    (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && return 0
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
    /usr/share/passwall2/app.sh socks_node_switch flag="jfa_ap$n" new_node="$landing_node" >"$swlog" 2>&1 || {
      log "AP$n PassWall2 socks_node_switch 返回失败"
      return 1
    }
  fi
  i=0
  while [ "$i" -lt 5 ]; do
    (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && return 0
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
    if (ss -lnut 2>/dev/null || netstat -lnut 2>/dev/null) | grep -q ":$tport "; then
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
  if [ -s "$RUN_DIR/router.pid" ] && kill -0 "$(cat "$RUN_DIR/router.pid")" 2>/dev/null; then
    if (ss -lnut 2>/dev/null || netstat -lnut 2>/dev/null) | grep -q ":$tport "; then
      router_state="running"
    else
      router_state="broken(no-listener:$tport)"
    fi
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
      listen="no"; (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && listen="yes"
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
  *) echo "Usage: juliang-fastacl {start|stop|restart|discover|firewall|firewall-check|switch AP1 nodeid|move AP1 nodeid|clear AP1|probe AP1|status}"; exit 1 ;;
esac
__JFA_END_BIN_FASTACL__

__JFA_BEGIN_BIN_LUCI_INSTALL__
#!/bin/sh
set -eu

FILE="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"
CTRL="/usr/lib/lua/luci/controller/juliang_fastacl.lua"
MARKER="JULIANG_FASTACL_V220"

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
    echo "[OK] FastACL v2.2 LuCI already installed"
    exit 0
fi

# Upgrade safely from any previous FastACL v2 UI patch. Always repatch from
# the original PassWall2 node list backup to avoid duplicate buttons/modals.
if grep -q 'JULIANG_FASTACL_V2' "$FILE" 2>/dev/null && [ -f "$FILE.jfa-v2.bak" ]; then
    cp -af "$FILE.jfa-v2.bak" "$FILE"
    echo "[INFO] restored original PassWall2 node list before v2.2 repatch"
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

    // JULIANG_FASTACL_V220
    var jfaNode = "";
    var jfaMap = {};
    var jfaLabels = {};
    var jfaIps = {};
    var jfaEngine = "unknown";
    var jfaPreproxy = {};
    var jfaAps = [];

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

        var keep = sel.value || "";
        while (sel.options.length) sel.remove(0);

        var head = document.createElement("option");
        head.value = "";
        head.text = "请选择无线";
        sel.add(head);

        for (var i = 0; i < jfaAps.length; i++) {
            var a = jfaAps[i];
            var o = document.createElement("option");
            o.value = a.ap;
            var name = a.ssid || a.ap;
            var net = a.network ? (" · " + a.network) : "";
            var subnet = a.subnet ? (" · " + a.subnet) : "";
            o.text = name + net + subnet;
            sel.add(o);
        }

        if (keep) sel.value = keep;
    }

    function jfa_load_status(done) {
        XHR.get('<%=jfa_url%>', { action: 'status' }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                jfaMap = result.map || {};
                jfaLabels = result.wireless_labels || {};
                jfaIps = result.ips || {};
                jfaEngine = result.engine || "unknown";
                jfaPreproxy = result.preproxy || {};
                jfaAps = result.aps || [];
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

            if (aps.length && /^AP[0-9]+$/.test(aps[0]))
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
    <div style="font-size:12px;opacity:.72;margin-bottom:13px;">自动读取 SSID / network / IPv4 网段 · 不重启系统 DNS · 只切换当前无线</div>
    <div style="margin:7px 0;">节点：<strong id="jfa_node_name" style="color:#159957"></strong></div>
    <div style="margin:7px 0;">当前：<strong id="jfa_current" style="color:#e6a23c">读取中…</strong></div>
    <div id="jfa_engine" style="margin:7px 0;font-weight:600;">FastACL：检测中…</div>
    <div style="margin:13px 0;">
        <select id="jfa_select" class="cbi-input-select" style="min-width:300px;">
            <option value="">自动读取中…</option>
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
echo "PassWall2 -> 节点列表：自动读取真实无线/网段 + 即时分配 + 跨内核快速前置，并显示出口 IP。"

__JFA_END_BIN_LUCI_INSTALL__

__JFA_BEGIN_BIN_UNINSTALL__
#!/bin/sh
set -u

BACKUP_DIR="/etc/juliang-fastacl/backup"
NODE_LIST="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"

echo "=================================================="
echo " JuLiang FastACL v2 rollback"
echo "=================================================="

/etc/init.d/juliang-fastacl stop >/dev/null 2>&1 || true
/etc/init.d/juliang-fastacl disable >/dev/null 2>&1 || true

# Keep all current PassWall2 nodes and the AP mappings FastACL mirrored into
# the original ACL sections. Only remove our shadow SOCKS holders and restore
# the three original engine switches.
n=1
while [ "$n" -le 64 ]; do
    uci -q delete passwall2.jfa_ap$n
    uci -q delete passwall2.jfa_pre$n
    n=$((n + 1))
done

if [ -f "$BACKUP_DIR/original-flags" ]; then
    . "$BACKUP_DIR/original-flags"
    uci -q set passwall2.@global[0].enabled="${PW2_ENABLED:-0}"
    uci -q set passwall2.@global[0].acl_enable="${PW2_ACL_ENABLE:-1}"
    uci -q set passwall2.@global[0].socks_enabled="${PW2_SOCKS_ENABLED:-0}"
fi
uci -q commit passwall2

if [ -f "$BACKUP_DIR/node_list.htm" ]; then
    cp -af "$BACKUP_DIR/node_list.htm" "$NODE_LIST"
    echo "[OK] restored PassWall2 node list UI"
fi

rm -f /etc/config/juliang_fastacl
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
rm -rf /tmp/juliang-fastacl

/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/passwall2 restart >/tmp/passwall2-fastacl-rollback.log 2>&1 &

echo "[OK] FastACL disabled; current nodes/AP mappings kept"
echo "PassWall2 is restoring in background; log: /tmp/passwall2-fastacl-rollback.log"

__JFA_END_BIN_UNINSTALL__

__JFA_BEGIN_LUA_ROUTER__
local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local cfg = "juliang_fastacl"
local port = tonumber(uci:get(cfg, "main", "tproxy_port") or "12345")
local dns_addr = uci:get(cfg, "main", "dns_server") or "1.1.1.1"

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
      name = s[".name"] or ("ap" .. slot)
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
  dns_servers[#dns_servers + 1] = {
    type = "tcp",
    tag = "dns-" .. tag,
    server = dns_addr,
    server_port = 53,
    detour = tag
  }
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

__JFA_END_LUA_ROUTER__

__JFA_BEGIN_LUA_RELAY__
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

__JFA_END_LUA_RELAY__

__JFA_BEGIN_LUA_DISCOVER__
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
  local key = (s.network and ("net:" .. s.network)) or (s.subnet and ("subnet:" .. s.subnet))
  if key then old[key] = s.node end
end)

-- Remove only AP slot sections; keep main and other future settings.
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
  local node = old["net:"..item.network] or old["subnet:"..item.subnet]
  if node and node ~= "" then uci:set("juliang_fastacl", sec, "node", node) end
end
uci:set("juliang_fastacl", "main", "ap_count", tostring(#items))
uci:commit("juliang_fastacl")

io.write(jsonc.stringify({ ok = (#items > 0), count = #items, aps = items }, true))

__JFA_END_LUA_DISCOVER__

__JFA_BEGIN_LUA_CONTROLLER__
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
    local ok = sys.call("(ss -lnut 2>/dev/null || netstat -lnut 2>/dev/null) | grep -q ':" .. port .. " '") == 0
    return ok and "running" or "broken"
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

__JFA_END_LUA_CONTROLLER__

__JFA_BEGIN_INIT_FASTACL__
#!/bin/sh /etc/rc.common
START=96
STOP=14

start() {
    [ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null)" = "1" ] || return 0
    mkdir -p /tmp/juliang-fastacl
    lua /usr/libexec/juliang-fastacl-discover.lua >/tmp/juliang-fastacl/discover-boot.json 2>/tmp/juliang-fastacl/discover-boot.log || true
    /usr/bin/juliang-fastacl start >/tmp/juliang-fastacl/start.log 2>&1 &
}

stop() {
    /usr/bin/juliang-fastacl stop >/dev/null 2>&1 || true
}

restart() {
    stop
    sleep 1
    start
}

__JFA_END_INIT_FASTACL__

__JFA_BEGIN_HOTPLUG_FASTACL__
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
[ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null)" = "1" ] || exit 0
[ "$INTERFACE" = "loopback" ] && exit 0

# Dynamic version: any interface may be one of the discovered wireless
# networks (a1/a2/tk1/custom names). Re-assert only FastACL's nft/policy rules.
# Node relays and the FastACL router are not restarted.
(
    sleep 1
    /usr/bin/juliang-fastacl firewall >/dev/null 2>&1 || true
) &

__JFA_END_HOTPLUG_FASTACL__
