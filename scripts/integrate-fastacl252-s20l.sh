#!/bin/sh
set -eu
test -f target/linux/mediatek/dts/mt7986a-clx-s20l.dts
# Preserve the actual hardware compatibility, partitions and flash definitions.
sed -i 's/model = "CLX S20L"/model = "JuLiangTK S20L"/' target/linux/mediatek/dts/mt7986a-clx-s20l.dts
mkdir -p package/fastacl252 package/juliangtk-dae
cp profiles/fastacl-v252/package-Makefile package/fastacl252/Makefile
cp profiles/fastacl-v252/core-Makefile package/juliangtk-dae/Makefile
cp -a profiles/fastacl-v252/root package/fastacl252/files
(cd profiles/fastacl-v252/dns && go mod tidy && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ../../../package/fastacl252/files/usr/bin/fastacl252-dns .)
# Remove legacy multi-SSID overlays and proxy config files from the build only.
rm -f files/root/setup-20wifi-acl.sh files/root/add_ap20_wifi.sh
rm -f files/root/ap20-wifi-config/passwall files/root/ap20-wifi-config/passwall2
rm -f files/etc/init.d/setup-20wifi-firstboot files/etc/uci-defaults/99-enable-20wifi-firstboot
rm -f package/base-files/files/etc/uci-defaults/99-dulwifi
for root in files package/base-files/files; do
  [ -d "$root" ] || continue
  find "$root" -type f \( -iname '*passwall*' -o -iname '*homeproxy*' -o -iname '*openclash*' -o -iname '*20wifi*' -o -iname '*juliang-fastacl*' \) -delete
done
sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/192.168.7.1/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JuLiangTK-S20L'/g" package/base-files/files/bin/config_generate
ROOT_HASH=$(openssl passwd -1 '@password@')
sed -i "s#^root:[^:]*:#root:${ROOT_HASH}:#" package/base-files/files/etc/shadow
find package/fastacl252/files/etc/init.d package/fastacl252/files/etc/hotplug.d package/fastacl252/files/etc/uci-defaults -type f -exec chmod 755 {} \;
chmod 755 package/fastacl252/files/usr/bin/fastacl252 package/fastacl252/files/usr/libexec/fastacl252-enable.sh
chmod 600 package/fastacl252/files/etc/config/fastacl252
cp build-configs/JuLiangTK-S20L-FastACL252.txt .config
sh scripts/integrate-fastacl252-dependencies.sh
for pkg in luci-app-store luci-app-quickstart luci-theme-argon luci-app-argon-config luci-app-ttyd luci-app-autoreboot luci-app-statistics nps npc luci-app-nps lyaml fastacl252 juliangtk-dae firewall4; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || { echo "Required package missing: $pkg"; exit 1; }
done
if grep -E '^CONFIG_PACKAGE_(luci-app-(passwall2?|homeproxy|openclash)|luci-i18n-(passwall2?|homeproxy|openclash)-[^=]+)=(y|m)$' .config; then echo 'Forbidden proxy plugin selected'; exit 1; fi
grep -q '^CONFIG_TARGET_mediatek_filogic_DEVICE_clx_s20l=y' .config
grep -q 'compatible = "clx,s20l", "mediatek,mt7986a"' target/linux/mediatek/dts/mt7986a-clx-s20l.dts
./scripts/diffconfig.sh > JuLiangTK-S20L-final.config
