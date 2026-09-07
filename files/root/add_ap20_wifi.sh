#!/bin/sh

PASSWORD="a1111111"

echo "======================================"
echo " MT7986 新增20个WiFi"
echo " 5G  AP1-AP14"
echo " 2.4G AP15-AP20"
echo "======================================"

#################################################
# 1. 创建网络 + DHCP
#################################################

for I in $(seq 1 20)
do

    N=$(printf "%02d" "$I")

    NET="ap${N}"
    DEV="apdev${N}"
    BR="br-ap${N}"
    IP="172.16.${I}.1"

    echo "创建 AP${I}: ${IP}"

    # bridge
    uci set network.${DEV}='device'
    uci set network.${DEV}.name="${BR}"
    uci set network.${DEV}.type='bridge'
    uci set network.${DEV}.bridge_empty='1'

    # interface
    uci set network.${NET}='interface'
    uci set network.${NET}.device="${BR}"
    uci set network.${NET}.proto='static'
    uci set network.${NET}.ipaddr="${IP}"
    uci set network.${NET}.netmask='255.255.255.0'
    uci set network.${NET}.delegate='0'


    # DHCP

    uci set dhcp.${NET}='dhcp'
    uci set dhcp.${NET}.interface="${NET}"
    uci set dhcp.${NET}.start='100'
    uci set dhcp.${NET}.limit='150'
    uci set dhcp.${NET}.leasetime='12h'

    uci set dhcp.${NET}.ignore='0'
    uci set dhcp.${NET}.force='1'

    # IPv4 DHCP
    uci set dhcp.${NET}.dhcpv4='server'

    #关闭IPv6
    uci set dhcp.${NET}.ra='disabled'
    uci set dhcp.${NET}.dhcpv6='disabled'
    uci set dhcp.${NET}.ndp='disabled'


    uci add_list dhcp.${NET}.dhcp_option="3,${IP}"
    uci add_list dhcp.${NET}.dhcp_option="6,${IP}"

done


#################################################
# 2. 创建无线
#################################################


echo "创建5G AP1-AP14"


for I in $(seq 1 14)
do

    N=$(printf "%02d" "$I")

    echo "5G AP${I}"

    uci set wireless.ap${N}='wifi-iface'

    uci set wireless.ap${N}.device='radio1'

    uci set wireless.ap${N}.network="ap${N}"

    uci set wireless.ap${N}.mode='ap'

    uci set wireless.ap${N}.ssid="AP${I}"

    uci set wireless.ap${N}.encryption='psk2+ccmp'

    uci set wireless.ap${N}.key="${PASSWORD}"

    uci set wireless.ap${N}.disabled='0'

    uci set wireless.ap${N}.isolate='1'

done



echo "创建2.4G AP15-AP20"


for I in $(seq 15 20)
do

    N=$(printf "%02d" "$I")

    echo "2.4G AP${I}"

    uci set wireless.ap${N}='wifi-iface'

    uci set wireless.ap${N}.device='radio0'

    uci set wireless.ap${N}.network="ap${N}"

    uci set wireless.ap${N}.mode='ap'

    uci set wireless.ap${N}.ssid="AP${I}"

    uci set wireless.ap${N}.encryption='psk2+ccmp'

    uci set wireless.ap${N}.key="${PASSWORD}"

    uci set wireless.ap${N}.disabled='0'

    uci set wireless.ap${N}.isolate='1'

done



#################################################
# 3. 防火墙
#################################################


uci -q delete firewall.apwifi

uci set firewall.apwifi='zone'
uci set firewall.apwifi.name='apwifi'
uci set firewall.apwifi.input='ACCEPT'
uci set firewall.apwifi.output='ACCEPT'
uci set firewall.apwifi.forward='REJECT'


for I in $(seq 1 20)
do

    N=$(printf "%02d" "$I")

    uci add_list firewall.apwifi.network="ap${N}"

done


uci set firewall.apwifi_wan='forwarding'
uci set firewall.apwifi_wan.src='apwifi'
uci set firewall.apwifi_wan.dest='wan'


#################################################
# 保存
#################################################


uci commit wireless
uci commit network
uci commit dhcp
uci commit firewall


echo
echo "======================================"
echo "完成"
echo
echo "5GHz:"
echo "AP1-AP14"
echo
echo "2.4GHz:"
echo "AP15-AP20"
echo
echo "密码:"
echo "${PASSWORD}"
echo
echo "网段:"
echo "172.16.1.1 - 172.16.20.1"
echo
echo "重启网络..."
echo "======================================"


/etc/init.d/network restart
sleep 8

/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart

wifi reload


