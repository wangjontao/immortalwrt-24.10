#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
PROFILE = ROOT / "profiles/fastacl-v252"


class X86VlanAssetTests(unittest.TestCase):
    def test_build_target_and_architecture_specific_dependencies(self):
        config = (ROOT / "build-configs/JuLiangTK-X86-64-FastACL300.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn("CONFIG_TARGET_x86_64=y", config)
        self.assertIn("CONFIG_TARGET_x86_64_DEVICE_generic=y", config)
        self.assertIn("CONFIG_TARGET_ROOTFS_EXT4FS=y", config)
        self.assertIn("CONFIG_GRUB_EFI_IMAGES=y", config)

        singbox = (PROFILE / "singbox-Makefile").read_text(encoding="utf-8")
        self.assertIn("SING_BOX_ARCH:=amd64", singbox)
        self.assertIn(
            "a1ec76e2b6b139eb747a1b1ebee7d14b8d4be5a833596cad8070a31ef960301f",
            singbox,
        )
        self.assertIn("SING_BOX_ARCH:=arm64", singbox)
        self.assertNotIn("DEPENDS:=@(TARGET_mediatek_filogic", singbox)

        integration = (ROOT / "scripts/integrate-fastacl300-x86.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("GOARCH=amd64", integration)
        self.assertIn("JuLiangTK-X86-64-FastACL300.txt", integration)
        self.assertIn("PKG_VERSION:=3.0", integration)

    def test_default_two_nic_layout_keeps_management_lan_untagged(self):
        defaults = (
            PROFILE / "root/etc/uci-defaults/75-juliangtk-x86-network"
        ).read_text(encoding="utf-8")
        self.assertIn('wan_if="$1"', defaults)
        self.assertIn('lan_if="$2"', defaults)
        self.assertIn("network.lan.ipaddr='192.168.7.1'", defaults)
        self.assertIn("fastacl252.main.vlan_mode='1'", defaults)
        self.assertIn('fastacl252.main.vlan_trunk="$lan_if"', defaults)
        self.assertNotIn("wifi-iface", defaults)

    def test_one_click_vlan_page_and_controller_routes_exist(self):
        controller = (
            PROFILE / "root/usr/lib/lua/luci/controller/fastacl252.lua"
        ).read_text(encoding="utf-8")
        view = (
            PROFILE / "root/usr/lib/lua/luci/view/fastacl252/vlan.htm"
        ).read_text(encoding="utf-8")
        self.assertIn("template('fastacl252/vlan')", controller)
        self.assertIn("fastacl252_vlan_action", controller)
        self.assertIn("一键创建并应用", view)
        self.assertIn("fastacl252_vlan_action", view)
        self.assertIn("H3C AP", view)
        self.assertIn("Trunk", view)

    def test_workflow_builds_both_bios_and_efi_images(self):
        workflow = (
            ROOT / ".github/workflows/JuLiangTK-X86-FastACL300.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("combined-efi.img.gz", workflow)
        self.assertIn("combined.img.gz", workflow)
        self.assertIn("image-efi.iso", workflow)
        self.assertIn("test_vlan.py", workflow)
        self.assertIn("test_vlan_policy.py", workflow)

    def test_x86_build_uses_fastacl_3_version(self):
        config = (ROOT / "build-configs/JuLiangTK-X86-64-FastACL300.txt").read_text(
            encoding="utf-8"
        )
        integration = (ROOT / "scripts/integrate-fastacl300-x86.sh").read_text(
            encoding="utf-8"
        )
        readme = (PROFILE / "README-3.0.md").read_text(encoding="utf-8")
        self.assertIn('CONFIG_VERSION_CODE="FastACL3.0-X86"', config)
        self.assertIn("PKG_VERSION:=3.0", integration)
        self.assertIn("FastACL 3.0", readme)


if __name__ == "__main__":
    unittest.main(verbosity=2)
