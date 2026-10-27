#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'root'
LUA = LuaRuntime(unpack_returned_tuples=True)
LUA.execute(
    'package.path=' + json.dumps(str(PROFILE / 'usr/lib/lua/?.lua').replace('\\', '/'))
    + "..';'..package.path"
)
LUA.globals().pyencode = lambda value: json.dumps(from_lua(value), separators=(',', ':'))
LUA.execute(
    "package.preload['luci.jsonc']=function() return {stringify=pyencode} end;"
    "package.preload['nixio']=function() return {bin={b64encode=function(v)return v end}} end"
)


def to_lua(value):
    if isinstance(value, dict):
        return LUA.table_from({key: to_lua(item) for key, item in value.items()})
    if isinstance(value, list):
        return LUA.table_from([to_lua(item) for item in value])
    return value


def from_lua(value):
    if hasattr(value, 'keys'):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [from_lua(value[index]) for index in range(1, len(keys) + 1)]
        return {key: from_lua(value[key]) for key in keys}
    return value


def config(dataplane='tun'):
    return {
        'network': 'lan',
        'interface': 'br-lan',
        'interfaces': ['br-lan', 'br-jfa25w01'],
        'wan_interface': 'eth1',
        'router_ip': '192.168.7.1',
        'netmask': '255.255.255.0',
        'port': 12525,
        'dataplane': dataplane,
        'tun_interface': 'fastacl-tun0',
        'tun_address': '172.19.0.1/30',
        'tun_mtu': 9000,
        'tun_stack': 'gvisor',
        'default_mode': 'direct',
        'dns_policy': 'direct',
        'dns_server': '223.5.5.5',
        'dns_name': 'dns.alidns.com',
        'private_dns_server': '9.9.9.9',
        'private_dns_name': 'dns.quad9.net',
        'platform_secret': 'ab' * 32,
        'cn_ipv4': ['1.0.1.0/24', '1.0.2.0/23', '223.5.5.0/24'],
        'nodes': {
            'us': {
                'protocol': 'socks',
                'outbound': {
                    'type': 'socks',
                    'server': 'proxy.example.com',
                    'server_port': 1080,
                    'username': 'a',
                    'password': 'secret',
                },
            },
            'front': {
                'protocol': 'vless',
                'outbound': {
                    'type': 'vless',
                    'server': '203.0.113.9',
                    'server_port': 443,
                    'uuid': '00000000-0000-0000-0000-000000000001',
                },
            },
        },
        'devices': [
            {
                'mac': '02:00:00:00:00:01',
                'ip': '192.168.7.101',
                'mode': 'proxy',
                'node': 'us',
                'preproxy': 'front',
                'split_mode': 'custom',
                'split_rules': 'block 203.0.113.10\ndirect 223.5.5.0/24\nproxy 1.1.1.0/24',
                'platforms': 'youtube',
                'dns_split': '1',
            },
            {
                'mac': '02:00:00:00:00:02',
                'ip': '192.168.7.102',
                'mode': 'direct',
                'dns_split': '0',
            },
        ],
        'wifis': [
            {
                'id': 'wifi01',
                'network': 'jfa25w01',
                'interface': 'br-jfa25w01',
                'router_ip': '172.16.1.1',
                'netmask': '255.255.255.0',
                'subnet': '172.16.1.0/24',
                'mode': 'proxy',
                'node': 'us',
                'split_mode': 'smart',
                'dns_split': '0',
            }
        ],
    }


