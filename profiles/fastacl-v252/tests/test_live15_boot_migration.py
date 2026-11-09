#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
wifi = (ROOT / "package/fastacl252/files/etc/init.d/juliang-wifi").read_text(
    encoding="utf-8"
)
defaults = (
    ROOT / "package/fastacl252/files/etc/uci-defaults/99-juliangtk-fastacl252"
).read_text(encoding="utf-8")
theme = (ROOT / "package/luci-theme-juliang/Makefile").read_text(encoding="utf-8")
argon = (
    ROOT / "custom/rax3000m-nand/files/usr/share/ucode/luci/template/themes/argon/header.ut"
).read_text(encoding="utf-8")

assert "USE_PROCD=0" not in wifi
assert "wifi_tuning" in wifi
assert "uci -q delete wireless.$name" not in wifi
assert "if [ \"$(uci -q get wireless.$name)\" = 'wifi-iface' ]" in wifi
assert "mk_iface live24g" in wifi
assert "mk_iface live5g" in wifi

assert "uci set 'luci.main.mediaurlbase=/luci-static/argon'" in defaults
assert "ensure_fastacl_live" in defaults
assert "/etc/init.d/juliang-wifi enable" in defaults

assert "uci -q set luci.main.mediaurlbase='/luci-static/juliang'" not in theme
assert "juliang-tech.css?v=1.5" in argon

print("Live 1.5 boot migration and WiFi persistence: OK")
