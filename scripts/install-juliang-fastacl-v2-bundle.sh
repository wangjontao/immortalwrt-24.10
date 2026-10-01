#!/bin/sh
set -eu

VERSION="2.0.3"
RUNTIME_SHA="f77823de55fb69811ba64681367473009e0811c7"
BASE="https://raw.githubusercontent.com/wangjontao/immortalwrt-24.10/$RUNTIME_SHA/profiles/juliang-fastacl-v2"
BACKUP_DIR="/etc/juliang-fastacl/backup"
TMP_DIR="/tmp/juliang-fastacl-install-$$"
NODE_LIST="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"

log() { echo "[JFA-INSTALL] $*"; }
fail() { echo "[JFA-INSTALL][ERROR] $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

fetch() {
    rel="$1"
    dst="$2"
    url="$BASE/$rel"
    mkdir -p "$(dirname "$dst")"
    log "fetch: $rel"

    # Prefer IPv4 on this S20L. raw.githubusercontent.com may resolve IPv6 first
    # and wget can sit on an unhealthy v6 path for a long time with no output.
    if command -v curl >/dev/null 2>&1; then
        if curl -4 -fL --connect-timeout 5 --max-time 30 --retry 2 --retry-delay 1 -o "$dst" "$url"; then
            [ -s "$dst" ] || fail "downloaded empty file: $rel"
            return 0
        fi
        log "curl IPv4 failed, trying wget IPv4..."
    fi

    if wget -4 --timeout=10 --tries=2 -O "$dst" "$url"; then
        [ -s "$dst" ] || fail "downloaded empty file: $rel"
        return 0
    fi

    fail "download failed: $rel"
}

find_acl_section() {
    n="$1"
    subnet="172.16.$n.0/24"
    uci -q show passwall2 | awk -F'[.=]' -v A="AP$n" -v S="$subnet" '
        /\.remarks=/{gsub("\047", "", $0); if ($0 ~ "=" A "$") print $2}
        /\.sources=/{gsub("\047", "", $0); if ($0 ~ "=" S "$") print $2}
    ' | head -n1
}

is_listening() {
    port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":$port "
    else
        netstat -lnt 2>/dev/null | grep -q ":$port "
    fi
}

emergency_rollback() {
    log "FastACL first start failed; restoring original PassWall2 configuration..."
    /usr/bin/juliang-fastacl stop >/dev/null 2>&1 || true
    if [ -f "$BACKUP_DIR/passwall2" ]; then
        cp -af "$BACKUP_DIR/passwall2" /etc/config/passwall2
    fi
    /etc/init.d/passwall2 restart >/tmp/passwall2-fastacl-emergency-rollback.log 2>&1 &
    log "PassWall2 rollback started in background."
    log "Rollback log: /tmp/passwall2-fastacl-emergency-rollback.log"
}

echo "=================================================="
echo " JuLiang FastACL v$VERSION"
echo " S20L 20WiFi fixed TProxy + instant AP node switch"
echo "=================================================="

[ "$(id -u)" = "0" ] || fail "run as root"
[ -f /etc/config/passwall2 ] || fail "PassWall2 config not found"
[ -f /usr/share/passwall2/app.sh ] || fail "PassWall2 runtime not found"
[ -f "$NODE_LIST" ] || fail "PassWall2 node list UI not found"

for cmd in uci nft ip lua sing-box curl wget; do
    command -v "$cmd" >/dev/null 2>&1 || fail "missing command: $cmd"
done

mkdir -p "$TMP_DIR" "$BACKUP_DIR"

# Persistent recovery material. Keep the very first pre-FastACL backup.
if [ ! -f "$BACKUP_DIR/passwall2" ]; then
    cp -a /etc/config/passwall2 "$BACKUP_DIR/passwall2"
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
        cp -a "$NODE_LIST.quick-acl.bak" "$BACKUP_DIR/node_list.htm"
    elif [ -f "$NODE_LIST.jfa-v2.bak" ]; then
        cp -a "$NODE_LIST.jfa-v2.bak" "$BACKUP_DIR/node_list.htm"
    else
        cp -a "$NODE_LIST" "$BACKUP_DIR/node_list.htm"
    fi
fi

log "Using bundled runtime payload; no additional GitHub downloads are needed."\ncat > "$TMP_DIR/juliang-fastacl" <<'JFA_PAYLOAD_1'
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
  uci set $APP.$sec.log='0'
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
    /usr/share/passwall2/app.sh socks_node_switch flag="jfa_ap$n" new_node="$node" >/dev/null 2>&1 || return 1
  fi
  i=0
  while [ "$i" -lt 30 ]; do
    (ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null) | grep -q ":$port " && return 0
    sleep 0.1; i=$((i+1))
  done
  log "AP$n 本地 SOCKS 端口 $port 未就绪"
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
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst return
     ip saddr @ap_sources meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $MARK_HEX accept
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
     ip saddr @ap_sources meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT meta mark set $MARK_HEX accept
     ip saddr @ap_sources ip daddr @local_dst return
     ip saddr @ap_sources meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $MARK_HEX accept
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
  clear) [ $# -eq 2 ] || exit 2; clear_ap "$2" ;;
  probe) n="$(ap_num "$2")" || exit 2; probe_ap "$n" ;;
  status) status ;;
  *) echo "Usage: juliang-fastacl {start|stop|restart|firewall|firewall-check|switch AP1 nodeid|clear AP1|probe AP1|status}"; exit 1 ;;
