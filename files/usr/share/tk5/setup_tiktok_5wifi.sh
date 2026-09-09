#!/bin/sh
set -eu
RADIO=''
for r in $(uci show wireless | sed -n 's/^wireless\.\([^=]*\)=wifi-device$/\1/p'); do
    [ "$(uci -q get wireless.$r.band || true)" = 5g ] && RADIO="$r"
done
[ -n "$RADIO" ] || { echo '5GHz radio not found'; exit 1; }
BACKUP="/root/tk5-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in wireless network dhcp firewall; do cp -p /etc/config/$f "$BACKUP/$f"; done
echo "Backup: $BACKUP"
for i in 1 2 3 4 5; do
    n="tk$i"
    uci set network.${n}_dev=device
    uci set network.${n}_dev.name="br-$n"
    uci set network.${n}_dev.type=bridge
    uci set network.${n}_dev.bridge_empty=1
    uci set network.${n}_dev.ipv6=0
    uci set network.$n=interface
    uci set network.$n.device="br-$n"
    uci set network.$n.proto=static
    uci set network.$n.ipaddr="172.16.$i.1"
    uci set network.$n.netmask=255.255.255.0
    uci set network.$n.delegate=0
    uci set dhcp.$n=dhcp
    uci set dhcp.$n.interface="$n"
    uci set dhcp.$n.start=100
    uci set dhcp.$n.limit=100
    uci set dhcp.$n.leasetime=12h
    uci set dhcp.$n.ra=disabled
    uci set dhcp.$n.dhcpv6=disabled
    uci set dhcp.$n.ndp=disabled
    uci set wireless.$n=wifi-iface
    uci set wireless.$n.device="$RADIO"
    uci set wireless.$n.network="$n"
    uci set wireless.$n.mode=ap
    uci set wireless.$n.ssid="A$i"
    uci set wireless.$n.encryption=psk2+ccmp
    uci set wireless.$n.key=a1111111
    uci set wireless.$n.isolate=1
    uci set wireless.$n.disabled=0
    uci set firewall.$n=zone
    uci set firewall.$n.name="$n"
    uci -q delete firewall.$n.network || true
    uci add_list firewall.$n.network="$n"
    uci set firewall.$n.input=ACCEPT
    uci set firewall.$n.output=ACCEPT
    uci set firewall.$n.forward=REJECT
    uci set firewall.${n}_dhcp=rule
    uci set firewall.${n}_dhcp.name="TK$i DHCP"
    uci set firewall.${n}_dhcp.src="$n"
    uci set firewall.${n}_dhcp.proto=udp
    uci set firewall.${n}_dhcp.dest_port=67
    uci set firewall.${n}_dhcp.family=ipv4
    uci set firewall.${n}_dhcp.target=ACCEPT
done
uci set firewall.@defaults[0].flow_offloading=0
uci set firewall.@defaults[0].flow_offloading_hw=0
for f in network wireless dhcp firewall; do uci commit "$f"; done
if ! fw4 check; then
    for f in network wireless dhcp firewall; do cp -p "$BACKUP/$f" /etc/config/$f; done
    echo 'Firewall validation failed; configurations restored'; exit 1
fi
/etc/init.d/firewall reload
/etc/init.d/network reload
sleep 5
/etc/init.d/dnsmasq restart
wifi reload
echo 'A1-A5 configured. No inter-zone forwarding. Proxy and proxy DNS configuration required.'
