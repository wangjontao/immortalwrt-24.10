#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
profile = ROOT / "profiles/fastacl-v252"

for relative in (
    "root/usr/lib/lua/luci/controller/juliang_upgrade.lua",
    "root/usr/lib/lua/luci/view/juliang_center/upgrade.htm",
    "root/usr/libexec/fastacl-upgrade-worker",
    "root/etc/config/fastacl-upgrade",
    "root/etc/fastacl-upgrade",
):
    assert not (profile / relative).exists(), relative

print("Online firmware upgrade is removed: OK")
