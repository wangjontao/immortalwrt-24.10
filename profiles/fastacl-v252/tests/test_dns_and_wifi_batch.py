#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile


PROFILE = Path(__file__).resolve().parents[1]
root = PROFILE / 'root'
dns = (root / 'usr/lib/lua/fastacl252_dns.lua').read_text(encoding='utf-8')
wifi = (root / 'usr/lib/lua/fastacl252_wifi.lua').read_text(encoding='utf-8')
controller = (
    root / 'usr/lib/lua/luci/controller/fastacl252.lua'
).read_text(encoding='utf-8')
console = (
    root / 'usr/lib/lua/luci/view/fastacl252/console.htm'
).read_text(encoding='utf-8')
runtime = (root / 'usr/bin/fastacl252').read_text(encoding='utf-8')
wifi_fw4 = (
    root / 'usr/libexec/fastacl252-wifi-fw4.lua'
).read_text(encoding='utf-8')
nps = (root / 'usr/libexec/juliang-nps-controller.lua').read_text(encoding='utf-8')

assert "kind=='doh' or kind=='udp' or kind=='tcp'" in dns
assert "mode=='proxy' and kind~='doh' and kind~='tcp'" in dns
assert "main[prefix..'_type']" in dns
assert 'function M.update_items' in wifi
assert 'function M.update_preproxy_many' in wifi
assert 'function M.update_many' in wifi
assert "req.action=='apply_batch'" in controller
assert "req.action=='preproxy_batch'" in controller
assert "version='2.6.8'" in controller
assert 'id="f25-wifi-apply-all"' in console
assert 'id="f25-wifi-pre-all"' in console
assert 'id="f25-direct-dns-custom"' in console
assert 'function customDnsEditor' in console
assert 'data-f25-setting-view="dataplane"' not in console
assert 'dnsmasq_ready' in runtime and 'ensure_dnsmasq' in runtime
assert "wireless_issues[#wireless_issues+1]=section..':bridge'" in wifi_fw4
assert "entry({\"admin\",\"system\",\"nps\"}" in nps

for number, script in enumerate(
        re.findall(r'<script>(.*?)</script>', console, re.DOTALL)):
    script = re.sub(r'<%.*?%>', '', script)
    with tempfile.NamedTemporaryFile(
            'w', suffix='.js', encoding='utf-8', delete=False) as handle:
        handle.write(script)
        path = handle.name
    subprocess.run(['node', '--check', path], check=True)
    Path(path).unlink()

print('FastACL custom DNS and multi-WiFi batch: OK')
