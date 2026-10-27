#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
script = (ROOT / 'scripts/integrate-fastacl252-s20l.sh').read_text(encoding='utf-8')
workflow = (ROOT / '.github/workflows/JuLiangTK-MT7981-FastACL262.yml').read_text(encoding='utf-8')
grouped_workflow = (ROOT / '.github/workflows/JuLiangTK-MT7981-FastACL262-Grouped.yml').read_text(encoding='utf-8')
grouped_workflow_263 = (ROOT / '.github/workflows/JuLiangTK-MT7981-FastACL263-Grouped.yml').read_text(encoding='utf-8')
grouped_workflow_266 = (ROOT / '.github/workflows/JuLiangTK-MT7981-FastACL266-Grouped.yml').read_text(encoding='utf-8')
image_makefile = (ROOT / 'target/linux/mediatek/image/filogic.mk').read_text(encoding='utf-8')
base_config = (ROOT / 'build-configs/JuLiangTK-S20L-FastACL258.txt').read_text(encoding='utf-8')
grouped_script = (ROOT / 'scripts/integrate-fastacl262-grouped.sh').read_text(encoding='utf-8')

DEVICES = {
    'philips_hy3000': ('PHILIPS-HY3000', 'mt7981b-philips-hy3000', 'philips,hy3000', 'Philips HY3000', None),
    'cmcc_rax3000m': ('RAX3000M-NAND', 'mt7981b-cmcc-rax3000m', 'cmcc,rax3000m', 'CMCC RAX3000M NAND', None),
    'cmcc_rax3000m-emmc': ('RAX3000M-EMMC', 'mt7981b-cmcc-rax3000m-emmc', 'cmcc,rax3000m-emmc', 'CMCC RAX3000M eMMC', None),
    'qihoo_360t7': ('QIHOO-360T7', 'mt7981b-qihoo-360t7', 'qihoo,360t7', 'Qihoo 360T7', None),
    'aigo_ags21': ('AIGO-AGS21', 'mt7981b-aigo-ags21', 'aigo,ags21', 'Aigo AGS21', None),
    'cmcc_a10-ubootmod': ('CMCC-A10-Ubootmod', 'mt7981b-cmcc-a10-ubootmod', 'cmcc,a10-ubootmod', 'CMCC A10 ubootmod', None),
    'konka_komi-a31': ('KONKA-KOMI-A31', 'mt7981b-konka-komi-a31', 'konka,komi-a31', 'Konka KOMI A31', None),
    'newland_nl-wr8103': ('NEWLAND-NL-WR8103', 'mt7981b-newland-nl-wr8103', 'newland,nl-wr8103', 'Newland NL-WR8103', None),
    'newland_nl-wr9103': ('NEWLAND-NL-WR9103', 'mt7981b-newland-nl-wr9103', 'newland,nl-wr9103', 'Newland NL-WR9103', None),
    'abt_asr3000': ('ABT-ASR3000', 'mt7981b-abt-asr3000', 'abt,asr3000', 'ABT ASR3000', None),
    'jcg_q30-pro': ('JCG-Q30-PRO', 'mt7981b-jcg-q30-pro', 'jcg,q30-pro', 'JCG Q30 Pro', None),
    'xiaomi_mi-router-ax3000t': ('Xiaomi-AX3000T', 'mt7981b-xiaomi-mi-router-ax3000t', 'xiaomi,mi-router-ax3000t', 'Xiaomi AX3000T', None),
    'xiaomi_mi-router-ax3000t-mtkuboot': ('Xiaomi-AX3000T-MTK-UBoot', 'mt7981b-xiaomi-mi-router-ax3000t-mtkuboot', 'xiaomi,mi-router-ax3000t-mtkuboot', 'Xiaomi AX3000T MTK U-Boot', None),
    'xiaomi_mi-router-ax3000t-ubootmod': ('Xiaomi-AX3000T-ubootmod', 'mt7981b-xiaomi-mi-router-ax3000t-ubootmod', 'xiaomi,mi-router-ax3000t-ubootmod', 'Xiaomi AX3000T ubootmod', None),
    'xiaomi_mi-router-wr30u-stock': ('Xiaomi-WR30U-Stock', 'mt7981b-xiaomi-mi-router-wr30u-stock', 'xiaomi,mi-router-wr30u-stock', 'Xiaomi WR30U stock', None),
    'xiaomi_mi-router-wr30u-ubootmod': ('Xiaomi-WR30U-ubootmod', 'mt7981b-xiaomi-mi-router-wr30u-ubootmod', 'xiaomi,mi-router-wr30u-ubootmod', 'Xiaomi WR30U ubootmod', None),
    'nokia_ea0326gmp': ('NOKIA-EA0326GMP', 'mt7981b-nokia-ea0326gmp', 'nokia,ea0326gmp', 'Nokia EA0326GMP', None),
    'sl_3000-emmc': ('SL-3000-EMMC', 'mt7981b-sl-3000-emmc', 'sl,3000-emmc', 'SL-3000 eMMC', None),
    'zbtlink_zbt-z8103ax-c': ('ZBT-Z8103AX-C', 'mt7981b-zbtlink-zbt-z8103ax-c', 'zbtlink,zbt-z8103ax-c', 'ZBT Z8103AX-C', None),
    'clt_r30b1': ('CLT-R30B1', 'mt7981b-clt-r30b1', 'clt,r30b1', 'Creatlentem CLT-R30B1', 'mt7981b-clt-r30b1-base.dtsi'),
}

