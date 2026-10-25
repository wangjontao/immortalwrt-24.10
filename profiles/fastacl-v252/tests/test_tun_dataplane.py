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
        'router_ip': '192.168.7.1',
        'netmask': '255.255.255.0',
        'port': 12525,
        'dataplane': dataplane,
        'tun_interface': 'fastacl-tun0',
        'tun_address': '172.19.0.1/30',
        'tun_mtu': 9000,
        'tun_stack': 'mixed',
        'default_mode': 'direct',
        'dns_policy': 'direct',
        'dns_server': '223.5.5.5',
        'dns_name': 'dns.alidns.com',
        'private_dns_server': '9.9.9.9',
        'private_dns_name': 'dns.quad9.net',
        'platform_secret': 'ab' * 32,
        'cn_ipv4': ['1.0.1.0/24', '1.0.2.0/23', '223.5.5.0/24'],
        'nodes': {
            'us': {'protocol': 'socks', 'address': 'proxy.example.com', 'port': '1080', 'username': 'a', 'password': 'secret'},
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
    def test_policy_defaults_to_ebpf(self):
        cfg = config('ebpf')
        cfg.pop('dataplane')
        result = from_lua(LUA.eval("require('fastacl252').validate")(to_lua(cfg)))
        self.assertEqual(result['dataplane'], 'ebpf')

    def test_invalid_dataplane_rejected(self):
        cfg = config('invalid')
        with self.assertRaises(Exception):
            LUA.eval("require('fastacl252').validate")(to_lua(cfg))

    def test_tun_compiler_keeps_dns_and_policy(self):
        result = from_lua(LUA.eval("require('fastacl252_singbox').compile")(to_lua(config())))
        inbound = result['inbounds'][0]
        self.assertEqual(inbound['type'], 'tun')
        self.assertEqual(inbound['interface_name'], 'fastacl-tun0')
        self.assertEqual(inbound['address'], ['172.19.0.1/30'])
        self.assertTrue(inbound['auto_route'])
        self.assertTrue(inbound['strict_route'])
        self.assertIn('192.168.7.0/24', inbound['route_exclude_address'])
        self.assertEqual(result['dns']['servers'][0]['server'], '127.0.0.1')
        self.assertEqual(result['dns']['servers'][0]['server_port'], 12553)
        self.assertEqual(result['route']['final'], 'direct')
        self.assertNotIn('rule_set', result['route'])

        tags = {outbound['tag']: outbound for outbound in result['outbounds']}
        self.assertIn('chain-us-front', tags)
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

    def test_runtime_and_ui_expose_mutually_exclusive_dataplane(self):
        runtime = (PROFILE / 'usr/bin/fastacl252').read_text(encoding='utf-8')
        controller = (PROFILE / 'usr/lib/lua/luci/controller/fastacl252.lua').read_text(encoding='utf-8')
        view = (PROFILE / 'usr/lib/lua/luci/view/fastacl252/console.htm').read_text(encoding='utf-8')
        config_text = (PROFILE / 'etc/config/fastacl252').read_text(encoding='utf-8')
        package = (ROOT / 'package-Makefile').read_text(encoding='utf-8')
        for required in ('dataplane_now', 'tun_alive', 'tun_ready', 'start_tun_next', 'tun_stop'):
            self.assertIn(required, runtime)
        self.assertIn('reload_tun_next', runtime)
        self.assertIn('dae_stop', runtime)
        self.assertIn('dataplane', controller)
        self.assertIn('id="f25-dataplane"', view)
        self.assertIn('id="f25-dataplane-save"', view)
        self.assertIn("option dataplane 'ebpf'", config_text)
        self.assertIn('+juliangtk-sing-box', package)

    def test_generated_config_with_official_core(self):
        core = globals().get('SING_BOX_CORE')
        if not core:
            self.skipTest('official sing-box core not provided')
        result = from_lua(LUA.eval("require('fastacl252_singbox').compile")(to_lua(config())))
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
