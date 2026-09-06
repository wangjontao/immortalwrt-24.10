#!/bin/sh
set -eu

DONE=/etc/add_ap20_wifi.done
[ -e "$DONE" ] && exit 0
PASSWORD="a1111111"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/ap20-wifi-backup-$STAMP"
mkdir -p "$BACKUP"
for cfg in network wireless dhcp firewall passwall passwall2; do
  [ -f "/etc/config/$cfg" ] && cp -p "/etc/config/$cfg" "$BACKUP/$cfg"
done
uci export > "$BACKUP/all-uci.txt"

# Detect radio names so this works with both mac80211 and MTK vendor wifi scripts.
RADIO_2G=""
RADIO_5G=""
for r in $(uci -q show wireless | sed -n "s/^wireless\.\([^=]*\)=wifi-device$/\1/p"); do
  band="$(uci -q get wireless.$r.band)"
  hwmode="$(uci -q get wireless.$r.hwmode)"
  case "$band:$hwmode" in
    2g:*|*:11g|*:11ng|*:11axg) RADIO_2G="$r" ;;
    5g:*|*:11a|*:11ac|*:11axa) RADIO_5G="$r" ;;
  esac
done
[ -n "$RADIO_2G" ] || RADIO_2G=radio0
[ -n "$RADIO_5G" ] || RADIO_5G=radio1
uci -q get wireless.$RADIO_2G >/dev/null || { logger -t ap20 "2.4G radio not found"; exit 1; }
uci -q get wireless.$RADIO_5G >/dev/null || { logger -t ap20 "5G radio not found"; exit 1; }

# Remove only a previous AP01-AP20 generated layout; keep the two default WiFi.
for i in $(seq 1 20); do
  n="$(printf '%02d' "$i")"
  uci -q delete network.apdev$n || true
  uci -q delete network.ap$n || true
  uci -q delete dhcp.ap$n || true
  uci -q delete wireless.ap$n || true
done
uci -q delete firewall.apwifi || true
uci -q delete firewall.apwifi_wan || true

# Networks and DHCP.
for i in $(seq 1 20); do
  n="$(printf '%02d' "$i")"
  net="ap$n"
  dev="apdev$n"
  br="br-ap$n"
  ip="172.16.$i.1"
  uci set network.$dev='device'
  uci set network.$dev.name="$br"
  uci set network.$dev.type='bridge'
  uci set network.$dev.bridge_empty='1'
  uci set network.$net='interface'
  uci set network.$net.device="$br"
  uci set network.$net.proto='static'
  uci set network.$net.ipaddr="$ip"
  uci set network.$net.netmask='255.255.255.0'
  uci set network.$net.delegate='0'
  uci set dhcp.$net='dhcp'
  uci set dhcp.$net.interface="$net"
  uci set dhcp.$net.start='100'
  uci set dhcp.$net.limit='150'
  uci set dhcp.$net.leasetime='12h'
  uci set dhcp.$net.ignore='0'
  uci set dhcp.$net.force='1'
  uci set dhcp.$net.dhcpv4='server'
  uci set dhcp.$net.dhcpv6='disabled'
  uci set dhcp.$net.ra='disabled'
  uci set dhcp.$net.ndp='disabled'
  uci add_list dhcp.$net.dhcp_option="3,$ip"
  uci add_list dhcp.$net.dhcp_option="6,$ip"
done

# AP1-AP14 on 5GHz, AP15-AP20 on 2.4GHz. Existing default WiFi is retained.
for i in $(seq 1 20); do
  n="$(printf '%02d' "$i")"
  [ "$i" -le 14 ] && radio="$RADIO_5G" || radio="$RADIO_2G"
  uci set wireless.ap$n='wifi-iface'
  uci set wireless.ap$n.device="$radio"
  uci set wireless.ap$n.network="ap$n"
  uci set wireless.ap$n.mode='ap'
  uci set wireless.ap$n.ssid="AP$i"
  uci set wireless.ap$n.encryption='psk2+ccmp'
  uci set wireless.ap$n.key="$PASSWORD"
  uci set wireless.ap$n.disabled='0'
  uci set wireless.ap$n.isolate='1'
done

# Dedicated AP zone and the forwarding requested by the supplied batch.
uci set firewall.apwifi='zone'
uci set firewall.apwifi.name='apwifi'
uci set firewall.apwifi.input='ACCEPT'
uci set firewall.apwifi.output='ACCEPT'
uci set firewall.apwifi.forward='REJECT'
for i in $(seq 1 20); do
  n="$(printf '%02d' "$i")"
  uci add_list firewall.apwifi.network="ap$n"
done
uci set firewall.apwifi_wan='forwarding'
uci set firewall.apwifi_wan.src='apwifi'
uci set firewall.apwifi_wan.dest='wan'

# Replace PassWall and PassWall2 with the user-supplied known-good ACL templates.
# The original files are backed up above; no ACL sections are generated here.
for cfg in passwall passwall2; do
  template="/root/ap20-wifi-config/$cfg"
  if [ -f "$template" ]; then
    cp -p "$template" "/etc/config/$cfg"
    logger -t ap20 "Installed supplied $cfg ACL template"
  fi
donefor cfg in wireless network dhcp firewall passwall passwall2; do uci -q commit "$cfg" || true; done

/etc/init.d/network restart
sleep 8
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
wifi reload
touch "$DONE"
echo "$BACKUP" > /root/ap20-wifi-last-backup
logger -t ap20 "AP01-AP20 first-boot setup completed"