assert len(DEVICES) == 20

for device, (tag, dts, compatible, label, identity_dts) in DEVICES.items():
    assert f'{device}) tag={tag}; dts={dts}; compatible={compatible}' in script
    assert f'- device: {device}' in workflow
    assert f'tag: {tag}' in workflow
    assert f'label: {label}' in workflow
    assert f'define Device/{device}' in image_makefile
    assert f'TARGET_DEVICES += {device}' in image_makefile
    dts_path = ROOT / 'target/linux/mediatek/dts' / f'{dts}.dts'
    assert dts_path.is_file(), dts_path
    identity_path = ROOT / 'target/linux/mediatek/dts' / (identity_dts or f'{dts}.dts')
    assert identity_path.is_file(), identity_path
    assert f'compatible = "{compatible}", "mediatek,mt7981";' in identity_path.read_text(encoding='utf-8')
    if identity_dts:
        assert f'dts_identity={identity_dts}' in script
    rewritten = re.sub(
        r'^CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y$',
        f'CONFIG_TARGET_mediatek_filogic_DEVICE_{device}=y',
        base_config,
        flags=re.MULTILINE,
    )
    assert f'CONFIG_TARGET_mediatek_filogic_DEVICE_{device}=y' in rewritten

for device in ('cmcc_a10-ubootmod', 'jcg_q30-pro'):
    block = image_makefile.split(f'define Device/{device}', 1)[1].split('endef', 1)[0]
    assert 'kmod-mt7915e' in block

clt_text = (ROOT / 'target/linux/mediatek/dts/mt7981b-clt-r30b1.dts').read_text(encoding='utf-8')
clt_base = (ROOT / 'target/linux/mediatek/dts/mt7981b-clt-r30b1-base.dtsi').read_text(encoding='utf-8')
assert 'mediatek,nmbm;' in clt_text
assert 'generic,nmbm' not in clt_text
assert 'nvmem-cells = <&eeprom_factory>;' in clt_text
assert '&hnat' not in clt_base
assert 'mdio: mdio-bus' not in clt_base

zbt_text = (ROOT / 'target/linux/mediatek/dts/mt7981b-zbtlink-zbt-z8103ax-c.dts').read_text(encoding='utf-8')
assert 'mediatek,nmbm;' in zbt_text
assert 'band@0' in zbt_text and 'band@1' in zbt_text

grouped_devices = []
for line in grouped_workflow.splitlines():
    if line.startswith('            devices: '):
        grouped_devices.append(line.split(':', 1)[1].strip().split())
assert len(grouped_devices) == 4
assert all(len(devices) == 5 for devices in grouped_devices)
assert {device for group in grouped_devices for device in group} == set(DEVICES)
assert 'max-parallel: 4' in grouped_workflow
assert 'integrate-fastacl262-grouped.sh' in grouped_workflow
assert 'immortalwrt-mediatek-filogic.manifest' in grouped_workflow_263
assert '${{ github.run_id }}' in grouped_workflow_263
assert 'find-fastacl-manifest.py' in grouped_workflow_266
assert 'upload/${device}.manifest' in grouped_workflow_266
assert '${{ github.run_id }}' in grouped_workflow_266
assert 'CONFIG_TARGET_MULTI_PROFILE=y' in grouped_script
assert 'CONFIG_TARGET_PER_DEVICE_ROOTFS=y' in grouped_script

assert "make defconfig" in script
assert "CONFIG_TARGET_mediatek_filogic_DEVICE_${device}=y" in script
assert "CONFIG_TARGET_MEDIATEK_FILOGIC_DEVICE_${device}=y" not in script
assert "max-parallel: 20" in workflow
assert "cancel-in-progress: false" in workflow
assert "branches: ['2.6.2']" in workflow
for path in (ROOT / '.github/workflows').glob('*FastACL262*.yml'):
    assert 'cancel-in-progress: false' in path.read_text(encoding='utf-8'), path

print('FastACL 2.6.2 MT7981 device matrix and DTS identities: OK')
