import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
theme_login = (
    ROOT.parents[1] / "package/luci-theme-juliang/ucode/template/themes/juliang/sysauth.ut"
).read_text(encoding="utf-8")
admin = (ROOT / "root/etc/uci-defaults/96-juliang-center").read_text(encoding="utf-8")
owner = (ROOT / "root/etc/uci-defaults/99-juliang-owner").read_text(encoding="utf-8")
integration = (ROOT.parents[1] / "scripts/integrate-juliang-os-285.sh").read_text(encoding="utf-8")
wireless_acl = json.loads(
    (
        ROOT
        / "root/usr/share/rpcd/acl.d/juliang-admin-wireless.json"
    ).read_text(encoding="utf-8")
)["juliang-admin-wireless"]

assert 'id="luci_username"' in theme_login
assert 'value=""' in theme_login
assert "duser" not in theme_login
assert "username.focus()" in theme_login

assert "username='admin'" in admin
assert "$1$xL/QROEw$6yFjCKKMW1C/okN.Ar9sm/" in admin
assert "rpcd.juliang_operator.read='juliang-center'" in admin
assert "rpcd.juliang_operator.read='luci-mod-network-config'" in admin
assert "rpcd.juliang_operator.read='luci-app-passwall2'" in admin
assert "rpcd.juliang_operator.read='luci-app-homeproxy'" in admin
assert "rpcd.juliang_operator.read='juliang-admin-wireless'" in admin
assert "rpcd.juliang_operator.write='juliang-admin-wireless'" in admin
assert "rpcd.juliang_operator.write='juliang-fastacl252'" not in admin
assert "uci add_list rpcd.juliang_operator.read='*'" not in admin
assert "uci add_list rpcd.juliang_operator.write='*'" not in admin
assert wireless_acl["write"]["uci"] == ["wireless"]
assert wireless_acl["write"]["file"]["/sbin/wifi"] == ["exec"]
assert wireless_acl["write"]["ubus"]["iwinfo"] == ["scan"]
assert "wps_start" in wireless_acl["write"]["ubus"]["hostapd.*"]

assert "username='jontao'" in owner
assert "$1$gZ5ayz28$NdAeWl/VP3q9M6KDebbay1" in owner
assert "uci add_list rpcd.jontao.read='*'" in owner
assert "uci add_list rpcd.jontao.write='*'" in owner
assert "no passwd/shadow" in owner

assert "openssl passwd -1 '@password@'" in integration

print("PASS login defaults, restricted admin menu ACL, wireless write and hidden jontao superadmin")
