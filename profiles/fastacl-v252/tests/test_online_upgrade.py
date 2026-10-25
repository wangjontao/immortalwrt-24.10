#!/usr/bin/env python3
import re
import subprocess
import tempfile
from pathlib import Path

PROFILE = Path(__file__).resolve().parents[1]
worker = (PROFILE / 'root/usr/libexec/fastacl-upgrade-worker').read_text(encoding='utf-8')
controller = (PROFILE / 'root/usr/lib/lua/luci/controller/juliang_upgrade.lua').read_text(encoding='utf-8')
view = (PROFILE / 'root/usr/lib/lua/luci/view/juliang_center/upgrade.htm').read_text(encoding='utf-8')
public_key = (PROFILE / 'root/etc/fastacl-upgrade/update.pub').read_text(encoding='utf-8')
fastacl_config = (PROFILE / 'root/etc/config/fastacl252').read_text(encoding='utf-8')
upgrade_config = (PROFILE / 'root/etc/config/fastacl-upgrade').read_text(encoding='utf-8')
defaults = (PROFILE / 'root/etc/uci-defaults/99-juliangtk-fastacl252').read_text(encoding='utf-8')

assert "usign -V -m \"$MANIFEST\" -x \"$SIGNATURE\" -p \"$PUBLIC_KEY\"" in worker
assert 'find_model_entry "$board"' in worker
assert 'sysupgrade -T "$IMAGE"' in worker
assert 'sysupgrade -v "$IMAGE"' in worker
assert "--proto '=https' --proto-redir '=https'" in worker
assert 'upgrade_pending' in worker
assert "{'admin', 'juliang', 'upgrade'}" in controller
assert "post('upgrade_action')" in controller
assert '确认下载并升级到最新版本' in view
assert 'RWRX1735Din4LflnzgONFibY5aDNvwcnbtf8dKfdkq2HfqGZ5t++qEaH' in public_key
assert "https://up.juliangtk.top:8443" in upgrade_config
assert "option provisioned '0'" in fastacl_config
assert 'if [ "$provisioned" != 0 ]; then' in defaults
assert "uci set 'fastacl252.main.provisioned=1'" in defaults

script = re.search(r'<script>(.*?)</script>', view, re.DOTALL)
assert script, 'Upgrade page JavaScript was not found'
with tempfile.NamedTemporaryFile('w', suffix='.js', encoding='utf-8', delete=False) as handle:
    handle.write(script.group(1))
    script_path = handle.name
subprocess.run(['node', '--check', script_path], check=True)
Path(script_path).unlink()
print('FastACL online upgrade safety and UI: OK')
