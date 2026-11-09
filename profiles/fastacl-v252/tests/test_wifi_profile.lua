local M=require('fastacl252_wifi')
local u={data={wireless={
 main={['.name']='main',['.type']='wifi-iface',mode='ap',ssid='Main',key='12345678',encryption='psk2+ccmp',hidden='0'},
 guest={['.name']='guest',['.type']='wifi-iface',mode='ap',ssid='Guest',key='abcdefgh',encryption='psk2+ccmp',hidden='0'}
}},writes=0}
function u:get_all(cfg,id)return self.data[cfg] and self.data[cfg][id] end
function u:foreach(cfg,kind,fn)for _,s in pairs(self.data[cfg] or {})do if not kind or s['.type']==kind then fn(s) end end end
function u:set(cfg,id,key,value)local s=self.data[cfg] and self.data[cfg][id];if not s then return false end;s[key]=value;self.writes=self.writes+1;return true end

local result=M.update_profile(u,{id='guest',ssid='Guest WiFi',key='newpass123',hidden=true})
assert(result.password_changed==true)
assert(u.data.wireless.guest.ssid=='Guest WiFi')
assert(u.data.wireless.guest.key=='newpass123')
assert(u.data.wireless.guest.hidden=='1')

result=M.update_profile(u,{id='guest',ssid='Guest WiFi',key='',hidden=false})
assert(result.password_changed==false)
assert(u.data.wireless.guest.key=='newpass123')
assert(u.data.wireless.guest.hidden=='0')

local writes=u.writes
assert(not pcall(M.update_profile,u,{id='guest',ssid='Main',key='',hidden=false}))
assert(u.writes==writes,'duplicate SSID partially wrote configuration')
print('PASS WiFi name, password and hidden state update')
