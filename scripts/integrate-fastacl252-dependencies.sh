#!/bin/sh
set -eu
test -f target/linux/mediatek/filogic/config-6.6
mkdir -p package/juliangtk-sing-box
cp profiles/fastacl-v252/singbox-Makefile package/juliangtk-sing-box/Makefile
sed -i \
  -e '/^CONFIG_PACKAGE_juliangtk-dae=/d' \
  -e '/^# CONFIG_PACKAGE_juliangtk-dae is not set/d' \
  -e '/^CONFIG_PACKAGE_juliangtk-sing-box=/d' \
  -e '/^# CONFIG_PACKAGE_juliangtk-sing-box is not set/d' \
  .config
cat profiles/fastacl-v252/dependencies.config >> .config
make defconfig
for pkg in juliangtk-sing-box kmod-tun kmod-sched-core kmod-sched-cake kmod-ifb ip-full tc-full ca-bundle curl nftables-json; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config || { echo "Missing sing-box dependency: $pkg"; exit 1; }
done
