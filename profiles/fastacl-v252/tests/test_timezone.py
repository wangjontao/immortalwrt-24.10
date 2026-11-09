#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
worker = (ROOT / "root/usr/libexec/fastacl252-timezone-sync").read_text(encoding="utf-8")
console = (ROOT / "root/usr/lib/lua/luci/view/fastacl252/console.htm").read_text(encoding="utf-8")
controller = (ROOT / "root/usr/lib/lua/luci/controller/fastacl252.lua").read_text(encoding="utf-8")
defaults = (ROOT / "root/etc/uci-defaults/99-juliangtk-fastacl252").read_text(encoding="utf-8")

assert "fastacl252-exit-probe" in worker
assert "lan.mode=='proxy'" in worker
assert "/etc/init.d/system reload" in worker
assert "timezone" in worker and "zonename" in worker
assert 'id="f25-auto-timezone"' in console
assert "payload.auto_timezone" in console
assert "auto_timezone=c.auto_timezone" in controller
assert "fastacl252.main.auto_timezone=1" in defaults

print("PASS main-exit timezone sync wiring")
