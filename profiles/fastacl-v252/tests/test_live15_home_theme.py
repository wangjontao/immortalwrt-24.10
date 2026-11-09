#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
controller = (
    ROOT / "custom/rax3000m-nand/files/usr/lib/lua/luci/controller/juliang_dashboard.lua"
).read_text(encoding="utf-8")
egress_probe = (
    ROOT / "custom/rax3000m-nand/files/usr/libexec/juliang-egress-probe"
).read_text(encoding="utf-8")
dashboard_init = (
    ROOT / "custom/rax3000m-nand/files/etc/init.d/juliang-dashboard"
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
footer = (
    ROOT / "package/luci-theme-juliang/ucode/template/themes/juliang/footer.ut"
).read_text(encoding="utf-8")
theme_root = ROOT / "package/luci-theme-juliang"
nav = (
    theme_root / "htdocs/luci-static/juliang/nav-r4.js"
).read_text(encoding="utf-8")
status = (
    theme_root / "htdocs/luci-static/juliang/status-r4.js"
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
assert "jd-egress-list" in home and "items.slice(0, 4)" in home
assert "createCountryIcon" in home and "jd-egress-icon" in home
assert "color: #67e9ac" in home
assert "/tmp/juliang-dashboard-egress.state" in controller
assert "/tmp/fastacl252/singbox.json" in controller
assert "source_ip_cidr" in controller and "items = items" in controller
assert "sing-box tools fetch" in egress_probe
assert "cdn-cgi/trace" in egress_probe
assert "juliang-dashboard-egress.state" in egress_probe
assert "outbounds[*].tag" in egress_probe
assert "active_tags" in egress_probe and "for tag in $tags" in egress_probe
assert "procd_set_param command /usr/libexec/juliang-egress-probe" in dashboard_init

assert "mediaurlbase='/luci-static/juliang'" in theme
assert "mediaurlbase='/luci-static/argon'" not in theme
assert "ui_assets" in theme and "ui_migration" in theme
assert "juliang-1.5-r4" in theme
assert "juliang.css?v=1.5-r4" in header
assert "status-r4.js?v=1.5-r4" in header
assert "nav-r4.js?v=1.5-r4" in footer
assert "L.require('menu-juliang')" not in footer
assert "menu-juliang" not in header + footer
for label in (
    "首页",
    "状态概览",
    "系统管理",
    "国际互联",
    "网络配置",
    "退出",
    "PassWall2",
    "直播 Live",
    "HomeProxy",
):
    assert label in header, label
assert "dropdown-menu" in nav and "aria-expanded" in nav
assert "renderPageTabs" in nav and "ui.menu.load" in nav
assert "getElementById('tabmenu')" in nav
assert "admin/home_status" in status and "egress" in status
assert "primary.items" in status and "renderEgress" in status
assert not list(theme_root.rglob("menu-juliang*.js"))
assert (theme_root / "htdocs/luci-static/juliang/nav-r4.js").is_file()
assert (theme_root / "htdocs/luci-static/juliang/status-r4.js").is_file()
assert "JuLiang Live hard theme" in css
assert "color:#67e9ac" in css
assert 'data-page^="admin-services-passwall2"' in css
assert "background:#0a1b29!important" in css
assert "background:#163246!important" in css
assert "#f25-wifi-count" in css

assert "CONFIG_PACKAGE_luci-theme-juliang=y" in config
assert "CONFIG_PACKAGE_luci-theme-argon=y" not in config
assert "CONFIG_PACKAGE_luci-app-argon-config=y" not in config
assert "rm -rf files/usr/share/ucode/luci/template/themes/argon" in integration
assert "Argon must not be selected" in integration

print("Live 1.5 home status, JuLiang theme, and dark colors: OK")
