from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
dts = (
    ROOT / "target/linux/mediatek/dts/mt7981b-ruijie-sr503.dts"
).read_text(encoding="utf-8")
nps = (
    ROOT / "profiles/fastacl-v252/root/usr/libexec/nps-wan-mac"
).read_text(encoding="utf-8")

assert "label-mac-device = &gmac0;" in dts
assert "macaddr_factory_4: macaddr@4" in dts
assert "reg = <0x4 0x6>;" in dts
assert "nvmem-cells = <&macaddr_factory_4>;" in dts
assert 'nvmem-cell-names = "mac-address";' in dts
assert 'CURRENT_KEY="$(uci -q get nps.@nps[0].vkey' in nps
assert '[ "$CURRENT_KEY" != "$NPS_KEY" ]' in nps

print("SR503 label MAC binding and NPS key refresh: OK")
