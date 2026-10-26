#!/usr/bin/env python3
"""Validate the complete FastACL 2.8.0 MT7981 and MT7986 build matrix."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
integration = (ROOT / "scripts/integrate-fastacl252-s20l.sh").read_text(encoding="utf-8")
mt7981_workflow = (
    ROOT / ".github/workflows/JuLiangTK-MT7981-FastACL280-Grouped.yml"
).read_text(encoding="utf-8")
mt7986_workflow = (
    ROOT / ".github/workflows/JuLiangTK-MT7986-FastACL280.yml"
).read_text(encoding="utf-8")
package = (ROOT / "profiles/fastacl-v252/package-Makefile").read_text(encoding="utf-8")

MT7981 = {
    "philips_hy3000",
    "cmcc_rax3000m",
    "cmcc_rax3000m-emmc",
    "qihoo_360t7",
    "aigo_ags21",
    "cmcc_a10-ubootmod",
    "konka_komi-a31",
    "newland_nl-wr8103",
    "newland_nl-wr9103",
    "abt_asr3000",
    "jcg_q30-pro",
    "xiaomi_mi-router-ax3000t",
    "xiaomi_mi-router-ax3000t-mtkuboot",
    "xiaomi_mi-router-ax3000t-ubootmod",
    "xiaomi_mi-router-wr30u-stock",
    "xiaomi_mi-router-wr30u-ubootmod",
    "nokia_ea0326gmp",
    "sl_3000-emmc",
    "zbtlink_zbt-z8103ax-c",
    "clt_r30b1",
}
MT7986 = {
    "clx_s20l": ("S20L", "JuLiangTK-S20L-FastACL280.txt"),
    "clx_s20p": ("S20P", "JuLiangTK-S20P-FastACL280.txt"),
    "jdcloud_re-cp-03": ("JDCloud-RE-CP-03", "JuLiangTK-JDCloud-RE-CP-03-FastACL280.txt"),
    "xiaomi_redmi-router-ax6000": (
        "Redmi-AX6000-NMBM110M",
        "JuLiangTK-Redmi-AX6000-NMBM110M-FastACL280.txt",
    ),
}

assert "PKG_VERSION:=2.8.0" in package
assert "PKG_RELEASE:=22" in package
assert "+nftables-json" in package and "+nftables " not in package
dependencies = (ROOT / "profiles/fastacl-v252/dependencies.config").read_text(encoding="utf-8")
assert "CONFIG_PACKAGE_nftables-json=y" in dependencies
assert "CONFIG_PACKAGE_nftables=y" not in dependencies

for device in MT7981:
    assert f"{device}) tag=" in integration, device
    assert device in mt7981_workflow, device

grouped_devices = []
for line in mt7981_workflow.splitlines():
    if line.startswith("            devices: "):
        grouped_devices.append(line.split(":", 1)[1].strip().split())
assert len(grouped_devices) == 4
assert all(len(devices) == 5 for devices in grouped_devices)
assert {device for group in grouped_devices for device in group} == MT7981

for device, (tag, config_name) in MT7986.items():
    assert f"{device}) tag={tag};" in integration, device
    assert f"device: {device}" in mt7986_workflow, device
    assert f"tag: {tag}" in mt7986_workflow, tag
    config = (ROOT / "build-configs" / config_name).read_text(encoding="utf-8")
    assert f"CONFIG_TARGET_mediatek_filogic_DEVICE_{device}=y" in config
    assert "CONFIG_PACKAGE_juliangtk-sing-box=y" in config
    assert "CONFIG_PACKAGE_juliangtk-dae=y" not in config
    assert 'CONFIG_VERSION_CODE="FastACL2.8.0"' in config
    assert 'CONFIG_VERSION_DIST="JuLiang OS"' in config
    assert 'CONFIG_VERSION_MANUFACTURER="JuLiang OS"' in config
    assert 'CONFIG_VERSION_PRODUCT="JuLiang OS"' in config

for workflow in (mt7981_workflow, mt7986_workflow):
    assert "branches: ['2.8.0']" in workflow
    assert "test_import.py" in workflow
    assert "test_traffic_ui.py" in workflow
    assert "test_fixed_exit.py" in workflow

assert "integrate-fastacl280-grouped.sh" in mt7981_workflow
assert "integrate-fastacl252-s20l.sh" in mt7986_workflow
assert "test_redmi_110m_layout.py" in mt7986_workflow
assert "README-2.8.0.md" in mt7986_workflow
assert "find-fastacl280-manifest.py" in mt7981_workflow
assert "find-fastacl280-manifest.py" in mt7986_workflow
assert 'JuLiang-OS-${DEVICE_GROUP}-final.config' in mt7981_workflow
assert 'JuLiang-OS-${DEVICE_TAG}-final.config' in mt7986_workflow

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    profiles = root / "profiles"
    profiles.mkdir()
    (root / "shared.manifest").write_text("shared", encoding="utf-8")
    (profiles / "clx_s20l.manifest").write_text("device", encoding="utf-8")
    result = subprocess.check_output(
        [
            sys.executable,
            str(ROOT / "scripts/find-fastacl280-manifest.py"),
            str(root),
            "clx_s20l",
        ],
        text=True,
    ).strip()
    assert Path(result).name == "clx_s20l.manifest"

print("FastACL 2.8.0 MT7981 and MT7986 build matrix: OK")
