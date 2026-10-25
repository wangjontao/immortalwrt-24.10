#!/bin/sh
set -eu

test "$#" -gt 0 || {
  echo "Usage: $0 device [device ...]" >&2
  exit 2
}

devices="$*"
first=$1
group=${DEVICE_GROUP:-devices}

for device in $devices; do
  grep -q "^define Device/${device}$" target/linux/mediatek/image/filogic.mk || {
    echo "Unknown image target: $device" >&2
    exit 1
  }
  grep -q "^TARGET_DEVICES += ${device}$" target/linux/mediatek/image/filogic.mk || {
    echo "Target is not exported: $device" >&2
    exit 1
  }
done

# Run the normal integration once to install FastACL and its package defaults,
# then turn the generated single-profile configuration into a multi-profile one.
sh scripts/integrate-fastacl252-s20l.sh "$first"

sed -i \
  -e '/^CONFIG_TARGET_mediatek_filogic_DEVICE_/d' \
  -e '/^# CONFIG_TARGET_mediatek_filogic_DEVICE_/d' \
  -e '/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/d' \
  -e '/^# CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/d' \
  -e '/^CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_/d' \
  -e '/^# CONFIG_TARGET_DEVICE_PACKAGES_mediatek_filogic_DEVICE_/d' \
  .config

{
  echo 'CONFIG_TARGET_MULTI_PROFILE=y'
  echo 'CONFIG_TARGET_PER_DEVICE_ROOTFS=y'
  for device in $devices; do
    echo "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${device}=y"
  done
} >> .config

make defconfig

grep -qx 'CONFIG_TARGET_MULTI_PROFILE=y' .config || {
  echo "Multi-profile mode was not retained" >&2
  exit 1
}
grep -qx 'CONFIG_TARGET_PER_DEVICE_ROOTFS=y' .config || {
  echo "Per-device rootfs mode was not retained" >&2
  exit 1
}
for device in $devices; do
  grep -qx "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_${device}=y" .config || {
    echo "Required target missing from grouped config: $device" >&2
    exit 1
  }
done

./scripts/diffconfig.sh > "JuLiangTK-${group}-final.config"
