#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
integration = (ROOT / "scripts/integrate-juliang-os-285.sh").read_text(encoding="utf-8")
wan_mac = (
    ROOT / "profiles/fastacl-v252/root/usr/libexec/nps-wan-mac"
).read_text(encoding="utf-8")

assert "nps.jontao.top" in integration
assert "nps.jontao.top" in wan_mac
assert "nps_domain=${NPS_DOMAIN:-nps.jontao.top}" in integration
assert "option server_addr '${nps_domain}'" in integration
assert "package/fastacl252/files/usr/libexec/nps-wan-mac" in integration
assert 'if [ ! -e "$DONE" ]' not in wan_mac
assert "uci -q set nps.@nps[0].server_addr='nps.jontao.top'" in wan_mac
assert "nps.66ccs.com" not in integration
assert "nps.66ccs.com" not in wan_mac

print("PASS JuLiang NPS endpoint nps.jontao.top")
