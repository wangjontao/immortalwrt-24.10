from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
dts = (
    ROOT / "target/linux/mediatek/dts/mt7981b-philips-hy3000.dts"
).read_text(encoding="utf-8")
image = (ROOT / "target/linux/mediatek/image/filogic.mk").read_text(
    encoding="utf-8"
)
integration = (
    ROOT / "scripts/integrate-juliang-live13-sr503.sh"
).read_text(encoding="utf-8")

assert 'compatible = "philips,hy3000", "mediatek,mt7981";' in dts
assert "root=PARTLABEL=rootfs rootwait rootfstype=squashfs,f2fs" in dts
assert "nvmem-cell-names = \"mac-address\";" in dts
assert "define Device/philips_hy3000" in image
assert "DEVICE_DTS := mt7981b-philips-hy3000" in image
assert "TARGET_DEVICES += philips_hy3000" in image
assert "JULIANG_DEVICE" in integration and "JULIANG_CONFIG" in integration

print("JuLiang OS Live 1.5 HY3000 target: OK")
