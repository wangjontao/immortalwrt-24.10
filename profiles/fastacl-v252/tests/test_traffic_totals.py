#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile


PROFILE = Path(__file__).resolve().parents[1]
controller = (
    PROFILE / 'root/usr/lib/lua/luci/controller/juliang_center.lua'
).read_text(encoding='utf-8')
view = (
    PROFILE / 'root/usr/lib/lua/luci/view/juliang_center/home.htm'
).read_text(encoding='utf-8')
wireless_view = (
    PROFILE / 'root/usr/lib/lua/luci/view/juliang_center/wireless.htm'
).read_text(encoding='utf-8')
console_view = (
    PROFILE / 'root/usr/lib/lua/luci/view/fastacl252/console.htm'
).read_text(encoding='utf-8')
login_css = (
    PROFILE / 'root/www/luci-static/argon/css/juliang-login.css'
).read_text(encoding='utf-8')
menu_cleanup = (
    PROFILE / 'root/usr/libexec/juliang-menu-cleanup.lua'
).read_text(encoding='utf-8')
setup = (
    PROFILE / 'root/usr/libexec/juliang-traffic-setup'
).read_text(encoding='utf-8')
init = (
    PROFILE / 'root/etc/init.d/juliang-traffic'
).read_text(encoding='utf-8')
hotplug = (
    PROFILE / 'root/etc/hotplug.d/iface/99-juliang-traffic'
).read_text(encoding='utf-8')
integration = (
    PROFILE.parents[1] / 'scripts/integrate-fastacl252-s20l.sh'
).read_text(encoding='utf-8')
package_makefile = (PROFILE / 'package-Makefile').read_text(encoding='utf-8')


assert '/usr/bin/vnstat --json' in controller
assert 'data.interfaces and data.interfaces[1]' in controller
assert 'traffic.day' in controller
assert 'traffic.month' in controller
assert 'traffic_totals=traffic_totals()' in controller
assert '<h3>流量统计</h3>' in view
assert 'linear-gradient(118deg,#d9ecff 0%,#d9f5ef 52%,#ebe7ff 100%)' in view
assert 'linear-gradient(118deg,#d9ecff 0%,#d9f5ef 52%,#ebe7ff 100%)' in console_view
assert 'color:#c93e4a' in view
assert 'color:#d94747' in wireless_view
assert 'linear-gradient(135deg,#eaf3ff 0%,#e3f8f1 52%,#f2ecff 100%)' in login_css
assert 'id="juliang-brand-gradient"' in menu_cleanup
assert '<span class="juliang-brand-name">监测中心</span>' in menu_cleanup
assert '266-monitor-center-1' in menu_cleanup
for element in ('today-up', 'today-down', 'month-up', 'month-down'):
    assert f'id="jc-{element}"' in view
assert '每 30 秒更新' in view
assert "jsonfilter -e '@.l3_device'" in setup
assert 'DatabaseDir "/etc/vnstat"' in setup
assert 'vnstat.@vnstat[0].interface' in setup
assert '/etc/sysupgrade.conf' in setup
assert '/etc/init.d/vnstat restart' in init
assert 'INTERFACE" = wan' in hotplug
assert 'CONFIG_PACKAGE_vnstat2=y' in integration
assert ' vnstat2; do' in integration
assert '+vnstat2' in package_makefile
assert '/usr/libexec/juliang-traffic-setup' in package_makefile

for script in re.findall(r'<script>(.*?)</script>', view, re.DOTALL):
    script = re.sub(r'<%.*?%>', '', script)
    with tempfile.NamedTemporaryFile(
        'w', suffix='.js', encoding='utf-8', delete=False
    ) as handle:
        handle.write(script)
        path = handle.name
    subprocess.run(['node', '--check', path], check=True)
    Path(path).unlink()

print('FastACL persistent WAN traffic totals: OK')
