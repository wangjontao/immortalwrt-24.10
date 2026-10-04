#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-files}"
FASTACL_COMMIT="144a65368fdd43df64690f60946a8b7c1a0bec69"
PASSWALL2_ACL_FIX_COMMIT="8d4fdd5"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=================================================="
echo " MT7986 FastACL 2.4.4 integration"
echo " core: $FASTACL_COMMIT"
echo " PassWall2 ACL page fix: $PASSWALL2_ACL_FIX_COMMIT"
echo "=================================================="

mkdir -p "$ROOT"

echo "[1/6] Download FastACL 2.4.4 profile..."
curl --fail --location --show-error --silent   --connect-timeout 30 --max-time 300 --retry 5 --retry-all-errors   "https://codeload.github.com/wangjontao/Actions-OpenWrt/tar.gz/$FASTACL_COMMIT"   -o "$TMP/fastacl.tar.gz"
mkdir -p "$TMP/src"
tar -xzf "$TMP/fastacl.tar.gz" --strip-components=1 -C "$TMP/src"
test -d "$TMP/src/profiles/fastacl-v9/root"
cp -a "$TMP/src/profiles/fastacl-v9/root/." "$ROOT/"

echo "[2/6] Install the verified PassWall2 access-control page fix..."
mkdir -p "$ROOT/usr/lib/lua/luci/view/passwall2"
curl --fail --location --show-error --silent   --connect-timeout 30 --max-time 120 --retry 5 --retry-all-errors   "https://raw.githubusercontent.com/wangjontao/Actions-OpenWrt/$PASSWALL2_ACL_FIX_COMMIT/profiles/proxy-realtime-ip-suite/root/usr/lib/lua/luci/view/passwall2/acl_ip_refresh.htm"   -o "$ROOT/usr/lib/lua/luci/view/passwall2/acl_ip_refresh.htm"
grep -q 'if not _jfa_enabled then' "$ROOT/usr/lib/lua/luci/view/passwall2/acl_ip_refresh.htm"
grep -q '<% end %>' "$ROOT/usr/lib/lua/luci/view/passwall2/acl_ip_refresh.htm"

echo "[3/6] Preset restricted LuCI operator and SSH port..."
cat > "$ROOT/etc/uci-defaults/97-juliang-operator-mode" <<'OPERATOR'
#!/bin/sh

# MT7986 FastACL Stable defaults:
# - root SSH stays root-only, port 20022
# - restricted LuCI-only operator: admin / admin888
[ -x /usr/bin/juliang-operator ] || chmod +x /usr/bin/juliang-operator 2>/dev/null || true
[ -f /usr/libexec/juliang-operator-patch.lua ] && lua /usr/libexec/juliang-operator-patch.lua >/tmp/juliang-operator-patch.log 2>&1 || true

found_dropbear=0
for sec in $(uci -q show dropbear 2>/dev/null | sed -n "s/^dropbear\.\([^.=]*\)=dropbear$/\1/p"); do
  uci set dropbear.$sec.Port='20022'
  found_dropbear=1
done
if [ "$found_dropbear" = '0' ]; then
  sec="$(uci add dropbear dropbear)"
  uci set dropbear.$sec.Port='20022'
fi
uci commit dropbear

[ -e /etc/config/juliang_operator ] || : > /etc/config/juliang_operator
uci -q delete rpcd.juliang_operator >/dev/null 2>&1 || true
uci set rpcd.juliang_operator='login'
uci set rpcd.juliang_operator.username='admin'
uci set rpcd.juliang_operator.password='$1$JFA239$ygsM7RgdJnZKjhDZe/DRv0'
uci add_list rpcd.juliang_operator.read='luci-base'
uci add_list rpcd.juliang_operator.read='luci-base-network-status'
uci add_list rpcd.juliang_operator.read='juliang-operator-home'
uci add_list rpcd.juliang_operator.read='juliang-fastacl-operator'
uci add_list rpcd.juliang_operator.read='juliang-wireless-operator'
uci commit rpcd

uci -q get juliang_operator.main >/dev/null 2>&1 || uci set juliang_operator.main='main'
uci set juliang_operator.main.username='admin'
uci set juliang_operator.main.enabled='1'
uci commit juliang_operator

/etc/init.d/dropbear restart >/dev/null 2>&1 || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache 2>/dev/null || true
exit 0
OPERATOR
chmod 0755 "$ROOT/etc/uci-defaults/97-juliang-operator-mode"

