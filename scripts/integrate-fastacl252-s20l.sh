#!/bin/sh
set -eu
device=${1:-clx_s20l}
dts_identity=
case "$device" in
  clx_s20l) tag=S20L; dts=mt7986a-clx-s20l; compatible=clx,s20l ;;
  clx_s20p) tag=S20P; dts=mt7986a-clx-s20p; compatible=clx,s20p ;;
  jdcloud_re-cp-03) tag=JDCloud-RE-CP-03; dts=mt7986a-jdcloud-re-cp-03; compatible=jdcloud,re-cp-03 ;;
  glinet_gl-mt6000) tag=GL-iNet-GL-MT6000; dts=mt7986a-glinet-gl-mt6000; compatible=glinet,gl-mt6000 ;;
  netcore_n60-pro) tag=Netcore-N60-Pro; dts=mt7986a-netcore-n60-pro; compatible=netcore,n60-pro ;;
  xiaomi_redmi-router-ax6000) tag=Redmi-AX6000-NMBM110M; dts=mt7986a-xiaomi-redmi-router-ax6000; compatible=xiaomi,redmi-router-ax6000 ;;
  xiaomi_redmi-router-ax6000-ubootmod) tag=Redmi-AX6000-ubootmod; dts=mt7986a-xiaomi-redmi-router-ax6000-ubootmod; compatible=xiaomi,redmi-router-ax6000-ubootmod ;;
  philips_hy3000) tag=PHILIPS-HY3000; dts=mt7981b-philips-hy3000; compatible=philips,hy3000 ;;
  cmcc_rax3000m) tag=RAX3000M-NAND; dts=mt7981b-cmcc-rax3000m; compatible=cmcc,rax3000m ;;
  cmcc_rax3000m-emmc) tag=RAX3000M-EMMC; dts=mt7981b-cmcc-rax3000m-emmc; compatible=cmcc,rax3000m-emmc ;;
  qihoo_360t7) tag=QIHOO-360T7; dts=mt7981b-qihoo-360t7; compatible=qihoo,360t7 ;;
  aigo_ags21) tag=AIGO-AGS21; dts=mt7981b-aigo-ags21; compatible=aigo,ags21 ;;
  cmcc_a10-ubootmod) tag=CMCC-A10-Ubootmod; dts=mt7981b-cmcc-a10-ubootmod; compatible=cmcc,a10-ubootmod ;;
  konka_komi-a31) tag=KONKA-KOMI-A31; dts=mt7981b-konka-komi-a31; compatible=konka,komi-a31 ;;
  newland_nl-wr8103) tag=NEWLAND-NL-WR8103; dts=mt7981b-newland-nl-wr8103; compatible=newland,nl-wr8103 ;;
  newland_nl-wr9103) tag=NEWLAND-NL-WR9103; dts=mt7981b-newland-nl-wr9103; compatible=newland,nl-wr9103 ;;
  abt_asr3000) tag=ABT-ASR3000; dts=mt7981b-abt-asr3000; compatible=abt,asr3000 ;;
  jcg_q30-pro) tag=JCG-Q30-PRO; dts=mt7981b-jcg-q30-pro; compatible=jcg,q30-pro ;;
  xiaomi_mi-router-ax3000t) tag=Xiaomi-AX3000T; dts=mt7981b-xiaomi-mi-router-ax3000t; compatible=xiaomi,mi-router-ax3000t ;;
  xiaomi_mi-router-ax3000t-mtkuboot) tag=Xiaomi-AX3000T-MTK-UBoot; dts=mt7981b-xiaomi-mi-router-ax3000t-mtkuboot; compatible=xiaomi,mi-router-ax3000t-mtkuboot ;;
  xiaomi_mi-router-ax3000t-ubootmod) tag=Xiaomi-AX3000T-ubootmod; dts=mt7981b-xiaomi-mi-router-ax3000t-ubootmod; compatible=xiaomi,mi-router-ax3000t-ubootmod ;;
  xiaomi_mi-router-wr30u-stock) tag=Xiaomi-WR30U-Stock; dts=mt7981b-xiaomi-mi-router-wr30u-stock; compatible=xiaomi,mi-router-wr30u-stock ;;
  xiaomi_mi-router-wr30u-ubootmod) tag=Xiaomi-WR30U-ubootmod; dts=mt7981b-xiaomi-mi-router-wr30u-ubootmod; compatible=xiaomi,mi-router-wr30u-ubootmod ;;
  nokia_ea0326gmp) tag=NOKIA-EA0326GMP; dts=mt7981b-nokia-ea0326gmp; compatible=nokia,ea0326gmp ;;
  sl_3000-emmc) tag=SL-3000-EMMC; dts=mt7981b-sl-3000-emmc; compatible=sl,3000-emmc ;;
  zbtlink_zbt-z8103ax-c) tag=ZBT-Z8103AX-C; dts=mt7981b-zbtlink-zbt-z8103ax-c; compatible=zbtlink,zbt-z8103ax-c ;;
  clt_r30b1) tag=CLT-R30B1; dts=mt7981b-clt-r30b1; compatible=clt,r30b1; dts_identity=mt7981b-clt-r30b1-base.dtsi ;;
  cmcc_a10-stock) tag=CMCC-A10-Stock; dts=mt7981b-cmcc-a10-stock; compatible=cmcc,a10-stock ;;
  livinet_zr-3020) tag=Livinet-ZR-3020; dts=mt7981b-livinet-zr-3020; compatible=livinet,zr-3020 ;;
  cetron_ct3003-ubootmod) tag=Cetron-CT3003-Ubootmod; dts=mt7981b-cetron-ct3003-ubootmod; compatible=cetron,ct3003-ubootmod ;;
  cmcc_rax3000me) tag=CMCC-RAX3000Me; dts=mt7981b-cmcc-rax3000me; compatible=cmcc,rax3000me ;;
  asus_rt-ax52) tag=ASUS-RT-AX52; dts=mt7981b-asus-rt-ax52; compatible=asus,rt-ax52 ;;
  glinet_gl-mt3000) tag=GL-iNet-GL-MT3000; dts=mt7981b-glinet-gl-mt3000; compatible=glinet,gl-mt3000 ;;
  huasifei_wh3000-emmc) tag=Huasifei-WH3000-eMMC; dts=mt7981b-huasifei-wh3000-emmc; compatible=huasifei,wh3000-emmc ;;
  huasifei_wh3000-pro) tag=Huasifei-WH3000-Pro; dts=mt7981b-huasifei-wh3000-pro; compatible=huasifei,wh3000-pro ;;
  umi_uax3000e) tag=UMI-UAX3000E; dts=mt7981b-umi-uax3000e; compatible=umi,uax3000e ;;
  zbtlink_zbt-z8102ax) tag=ZBT-Z8102AX; dts=mt7981b-zbtlink-zbt-z8102ax; compatible=zbtlink,zbt-z8102ax ;;
  zbtlink_zbt-z8103ax) tag=ZBT-Z8103AX; dts=mt7981b-zbtlink-zbt-z8103ax; compatible=zbtlink,zbt-z8103ax ;;
  cudy_tr3000-v1) tag=Cudy-TR3000; dts=mt7981b-cudy-tr3000-v1; compatible=cudy,tr3000-v1 ;;
  cudy_tr3000-v1-256mb) tag=Cudy-TR3000-256MB; dts=mt7981b-cudy-tr3000-v1-256mb; compatible=cudy,tr3000-v1-256mb ;;
  cudy_tr3000-v1-ubootmod) tag=Cudy-TR3000-Ubootmod; dts=mt7981b-cudy-tr3000-v1-ubootmod; compatible=cudy,tr3000-v1-ubootmod ;;
  *) echo "Unsupported FastACL device: $device" >&2; exit 1 ;;
