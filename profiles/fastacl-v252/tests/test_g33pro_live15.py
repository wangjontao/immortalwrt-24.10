#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
dts = (ROOT / "target/linux/mediatek/dts/mt7981b-gielink-g33pro.dts").read_text(
    encoding="utf-8"
)
image = (ROOT / "target/linux/mediatek/image/filogic.mk").read_text(encoding="utf-8")
network = (
    ROOT / "target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
).read_text(encoding="utf-8")

assert 'model = "GIE-LINK G33 Pro";' in dts
assert 'compatible = "gielink,g33pro", "mediatek,mt7981";' in dts
assert "reg = <0x0580000 0x7200000>;" in dts
assert "mediatek,nmbm;" in dts
assert "macaddr_wan: macaddr@a0024" in dts
assert "macaddr_lan: macaddr@a002a" in dts

assert "define Device/gielink_g33pro" in image
assert "DEVICE_DTS := mt7981b-gielink-g33pro" in image
assert "IMAGE_SIZE := 116736k" in image
assert "IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)" in image
assert "TARGET_DEVICES += gielink_g33pro" in image

assert "gielink,g33pro|\\" in network
assert 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan' in network

makefile = (ROOT / "package/fastacl252/Makefile").read_text(encoding="utf-8")
assert "PKG_VERSION:=1.5" in makefile
assert (ROOT / "package/fastacl252/files/usr/lib/lua/luci/view/fastacl252/live13.htm").is_file()

print("JuLiang OS Live 1.5 G33 Pro target: OK")
