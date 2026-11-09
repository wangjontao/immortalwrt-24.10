#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
controller = (
    ROOT / "custom/rax3000m-nand/files/usr/lib/lua/luci/controller/juliang_dashboard.lua"
).read_text(encoding="utf-8")
home = (
    ROOT / "custom/rax3000m-nand/files/usr/lib/lua/luci/view/juliang_dashboard/home.htm"
).read_text(encoding="utf-8")
theme = (ROOT / "package/luci-theme-juliang/root/etc/init.d/juliang-theme").read_text(
    encoding="utf-8"
)
css = (
    ROOT / "package/luci-theme-juliang/htdocs/luci-static/juliang/juliang.css"
).read_text(encoding="utf-8")
header = (
    ROOT / "package/luci-theme-juliang/ucode/template/themes/juliang/header.ut"
).read_text(encoding="utf-8")
config = (ROOT / "build-configs/JuLiang-OS-Live1.3-SR503.txt").read_text(
    encoding="utf-8"
)
integration = (ROOT / "scripts/integrate-juliang-live13-sr503.sh").read_text(
    encoding="utf-8"
)

assert 'entry({"admin", "home_status"}, call("dashboard_status"), nil)' in controller
assert 'build_url("admin", "home_status")' in home
assert "admin/home/status" not in controller
assert "admin/home/status" not in home

assert "mediaurlbase='/luci-static/juliang'" in theme
assert "mediaurlbase='/luci-static/argon'" not in theme
assert "ui_assets" in theme and "ui_migration" in theme
assert "juliang.css?v=1.5-r3" in header
assert "JuLiang Live hard theme" in css
assert "background:#0a1b29!important" in css
assert "background:#163246!important" in css
assert "#f25-wifi-count" in css

assert "CONFIG_PACKAGE_luci-theme-juliang=y" in config
assert "CONFIG_PACKAGE_luci-theme-argon=y" not in config
assert "CONFIG_PACKAGE_luci-app-argon-config=y" not in config
assert "rm -rf files/usr/share/ucode/luci/template/themes/argon" in integration
assert "Argon must not be selected" in integration

print("Live 1.5 home status, JuLiang theme, and dark colors: OK")
