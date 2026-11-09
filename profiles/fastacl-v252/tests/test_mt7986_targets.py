#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TARGETS = {
    "clx_s20l": ("mt7986a-clx-s20l.dts", "clx,s20l"),
    "clx_s20p": ("mt7986a-clx-s20p.dts", "clx,s20p"),
    "jdcloud_re-cp-03": ("mt7986a-jdcloud-re-cp-03.dts", "jdcloud,re-cp-03"),
    "xiaomi_redmi-router-ax6000": (
        "mt7986a-xiaomi-redmi-router-ax6000.dts",
        "xiaomi,redmi-router-ax6000",
    ),
}

image_mk = (ROOT / "target/linux/mediatek/image/filogic.mk").read_text(encoding="utf-8")
network = (ROOT / "target/linux/mediatek/filogic/base-files/etc/board.d/02_network").read_text(encoding="utf-8")
platform = (ROOT / "target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh").read_text(encoding="utf-8")
uboot = (ROOT / "package/boot/uboot-envtools/files/mediatek_filogic").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/JuLiangOS-v2.8.5-S20L-LEDE.yml").read_text(encoding="utf-8")

for device, (dts_name, compatible) in TARGETS.items():
    dts = ROOT / "target/linux/mediatek/dts" / dts_name
    assert dts.is_file(), f"missing DTS: {dts_name}"
    assert compatible in dts.read_text(encoding="utf-8"), f"wrong compatible: {dts_name}"
    assert f"define Device/{device}" in image_mk, f"missing image target: {device}"
    assert compatible in network, f"missing network board mapping: {device}"
    if device != "xiaomi_redmi-router-ax6000":
        assert compatible in platform, f"missing sysupgrade mapping: {device}"
    assert compatible in uboot, f"missing U-Boot environment mapping: {device}"
    assert f"device: {device}" in workflow, f"missing workflow matrix entry: {device}"

print("PASS four MT7986 build targets and board integration")
