from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
THEME = ROOT / "package/luci-theme-juliang"
CONFIG = ROOT / "build-configs/JuLiang-OS-Live1.3-SR503.txt"


header = (THEME / "ucode/template/themes/juliang/header.ut").read_text(encoding="utf-8")
footer = (THEME / "ucode/template/themes/juliang/footer.ut").read_text(encoding="utf-8")
login = (THEME / "ucode/template/themes/juliang/sysauth.ut").read_text(encoding="utf-8")
nav = (THEME / "htdocs/luci-static/juliang/nav-r4.js").read_text(encoding="utf-8")
css = (THEME / "htdocs/luci-static/juliang/juliang.css").read_text(encoding="utf-8")
makefile = (THEME / "Makefile").read_text(encoding="utf-8")
config = CONFIG.read_text(encoding="utf-8")
target_mk = (ROOT / "include/target.mk").read_text(encoding="utf-8")
console = (THEME.parents[1] / "profiles/fastacl-v252/root/usr/lib/lua/luci/view/fastacl252/console.htm").read_text(encoding="utf-8")
fastacl_controller = (ROOT / "profiles/fastacl-v252/root/usr/lib/lua/luci/controller/fastacl252.lua").read_text(encoding="utf-8")
theme_defaults = (THEME / "root/etc/uci-defaults/30_luci-theme-juliang").read_text(encoding="utf-8")
theme_migration = (THEME / "root/etc/init.d/juliang-theme").read_text(encoding="utf-8")
fastacl_defaults = (
    ROOT / "profiles/fastacl-v252/root/etc/uci-defaults/99-juliangtk-fastacl252"
).read_text(encoding="utf-8")
fastacl_config = (
    ROOT / "profiles/fastacl-v252/root/etc/config/fastacl252"
).read_text(encoding="utf-8")
luci_session = (
    ROOT / "profiles/fastacl-v252/root/etc/uci-defaults/97-juliang-luci-session"
).read_text(encoding="utf-8")

assert "JuLiang OS" in header
assert "v1.5" in header and "v1.5" in footer
assert "routeTitles['admin-juliang-home']" not in header
assert "const routeTitles = {\n\t\t'': 'JuLiang OS 监测中心'" in header
assert "炬量网络控制台" in login
assert "juliang-access-mark" not in login
assert "juliang-login-version" not in login
assert 'name="luci_username"' in login and 'name="luci_password"' in login
assert "nav-r4.js" in footer
assert "L.require('menu-juliang')" not in footer
assert "menu-juliang" not in header + footer
assert "国际互联" in header and "PassWall2" in header and "HomeProxy" in header
assert "dropdown-menu" in nav
assert "juliang-theme" in css and "--jl-cyan: #67dce7" in css
assert "linear-gradient" in css and "@media (max-width: 900px)" in css
assert "letter-spacing: -" not in css
assert "-webkit-font-smoothing: antialiased" in css and "text-rendering: auto" in css
assert "overflow-y: auto" in css
assert ".juliang-theme input:disabled" in css and ".juliang-theme select:disabled" in css
assert "html body.juliang-theme button:disabled" in css
assert "juliang.css?v=1.5-r4" in header
assert "html body:has(.f252){height:auto!important" in console
assert "body:has(.f252) .f25-content{flex:none!important" in console
assert ".f252 .field select:disabled" in console and "background:#0d2231!important" in console
assert ".f252 .split-editor{" in console and "background:#0c2030!important" in console
assert ".f252 .wifi-dns-custom{" in console
assert "background:linear-gradient(120deg,#0c2232,#102738)!important" in console
assert "color:var(--jl-cyan-2,#a7f7ff)!important" in console
assert "#eef9ff" not in console and "#f3f7ff" not in console
assert ".f252 .split-platforms label.split-platform-chip" in console
assert "bootstrap-dark" not in header
assert "menu-bootstrap" not in footer and "argon" not in (header + footer + nav).lower()
assert "luci-theme-juliang" in makefile and "PKG_VERSION:=1.5" in makefile
assert "PKG_RELEASE:=4" in makefile
assert "include $(TOPDIR)/feeds/luci/luci.mk" in makefile
assert "luci.themes.JuLiang='/luci-static/juliang'" in theme_defaults
assert "No related RPC reply" in login and "clearPreauthRpcNotice" in login
assert "PKG_UPGRADE" not in theme_defaults
assert "luci.sauth.sessiontime='86400'" in luci_session
assert 'current="$(uci -q get luci.main.mediaurlbase)"' in theme_migration
assert '[ -f "/www${current}/cascade.css" ] && return 0' in theme_migration
assert "mediaurlbase='/luci-static/juliang'" in theme_migration
assert "luci-indexcache" in theme_migration
assert "hostname=JuLiang-OS" in fastacl_defaults
assert "max_wifi_5g=14" in fastacl_defaults and "max_wifi_2g=10" in fastacl_defaults
assert "option max_wifi_5g '14'" in fastacl_config and "option max_wifi_2g '10'" in fastacl_config
assert "capacity_profile=c.capacity_profile" in fastacl_controller
assert "CONFIG_PACKAGE_luci-theme-juliang=y" in config
assert "CONFIG_PACKAGE_luci-theme-argon=y" not in config
assert "ddns-scripts_aliyun" not in target_mk
assert "luci-app-ddns" not in target_mk
for package in (
    "luci-app-store",
    "luci-app-quickstart",
    "luci-app-ddns",
    "ddns-scripts",
    "luci-app-wol",
    "luci-app-filemanager",
):
    assert f"CONFIG_PACKAGE_{package}=y" not in config, package

print("PASS JuLiang OS v1.5 independent theme and clean build profile")