esac
if [ -z "$dts_identity" ]; then
  dts_identity=${dts}.dts
fi
test -f "target/linux/mediatek/dts/$dts.dts"
mkdir -p package/fastacl252 package/juliangtk-sing-box
cp profiles/fastacl-v252/package-Makefile package/fastacl252/Makefile
cp profiles/fastacl-v252/singbox-Makefile package/juliangtk-sing-box/Makefile
cp -a profiles/fastacl-v252/root package/fastacl252/files
(cd profiles/fastacl-v252/dns && go mod tidy && go mod vendor && python3 ../patch_outbound.py . && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -mod=vendor -trimpath -ldflags="-s -w" -o ../../../package/fastacl252/files/usr/bin/fastacl252-dns .)

rm -f files/root/setup-20wifi-acl.sh files/root/add_ap20_wifi.sh
rm -f files/root/ap20-wifi-config/passwall files/root/ap20-wifi-config/passwall2
rm -f files/etc/init.d/setup-20wifi-firstboot files/etc/uci-defaults/99-enable-20wifi-firstboot
rm -f package/base-files/files/etc/uci-defaults/99-dulwifi
for root in files package/base-files/files; do
  [ -d "$root" ] || continue
  find "$root" -type f \( -iname '*passwall*' -o -iname '*homeproxy*' -o -iname '*openclash*' -o -iname '*20wifi*' -o -iname '*juliang-fastacl*' \) -delete
done

# NPS uses a domain in Lite. Keep the feed defaults and LuCI validator aligned
# so nps.jontao.top can be displayed, edited and saved without an IP-only error.
for p in $(find feeds/luci package/feeds/luci -path '*/luci-app-nps/root/etc/config/nps' -type f 2>/dev/null); do
  sed -i 's/47\.83\.9\.208/nps.jontao.top/g' "$p"
