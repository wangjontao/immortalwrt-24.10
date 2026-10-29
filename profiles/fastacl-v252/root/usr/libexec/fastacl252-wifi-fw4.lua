local u=require('uci').cursor()
local wifi=require('fastacl252_wifi')
local json=require('luci.jsonc')
local sys=require('luci.sys')
local changed=wifi.sync_firewall_devices(u)
local reload=changed>0
local status=json.parse(sys.exec('ubus call network.wireless status 2>/dev/null')) or {}
local runtime_seen,wireless_ok,wireless_issues={},true,{}
for _,radio in pairs(status) do
 for _,iface in ipairs(radio.interfaces or {}) do
  local section=tostring(iface.section or '')
  if section:match('^jfa25w%d+$') then
   runtime_seen[section]=true
   local expected=tostring(u:get('wireless',section,'network') or '')
   local actual=iface.config and iface.config.network or ''
   if type(actual)=='table' then actual=actual[1] end
   if expected=='' or expected~=tostring(actual or '') then wireless_ok=false;wireless_issues[#wireless_issues+1]=section..':network' end
   local device=tostring(iface.ifname or '')
   local bridge=tostring(u:get('network',expected,'device') or '')
   if device~='' and bridge~='' then
    local master=sys.exec('readlink /sys/class/net/'..device..'/master 2>/dev/null'):match('([^/%s]+)%s*$')
    if master~=bridge then wireless_ok=false;wireless_issues[#wireless_issues+1]=section..':bridge' end
   end
  end
 end
end
u:foreach('fastacl252','wifi',function(s)
 if s.jfa25_owner==wifi.owner and s['.name']:match('^jfa25w%d+$') and not runtime_seen[s['.name']] then wireless_ok=false;wireless_issues[#wireless_issues+1]=s['.name']..':missing' end
end)
if next(runtime_seen) and not wireless_ok then
 assert(sys.call('wifi reconf >/tmp/fastacl252-wifi-reconf.log 2>&1')==0,'Cannot reconcile managed WiFi network mapping')
 reload=true
end
if not reload then
 local pipe=io.popen('nft list ruleset 2>/dev/null')
 local rules=pipe and pipe:read('*a') or ''
 if pipe then pipe:close() end
 u:foreach('fastacl252','wifi',function(s)
  if s.jfa25_owner==wifi.owner and tostring(s.network or ''):match('^jfa25w%d+$') then
   local id=s.network
   for _,prefix in ipairs({'input_','output_','forward_'}) do
    if not rules:find('jump '..prefix..id,1,true) then wireless_issues[#wireless_issues+1]=id..':'..prefix;reload=true end
   end
  end
 end)
end
if changed>0 then
 assert(u:commit('firewall'),'Cannot save managed WiFi firewall bridges')
end
if reload then
 assert(os.execute('/etc/init.d/firewall reload >/tmp/fastacl252-wifi-fw4.log 2>&1')==0,'Cannot reload WiFi DHCP/DNS firewall rules')
end
print('Managed WiFi firewall and isolation settings updated: '..changed..(reload and ', runtime rules reloaded' or '')..(#wireless_issues>0 and ' ['..table.concat(wireless_issues,',')..']' or ''))
