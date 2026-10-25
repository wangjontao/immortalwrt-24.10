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
    image = artifacts / 'immortalwrt-mediatek-filogic-cmcc_rax3000m-emmc-squashfs-sysupgrade.bin'
    image.write_bytes(b'firmware')
    models = json.loads((ROOT / 'profiles/fastacl-v252/update-models.json').read_text(encoding='utf-8'))
    assert len({entry['board'] for entry in models}) == len(models)
    assert len([entry for entry in models if entry['device'] in {
        'philips_hy3000', 'cmcc_rax3000m', 'cmcc_rax3000m-emmc', 'qihoo_360t7', 'aigo_ags21',
        'cmcc_a10-ubootmod', 'konka_komi-a31', 'newland_nl-wr8103', 'newland_nl-wr9103', 'abt_asr3000',
        'jcg_q30-pro', 'xiaomi_mi-router-ax3000t', 'xiaomi_mi-router-ax3000t-mtkuboot',
        'xiaomi_mi-router-ax3000t-ubootmod', 'xiaomi_mi-router-wr30u-stock',
        'xiaomi_mi-router-wr30u-ubootmod', 'nokia_ea0326gmp', 'sl_3000-emmc',
        'zbtlink_zbt-z8103ax-c', 'clt_r30b1'
    }]) == 20
    assert module.sha256(image) == 'c3bf47ea1f4a4a605470313cacb3a44f4a461f68c6faeab07e737610cb5ac835'

print('FastACL update manifest generation: OK')