esac
JFA_PAYLOAD_1
cat > "$TMP_DIR/juliang-fastacl-luci-install" <<'JFA_PAYLOAD_2'
#!/bin/sh
set -eu

FILE="/usr/lib/lua/luci/view/passwall2/node_list/node_list.htm"
CTRL="/usr/lib/lua/luci/controller/juliang_fastacl.lua"
MARKER="JULIANG_FASTACL_V2"

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

    // JULIANG_FASTACL_V2
    var jfaNode = "";
    var jfaMap = {};
    var jfaLabels = {};
    var jfaIps = {};
    var jfaEngine = "unknown";

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
                jfa_refresh_select();
                jfa_update_buttons();
            }
            if (done) done(result || {});
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

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "[OK] FastACL v2 LuCI installed"
echo "PassWall2 -> 节点列表：每个节点右侧显示“分配无线/无线SSID”，并显示已检测出口 IP。"

JFA_PAYLOAD_2
cat > "$TMP_DIR/uninstall-juliang-fastacl" <<'JFA_PAYLOAD_3'
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
while [ "$n" -le 20 ]; do
    uci -q delete passwall2.jfa_ap$n
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

JFA_PAYLOAD_3
cat > "$TMP_DIR/juliang-fastacl-router.lua" <<'JFA_PAYLOAD_4'
local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local cfg = "juliang_fastacl"
local port = tonumber(uci:get(cfg, "main", "tproxy_port") or "12345")
local dns_addr = uci:get(cfg, "main", "dns_server") or "1.1.1.1"

local outbounds = { { type = "direct", tag = "direct" } }
local route_rules = {}
local dns_servers = {}
local dns_rules = {}

for i = 1, 20 do
  local s = "ap" .. i
  local subnet = uci:get(cfg, s, "subnet") or string.format("172.16.%d.0/24", i)
  local sport = tonumber(uci:get(cfg, s, "socks_port") or tostring(13100 + i))
  local tag = "ap" .. i
  outbounds[#outbounds + 1] = {
    type = "socks",
    tag = tag,
    server = "127.0.0.1",
    server_port = sport,
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
    source_ip_cidr = { subnet },
    action = "route",
    server = "dns-" .. tag
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { subnet },
    port = { 53 },
    action = "hijack-dns"
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { subnet },
    action = "route",
    outbound = tag
  }
end

