#!/bin/sh
set -eu
echo "=================================================="
echo " JuLiang FastACL 2.2.4-hotfix"
echo " remove stale PassWall2 fwmark 0x1 rules"
echo "=================================================="

for pref in $(ip rule show 2>/dev/null | awk '/fwmark 0x1/ && /lookup 100/ {gsub(":", "", $1); print $1}'); do
  echo "[INFO] removing stale rule priority $pref"
  ip rule del priority "$pref" >/dev/null 2>&1 || true
done

echo "===== remaining policy rules ====="
ip rule show | grep -E '0x66|0x1' || true

echo "===== FastACL status ====="
/usr/bin/juliang-fastacl status

echo "[OK] stale PassWall2 fwmark 0x1 cleanup complete"