class TunDataplaneTests(unittest.TestCase):
    def test_policy_defaults_to_singbox(self):
        cfg = config('singbox')
        cfg.pop('dataplane')
        result = from_lua(LUA.eval("require('fastacl252').validate")(to_lua(cfg)))
        self.assertEqual(result['dataplane'], 'singbox')

    def test_invalid_dataplane_rejected(self):
        cfg = config('invalid')
        with self.assertRaises(Exception):
            LUA.eval("require('fastacl252').validate")(to_lua(cfg))

    def test_tun_compiler_keeps_dns_and_policy(self):
        result = from_lua(LUA.eval("require('fastacl252_singbox').compile")(to_lua(config('tun'))))
        inbound = result['inbounds'][0]
        self.assertEqual(inbound['type'], 'tun')
        self.assertEqual(inbound['interface_name'], 'fastacl-tun0')
        self.assertEqual(inbound['address'], ['172.19.0.1/30'])
        self.assertFalse(inbound['auto_route'])
        self.assertFalse(inbound['strict_route'])
        self.assertIn('192.168.7.0/24', inbound['route_exclude_address'])
        self.assertEqual(result['dns']['servers'][0]['server'], '127.0.0.1')
        self.assertEqual(result['dns']['servers'][0]['server_port'], 12553)
        self.assertEqual(result['route']['final'], 'direct')
        self.assertFalse(result['route']['auto_detect_interface'])
        self.assertNotIn('rule_set', result['route'])

        tags = {outbound['tag']: outbound for outbound in result['outbounds']}
        self.assertEqual(tags['direct']['bind_interface'], 'eth1')
        self.assertIn('chain-us-front', tags)
        self.assertEqual(tags['node-us']['bind_interface'], 'eth1')
        self.assertEqual(tags['chain-us-front']['detour'], 'node-front')
        platform = next(outbound for outbound in result['outbounds'] if outbound['tag'].startswith('platform-'))
        self.assertEqual(platform['type'], 'socks')
        self.assertEqual(platform['server_port'], 15443)
        self.assertTrue(platform['username'].startswith('platform_'))

        rules = result['route']['rules']
        self.assertTrue(any(rule.get('action') == 'reject' and rule.get('ip_cidr') == ['203.0.113.10/32'] for rule in rules))
        self.assertTrue(any(rule.get('ip_cidr') == ['1.0.1.0/24', '1.0.2.0/23', '223.5.5.0/24'] and rule.get('source_ip_cidr') == ['172.16.1.0/24'] for rule in rules))
        self.assertTrue(any(rule.get('ip_cidr') == ['198.19.0.0/16'] and rule.get('source_ip_cidr') == ['192.168.7.101/32'] for rule in rules))
        self.assertTrue(any(rule.get('source_ip_cidr') == ['192.168.7.101/32'] and rule.get('outbound') == 'chain-us-front' for rule in rules))

    def test_tproxy_compiler_keeps_dns_and_policy(self):
        result = from_lua(LUA.eval("require('fastacl252_singbox').compile")(to_lua(config('singbox'))))
        self.assertEqual([inbound['type'] for inbound in result['inbounds']], ['tproxy', 'tproxy'])
        self.assertEqual([inbound['network'] for inbound in result['inbounds']], ['tcp', 'udp'])
        self.assertTrue(all(inbound['listen'] == '0.0.0.0' for inbound in result['inbounds']))
        self.assertTrue(all(inbound['listen_port'] == 12525 for inbound in result['inbounds']))
        self.assertEqual(result['dns']['servers'][0]['server'], '127.0.0.1')
        self.assertEqual(result['route']['final'], 'direct')

    def test_policy_compile_uses_native_singbox_and_relay(self):
        compiled = LUA.eval("require('fastacl252').compile")(to_lua(config('singbox')))
        singbox, relay = compiled[0], compiled[1]
        singbox = from_lua(singbox)
        relay = from_lua(relay)
        self.assertEqual([inbound['type'] for inbound in singbox['inbounds']], ['tproxy', 'tproxy'])
        self.assertEqual(relay['listen'], '0.0.0.0:12553')
        self.assertEqual(relay['data_listen'], '127.0.0.1:15443')
        self.assertEqual(relay['device_policies']['192.168.7.101']['exit'], 12600)
        self.assertEqual(relay['network_policies']['172.16.1.0/24']['exit'], 12601)
        self.assertIn('12600', relay['exits'])
        self.assertIn('12601', relay['exits'])
        self.assertEqual(relay['data_slots']['platform_device_020000000001'], 12600)

    def test_runtime_and_ui_expose_mutually_exclusive_dataplane(self):
        runtime = (PROFILE / 'usr/bin/fastacl252').read_text(encoding='utf-8')
        controller = (PROFILE / 'usr/lib/lua/luci/controller/fastacl252.lua').read_text(encoding='utf-8')
        view = (PROFILE / 'usr/lib/lua/luci/view/fastacl252/console.htm').read_text(encoding='utf-8')
        config_text = (PROFILE / 'etc/config/fastacl252').read_text(encoding='utf-8')
        package = (ROOT / 'package-Makefile').read_text(encoding='utf-8')
        for required in (
            'dataplane_now',
            'tun_alive',
            'tun_interface_ready',
            'tun_routes_ready',
            'tun_routes_clone_connected',
            'tun_routes_prepare',
            'tun_routes_activate',
            'tun_routes_start',
            'tun_routes_stop',
            'tun_firewall_ensure',
            'start_tun_core',
            'tun_core_stop',
            'start_tun_next',
            'tun_stop',
            'singbox_alive',
            'singbox_tproxy_routes_ready',
            'singbox_tproxy_ready',
            'singbox_tproxy_routes_start',
            'singbox_tproxy_routes_stop',
            'start_singbox_tproxy_next',
            'singbox_tproxy_stop',
        ):
            self.assertIn(required, runtime)
        self.assertIn('TUN_TABLE', runtime)
        self.assertIn('TUN_FWMARK', runtime)
        self.assertIn('fwmark "$TUN_FWMARK" lookup "$TUN_TABLE"', runtime)
        self.assertIn('iif lo lookup main', runtime)
        self.assertIn('LAN firewall zone not found', runtime)
        self.assertIn('uci add_list firewall.fastacl_tun.device="$iface"', runtime)
        self.assertIn('ip link delete "$iface"', runtime)
        self.assertIn('/sbin/start-stop-daemon -S -b -m', runtime)
        self.assertIn('SINGBOX_TPROXY_TABLE', runtime)
        self.assertIn('SINGBOX_TPROXY_FWMARK', runtime)
        self.assertIn('start_singbox_tproxy_next', runtime)
        self.assertIn('reload_tun_next', runtime)
        self.assertNotIn('dae_stop', runtime)
        self.assertIn('dataplane', controller)
        self.assertIn('id="f25-dataplane"', view)
        self.assertIn('id="f25-dataplane-save"', view)
        self.assertIn("$('dataplane').onchange=updateDataplaneFields", view)
        self.assertNotIn("$('dataplane').onchange=()=>renderDataplane()", view)
        self.assertIn("option dataplane 'singbox'", config_text)
        self.assertIn('+juliangtk-sing-box', package)
        self.assertNotIn('+juliangtk-dae', package)
        kernel_check = (ROOT / 'check-kernel.sh').read_text(encoding='utf-8')
        self.assertIn('TUN NFT_TPROXY', kernel_check)
        self.assertNotIn('NETFILTER_XT_TARGET_TPROXY', kernel_check)

    def test_firewall_marks_only_proxy_sources_for_tun(self):
        cfg = config('tun')
        cfg['devices'][0]['split_mode'] = 'all'
        cfg['devices'][0]['split_rules'] = ''
        cfg['wifis'][0]['split_mode'] = 'all'
        result = from_lua(LUA.eval("require('fastacl252').firewall")(to_lua(cfg), 'nft'))
        nft = result['nft']
        self.assertIn('set tun_sources { type ipv4_addr; flags interval; auto-merge;', nft)
        self.assertIn('192.168.7.101/32, 172.16.1.0/24', nft)
        self.assertIn('ip saddr @tun_sources meta mark set 0x2027', nft)
        self.assertNotIn('iifname @proxy_wifi_ifaces drop', nft)

    def test_tproxy_firewall_intercepts_only_proxy_sources(self):
        cfg = config('singbox')
        cfg['devices'][0]['split_mode'] = 'all'
        cfg['devices'][0]['split_rules'] = ''
        cfg['wifis'][0]['split_mode'] = 'all'
        nft = from_lua(LUA.eval("require('fastacl252').firewall")(to_lua(cfg), 'nft'))['nft']
        self.assertIn('table ip fastacl252_tproxy {', nft)
        self.assertIn('ip saddr @tproxy_sources ip daddr @tproxy_excludes return', nft)
        self.assertIn('meta mark set 0x2028 tproxy to :12525 accept', nft)
        self.assertNotIn('ip tproxy to', nft)
        self.assertIn('meta l4proto tcp', nft)
        self.assertIn('meta l4proto udp', nft)
        self.assertNotIn('iifname @proxy_wifi_ifaces drop', nft)

    def test_removed_legacy_firewall_fallback_is_not_generated(self):
        cfg = config('tun')
        cfg['devices'][0]['split_mode'] = 'all'
        cfg['devices'][0]['split_rules'] = ''
        cfg['wifis'][0]['split_mode'] = 'all'
        result = from_lua(LUA.eval("require('fastacl252').firewall")(to_lua(cfg), 'nft'))
        nft = result['nft']
        self.assertNotIn('proxy_wifi_ifaces', nft)
        self.assertNotIn('iifname "br-lan" ip saddr @proxy_ips drop', nft)

    def test_production_runtime_has_no_dae_core_path(self):
        production = '\n'.join(
            path.read_text(encoding='utf-8', errors='ignore')
            for path in (PROFILE / 'usr').rglob('*')
            if path.is_file() and path.suffix in ('.lua', '.sh', '')
        )
        runtime = (PROFILE / 'usr/bin/fastacl252').read_text(encoding='utf-8')
        package = (ROOT / 'package-Makefile').read_text(encoding='utf-8')
        for removed in ('fastacl252_dae', 'router.next.dae', 'dae validate', 'dae run ', 'dae reload'):
            self.assertNotIn(removed, production)
        self.assertNotIn('juliangtk-dae', package)
        self.assertIn('CORE_FD_LIMIT', runtime)

    def test_generated_config_with_official_core(self):
        core = globals().get('SING_BOX_CORE')
        if not core:
            self.skipTest('official sing-box core not provided')
        for mode in ('singbox', 'tun'):
            result = from_lua(LUA.eval("require('fastacl252_singbox').compile")(to_lua(config(mode))))
            with tempfile.NamedTemporaryFile('w', suffix='.json', encoding='utf-8', delete=False) as handle:
                json.dump(result, handle)
                path = handle.name
            try:
                subprocess.run([core, 'check', '-c', path], check=True)
            finally:
                Path(path).unlink()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sing-box')
    options, remaining = parser.parse_known_args()
    globals()['SING_BOX_CORE'] = options.sing_box
    result = unittest.main(argv=['test_tun_dataplane'] + remaining, exit=False).result
    raise SystemExit(0 if result.wasSuccessful() else 1)
