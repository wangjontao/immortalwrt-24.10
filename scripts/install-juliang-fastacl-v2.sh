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

log "Downloading pinned runtime $RUNTIME_SHA ..."
log "IPv4 + per-file timeout enabled; this stage should finish in under a few minutes."
fetch "usr/bin/juliang-fastacl" "$TMP_DIR/juliang-fastacl"
fetch "usr/bin/juliang-fastacl-luci-install" "$TMP_DIR/juliang-fastacl-luci-install"
fetch "usr/bin/uninstall-juliang-fastacl" "$TMP_DIR/uninstall-juliang-fastacl"
fetch "usr/libexec/juliang-fastacl-router.lua" "$TMP_DIR/juliang-fastacl-router.lua"
fetch "usr/libexec/juliang-fastacl-relay.lua" "$TMP_DIR/juliang-fastacl-relay.lua"
fetch "usr/lib/lua/luci/controller/juliang_fastacl.lua" "$TMP_DIR/juliang_fastacl.lua"
fetch "etc/init.d/juliang-fastacl" "$TMP_DIR/juliang-fastacl.init"
fetch "etc/hotplug.d/iface/99-juliang-fastacl" "$TMP_DIR/99-juliang-fastacl"

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
