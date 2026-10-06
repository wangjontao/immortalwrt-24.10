#!/bin/sh
set -eu
uci set 'firewall.fastacl25_input=rule'
uci set 'firewall.fastacl25_input.name=FastACL25 TProxy input'
uci set 'firewall.fastacl25_input.src=*'
uci set 'firewall.fastacl25_input.family=ipv4'
uci set 'firewall.fastacl25_input.proto=all'
uci set 'firewall.fastacl25_input.mark=0x65/0xff'
uci set 'firewall.fastacl25_input.target=ACCEPT'
uci set 'firewall.@defaults[0].flow_offloading=0'
uci set 'firewall.@defaults[0].flow_offloading_hw=0'
uci commit firewall; /etc/init.d/firewall reload
# This release assigns IPv4 devices. Do not advertise an IPv6 DNS path to phones.
uci set 'dhcp.lan.ra=disabled'
uci set 'dhcp.lan.dhcpv6=disabled'
uci set 'dhcp.lan.ndp=disabled'
uci commit dhcp; /etc/init.d/dnsmasq reload
uci set 'fastacl25.main.enabled=1'; uci commit fastacl25
