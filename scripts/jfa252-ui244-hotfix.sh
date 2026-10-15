#!/bin/sh
set -eu

TAG="jfa252-ui244-20261015"
TARGET="/usr/lib/lua/luci/view/fastacl252/console.htm"
RAW="https://raw.githubusercontent.com/wangjontao/immortalwrt-24.10/codex/fastacl252-ui244-fix/profiles/fastacl-v252/root/usr/lib/lua/luci/view/fastacl252/console.htm"
TMP="/tmp/${TAG}.console.htm"
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
BACKUP="/root/${TAG}-backup-${STAMP}"

printf '%s\n' "=================================================="
printf '%s\n' " JuLiangTK FastACL 2.5.2 UI -> 2.4.4 style hotfix"
printf '%s\n' "=================================================="

[ -f "$TARGET" ] || { echo "[ERR] FastACL 2.5.2 console not found: $TARGET"; exit 1; }
mkdir -p "$BACKUP"
cp -p "$TARGET" "$BACKUP/console.htm"
echo "[OK] backup: $BACKUP/console.htm"

rm -f "$TMP"
if command -v curl >/dev/null 2>&1; then
  curl -4 -fL --connect-timeout 10 --max-time 90 --retry 3 -o "$TMP" "$RAW"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMP" "$RAW"
else
  echo "[ERR] curl/wget not found"
  exit 1
fi

[ -s "$TMP" ] || { echo "[ERR] downloaded UI is empty"; exit 1; }
grep -q '2.4.4 风格控制台' "$TMP" || { echo "[ERR] UI marker missing"; exit 1; }
grep -q 'id="f25-assign-bg"' "$TMP" || { echo "[ERR] assignment modal missing"; exit 1; }
grep -q 'function renderBatch()' "$TMP" || { echo "[ERR] batch-node renderer missing"; exit 1; }
grep -q '主 WiFi · 设备分配' "$TMP" || { echo "[ERR] device assignment table missing"; exit 1; }

chmod 0644 "$TMP"
mv -f "$TMP" "$TARGET"

rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

cat <<EOF
[OK] FastACL 2.5.2 UI hotfix installed.
[OK] No network / WiFi / firewall / dae restart was performed.
[OK] Existing imported nodes and UCI configuration were not changed.

Browser: Ctrl+F5 hard refresh, then verify:
  1. 节点分配 -> each node has [分配]
  2. 分配 target can choose 主 WiFi 设备 / 附加 WiFi
  3. 主 WiFi table node dropdown contains imported nodes
  4. batch node dropdown is populated
  5. 附加 WiFi table can independently choose node

Rollback:
  cp -f "$BACKUP/console.htm" "$TARGET"
  rm -f /tmp/luci-indexcache /tmp/luci-indexcache.*
  /etc/init.d/uhttpd restart
EOF
