#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/hanwckf/bl-mt798x.git}"
UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-abe158087c80ed1896f2c281e2dae5e43ffbee41}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
SRC_DIR="${SRC_DIR:-$BUILD_ROOT/bl-mt798x}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
PATCH_FILE="${PATCH_FILE:-$ROOT/patches/0001-ax3000t-112m-mesh-web.patch}"

command -v aarch64-linux-gnu-gcc >/dev/null
command -v dtc >/dev/null
command -v python3 >/dev/null
command -v python >/dev/null

mkdir -p "$BUILD_ROOT" "$OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  git clone --filter=blob:none --no-checkout "$UPSTREAM_REPO" "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --depth 1 origin "$UPSTREAM_COMMIT"
git checkout --force --detach "$UPSTREAM_COMMIT"
git clean -fdx
git apply "$PATCH_FILE"

SOC=mt7981 \
BOARD=ax3000t \
MULTI_LAYOUT=1 \
FIXED_MTDPARTS=1 \
./build.sh

FIP=output/mt7981_ax3000t-fip-fixed-parts-multi-layout.bin
grep -a -F -q '112m(ubi)' "$FIP"
grep -a -F -q 'Mesh or reset button pressed, starting Web failsafe' "$FIP"
grep -a -F -q 'Start Web failsafe' "$FIP"

cp -f output/mt7981_ax3000t-fip-fixed-parts-multi-layout.bin "$OUT_DIR/"
if [ -f output/mt7981_ax3000t-bl2.bin ]; then
  cp -f output/mt7981_ax3000t-bl2.bin "$OUT_DIR/"
fi

cd "$OUT_DIR"
sha256sum *.bin > SHA256SUMS
cat SHA256SUMS
