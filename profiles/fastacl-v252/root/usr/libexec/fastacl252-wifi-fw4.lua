local u=require('uci').cursor()
local wifi=require('fastacl252_wifi')
local changed=wifi.sync_firewall_devices(u)
changed=changed+wifi.sync_wifi_isolation(u)
if changed>0 then
 assert(u:commit('firewall'),'Cannot save managed WiFi firewall bridges')
 assert(u:commit('wireless'),'Cannot save managed WiFi client isolation')
 assert(os.execute('/etc/init.d/firewall reload >/tmp/fastacl252-wifi-fw4.log 2>&1')==0,'Cannot reload WiFi DHCP/DNS firewall rules')
end
print('Managed WiFi firewall and isolation settings updated: '..changed)