echo "[4/6] Install main-only WiFi defaults..."
install -D -m0755 scripts/juliang-mainwifi-setup.sh "$ROOT/usr/libexec/juliang-mainwifi-setup"
grep -q 'JuLiangTk-5G:48' "$ROOT/usr/libexec/juliang-mainwifi-setup"
grep -q 'JuLiangTk-2.4G:9' "$ROOT/usr/libexec/juliang-mainwifi-setup"
echo "[5/6] Add series runtime guard..."
cat > "$ROOT/etc/uci-defaults/98-fastacl-mt7986-series" <<'SERIES'
#!/bin/sh
[ "$(uci -q get juliang_fastacl.main.runtime_mode)" = normal_proxy ] && exit 0
# FastACL owns transparent dataplane. PassWall/PassWall2 remain installed for
# node storage/UI and as manual fallback when FastACL is intentionally disabled.
uci -q get passwall.@global[0] >/dev/null 2>&1 && {
  uci -q set passwall.@global[0].enabled='0'
  uci -q set passwall.@global[0].acl_enable='0'
  uci -q commit passwall
}
/etc/init.d/passwall stop >/dev/null 2>&1 || true
/etc/init.d/passwall disable >/dev/null 2>&1 || true

uci -q get passwall2.@global[0] >/dev/null 2>&1 && {
  uci -q set passwall2.@global[0].enabled='0'
  uci -q set passwall2.@global[0].acl_enable='0'
  uci -q set passwall2.@global[0].socks_enabled='0'
  uci -q commit passwall2
}
/etc/init.d/passwall2 stop >/dev/null 2>&1 || true
/etc/init.d/passwall2 disable >/dev/null 2>&1 || true
exit 0
SERIES
chmod 0755 "$ROOT/etc/uci-defaults/98-fastacl-mt7986-series"

echo "[6/6] Validate staged FastACL..."
chmod 0755   "$ROOT/usr/bin/juliang-fastacl"   "$ROOT/usr/bin/juliang-fastacl-guard"   "$ROOT/usr/bin/juliang-fastacl-luci-install"   "$ROOT/usr/bin/uninstall-juliang-fastacl"   "$ROOT/usr/bin/juliang-operator"   "$ROOT/etc/init.d/juliang-fastacl"   "$ROOT/etc/hotplug.d/iface/99-juliang-fastacl"   "$ROOT/etc/uci-defaults/94-juliang-fastacl-v9"

sh -n "$ROOT/usr/bin/juliang-fastacl"
sh -n "$ROOT/usr/bin/juliang-fastacl-guard"
sh -n "$ROOT/usr/bin/juliang-operator"
sh -n "$ROOT/etc/uci-defaults/94-juliang-fastacl-v9"
sh -n "$ROOT/etc/uci-defaults/97-juliang-operator-mode"
sh -n "$ROOT/etc/uci-defaults/98-fastacl-mt7986-series"
grep -q 'juliang_killswitch' "$ROOT/usr/bin/juliang-fastacl"
grep -q 'move_node(){' "$ROOT/usr/bin/juliang-fastacl"
grep -q 'runtime_mode' "$ROOT/usr/bin/juliang-fastacl-guard"
grep -q "option version '2.4.4'" "$ROOT/etc/config/juliang_fastacl"
grep -q "Port='20022'" "$ROOT/etc/uci-defaults/97-juliang-operator-mode"
grep -q "username='admin'" "$ROOT/etc/uci-defaults/97-juliang-operator-mode"
grep -q 'juliang_operator_stats' "$ROOT/usr/lib/lua/luci/controller/juliang_operator.lua"
grep -q 'router_down_bytes' "$ROOT/usr/lib/lua/luci/controller/juliang_operator.lua"

echo "[OK] FastACL 2.4.4 staged for MT7986 series."
echo "[OK] PassWall2 ACL page uses verified FastACL-aware syntax fix."
echo "[OK] Uploaded PassWall/PassWall2 ACL profiles remain fallback-only."

# Patch the pinned PassWall2 importer before rootfs packaging.
sed "s|^TARGET=/usr/share/passwall2/subscribe.lua$|TARGET=$PWD/package/luci-app-passwall2/root/usr/share/passwall2/subscribe.lua|; s|^BASE=/etc/passwall2-import-repair$|BASE=$TMP/import-backup|" "$ROOT/usr/bin/juliang-fastacl-import-repair" > "$TMP/import-repair.sh"
sh "$TMP/import-repair.sh"
grep -q 'visibility_all' "$ROOT/usr/lib/lua/luci/controller/juliang_operator.lua"
grep -q 'toggleAllVisibility' "$ROOT/usr/lib/lua/luci/view/juliang_operator/wireless.htm"
test -x "$ROOT/usr/bin/juliang-fastacl-runtime"
