#!/bin/sh
set -eu

device=ruijie_sr503
tag=SR503
dts=mt7981b-ruijie-sr503
compatible=ruijie,sr503
nps_domain=${NPS_DOMAIN:-nps.jontao.top}

case "$nps_domain" in
  ''|*[!A-Za-z0-9.-]*) echo "Invalid NPS domain: $nps_domain" >&2; exit 1 ;;
esac

test -f "target/linux/mediatek/dts/$dts.dts"
rm -rf package/juliangtk-sing-box
mkdir -p package/fastacl252
cp profiles/fastacl-v252/package-Makefile package/fastacl252/Makefile
rm -rf package/fastacl252/files
mkdir -p package/fastacl252/files
cp -a profiles/fastacl-v252/root/. package/fastacl252/files/
find package/fastacl252/files -type f -exec sed -i 's/2\.8\.6/1.5/g' {} +
sed -i 's/2\.8\.6/1.5/g' package/fastacl252/Makefile
sed -i 's/+juliangtk-sing-box/+sing-box/g' package/fastacl252/Makefile

# Live 1.5 uses the older dashboard as the root page and keeps the standard
# LuCI application menus, including PassWall2, HomeProxy and FileTransfer.
rm -f package/fastacl252/files/etc/uci-defaults/97-juliang-menu-cleanup
sed -i '/juliang-menu-cleanup\.lua/d' package/fastacl252/Makefile
sed -i "s/entry({'admin','juliang'},firstchild(),_('JuLiang OS 控制面板'),1)/entry({'admin','juliang'},firstchild(),_('JuLiang OS 控制面板'),50)/" \
  package/fastacl252/files/usr/lib/lua/luci/controller/juliang_center.lua
(cd profiles/fastacl-v252/dns &&
  if [ ! -d vendor ]; then
    go mod tidy &&
    go mod vendor
  fi &&
  python3 ../patch_outbound.py . &&
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -mod=vendor -trimpath \
    -ldflags="-s -w" -o ../../../package/fastacl252/files/usr/bin/fastacl252-dns .)

rm -rf files
mkdir -p files
cp -a custom/rax3000m-nand/files/. files/

ROOT_HASH=$(openssl passwd -1 '@password@')
cp package/base-files/files/etc/shadow files/etc/shadow
sed -i "s#^root:[^:]*:#root:${ROOT_HASH}:#" files/etc/shadow
printf '%s\n' "$ROOT_HASH" > files/etc/dulwifi-root.hash
chmod 600 files/etc/shadow files/etc/dulwifi-root.hash

# The Live 1.5 shell is the JuLiang-branded Argon layout.
sed -i "s/HOSTNAME='JuLiang-OS'/HOSTNAME='JuLiang-OS'/" files/etc/uci-defaults/99-zz-dulwifi

# Live WiFi is intentionally not client-isolated in the confirmed layout.
sed -i "s/'Live-2.4G'       '1'/'Live-2.4G'       ''/" files/etc/init.d/juliang-wifi
sed -i "s/'Live-5G'         '1'/'Live-5G'         ''/" files/etc/init.d/juliang-wifi

cat > files/etc/uci-defaults/99-zzzz-live13-defaults <<'EOF'
#!/bin/sh
uci set system.@system[0].hostname='JuLiang-OS'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci set argon.@global[0].mode='dark'
uci set dropbear.@dropbear[0].Port='22'
uci commit system
uci commit luci
uci commit dropbear
exit 0
EOF
chmod 755 files/etc/uci-defaults/99-zzzz-live13-defaults

for f in \
  files/etc/init.d/dulwifi-firstboot \
  files/etc/init.d/juliang-dashboard \
  files/etc/init.d/juliang-wifi \
  files/etc/init.d/wan-lease-guard \
  files/usr/libexec/dulwifi-firstboot \
  files/usr/libexec/nps-wan-mac \
  files/usr/libexec/wan-lease-guard \
  files/usr/bin/juliang-traffic-daemon \
  files/usr/bin/juliang-traffic-sample
do
  [ -e "$f" ] && chmod 755 "$f"
done
find files/etc/uci-defaults files/etc/hotplug.d -type f -exec chmod 755 {} +

mkdir -p files/etc/rc.d
rm -f files/etc/rc.d/S20juliang-wifi files/etc/rc.d/K20juliang-wifi
ln -sf ../init.d/juliang-wifi files/etc/rc.d/S95juliang-wifi
ln -sf ../init.d/wan-lease-guard files/etc/rc.d/S95wan-lease-guard

for p in \
  package/fastacl252/files/usr/libexec/nps-wan-mac \
  package/base-files/files/usr/libexec/nps-wan-mac \
  files/usr/libexec/nps-wan-mac
do
  [ -f "$p" ] || continue
  sed -i \
    -e 's/47\.83\.9\.208/nps.jontao.top/g' \
    -e "s/nps\.jontao\.top/${nps_domain}/g" \
    -e "s/nps\.66ccs\.com/${nps_domain}/g" \
    "$p"
done

for p in $(find feeds/luci package/feeds/luci feeds/lede_luci package/feeds/lede_luci \
  -path '*/luci-app-nps/root/etc/config/nps' -type f 2>/dev/null); do
  sed -i \
    -e "s/option server_addr '.*'/option server_addr '${nps_domain}'/" \
    -e "s/47\.83\.9\.208/${nps_domain}/g" "$p"
done

sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/192.168.7.1/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JuLiang-OS'/g" package/base-files/files/bin/config_generate
sed -i "s/template(\"juliang_dashboard\/home\"), _(\"首页\"), 5/template(\"juliang_dashboard\/home\"), _(\"首页\"), 0/" \
  files/usr/lib/lua/luci/controller/juliang_dashboard.lua
cp build-configs/JuLiang-OS-Live1.3-SR503.txt .config
make defconfig
sed -i '/^CONFIG_PACKAGE_juliangtk-sing-box=/d' .config

sed -i \
  -e 's/^CONFIG_VERSION_HWREV=.*/CONFIG_VERSION_HWREV="SR503"/' \
  -e 's/^CONFIG_VERSION_CODE=.*/CONFIG_VERSION_CODE="SR503-1.5-Live"/' \
  -e 's/^CONFIG_VERSION_NUMBER=.*/CONFIG_VERSION_NUMBER="v1.5"/' \
  -e 's/^CONFIG_VERSION_PRODUCT=.*/CONFIG_VERSION_PRODUCT="JuLiang OS"/' \
  .config

for pkg in \
  luci-theme-juliang luci-theme-argon luci-app-passwall2 luci-app-homeproxy \
  luci-app-filetransfer luci-app-arpbind luci-app-upnp \
  luci-app-sqm sqm-scripts kmod-sched-cake kmod-ifb tc-tiny \
  luci-app-nps npc fastacl252 sing-box kmod-tcp-bbr
do
  grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config || {
    echo "Required Live 1.3 package missing: $pkg" >&2
    exit 1
  }
done

grep -q "^CONFIG_TARGET_mediatek_filogic_DEVICE_${device}=y$" .config || {
  echo "SR503 target missing from .config" >&2
  exit 1
}
grep -Fq "\"$compatible\"" "target/linux/mediatek/dts/$dts.dts"

./scripts/diffconfig.sh > "JuLiang-OS-${tag}-Live1.5-final.config"
