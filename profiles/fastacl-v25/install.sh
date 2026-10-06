#!/bin/sh
set -eu
MODE=${1:---check}
case "$MODE" in --check|--preview|--activate) :;; *) echo 'Usage: install.sh --check|--preview|--activate'; exit 2;; esac
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -d "$BASE/root" ] || { echo 'Extract the complete package first'; exit 1; }
[ "$(id -u)" = 0 ] || exit 1
for cmd in lua uci ubus sing-box nft fw4 sha256sum curl; do command -v "$cmd" >/dev/null || { echo "Missing $cmd"; exit 1; }; done
sing-box version | head -n1 | grep -q 'version 1\.12\.' || { echo 'Requires sing-box 1.12.x'; exit 1; }
lua -e 'require "luci.template.parser"; require "luci.jsonc"; require "nixio.fs"; require "lyaml"; local u=require("uci").cursor(); for _,c in ipairs({"fastacl25","dhcp","firewall"}) do local a=u:changes(c); assert(not a or not next(a),"Commit or revert pending UCI changes") end'
find "$BASE/root" -name '*.lua' -type f | while read -r file; do JFA25_FILE="$file" lua -e 'assert(loadfile(os.getenv("JFA25_FILE")))'; done
[ "$MODE" != --check ] || { echo '[OK] FastACL 2.5 fw4 preflight; no files changed'; exit 0; }
B=/etc/fastacl25-backup-$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$B/root"; chmod 700 "$B"; : > "$B/created"
find "$BASE/root" -type f | while read -r file; do
  rel=${file#"$BASE/root/"}
  if [ -f "/$rel" ]; then mkdir -p "$B/root/$(dirname "$rel")"; cp -p "/$rel" "$B/root/$rel"; else echo "$rel" >> "$B/created"; fi
done
mkdir -p "$B/root/etc/config"; cp /etc/config/firewall /etc/config/dhcp "$B/root/etc/config/"
cat > "$B/rollback.sh" <<'ROLLBACK'
#!/bin/sh
set -eu
B=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
/etc/init.d/fastacl25 stop 2>/dev/null || true
/etc/init.d/fastacl25 disable 2>/dev/null || true
/usr/bin/fastacl25 cleanup 2>/dev/null || true
while read -r file; do rm -f "/$file"; done < "$B/created"
cp -a "$B/root/." /
/etc/init.d/firewall reload; /etc/init.d/dnsmasq reload; /etc/init.d/rpcd restart
rm -f /tmp/luci-indexcache.*.json
ROLLBACK
chmod 700 "$B/rollback.sh"
FAILED=1; trap '[ "$FAILED" = 0 ] || sh "$B/rollback.sh"' EXIT HUP INT TERM
find "$BASE/root" -type f | while read -r file; do
  rel=${file#"$BASE/root/"}
  [ "$rel" != etc/config/fastacl25 ] || [ ! -f /etc/config/fastacl25 ] || continue
  mkdir -p "/$(dirname "$rel")"; cp "$file" "/$rel"
done
chmod 755 /usr/bin/fastacl25 /usr/libexec/fastacl25-*.lua /usr/libexec/fastacl25-enable.sh /etc/init.d/fastacl25
if [ "$MODE" = --activate ]; then
  /usr/libexec/fastacl25-enable.sh; /usr/bin/fastacl25 apply
  /etc/init.d/fastacl25 enable; /etc/init.d/fastacl25 start
fi
rm -f /tmp/luci-indexcache.*.json; /etc/init.d/rpcd restart
FAILED=0
echo "[OK] FastACL 2.5.0-dev.1 installed ($MODE); rollback: sh $B/rollback.sh"