done
for p in $(find feeds/luci package/feeds/luci -path '*/luci-app-nps/*' -type f -name '*.lua' 2>/dev/null); do
  sed -i -e 's/server\.datatype[[:space:]]*=[[:space:]]*"ipaddr"/server.datatype = "host"/g' \
         -e "s/server\.datatype[[:space:]]*=[[:space:]]*'ipaddr'/server.datatype = 'host'/g" "$p"
done
if [ -f package/base-files/files/usr/libexec/nps-wan-mac ]; then
  sed -i 's/47\.83\.9\.208/nps.jontao.top/g' package/base-files/files/usr/libexec/nps-wan-mac
fi

sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/192.168.7.1/g" package/base-files/files/bin/config_generate
sed -i "s/hostname='.*'/hostname='JuLiangTK-${tag}'/g" package/base-files/files/bin/config_generate
ROOT_HASH=$(openssl passwd -1 '@password@')
sed -i "s#^root:[^:]*:#root:${ROOT_HASH}:#" package/base-files/files/etc/shadow
find package/fastacl252/files/etc/init.d package/fastacl252/files/etc/hotplug.d package/fastacl252/files/etc/uci-defaults -type f -exec chmod 755 {} \;
chmod 755 package/fastacl252/files/usr/bin/fastacl252 package/fastacl252/files/usr/libexec/fastacl252-enable.sh
chmod 600 package/fastacl252/files/etc/config/fastacl252

grep -q "fastacl252.main.version=2.8.1" package/fastacl252/files/etc/uci-defaults/99-juliangtk-fastacl252
grep -q "PKG_VERSION:=2.8.1" package/fastacl252/Makefile
grep -q "rpcd.juliang_operator.username='admin'" package/fastacl252/files/etc/uci-defaults/96-juliang-center
grep -q "rpcd.juliang_operator.read='juliang-bbr'" package/fastacl252/files/etc/uci-defaults/96-juliang-center
grep -q "rpcd.juliang_operator.write='juliang-bbr'" package/fastacl252/files/etc/uci-defaults/96-juliang-center
grep -Fq "ADMIN_HASH='\$1\$" package/fastacl252/files/etc/uci-defaults/96-juliang-center

config="build-configs/JuLiangTK-${tag}-FastACL281.txt"
if [ -f "$config" ]; then
  cp "$config" .config
else
  sed "s/^CONFIG_TARGET_mediatek_filogic_DEVICE_.*=y$/CONFIG_TARGET_mediatek_filogic_DEVICE_${device}=y/" \
    build-configs/JuLiangTK-S20L-FastACL281.txt > .config
fi
make defconfig
sed -i "s/JuLiangTK-S20L/JuLiangTK-${tag}/g" package/fastacl252/files/etc/uci-defaults/99-juliangtk-fastacl252
sh scripts/integrate-fastacl252-dependencies.sh
for pkg in luci-theme-argon luci-app-argon-config luci-app-ttyd luci-app-autoreboot nps npc luci-app-nps lyaml fastacl252 juliangtk-sing-box kmod-tun firewall4; do
  grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || { echo "Required package missing: $pkg"; exit 1; }
done
if grep -E '^CONFIG_PACKAGE_(luci-app-store|luci-app-quickstart|quickstart|taskd)=y$' .config; then echo 'iStore/QuickStart must not be selected in Lite'; exit 1; fi
if grep -E '^CONFIG_PACKAGE_(luci-app-(passwall2?|homeproxy|openclash)|luci-i18n-(passwall2?|homeproxy|openclash)-[^=]+)=(y|m)$' .config; then echo 'Forbidden proxy plugin selected'; exit 1; fi
grep -q "^CONFIG_TARGET_mediatek_filogic_DEVICE_${device}=y" .config || {
  echo "Required target missing from .config: $device" >&2
  exit 1
}
grep -Fq "\"$compatible\"" "target/linux/mediatek/dts/$dts_identity" || {
  echo "Required compatible missing from DTS: $compatible" >&2
  exit 1
}
./scripts/diffconfig.sh > "JuLiang-OS-${tag}-final.config"

# Use the network-service brand without changing hardware identity.
find feeds package -type f \( -name header.ut -o -name header_login.ut -o -name header.htm \) -path '*argon*' 2>/dev/null | while IFS= read -r view; do
  sed -i -e 's/>{{ hostname }}<\/a>/>JuLiang 网络服务<\/a>/g' \
    -e 's/><%=hostname%><\/a>/>JuLiang 网络服务<\/a>/g' "$view"
done

# V2.6.2: use Factory radio identity in MTWiFi configuration generation.
python3 scripts/patch-fastacl260-mtwifi.py
