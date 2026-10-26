local u=require('uci').cursor()
local changed=require('fastacl252_wifi').sync_firewall_devices(u)
local managed=0
u:foreach('fastacl252','wifi',function() managed=managed+1 end)
if changed>0 then
 assert(u:commit('firewall'),'Cannot save managed WiFi firewall bridges')
end
if changed>0 or managed>0 then
 assert(os.execute('/etc/init.d/firewall reload >/tmp/fastacl252-wifi-fw4.log 2>&1')==0,'Cannot reload WiFi DHCP/DNS firewall rules')
end
print('Managed WiFi firewall bridge bindings updated: '..changed..', runtime reloaded: '..(managed>0 and 'yes' or 'no'))
