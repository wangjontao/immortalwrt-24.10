#!/bin/sh
set -eu

test -f build-configs/JuLiangTK-X86-64-FastACL300.txt
test -f profiles/fastacl-v252/root/usr/lib/lua/fastacl252_vlan.lua
test -f profiles/fastacl-v252/root/usr/lib/lua/luci/view/fastacl252/vlan.htm

mkdir -p package/fastacl252 package/juliangtk-sing-box
cp profiles/fastacl-v252/package-Makefile package/fastacl252/Makefile
cp profiles/fastacl-v252/singbox-Makefile package/juliangtk-sing-box/Makefile
rm -rf package/fastacl252/files
cp -a profiles/fastacl-v252/root package/fastacl252/files

# FastACL 3.0 is the X86 VLAN gateway product. The shared router profile
# remains on its own release line until the 3.0 branch is promoted.
sed -i \
  -e 's/^PKG_VERSION:=2\.8\.2$/PKG_VERSION:=3.0/' \
  -e 's/FastACL 2\.8\.2/FastACL 3.0/' \
  package/fastacl252/Makefile
sed -i \
  -e "s/version='2\.8\.2'/version='3.0'/g" \
  -e "s/V2\.8\.2/V3.0/g" \
  -e "s/FastACL 2\.8\.2/FastACL 3.0/g" \
  package/fastacl252/files/usr/lib/lua/luci/controller/fastacl252.lua \
  package/fastacl252/files/usr/lib/lua/luci/controller/juliang_center.lua \
  package/fastacl252/files/usr/lib/lua/luci/view/fastacl252/console.htm \
  package/fastacl252/files/usr/lib/lua/luci/view/juliang_center/home.htm
sed -i \
  -e "s/option version '2\.8\.2'/option version '3.0'/" \
  package/fastacl252/files/etc/config/fastacl252
sed -i \
  -e "s/main\.version=2\.8\.2/main.version=3.0/g" \
  -e "s/main\.version='2\.8\.2'/main.version='3.0'/g" \
  package/fastacl252/files/etc/uci-defaults/99-juliangtk-fastacl252 \
  package/fastacl252/files/etc/uci-defaults/99-juliangtk-fastacl252-x86

(
  cd profiles/fastacl-v252/dns
  go mod tidy
  go mod vendor
  python3 ../patch_outbound.py .
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -mod=vendor -trimpath -ldflags="-s -w" \
    -o ../../../package/fastacl252/files/usr/bin/fastacl252-dns .
)

rm -f files/root/setup-20wifi-acl.sh files/root/add_ap20_wifi.sh
rm -f files/root/ap20-wifi-config/passwall files/root/ap20-wifi-config/passwall2
rm -f files/etc/init.d/setup-20wifi-firstboot files/etc/uci-defaults/99-enable-20wifi-firstboot
rm -f package/base-files/files/etc/uci-defaults/99-dulwifi
for root in files package/base-files/files; do
  [ -d "$root" ] || continue
  find "$root" -type f \( \
    -iname '*passwall*' -o -iname '*homeproxy*' -o -iname '*openclash*' \
    -o -iname '*20wifi*' -o -iname '*juliang-fastacl*' \
  \) -delete
done

cp build-configs/JuLiangTK-X86-64-FastACL300.txt .config
make defconfig
sh scripts/integrate-fastacl252-dependencies.sh

for pkg in \
  fastacl252 juliangtk-sing-box kmod-tun firewall4 dnsmasq-full \
  ip-full curl ca-bundle nftables-json sqm-scripts kmod-sched-cake kmod-ifb
do
  grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config || {
    echo "Required package missing: $pkg" >&2
    exit 1
  }
done

for line in \
  'CONFIG_TARGET_x86=y' \
  'CONFIG_TARGET_x86_64=y' \
  'CONFIG_TARGET_x86_64_DEVICE_generic=y' \
  'CONFIG_TARGET_ROOTFS_EXT4FS=y'
do
  grep -qx "$line" .config || {
    echo "Required X86 image option missing: $line" >&2
    exit 1
  }
done

if grep -E '^CONFIG_PACKAGE_(luci-app-store|luci-app-quickstart|quickstart|taskd)=y$' .config; then
  echo "iStore/QuickStart must not be selected in FastACL X86" >&2
  exit 1
fi
if grep -E '^CONFIG_PACKAGE_(luci-app-(passwall2?|homeproxy|openclash)|luci-i18n-(passwall2?|homeproxy|openclash)-[^=]+)=(y|m)$' .config; then
  echo "Forbidden proxy plugin selected" >&2
  exit 1
fi

find package/fastacl252/files/etc/init.d package/fastacl252/files/etc/hotplug.d \
  package/fastacl252/files/etc/uci-defaults -type f -exec chmod 755 {} \;
chmod 755 package/fastacl252/files/usr/bin/fastacl252 \
  package/fastacl252/files/usr/bin/fastacl252-dns \
  package/fastacl252/files/usr/libexec/fastacl252-enable.sh
chmod 600 package/fastacl252/files/etc/config/fastacl252

grep -q "PKG_VERSION:=3.0" package/fastacl252/Makefile
grep -q "version='3.0'" package/fastacl252/files/usr/lib/lua/luci/controller/fastacl252.lua
grep -q "TARGET_x86_64" package/juliangtk-sing-box/Makefile
grep -q "sing-box-.*-linux-amd64.tar.gz" package/juliangtk-sing-box/Makefile
file package/fastacl252/files/usr/bin/fastacl252-dns | grep -q 'x86-64'
./scripts/diffconfig.sh > JuLiang-OS-X86-64-fastacl300-final.config
