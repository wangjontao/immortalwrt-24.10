from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
THEME = ROOT / "package/luci-theme-juliang"
CONFIG = ROOT / "build-configs/JuLiang-OS-S20L-v2.8.5.txt"


header = (THEME / "ucode/template/themes/juliang/header.ut").read_text(encoding="utf-8")
footer = (THEME / "ucode/template/themes/juliang/footer.ut").read_text(encoding="utf-8")
login = (THEME / "ucode/template/themes/juliang/sysauth.ut").read_text(encoding="utf-8")
menu = (THEME / "htdocs/luci-static/resources/menu-juliang.js").read_text(encoding="utf-8")
css = (THEME / "htdocs/luci-static/juliang/juliang.css").read_text(encoding="utf-8")
makefile = (THEME / "Makefile").read_text(encoding="utf-8")
config = CONFIG.read_text(encoding="utf-8")

assert "JuLiang OS" in header
assert "v2.8.5" in header and "v2.8.5" in footer and "v2.8.5" in login
assert 'name="luci_username"' in login and 'name="luci_password"' in login
assert "L.require('menu-juliang')" in footer
assert "menu-juliang" not in header
assert "juliang-theme" in css and "--jl-cyan: #67dce7" in css
assert "linear-gradient" in css and "@media (max-width: 900px)" in css
assert "letter-spacing: -" not in css
assert "bootstrap-dark" not in header
assert "menu-bootstrap" not in footer and "argon" not in (header + footer + menu).lower()
assert "luci-theme-juliang" in makefile and "PKG_VERSION:=2.8.5" in makefile
assert "CONFIG_PACKAGE_luci-theme-juliang=y" in config
assert "CONFIG_PACKAGE_luci-theme-argon=y" not in config
for package in (
    "luci-app-store",
    "luci-app-quickstart",
    "luci-app-ddns",
    "ddns-scripts",
    "luci-app-upnp",
    "luci-app-wol",
    "luci-app-filemanager",
):
    assert f"CONFIG_PACKAGE_{package}=y" not in config, package

print("PASS JuLiang OS v2.8.5 independent theme and clean build profile")
