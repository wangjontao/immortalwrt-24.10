#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('manifest', ROOT / 'scripts/fastacl-update-manifest.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    artifacts = root / 'artifacts'
    artifacts.mkdir()
    image = artifacts / 'juliang-os-mediatek-filogic-cmcc_rax3000m-emmc-squashfs-sysupgrade.bin'
    image.write_bytes(b'firmware')
    models = json.loads((ROOT / 'profiles/fastacl-v252/update-models.json').read_text(encoding='utf-8'))
    assert len({entry['board'] for entry in models}) == len(models)
    assert len([entry for entry in models if entry['device'] in {
        'philips_hy3000', 'cmcc_rax3000m', 'cmcc_rax3000m-emmc', 'qihoo_360t7', 'aigo_ags21',
        'cmcc_a10-ubootmod', 'konka_komi-a31', 'newland_nl-wr8103', 'newland_nl-wr9103', 'abt_asr3000',
        'jcg_q30-pro', 'xiaomi_mi-router-ax3000t', 'xiaomi_mi-router-ax3000t-mtkuboot',
        'xiaomi_mi-router-ax3000t-ubootmod', 'xiaomi_mi-router-wr30u-stock',
        'xiaomi_mi-router-wr30u-ubootmod', 'nokia_ea0326gmp', 'sl_3000-emmc',
        'zbtlink_zbt-z8103ax-c', 'clt_r30b1', 'cetron_ct3003-ubootmod', 'cmcc_rax3000me',
        'asus_rt-ax52', 'glinet_gl-mt3000', 'huasifei_wh3000-emmc', 'huasifei_wh3000-pro',
        'umi_uax3000e', 'zbtlink_zbt-z8102ax', 'zbtlink_zbt-z8103ax', 'cudy_tr3000-v1',
        'cudy_tr3000-v1-256mb', 'cudy_tr3000-v1-ubootmod'
    }]) == 32
    devices = {entry['device'] for entry in models}
    assert {'clx_s20l', 'clx_s20p', 'jdcloud_re-cp-03', 'glinet_gl-mt6000', 'netcore_n60-pro'} <= devices
    assert 'generic' in devices
    assert 'xiaomi_redmi-router-ax6000' not in devices
    assert module.sha256(image) == 'c3bf47ea1f4a4a605470313cacb3a44f4a461f68c6faeab07e737610cb5ac835'
    x86 = artifacts / 'juliang-os-x86-64-generic-ext4-combined-efi.img.gz'
    x86.write_bytes(b'x86-firmware')
    (artifacts / 'juliang-os-x86-64-generic-ext4-combined.img.gz').write_bytes(b'bios')
    assert module.find_image(artifacts, 'generic') == x86

print('FastACL update manifest generation: OK')
