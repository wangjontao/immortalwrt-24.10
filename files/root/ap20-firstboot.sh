#!/bin/sh
set -eu
DONE=/etc/ap20-supplied-config-v2.done
STATE=/root/ap20-firstboot-backup-v2
[ -e "$DONE" ] && exit 0
mkdir /tmp/ap20-firstboot.lock 2>/dev/null || exit 0
trap 'rmdir /tmp/ap20-firstboot.lock' EXIT
exec >>/root/ap20-firstboot.log 2>&1
echo "Waiting 60 seconds after rc.local: $(date)"
sleep 60
mkdir -p "$STATE"
for cfg in network wireless dhcp firewall passwall passwall2; do
    if [ -f "/etc/config/$cfg" ] && [ ! -e "$STATE/$cfg" ]; then
        cp -p "/etc/config/$cfg" "$STATE/$cfg"
    fi
done
if [ ! -e "$STATE/wifi.done" ]; then
    /bin/sh /root/add_ap20_wifi.sh
    touch "$STATE/wifi.done"
fi
echo "WiFi script finished; waiting 20 seconds: $(date)"
sleep 20
for cfg in passwall passwall2; do
    test -s "/root/ap20-wifi-config/$cfg"
done
for cfg in passwall passwall2; do
    [ ! -x "/etc/init.d/$cfg" ] || "/etc/init.d/$cfg" stop || true
    cp "/root/ap20-wifi-config/$cfg" "/etc/config/.$cfg.ap20-new"
    chmod 600 "/etc/config/.$cfg.ap20-new"
    mv -f "/etc/config/.$cfg.ap20-new" "/etc/config/$cfg"
    cmp -s "/root/ap20-wifi-config/$cfg" "/etc/config/$cfg"
done
touch "$DONE"
echo "Supplied configs copied unchanged; complete: $(date)"
for cfg in passwall passwall2; do
    [ ! -x "/etc/init.d/$cfg" ] || "/etc/init.d/$cfg" start || true
done