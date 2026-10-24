#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
script = (ROOT / 'scripts/integrate-fastacl252-s20l.sh').read_text(encoding='utf-8')
workflow = (ROOT / '.github/workflows/JuLiangTK-MT7981-FastACL261.yml').read_text(encoding='utf-8')

DEVICES = {
    'cmcc_rax3000m': ('RAX3000M-NAND', 'mt7981b-cmcc-rax3000m', 'cmcc,rax3000m'),
    'cmcc_rax3000m-emmc': ('RAX3000M-EMMC', 'mt7981b-cmcc-rax3000m-emmc', 'cmcc,rax3000m-emmc'),
    'cmcc_a10-stock': ('CMCC-A10-Stock', 'mt7981b-cmcc-a10-stock', 'cmcc,a10-stock'),
    'cmcc_a10-ubootmod': ('CMCC-A10-Ubootmod', 'mt7981b-cmcc-a10-ubootmod', 'cmcc,a10-ubootmod'),
    'qihoo_360t7': ('Qihoo-360T7', 'mt7981b-qihoo-360t7', 'qihoo,360t7'),
    'jcg_q30-pro': ('JCG-Q30-PRO', 'mt7981b-jcg-q30-pro', 'jcg,q30-pro'),
    'konka_komi-a31': ('Konka-KOMI-A31', 'mt7981b-konka-komi-a31', 'konka,komi-a31'),
    'livinet_zr-3020': ('Livinet-ZR-3020', 'mt7981b-livinet-zr-3020', 'livinet,zr-3020'),
}

for device, (tag, dts, compatible) in DEVICES.items():
    assert f'{device}) tag={tag}; dts={dts}; compatible={compatible} ;;' in script
    assert f'- device: {device}' in workflow
    dts_path = ROOT / 'target/linux/mediatek/dts' / f'{dts}.dts'
    assert dts_path.is_file(), dts_path
    assert f'compatible = "{compatible}", "mediatek,mt7981";' in dts_path.read_text(encoding='utf-8')

assert "make defconfig" in script
assert "CONFIG_TARGET_MEDIATEK_FILOGIC_DEVICE_${device}=y" in script
assert "max-parallel: 2" in workflow
assert "branches: ['2.6.1']" in workflow

print('FastACL 2.6.1 MT7981 device matrix and DTS identities: OK')
