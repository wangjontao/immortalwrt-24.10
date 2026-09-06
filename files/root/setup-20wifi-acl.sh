#!/bin/sh
set -eu
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/multiwifi-backup-$STAMP"
mkdir -p "$BACKUP"
for cfg in network wireless dhcp firewall passwall passwall2; do
  [ -f "/etc/config/$cfg" ] && cp -p "/etc/config/$cfg" "$BACKUP/$cfg"
done
uci export > "$BACKUP/all-uci.txt"
echo "$BACKUP" > /root/multiwifi-last-backup

for i in $(seq 1 20); do
  uci -q delete network.br_a$i || true
  uci -q delete network.a$i || true
  uci -q delete dhcp.a$i || true
  uci -q delete wireless.a$i || true
done
uci -q delete firewall.multiwifi || true

# PassWall startup scripts only detect anonymous @acl_rule sections.
# Remove sections created by an earlier run using our private marker.
for app in passwall passwall2; do
  while :; do
    sid="$(uci -q show "$app" | sed -n "s/^$app\.\([^.]\+\)\.multiwifi='1'$/\1/p" | head -n1)"
    [ -n "$sid" ] || break
    uci -q delete "$app.$sid"
  done
  for i in $(seq 1 20); do uci -q delete "$app.mw_a$i" || true; done
done

uci set firewall.multiwifi='zone'
uci set firewall.multiwifi.name='multiwifi'
uci set firewall.multiwifi.input='ACCEPT'
uci set firewall.multiwifi.output='ACCEPT'
uci set firewall.multiwifi.forward='REJECT'
uci -q delete firewall.multiwifi.network || true

for i in $(seq 1 20); do
  net="a$i"
  br="br-a$i"
  subnet="172.16.$i"
  if [ "$i" -le 15 ]; then radio='radio1'; else radio='radio0'; fi

  uci set network.br_a$i='device'
  uci set network.br_a$i.name="$br"
  uci set network.br_a$i.type='bridge'
  uci set network.br_a$i.bridge_empty='1'
  uci set network.a$i='interface'
  uci set network.a$i.device="$br"
  uci set network.a$i.proto='static'
  uci set network.a$i.ipaddr="$subnet.1"
  uci set network.a$i.netmask='255.255.255.0'
  uci set network.a$i.delegate='0'

  uci set dhcp.a$i='dhcp'
  uci set dhcp.a$i.interface="$net"
  uci set dhcp.a$i.start='100'
  uci set dhcp.a$i.limit='150'
  uci set dhcp.a$i.leasetime='12h'
  uci set dhcp.a$i.dhcpv4='server'
  uci set dhcp.a$i.dhcpv6='disabled'
  uci set dhcp.a$i.ra='disabled'

  uci set wireless.a$i='wifi-iface'
  uci set wireless.a$i.device="$radio"
  uci set wireless.a$i.network="$net"
  uci set wireless.a$i.mode='ap'
  uci set wireless.a$i.ssid="A$i"
  uci set wireless.a$i.encryption='psk2+ccmp'
  uci set wireless.a$i.key='a1111111'
  uci set wireless.a$i.isolate='1'
  uci set wireless.a$i.disabled='0'

  uci add_list firewall.multiwifi.network="$net"

  pw_sid="$(uci add passwall acl_rule)"
  uci set passwall.$pw_sid.enabled='1'
  uci set passwall.$pw_sid.remarks="A$i - $subnet.0/24"
  uci add_list passwall.$pw_sid.sources="$subnet.0/24"
  uci set passwall.$pw_sid.interface="$net"
  uci set passwall.$pw_sid.tcp_no_redir_ports='disable'
  uci set passwall.$pw_sid.udp_no_redir_ports='disable'
  uci set passwall.$pw_sid.use_global_config='1'
  uci set passwall.$pw_sid.multiwifi='1'

  pw2_sid="$(uci add passwall2 acl_rule)"
  uci set passwall2.$pw2_sid.enabled='1'
  uci set passwall2.$pw2_sid.remarks="A$i - $subnet.0/24"
  uci add_list passwall2.$pw2_sid.sources="$subnet.0/24"
  uci set passwall2.$pw2_sid.interface="$net"
  uci set passwall2.$pw2_sid.tcp_no_redir_ports='disable'
  uci set passwall2.$pw2_sid.udp_no_redir_ports='disable'
  uci set passwall2.$pw2_sid.node=''
  uci set passwall2.$pw2_sid.multiwifi='1'
done

uci set passwall.@global[0].acl_enable='0'
uci set passwall2.@global[0].acl_enable='0'
uci commit network
uci commit dhcp
uci commit wireless
uci commit firewall
uci commit passwall
uci commit passwall2

if uci -q show firewall | grep -q "src='multiwifi'"; then
  echo "Unexpected multiwifi forwarding exists" >&2
  exit 1
fi

/etc/init.d/network reload
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
wifi reload
echo "Created A1-A15 on radio1 (5G), A16-A20 on radio0 (2.4G)."
echo "Backup: $BACKUP"

