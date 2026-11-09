from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
theme_login = (
    ROOT.parents[1] / "package/luci-theme-juliang/ucode/template/themes/juliang/sysauth.ut"
).read_text(encoding="utf-8")
admin = (ROOT / "root/etc/uci-defaults/96-juliang-center").read_text(encoding="utf-8")
owner = (ROOT / "root/etc/uci-defaults/99-juliang-owner").read_text(encoding="utf-8")
integration = (ROOT.parents[1] / "scripts/integrate-juliang-os-285.sh").read_text(encoding="utf-8")
dropbear_defaults = (
    ROOT.parents[1] / "package/network/services/dropbear/files/dropbear.config"
).read_text(encoding="utf-8")
wifi_defaults = (
    ROOT / "root/etc/uci-defaults/99-juliangtk-fastacl252"
).read_text(encoding="utf-8")

assert 'id="luci_username"' in theme_login
assert 'value=""' in theme_login
assert "duser" not in theme_login
assert "username.focus()" in theme_login

assert "username='admin'" in admin
assert "$1$xL/QROEw$6yFjCKKMW1C/okN.Ar9sm/" in admin
assert "rpcd.juliang_operator.read='juliang-center'" in admin
assert "rpcd.juliang_operator.write='juliang-fastacl252'" in admin
assert "uci add_list rpcd.juliang_operator.read='*'" not in admin
assert "uci add_list rpcd.juliang_operator.write='*'" not in admin

assert "username='jontao'" in owner
assert "$1$gZ5ayz28$NdAeWl/VP3q9M6KDebbay1" in owner
assert "uci add_list rpcd.jontao.read='*'" in owner
assert "uci add_list rpcd.jontao.write='*'" in owner
assert "no passwd/shadow" in owner

assert "openssl passwd -1 '@password@'" in integration
assert "rm -rf package/fastacl252/files" in integration
assert "cp -a profiles/fastacl-v252/root/. package/fastacl252/files/" in integration
assert "find files -type f -iname '*dulwifi*' -delete" in integration
legacy_dulwifi = [
    path
    for path in (ROOT.parents[1] / "files").rglob("*")
    if "dulwifi" in path.name.lower()
]
assert not legacy_dulwifi, legacy_dulwifi
assert "option Port         '20022'" in dropbear_defaults
assert "network.lan.ipaddr=192.168.7.1" in wifi_defaults
assert "wireless.$iface.ssid=JuLiang-OS-2.4G" in wifi_defaults
assert "wireless.$iface.ssid=JuLiang-OS-5G" in wifi_defaults
assert "wireless.$iface.key=66668888" in wifi_defaults

print("PASS login defaults, network/WiFi defaults, admin operator ACL and hidden jontao superadmin")
