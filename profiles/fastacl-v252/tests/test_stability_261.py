#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'root'

runtime = (PROFILE / 'usr/bin/fastacl252').read_text(encoding='utf-8')
watchdog = (PROFILE / 'usr/bin/wan-watchdog').read_text(encoding='utf-8')
init = (PROFILE / 'etc/init.d/wan-watchdog').read_text(encoding='utf-8')
config = (PROFILE / 'etc/config/wan-watchdog').read_text(encoding='utf-8')
fastacl_config = (PROFILE / 'etc/config/fastacl252').read_text(encoding='utf-8')
defaults = (PROFILE / 'etc/uci-defaults/99-juliangtk-fastacl252').read_text(encoding='utf-8')
migration = (PROFILE / 'etc/uci-defaults/98-juliang-wifi-stability').read_text(encoding='utf-8')
wifi = (PROFILE / 'usr/lib/lua/fastacl252_wifi.lua').read_text(encoding='utf-8')
nps = (PROFILE / 'usr/libexec/nps-wan-mac').read_text(encoding='utf-8')
nps_init = (PROFILE / 'etc/init.d/nps-wan-mac').read_text(encoding='utf-8')
nps_hotplug = (PROFILE / 'etc/hotplug.d/iface/99-nps-wan-mac').read_text(encoding='utf-8')

for required in (
    'socks_backlog',
    'dns_guard_ready',
    'runtime_failure',
    'health_snapshot',
    'DAE_TCP_RELAY_HALF_CLOSE_TIMEOUT=30s',
    'DAE_TCP_RELAY_IDLE_TIMEOUT=300s',
):
    assert required in runtime, required

assert "option enabled '1'" in config
assert "option interval '10'" in config
assert 'wan-watchdog.main.enabled' in init
assert 'procd_add_reload_trigger wan-watchdog' in init
assert 'ubus call network.interface.wan renew' in watchdog
assert 'ubus call network.interface.wan down' in watchdog
assert 'ubus call network.interface.wan up' in watchdog
assert 'state=carrier-down' in watchdog
assert 'state=no-lease' in watchdog
assert 'PROBE_FAILURE_LIMIT' in runtime
assert 'recovering DNS proxy' in runtime
assert 'start_dns_next' in runtime
for profile in ('high', 'quad', 'balanced', 'compact'):
    assert profile in runtime
assert 'FD_HARD_LIMIT=65536' in runtime
assert 'DAE_FD_LIMIT=57344' in runtime
assert 'DNS_FD_LIMIT=57344' in runtime
assert 'ulimit -Hn "$FD_HARD_LIMIT"' in runtime
assert 'tcp_idle_timeout' in fastacl_config and "'300s'" in fastacl_config
assert 'tcp_half_close_timeout' in fastacl_config and "'30s'" in fastacl_config
assert "capacity_profile 'auto'" in fastacl_config
assert "data_max_connections 'auto'" in fastacl_config
assert "data_max_connections_per_session 'auto'" in fastacl_config
assert 'ip -4 route show default' in nps
assert 'mkdir "$LOCK"' in nps
assert 'NPS restarted after WAN ready' in nps
assert 'touch /tmp/nps-wan-mac.ready' in nps
assert 'sleep 40' in nps_init
assert '/tmp/nps-wan-mac.ready' in nps_init
assert '[ -e /etc/nps-wan-mac.done ] ||' not in nps_init
assert 'ifup|ifupdate' in nps_hotplug
assert '/usr/libexec/nps-wan-mac' in nps_hotplug

assert 'wireless.$radio.channel=36' in defaults
assert 'wireless.$radio.htmode=HE80' in defaults
assert 'wireless.$radio.channel=1' in defaults
assert 'wireless.$radio.htmode=HE20' in defaults
assert '/etc/init.d/wan-watchdog enable' in defaults
assert 'case "$channel" in' in migration
assert '|48)' in migration and '|9)' in migration
assert 'SSID 已存在' in wifi
assert 'planned_ssids' in wifi
assert (ROOT / 'tests/test_wifi_creation.py').is_file()

menu = json.loads((PROFILE / 'usr/share/luci/menu.d/luci-app-wan-watchdog.json').read_text(encoding='utf-8'))
acl = json.loads((PROFILE / 'usr/share/rpcd/acl.d/luci-app-wan-watchdog.json').read_text(encoding='utf-8'))
assert 'admin/system/wan-watchdog' in menu
assert 'luci-app-wan-watchdog' in acl
assert (PROFILE / 'www/luci-static/resources/view/wan-watchdog.js').is_file()

pkg = (ROOT / 'package-Makefile').read_text(encoding='utf-8')
assert 'PKG_VERSION:=2.6.1' in pkg
assert 'PKG_RELEASE:=3' in pkg
assert '/usr/bin/wan-watchdog' in pkg
assert '/etc/init.d/wan-watchdog' in pkg
assert '/etc/config/wan-watchdog' in pkg

print('FastACL 2.6.1 stability, DNS guard and WAN watchdog: OK')
