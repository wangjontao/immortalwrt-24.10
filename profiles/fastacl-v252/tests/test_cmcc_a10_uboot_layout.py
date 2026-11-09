#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
dts = (
    ROOT / "target/linux/mediatek/dts/mt7981b-cmcc-a10-mod.dts"
).read_text(encoding="utf-8")

assert "bootargs-append = \" ubi.mtd=ubi root=/dev/ubiblock0_1\"" in dts
assert "reg = <0x0580000 0x7280000>" in dts
assert "/delete-node/ partition@4580000" in dts
assert "/delete-node/ partition@6580000" in dts
assert "/delete-node/ partition@6680000" in dts

print("PASS CMCC A10 U-Boot uses the 114.5 MiB expanded UBI layout")
