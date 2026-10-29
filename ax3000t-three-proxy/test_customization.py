from pathlib import Path
import importlib.util
import json
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

    def test_juliang_customer_defaults(self):
        config = (P / 'ax3000t-ubootmod.config').read_text(encoding='utf-8')
        self.assertIn('CONFIG_PACKAGE_luci-theme-argon=y', config)
        self.assertIn('CONFIG_PACKAGE_luci-app-passwall2=y', config)
        self.assertIn('CONFIG_PACKAGE_geoview=y', config)
        self.assertIn('CONFIG_IMAGEOPT=y', config)
        self.assertIn('CONFIG_VERSIONOPT=y', config)
        self.assertIn('CONFIG_VERSION_DIST="JuLiang OS"', config)
        self.assertNotIn('CONFIG_PACKAGE_luci-app-passwall=y', config)

        defaults = (P / 'files/etc/uci-defaults/99-three-proxy-defaults').read_text(encoding='utf-8')
        for value in ['JuLiang-2.4G', 'JuLiang-5G', '66668888',
                      "psk2+ccmp", '/luci-static/argon', 'passwall2']:
            self.assertIn(value, defaults)

        branding = (P / 'files/usr/libexec/juliang-branding.lua').read_text(encoding='utf-8')
        self.assertIn("data.model.name = 'JuLiang OS'", branding)

    def test_juliang_live_is_the_ordered_root_page(self):
        controller = (P / 'files/usr/lib/lua/luci/controller/juliang_live.lua').read_text(encoding='utf-8')
        view = (P / 'files/usr/lib/lua/luci/view/juliang_live/home.htm').read_text(encoding='utf-8')
        self.assertIn("entry({'admin', 'juliang'}, firstchild(), _('JuLiang Live'), 0)", controller)
        self.assertIn("template('juliang_live/home')", controller)
        self.assertIn('JuLiang Live', view)
        self.assertIn('JuLiang-2.4G / JuLiang-5G', view)
        self.assertIn("build_url('admin','services','passwall2')", view)
        self.assertNotIn('<script src=', view)
        self.assertNotIn('url(http', view)

    def test_juliang_superuser_and_login_assets(self):
        admin = (P / 'files/etc/uci-defaults/98-juliang-admin').read_text(encoding='utf-8')
        login = (P / 'files/usr/libexec/juliang-login-theme.lua').read_text(encoding='utf-8')
        css = (P / 'files/www/luci-static/argon/css/juliang-login.css').read_text(encoding='utf-8')
        background = P / 'files/www/luci-static/argon/img/juliang-login-bg.jpg'
        self.assertIn("uci set rpcd.jontao.username='jontao'", admin)
        self.assertIn("uci add_list rpcd.jontao.write='*'", admin)
        self.assertIn("$1$jL2026x$ziuf.jxVpn9qWKfevOnE11", admin)
        self.assertIn('JuLiang 网络服务', login)
        self.assertIn('juliang-login-bg.jpg', css)
        self.assertIn('luci_username', css)
        self.assertIn('luci_password', css)
        self.assertGreater(background.stat().st_size, 100000)

    def test_jontao_password_hash(self):
        try:
            import crypt
            result = crypt.crypt('jontao', '$1$jL2026x$')
        except (ImportError, OSError):
            self.skipTest('System crypt is unavailable')
        self.assertEqual(result, '$1$jL2026x$ziuf.jxVpn9qWKfevOnE11')

    def test_login_theme_is_idempotent(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest('lupa is only installed by the build workflow')
        lua = LuaRuntime(unpack_returned_tuples=True)
        path = '/usr/share/ucode/luci/template/themes/argon/sysauth.ut'
        files = {
            path: '''<div class="login-page"><div class="login-form">
<span class="brand-text">
OpenWrt</span>
<form><input name="luci_username"><input name="luci_password"></form></div></div>'''
        }
        lua.globals().read = lambda p: files.get(p)
        lua.globals().write = lambda p, value: files.__setitem__(p, value) or True
        lua.globals().exists = lambda p: p in files
        lua.globals().rename = lambda source, target: files.__setitem__(target, files.pop(source)) or True
        lua.globals().chmod = lambda *_: True
        lua.execute("""package.loaded['nixio.fs']={
readfile=read,writefile=write,access=exists,rename=rename,chmod=chmod
}""")
        script = (P / 'files/usr/libexec/juliang-login-theme.lua').read_text(encoding='utf-8')
        script = script.split('\n', 1)[1]
        lua.execute(script)
        lua.execute(script)
        result = files[path]
        self.assertEqual(result.count('juliang-login-style'), 1)
        self.assertEqual(result.count('juliang-login-fields'), 1)
        self.assertEqual(result.count('JuLiang 网络服务'), 1)
        self.assertIn('class="login-page juliang-login"', result)

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
            packages = [('passwall2', 'luci-app-passwall2', 'PKG_VERSION:=26.10.20\nPKG_RELEASE:=1\n+geoview +v2ray-geoip +v2ray-geosite'),
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
                with patch.object(module, 'run'), patch.object(module, 'patch_ssrplus_singbox'):
                    module.prepare()
                self.assertIn('26.10.20', Path('package/custom-proxy-ui/luci-app-passwall2/Makefile').read_text())
                self.assertFalse(Path('package/feeds/luci/luci-app-passwall2').exists())
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
