#!/usr/bin/env bash
set -euo pipefail

UBOOT_DIR="${1:?usage: verify-pair.sh UBOOT_DIR FACTORY.ubi SYSUPGRADE.bin}"
FACTORY="${2:?usage: verify-pair.sh UBOOT_DIR FACTORY.ubi SYSUPGRADE.bin}"
SYSUPGRADE="${3:?usage: verify-pair.sh UBOOT_DIR FACTORY.ubi SYSUPGRADE.bin}"
DUMPIMAGE="${DUMPIMAGE:-/home/builder/juliang-ax3000t-build/build_dir/host/u-boot-2024.07/tools/dumpimage}"
DTC="${DTC:-/home/builder/bl-mt798x-uboot/uboot-mtk-20230718-09eda825/scripts/dtc/dtc}"

FIP="$UBOOT_DIR/mt7981_ax3000t-fip-fixed-parts-multi-layout.bin"
BL2="$UBOOT_DIR/mt7981_ax3000t-bl2.bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

test -s "$BL2"
test -s "$FIP"
test -s "$FACTORY"
test -s "$SYSUPGRADE"
test -x "$DUMPIMAGE"
test -x "$DTC"

grep -a -F -q '112m(ubi)' "$FIP"
grep -a -F -q 'Mesh or reset button pressed, starting Web failsafe' "$FIP"
grep -a -F -q 'Start Web failsafe' "$FIP"
grep -a -F -q 'nmbm0:1024k(bl2),256k(Nvram),256k(Bdata),2048k(factory),2048k(fip),256k(crash),256k(crash_log),112m(ubi),256k(KF)' "$FIP"

test "$(head -c 4 "$FACTORY")" = "UBI#"
test "$(dd if="$SYSUPGRADE" bs=1 skip=257 count=5 status=none)" = "ustar"

tar -xf "$SYSUPGRADE" -C "$TMP" sysupgrade-xiaomi_mi-router-ax3000t-112m/kernel
"$DUMPIMAGE" -l "$TMP/sysupgrade-xiaomi_mi-router-ax3000t-112m/kernel" > "$TMP/fit.txt"
grep -F -q 'Default Configuration: '\''config-1'\''' "$TMP/fit.txt"
grep -F -q 'Image 1 (fdt-1)' "$TMP/fit.txt"

"$DUMPIMAGE" -T flat_dt -p 1 -o "$TMP/fdt.dtb" "$TMP/sysupgrade-xiaomi_mi-router-ax3000t-112m/kernel"
"$DTC" -I dtb -O dts "$TMP/fdt.dtb" > "$TMP/fdt.dts" 2>/dev/null
grep -F -q 'model = "Xiaomi Mi Router AX3000T (112M UBI layout)";' "$TMP/fdt.dts"
grep -F -q 'partition@600000 {' "$TMP/fdt.dts"
grep -F -q 'label = "ubi";' "$TMP/fdt.dts"
grep -F -q 'reg = <0x600000 0x7000000>;' "$TMP/fdt.dts"

printf 'U-Boot and 112 MiB firmware layout match\n'
sha256sum "$BL2" "$FIP" "$FACTORY" "$SYSUPGRADE"
