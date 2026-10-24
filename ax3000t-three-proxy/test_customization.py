from pathlib import Path
import importlib.util
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

P = Path(__file__).resolve().parent


class CustomizationTest(unittest.TestCase):
    def test_management_defaults(self):
        text = (P / 'files/etc/uci-defaults/98-ax3000t-management').read_text()
        self.assertIn("network.lan.ipaddr='192.168.9.1'", text)
        self.assertIn("ROOT_HASH='$6$", text)
        self.assertNotIn('@ROOT_PASSWORD_HASH@', text)
        self.assertIn('47.83.9.208', text)

    def test_wan_mac_writes_expected_nps_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'sys/wan0').mkdir(parents=True)
            (root / 'sys/wan0/address').write_text('aa:bb:cc:dd:ee:02\n')
            service = root / 'nps'
            service.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\n')
            service.chmod(0o755)
            text = (P / 'files/usr/libexec/nps-wan-mac').read_text()
            text = text.replace('/tmp/etc', (root / 'runtime').as_posix())
            helper = root / 'helper'
            helper.write_text(text)
            script = '''uci() {
 if [ "$*" = '-q get network.wan.device' ]; then echo wan0;
 else printf '%s\\n' "$*" >> "$CALLS"; fi
}
logger() { return 0; }
. "$HELPER"
'''
            env = dict(os.environ, NPS_SYS_NET=(root / 'sys').as_posix(),
                       NPS_INIT=service.as_posix(), NPS_MAC_LOCK=(root / 'lock').as_posix(),
                       HELPER=helper.as_posix(), CALLS=(root / 'calls').as_posix())
            subprocess.run([os.environ.get('CUSTOM_TEST_SH', 'sh'), '-c', script],
                           env=env, check=True, capture_output=True, text=True)
            calls = (root / 'calls').read_text()
            self.assertIn('vkey=AABBCCDDEE02', calls)
            self.assertIn('server_addr=47.83.9.208', calls)
            self.assertIn('server_port=8024', calls)
            self.assertIn('restart', calls)

    def test_old_luci_provider_is_replaced(self):
        spec = importlib.util.spec_from_file_location('ax_build', P / 'build.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packages = [('passwall', 'luci-app-passwall', 'PKG_VERSION:=26.10.22\nPKG_RELEASE:=2'),
                        ('helloworld', 'luci-app-ssr-plus', 'PKG_VERSION:=198\nPKG_RELEASE:=2\nAnyTLS'),
                        ('openclash', 'luci-app-openclash', 'PKG_VERSION:=0.48.002')]
            for feed, name, contents in packages:
                source = root / 'feeds' / feed / name
                source.mkdir(parents=True)
                (source / 'Makefile').write_text(contents)
                old = root / 'old' / name
                old.mkdir(parents=True)
                (old / 'Makefile').write_text('old version')
                installed = root / 'package/feeds/luci' / name
                installed.parent.mkdir(parents=True, exist_ok=True)
                try:
                    installed.symlink_to(old, target_is_directory=True)
                except OSError:
                    self.skipTest('Directory symlinks unavailable on this host')
            try:
                os.chdir(root)
                with patch.object(module, 'run'):
                    module.prepare()
                self.assertIn('26.10.22', Path('package/custom-proxy-ui/luci-app-passwall/Makefile').read_text())
                self.assertFalse(Path('package/feeds/luci/luci-app-passwall').exists())
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
