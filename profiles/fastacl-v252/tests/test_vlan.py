#!/usr/bin/env python3
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class VlanTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(
            f"package.path='{(ROOT / 'root/usr/lib/lua').as_posix()}/?.lua;'..package.path"
        )
        lua.execute(
            r'''
configs={network={},dhcp={},firewall={},fastacl252={}}
configs.fastacl252.main={['.name']='main',['.type']='main',vlan_mode='1',vlan_trunk=''}
configs.network.lan={['.name']='lan',['.type']='interface',device='eth1',proto='static',ipaddr='192.168.7.1',netmask='255.255.255.0'}
configs.network.wan={['.name']='wan',['.type']='interface',device='eth0',proto='dhcp'}
writes=0
u={}
function u:get(cfg,id,key)
  local section=configs[cfg][id]
  if not section then return nil end
  if key==nil then return section['.type'] end
  return section[key]
end
function u:get_all(cfg,id) return configs[cfg][id] end
function u:foreach(cfg,kind,fn)
  for _,section in pairs(configs[cfg]) do
    if not kind or section['.type']==kind then fn(section) end
  end
end
function u:set(cfg,id,key,value)
  local section=configs[cfg][id]
  if not section then
    if key==nil then return false end
    section={['.name']=id,['.type']=key}
    configs[cfg][id]=section
  end
  if value~=nil then section[key]=value end
  writes=writes+1
  return true
end
function u:delete(cfg,id,key)
  if key==nil then configs[cfg][id]=nil else
    local section=configs[cfg][id]
    if section then section[key]=nil end
  end
end
function u:add(cfg,kind)
  local id=(kind or 'section')..tostring(writes+1)
  configs[cfg][id]={['.name']=id,['.type']=kind}
  writes=writes+1
  return id
end
package.preload['luci.sys']=function()
  return {
    exec=function(command)
      if command:find('ls -1 /sys/class/net',1,true) then return 'eth0\neth1\n' end
      if command:find('route show default',1,true) then return 'eth0\n' end
      return ''
    end
  }
end
package.preload['fastacl252_dns']=function()
  return {
    valid_id=function(id) return id~=nil and id~='' end,
    provider=function() return {} end,
    allowed=function() return true end,
    resolve=function(tmp) tmp.dns_type='doh' end
  }
end
package.preload['fastacl252']=function()
  local M={}
  function M.ipnum(value)
    local a,b,c,d=tostring(value or ''):match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
    if not a or a>255 or b>255 or c>255 or d>255 then return nil end
    return ((a*256+b)*256+c)*256+d
  end
  function M.prefix(mask)
    local p=tonumber(mask)
    if p then return p end
    local n=M.ipnum(mask)
    if n==4294967040 then return 24 end
    if n==4294967295 then return 32 end
    return nil
  end
  function M.cidr(ip,prefix)
    local n=M.ipnum(ip)
    local size=2^(32-prefix)
    n=math.floor(n/size)*size
    return string.format('%d.%d.%d.%d/%d',math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256,prefix)
  end
  function M.dev(value) return type(value)=='string' and value:match('^[%w_.:-]+$')~=nil and #value<=32 end
  function M.id(value) return type(value)=='string' and value:match('^[%w_]+$')~=nil and #value<=64 end
  function M.section(cursor,cfg,kind,name,values)
    if not M.id(name) or not cursor:set(cfg,name,kind) then return false end
    for key,value in pairs(values or {}) do if not cursor:set(cfg,name,key,value) then return false end end
    return true
  end
  return M
end
manager=require('fastacl252_vlan')
'''
        )
        return lua

    def test_batch_plan_and_create(self):
        lua = self.runtime()
        result = lua.eval(
            "manager.plan(u,{count=3,start_vlan=10,start_subnet=20,ssid_prefix='AP'})"
        )
        self.assertEqual(result["trunk"], "eth1")
        self.assertEqual([row["vlan"] for row in result["rows"].values()], [10, 11, 12])
        self.assertEqual(result["rows"][1]["subnet"], "192.168.20.0/24")
        self.assertEqual(result["rows"][3]["interface"], "eth1.12")

        lua.execute(
            "manager.create_batch(u,{count=2,start_vlan=10,start_subnet=20,ssid_prefix='AP',dns='inherit'})"
        )
        self.assertEqual(lua.eval("configs.network.jfa25v10_dev.type"), "8021q")
        self.assertEqual(lua.eval("configs.network.jfa25v10_dev.ifname"), "eth1")
        self.assertEqual(lua.eval("configs.network.jfa25v10_dev.vid"), "10")
        self.assertEqual(lua.eval("configs.network.jfa25v10.ipaddr"), "192.168.20.1")
        self.assertEqual(lua.eval("configs.dhcp.jfa25v10.interface"), "jfa25v10")
        self.assertEqual(lua.eval("configs.firewall.jfa25v10.masq"), "1")
        self.assertEqual(lua.eval("configs.fastacl252.jfa25v10.ssid"), "AP-10")
        self.assertEqual(lua.eval("configs.fastacl252.main.vlan_trunk"), "eth1")

    def test_rejects_overlap_duplicate_and_missing_mode(self):
        lua = self.runtime()
        lua.execute("configs.fastacl252.jfa25v10={['.name']='jfa25v10',['.type']='vlan',owner='fastacl252-vlan'}")
        with self.assertRaises(Exception):
            lua.execute(
                "manager.plan(u,{count=1,start_vlan=10,start_subnet=20,ssid_prefix='AP'})"
            )
        lua = self.runtime()
        with self.assertRaises(Exception):
            lua.execute(
                "manager.plan(u,{count=1,start_vlan=20,start_subnet=7,ssid_prefix='AP'})"
            )
        lua = self.runtime()
        lua.execute("configs.fastacl252.main.vlan_mode='0'")
        with self.assertRaises(Exception):
            lua.execute(
                "manager.plan(u,{count=1,start_vlan=20,start_subnet=20,ssid_prefix='AP'})"
            )

    def test_remove_cleans_all_vlan_sections(self):
        lua = self.runtime()
        lua.execute(
            "manager.create_batch(u,{count=1,start_vlan=10,start_subnet=20,ssid_prefix='AP',dns='inherit'})"
        )
        removed = lua.eval("manager.remove_many(u,{'jfa25v10'})")
        self.assertEqual(list(removed.values()), ["jfa25v10"])
        for config in ("network", "dhcp", "firewall", "fastacl252"):
            self.assertIsNone(lua.eval(f"configs.{config}.jfa25v10"))
        for suffix in ("_dev", "_dhcp", "_dns", "_tproxy", "_wan"):
            self.assertIsNone(lua.eval(f"configs.network.jfa25v10{suffix}"))
            self.assertIsNone(lua.eval(f"configs.firewall.jfa25v10{suffix}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