local conf = {
  log = { level = "warn", timestamp = true },
  dns = {
    servers = dns_servers,
    rules = dns_rules,
    final = "dns-ap1"
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

JFA_PAYLOAD_4
cat > "$TMP_DIR/juliang-fastacl-relay.lua" <<'JFA_PAYLOAD_5'
local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local node = arg[1] or ""
local port = tonumber(arg[2] or "0")
local outfile = arg[3] or ""
if node == "" or port == 0 or outfile == "" then os.exit(2) end
local n = uci:get_all("passwall2", node)
if not n then os.exit(3) end
local t = string.lower(n.type or "")
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
local conf = {
  log = { level = "error" },
  inbounds = { { type = "socks", tag = "in", listen = "127.0.0.1", listen_port = port } },
  outbounds = { out },
  route = { final = "proxy" }
}
local f = assert(io.open(outfile, "w"))
f:write(jsonc.stringify(conf, true))
f:close()

JFA_PAYLOAD_5
cat > "$TMP_DIR/juliang_fastacl.lua" <<'JFA_PAYLOAD_6'
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
        local result = exec_json(
            "/usr/bin/juliang-fastacl switch " ..
            ap .. " " .. util.shellquote(node)
        )

        local cleared = {}
        if result.ok and exclusive then
            for i = 1, 20 do
                if i ~= n and (uci:get("juliang_fastacl", "ap" .. i, "node") or "") == node then
                    local old_ap = "AP" .. i
                    local r = exec_json("/usr/bin/juliang-fastacl clear " .. old_ap)
                    if r.ok then cleared[#cleared + 1] = old_ap end
                end
            end
        end

        result.cleared = cleared
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

JFA_PAYLOAD_6
cat > "$TMP_DIR/juliang-fastacl.init" <<'JFA_PAYLOAD_7'
#!/bin/sh /etc/rc.common
START=96
STOP=14

start() {
    [ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null)" = "1" ] || return 0
    mkdir -p /tmp/juliang-fastacl
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

JFA_PAYLOAD_7
cat > "$TMP_DIR/99-juliang-fastacl" <<'JFA_PAYLOAD_8'
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
[ "$(uci -q get juliang_fastacl.main.enabled 2>/dev/null)" = "1" ] || exit 0

# Re-assert only our dedicated fixed table and policy route.
# Node processes/router are not restarted.
case "$INTERFACE" in
    lan|wan|tk*|loopback)
        /usr/bin/juliang-fastacl firewall >/dev/null 2>&1 || true
        ;;
esac

JFA_PAYLOAD_8

mkdir -p /usr/libexec /usr/lib/lua/luci/controller /etc/hotplug.d/iface
cp -af "$TMP_DIR/juliang-fastacl" /usr/bin/juliang-fastacl
cp -af "$TMP_DIR/juliang-fastacl-luci-install" /usr/bin/juliang-fastacl-luci-install
cp -af "$TMP_DIR/uninstall-juliang-fastacl" /usr/bin/uninstall-juliang-fastacl
cp -af "$TMP_DIR/juliang-fastacl-router.lua" /usr/libexec/juliang-fastacl-router.lua
cp -af "$TMP_DIR/juliang-fastacl-relay.lua" /usr/libexec/juliang-fastacl-relay.lua
cp -af "$TMP_DIR/juliang_fastacl.lua" /usr/lib/lua/luci/controller/juliang_fastacl.lua
cp -af "$TMP_DIR/juliang-fastacl.init" /etc/init.d/juliang-fastacl
cp -af "$TMP_DIR/99-juliang-fastacl" /etc/hotplug.d/iface/99-juliang-fastacl
chmod 0755 /usr/bin/juliang-fastacl /usr/bin/juliang-fastacl-luci-install /usr/bin/uninstall-juliang-fastacl
chmod 0755 /etc/init.d/juliang-fastacl /etc/hotplug.d/iface/99-juliang-fastacl
chmod 0644 /usr/libexec/juliang-fastacl-router.lua /usr/libexec/juliang-fastacl-relay.lua /usr/lib/lua/luci/controller/juliang_fastacl.lua

lua -e 'assert(loadfile("/usr/libexec/juliang-fastacl-router.lua"))'
lua -e 'assert(loadfile("/usr/libexec/juliang-fastacl-relay.lua"))'
lua -e 'assert(loadfile("/usr/lib/lua/luci/controller/juliang_fastacl.lua"))'

# Create FastACL UCI without discarding existing FastACL mappings on re-install.
touch /etc/config/juliang_fastacl
[ "$(uci -q get juliang_fastacl.main 2>/dev/null || true)" = "main" ] || uci set juliang_fastacl.main='main'
uci set juliang_fastacl.main.enabled='1'
uci set juliang_fastacl.main.app='passwall2'
uci set juliang_fastacl.main.tproxy_port='12345'
uci set juliang_fastacl.main.mark='102'
uci set juliang_fastacl.main.route_table='100'
uci set juliang_fastacl.main.dns_server='1.1.1.1'

log "Migrating AP1-AP20 mappings from existing PassWall2 ACL..."
n=1
while [ "$n" -le 20 ]; do
    sec="ap$n"
    [ "$(uci -q get juliang_fastacl.$sec 2>/dev/null || true)" = "ap" ] || uci set juliang_fastacl.$sec='ap'
    uci set juliang_fastacl.$sec.subnet="172.16.$n.0/24"
    uci set juliang_fastacl.$sec.socks_port="$((13100 + n))"

    existing="$(uci -q get juliang_fastacl.$sec.node 2>/dev/null || true)"
    if [ -z "$existing" ]; then
        acl="$(find_acl_section "$n")"
        if [ -n "$acl" ]; then
            node="$(uci -q get passwall2.$acl.node 2>/dev/null || true)"
            if [ -n "$node" ] && [ "$(uci -q get passwall2.$node 2>/dev/null || true)" = "nodes" ]; then
                uci set juliang_fastacl.$sec.node="$node"
            fi
        fi
    fi

    node="$(uci -q get juliang_fastacl.$sec.node 2>/dev/null || true)"
    log "migrate AP$n -> ${node:-unassigned}"
    uci -q delete passwall2.jfa_ap$n >/dev/null 2>&1 || true
    uci set passwall2.jfa_ap$n='socks'
    uci set passwall2.jfa_ap$n.enabled='0'
    uci set passwall2.jfa_ap$n.bind_local='1'
    uci set passwall2.jfa_ap$n.port="$((13100 + n))"
    uci set passwall2.jfa_ap$n.http_port='0'
    uci set passwall2.jfa_ap$n.log='0'
    uci set passwall2.jfa_ap$n.enable_autoswitch='0'
    [ -n "$node" ] && uci set passwall2.jfa_ap$n.node="$node" || true

    n=$((n + 1))
done
uci commit juliang_fastacl
uci commit passwall2

# Preflight happens BEFORE taking over traffic. If either check fails, the
# existing PassWall2 runtime remains untouched.
mkdir -p /etc/juliang-fastacl /tmp/juliang-fastacl
lua /usr/libexec/juliang-fastacl-router.lua > /tmp/juliang-fastacl/router-preflight.json
if ! sing-box check -c /tmp/juliang-fastacl/router-preflight.json >/tmp/juliang-fastacl/router-preflight.log 2>&1; then
    cat /tmp/juliang-fastacl/router-preflight.log
    fail "sing-box router preflight failed; PassWall2 was not stopped"
fi

if ! /usr/bin/juliang-fastacl firewall-check >/tmp/juliang-fastacl/nft-preflight.log 2>&1; then
    cat /tmp/juliang-fastacl/nft-preflight.log
    fail "nftables TProxy preflight failed; PassWall2 was not stopped"
fi

log "Preflight OK."
log "One-time handover: stopping the old PassWall2 ACL engine."
log "Your current PassWall2 stop path may take about 1-2 minutes THIS ONE TIME."
/etc/init.d/passwall2 stop >/tmp/juliang-fastacl/passwall2-one-time-stop.log 2>&1 || true

# PassWall2 stays installed as the node database/UI. Only its transparent
# proxy/ACL runtime is disabled. FastACL now owns AP1-AP20 interception.
uci -q set passwall2.@global[0].enabled='0'
uci -q set passwall2.@global[0].acl_enable='0'
uci -q set passwall2.@global[0].socks_enabled='0'
uci commit passwall2

log "Starting fixed FastACL router and current AP mappings..."
if ! /usr/bin/juliang-fastacl start >/tmp/juliang-fastacl/first-start.log 2>&1; then
    cat /tmp/juliang-fastacl/first-start.log
    emergency_rollback
    fail "FastACL start failed; original PassWall2 restored"
fi

# Hard health checks: fixed router + nft table + every migrated AP local SOCKS.
[ -s /tmp/juliang-fastacl/router.pid ] || {
    emergency_rollback
    fail "FastACL router PID missing"
}
kill -0 "$(cat /tmp/juliang-fastacl/router.pid)" >/dev/null 2>&1 || {
    cat /tmp/juliang-fastacl/router.log 2>/dev/null || true
    emergency_rollback
    fail "FastACL router process exited"
}
nft list table inet juliang_fastacl >/dev/null 2>&1 || {
    emergency_rollback
    fail "FastACL nftables table missing"
}

bad=0
mapped=0
n=1
while [ "$n" -le 20 ]; do
    node="$(uci -q get juliang_fastacl.ap$n.node 2>/dev/null || true)"
    if [ -n "$node" ]; then
        mapped=$((mapped + 1))
        port=$((13100 + n))
        if ! is_listening "$port"; then
            log "AP$n local SOCKS $port is NOT listening"
            bad=$((bad + 1))
        fi
    fi
    n=$((n + 1))
done

if [ "$bad" -gt 0 ]; then
    cat /tmp/juliang-fastacl/first-start.log 2>/dev/null || true
    emergency_rollback
    fail "$bad migrated AP relay(s) failed; original PassWall2 restored"
fi

/etc/init.d/juliang-fastacl enable
/usr/bin/juliang-fastacl-luci-install

# Remove the obsolete v1 Quick-ACL API/helper after the v2 UI is live.
rm -f /usr/lib/lua/luci/controller/juliang_quick_acl.lua
rm -f /usr/bin/juliang-quick-acl-apply
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo
echo "=================================================="
echo " FastACL v2 installation complete"
echo "=================================================="
echo "Migrated AP mappings: $mapped"
echo "Switching a node now changes only one AP local proxy on ports 13101-13120."
echo "Fixed nftables TProxy stays on port 12345; system dnsmasq is not restarted."
echo
/usr/bin/juliang-fastacl status
echo
echo "Open: PassWall2 -> Node List"
echo "Use: 分配无线 -> 无线AP1...无线AP20 -> 立即切换"
echo "Rollback: /usr/bin/uninstall-juliang-fastacl"
