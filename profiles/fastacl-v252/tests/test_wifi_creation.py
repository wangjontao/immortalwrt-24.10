#!/usr/bin/env python3
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class WifiCreationTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(f"package.path='{(ROOT / 'root/usr/lib/lua').as_posix()}/?.lua;'..package.path")
        lua.execute(r'''
package.preload['juliang_wifi_hardware']=function()
  return {preflight=function() return nil end}
end
package.preload['luci.sys']=function()
  return {exec=function() return '' end}
end
package.preload['fastacl252_dns']=function()
  return {
    valid_id=function() return true end,
    provider=function() return {} end,
    allowed=function() return true end,
    resolve=function(tmp) tmp.dns_type='doh' end
  }
end
package.preload['fastacl252']=function()
  return {
    ipnum=function(ip) if ip=='172.16.0.0' then return 2886860800 end end,
    prefix=function(mask) if mask=='255.255.255.0' then return 24 end end,
    section=function(u,cfg,kind,name,values)
      local row={['.name']=name,['.type']=kind}
      for k,v in pairs(values or {}) do row[k]=v end
      configs[cfg][name]=row
      return true
    end
  }
end
configs={fastacl252={},network={},wireless={},firewall={},dhcp={}}
configs.fastacl252.main={['.name']='main',['.type']='main',network='lan',max_wifi_5g='14',max_wifi_2g='8'}
configs.wireless.radio5={['.name']='radio5',['.type']='wifi-device',band='5g',hwmode='11a'}
configs.wireless.radio2={['.name']='radio2',['.type']='wifi-device',band='2g',hwmode='11g'}
configs.wireless.main={['.name']='main',['.type']='wifi-iface',mode='ap',ssid='Main'}
u={writes=0}
function u:get(cfg,id,key)
  local s=self.data and self.data[cfg][id] or configs[cfg][id]
  if not s then return nil end
  if key==nil then return s end
  return s[key]
end
function u:get_all(cfg,id) return (self.data and self.data[cfg][id]) or configs[cfg][id] end
function u:foreach(cfg,kind,fn)
  for _,s in pairs((self.data and self.data[cfg]) or configs[cfg]) do
    if not kind or s['.type']==kind then fn(s) end
  end
end
function u:set(cfg,id,key,value)
  local s=configs[cfg][id];if not s then return false end
  s[key]=value;self.writes=self.writes+1;return true
end
function u:delete(cfg,id,key) local s=configs[cfg][id];if s then s[key]=nil end end
M=require('fastacl252_wifi')
''')
        return lua

    def reset(self):
        lua = self.runtime()
        lua.execute(r'''
configs={fastacl252={},network={},wireless={},firewall={},dhcp={}}
configs.fastacl252.main={['.name']='main',['.type']='main',network='lan',max_wifi_5g='14',max_wifi_2g='8'}
configs.wireless.radio5={['.name']='radio5',['.type']='wifi-device',band='5g',hwmode='11a'}
configs.wireless.radio2={['.name']='radio2',['.type']='wifi-device',band='2g',hwmode='11g'}
configs.wireless.main={['.name']='main',['.type']='wifi-iface',mode='ap',ssid='Main'}
configs.wireless.legacy={['.name']='legacy',['.type']='wifi-iface',mode='ap',ssid='AP10'}
u.writes=0
''')
        return lua

    def test_batch_uses_start_number_and_unique_band_mapping(self):
        lua = self.runtime()
        lua.execute("M.create(u,{count5=3,count2=2,prefix='AP',start=10,key='12345678',node='',dns='inherit'})")

        rows = []
        for _, row in lua.eval("configs.wireless").items():
            if row['.type'] == 'wifi-iface' and row['.name'] != 'main':
                rows.append(row)
        rows.sort(key=lambda row: row['ssid'])

        self.assertEqual([row['ssid'] for row in rows], [f'AP{n}' for n in range(10, 15)])
        self.assertEqual([row['device'] for row in rows],
                         ['radio5', 'radio5', 'radio5', 'radio2', 'radio2'])
        for row in rows:
            self.assertNotIn('macaddr', row)
            self.assertNotIn('bssid', row)
            self.assertNotIn('MacAddress', row)

        networks = [row for name, row in lua.eval("configs.network").items()
                    if name.startswith('jfa25w') and row['.type'] == 'interface']
        self.assertEqual(len({row['ipaddr'] for row in networks}), 5)
        for name, row in lua.eval("configs.dhcp").items():
            if name.startswith('jfa25w') and row['.type'] == 'dhcp':
                ip = lua.eval(f"configs.network['{name}'].ipaddr")
                self.assertEqual(list(row['dhcp_option'].values()), [f'3,{ip} 6,{ip}'])

    def test_duplicate_or_too_long_essid_is_rejected_before_any_write(self):
        lua = self.reset()
        with self.assertRaises(Exception):
            lua.execute("M.create(u,{count5=2,count2=1,prefix='AP',start=10,key='12345678',node='',dns='inherit'})")
        self.assertEqual(lua.eval("u.writes"), 0)

        lua = self.reset()
        with self.assertRaises(Exception):
            lua.execute("M.create(u,{count5=1,count2=0,prefix='12345678901234567890123456789012',start=1,key='12345678',node='',dns='inherit'})")
        self.assertEqual(lua.eval("u.writes"), 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
