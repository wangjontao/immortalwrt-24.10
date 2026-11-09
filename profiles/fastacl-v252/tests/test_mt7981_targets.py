#!/usr/bin/env python3
import importlib.util
import json
import re
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "mt7981_builder", ROOT / "scripts/juliang-os-mt7981.py"
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)

data = json.loads(builder.MANIFEST.read_text(encoding="utf-8"))
entries = data["devices"]
assert len(entries) == 38
assert len({entry["device"] for entry in entries}) == len(entries)
assert len({entry["compatible"] for entry in entries if entry["device"] != "cmcc_rax3000me-nand"}) == 37

filogic = (ROOT / "target/linux/mediatek/image/filogic.mk").read_text(encoding="utf-8")
actual = {}
for match in re.finditer(r"(?ms)^define Device/([^\r\n]+)\r?\n(.*?)^endef", filogic):
    device = match.group(1)
    dts_match = re.search(r"^\s*DEVICE_DTS\s*:=\s*([^\r\n]+)", match.group(2), re.MULTILINE)
    if dts_match and dts_match.group(1).strip().startswith("mt7981"):
        actual[device] = dts_match.group(1).strip()

manifest = {entry["device"]: entry["dts"] for entry in entries}
assert manifest == actual
assert builder.image_name("jcg_q30-pro") == "juliang-os-v2.8.5-mediatek-filogic-jcg_q30-pro-squashfs-sysupgrade.bin"

for entry in entries:
    dts = (ROOT / f"target/linux/mediatek/dts/{entry['dts']}.dts").read_text(encoding="utf-8")
    compatible = re.search(r'^\s*compatible\s*=\s*"([^"]+)"', dts, re.MULTILINE)
    assert compatible and compatible.group(1) == entry["compatible"], entry["device"]

base = (ROOT / "build-configs/JuLiang-OS-S20L-v2.8.5.txt").read_text(encoding="utf-8")
with tempfile.TemporaryDirectory() as directory:
    config = Path(directory) / ".config"
    config.write_text(base, encoding="utf-8")
    builder.configure(config)
    builder.verify_config(config)
    text = config.read_text(encoding="utf-8")
    assert "CONFIG_TARGET_mediatek_filogic_DEVICE_clx_s20l=y" not in text
    assert text.count("CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_") == 38
    assert "CONFIG_TARGET_MULTI_PROFILE=y" in text
    assert "CONFIG_TARGET_PER_DEVICE_ROOTFS=y" in text
    assert "# CONFIG_TARGET_ALL_PROFILES is not set" in text
    assert 'CONFIG_VERSION_NUMBER="v2.8.5"' in text
    assert 'CONFIG_VERSION_HWREV="MT7981"' in text
    assert 'CONFIG_VERSION_CODE="MT7981-ALL"' in text
    assert "ARTIFACTS := $(if $(CONFIG_TARGET_MULTI_PROFILE),,emmc-preloader.bin emmc-bl31-uboot.fip)" in filogic
    assert "ARTIFACTS := $(if $(CONFIG_TARGET_MULTI_PROFILE),,nand-ddr3-preloader.bin nand-ddr3-bl31-uboot.fip nand-ddr4-preloader.bin nand-ddr4-bl31-uboot.fip)" in filogic
    for package in builder.OPTIONAL_BOOTLOADER_PACKAGES:
        assert f"CONFIG_PACKAGE_{package}=" not in text

print("JuLiang OS MT7981 target manifest: OK")
