import json, unittest
from test_import import runtime, table, parser
from test_policy import from_lua
runtime.globals().pystringify=lambda value:json.dumps(from_lua(value),ensure_ascii=False,sort_keys=True)
runtime.execute("package.loaded['luci.jsonc'].stringify=pystringify; package.preload['nixio.fs']=function() return {} end; package.preload['luci.sys']=function() return {} end")
manager=runtime.eval("require('fastacl25_nodes')")
make=runtime.eval('''function()
 local db={}; local u={db=db}
 function u:get(c,id,key) local s=db[id]; return s and (key and s[key] or s['.type']) end
 function u:set(c,id,key,value) db[id][key]=value end
 function u:section(c,t,id,data) data['.name']=id; data['.type']=t; db[id]=data end
 function u:delete(c,id) db[id]=nil end
 function u:foreach(c,t,callback) local ids={}; for id,s in pairs(db) do if s['.type']==t then ids[#ids+1]=id end end; for _,id in ipairs(ids) do callback(db[id]) end end
 return u
end''')
def node(name,host='proxy.example'):
    return dict(name=name,protocol='socks',outbound=dict(type='socks',server=host,server_port=1080,version='5'))
class SubscriptionTests(unittest.TestCase):
    def test_renewed_endpoint_preserves_binding_id(self):
        u=make(); manager.replace(u,table([node('US')]),'airport1'); before=next(iter(u.db.keys()))
        manager.replace(u,table([node('US','new.example')]),'airport1'); self.assertEqual(list(u.db.keys()),[before]); self.assertIn('new.example',u.db[before]['outbound'])
    def test_removed_bound_node_retained(self):
        u=make(); manager.replace(u,table([node('US'),node('JP')]),'airport1')
        old=next(k for k in u.db.keys() if u.db[k]['name']=='US')
        u.section(u,'fastacl25','device','device1',table(dict(node=old)))
        manager.replace(u,table([node('JP')]),'airport1'); self.assertEqual(u.db[old]['retired'],'1'); self.assertEqual(u.db['device1']['node'],old)
    def test_removed_unbound_node_deleted(self):
        u=make(); manager.replace(u,table([node('US'),node('JP')]),'airport1'); manager.replace(u,table([node('JP')]),'airport1')
        self.assertEqual(len(list(u.db.keys())),1)
    def test_multiple_subscriptions_same_names_are_distinct(self):
        u=make(); manager.replace(u,table([node('US')]),'airport1'); manager.replace(u,table([node('US')]),'airport2'); self.assertEqual(len(list(u.db.keys())),2)
    def test_duplicate_names_not_overwritten(self):
        u=make(); manager.replace(u,table([node('US'),node('US','second.example')]),'airport1'); self.assertEqual(len(list(u.db.keys())),2)
    def test_bad_clash_does_not_silently_skip_nodes(self):
        with self.assertRaises(Exception):parser.subscription('proxies:\n- name: Old\n  type: socks5\n  server: proxy.example\n  port: 1080\n- name: Unknown\n  type: ssr\n  server: proxy.example\n  port: 443\n')
if __name__=='__main__':unittest.main(verbosity=2)
