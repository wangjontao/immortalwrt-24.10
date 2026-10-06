"""Offline regressions for the real Lua policy compiler; never contacts a router."""
import argparse, copy, json, pathlib, re, subprocess, tempfile, unittest
from lupa.lua51 import LuaRuntime

ROOT=pathlib.Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path="+json.dumps(str(ROOT/'root/usr/lib/lua/?.lua').replace('\\','/'))+"..';'..package.path")
policy=lua.eval("require('fastacl25')")

def to_lua(value):
    if isinstance(value,dict): return lua.table_from({k:to_lua(v) for k,v in value.items()})
    if isinstance(value,list): return lua.table_from([to_lua(v) for v in value])
    return value
def from_lua(value):
    if hasattr(value,'keys'):
        keys=list(value.keys())
        if keys and all(isinstance(k,int) for k in keys): return [from_lua(value[i]) for i in range(1,len(keys)+1)]
        return {k:from_lua(value[k]) for k in keys}
    return value

def config():
    return dict(network='lan',interface='br-lan',router_ip='192.168.7.1',netmask='255.255.255.0',port=12525,default_mode='direct',dns_policy='direct',dns_server='223.5.5.5',dns_name='dns.alidns.com',private_dns_server='9.9.9.9',private_dns_name='dns.quad9.net',nodes={
        'us':dict(protocol='socks',address='proxy.example.com',port='1080',username='a',password='secret'),
        'jp':dict(protocol='http',address='203.0.113.8',port='8080'),
        'front':dict(protocol='vless',outbound=dict(type='vless',server='203.0.113.9',server_port=443,uuid='00000000-0000-0000-0000-000000000001')),
        'front2':dict(protocol='vmess',address='203.0.113.10',port='443'),
    },devices=[
        dict(mac='02:00:00:00:00:01',ip='192.168.7.101',mode='proxy',node='us'),
        dict(mac='02:00:00:00:00:02',ip='192.168.7.102',mode='proxy',node='jp'),
        dict(mac='02:00:00:00:00:03',ip='192.168.7.103',mode='direct'),
    ])
def compile(c):
    conf,bridges=policy.compile(to_lua(c))
    conf=from_lua(conf); bridges=from_lua(bridges)
    # Lua empty tables are represented as {}, normalize schema array fields.
    for path in [('dns','rules')]:
        if conf[path[0]][path[1]]=={}: conf[path[0]][path[1]]=[]
    return conf,bridges

class PolicyTests(unittest.TestCase):
    def test_per_device_routes(self):
        c=config(); out,bridges=compile(c)
        rules=out['route']['rules']; self.assertEqual(rules[0]['action'],'hijack-dns')
        self.assertEqual([(r['source_ip_cidr'][0],r['outbound']) for r in rules[1:]], [('192.168.7.101/32','node-us'),('192.168.7.102/32','node-jp')])
        self.assertEqual(out['route']['final'],'direct'); self.assertFalse(bridges)
    def test_shared_native_outbound(self):
        c=config(); c['devices'][1]['node']='us'; out,_=compile(c)
        self.assertEqual(len(out['outbounds']),2)
        self.assertEqual(len(out['route']['rules']),3)
    def test_direct_encrypted_dns(self):
        out,_=compile(config()); servers=out['dns']['servers']
        self.assertEqual(len(servers),1); self.assertEqual(servers[0]['type'],'https'); self.assertNotIn('detour',servers[0])
        self.assertTrue(servers[0]['tls']['enabled']); self.assertEqual(out['dns']['final'],'dns-direct')
    def test_private_dns_uses_device_exit(self):
        c=config(); c['dns_policy']='private'; out,_=compile(c)
        self.assertEqual(len(out['dns']['servers']),3)
        for d,r in zip(c['devices'],out['dns']['rules']):
            self.assertEqual(r['source_ip_cidr'],[d['ip']+'/32'])
            server=next(s for s in out['dns']['servers'] if s['tag']==r['server'])
            self.assertEqual(server['detour'],'node-'+d['node'])
    def test_chain_is_per_device(self):
        c=config(); c['devices'][0]['preproxy']='front'; c['devices'][1]['node']='us'
        out,b=compile(c); self.assertFalse(b)
        chained=next(x for x in out['outbounds'] if x['tag']=='chain-us-front')
        direct=next(x for x in out['outbounds'] if x['tag']=='node-us')
        self.assertEqual(chained['detour'],'node-front'); self.assertNotIn('detour',direct)
    def test_invalid_bindings(self):
        changes=[('ip','192.168.8.2'),('ip','192.168.7.1'),('ip','192.168.7.0'),('ip','192.168.7.255'),('ip','192.168.7.999'),('mac','FF:00:00:00:00:01'),('mac','bad'),('node','missing'),('node','us;touch /tmp/pwned'),('preproxy','us')]
        for key,value in changes:
            with self.subTest(key=key,value=value):
                c=config(); c['devices'][0][key]=value
                with self.assertRaises(Exception): compile(c)
    def test_duplicate_ip_and_mac(self):
        for key in ('mac','ip'):
            c=config(); c['devices'][1][key]=c['devices'][0][key]
            with self.assertRaises(Exception): compile(c)
    def test_invalid_dns_and_interface(self):
        for key,value in [('dns_server','example.com'),('dns_policy','udp'),('interface','br-lan;rm'),('port',65536)]:
            c=config(); c[key]=value
            with self.assertRaises(Exception): compile(c)
    def test_protection_covers_mac_and_ip(self):
        c=config()
        for backend in ('nft',):
            rules=from_lua(policy.firewall(to_lua(c),backend)); text='\n'.join(rules.values())
            self.assertIn(c['devices'][0]['mac'],text); self.assertIn(c['devices'][0]['ip'],text)
            if backend=='iptables':
                self.assertIn('JFA25_GUARD6',rules['ipv6']); self.assertIn('--dport 53 -j DROP',rules['ipv6'])
                self.assertNotIn(c['devices'][2]['mac'],rules['filter'])
                self.assertLess(rules['mangle'].index('! -s 192.168.7.101/32 -j DROP'),rules['mangle'].index('--dport 53 -j TPROXY'))
            else:
                self.assertIn('meta nfproto ipv6',text)
                self.assertLess(text.index('ip saddr != 192.168.7.101 drop'),text.index('th dport 53 meta mark'))
    def test_deleted_node_remains_protected(self):
        c=config(); del c['nodes']['us']
        with self.assertRaises(Exception): compile(c)
        for b in ('nft',):
            r=from_lua(policy.firewall(to_lua(c),b)); self.assertIn('192.168.7.101','\n'.join(r.values()))
    def test_empty_network_starts_direct_dns(self):
        c=config(); c['devices']=[]; out,_=compile(c)
        self.assertEqual(out['route']['final'],'direct'); self.assertEqual(len(out['outbounds']),1)
    def test_256_devices_one_core_one_outbound(self):
        c=config(); c['netmask']='255.255.0.0'; c['devices']=[dict(mac=f'02:00:00:00:{i//256:02X}:{i%256:02X}',ip=f'192.168.8.{i%254+1}' if i<254 else f'192.168.9.{i-253}',mode='proxy',node='us') for i in range(256)]
        out,b=compile(c); self.assertEqual(len(out['outbounds']),2); self.assertFalse(b); self.assertEqual(len(out['route']['rules']),257)
    def test_lua_and_template_syntax(self):
        load=lua.eval('function(s,n) local f,e=loadstring(s,n); assert(f,e); return true end')
        for p in ROOT.glob('root/**/*.lua'): load(p.read_text(encoding='utf-8'),str(p))
        for p in ROOT.glob('root/**/*.htm'):
            blocks=[b for b in re.findall(r'<%([\s\S]*?)%>',p.read_text(encoding='utf-8')) if not b.startswith('+')]
            load('\n'.join('local _ = '+b[1:] if b.startswith('=') else b for b in blocks),str(p))

def fixtures(destination):
    destination.mkdir(parents=True,exist_ok=True)
    for name,c in [('direct',config()),('private',dict(config(),dns_policy='private')),('chain',config()),('empty',dict(config(),devices=[]))]:
        if name=='chain': c['devices'][0]['preproxy']='front'
        out,_=compile(c); (destination/(name+'.json')).write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
    for backend in ('nft',):
        for kind,text in from_lua(policy.firewall(to_lua(config()),backend)).items():
            (destination/(kind+'.rules')).write_text(text,encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--sing-box'); p.add_argument('--fixtures',type=pathlib.Path); args=p.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PolicyTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    with tempfile.TemporaryDirectory() as tmp:
        folder=args.fixtures or pathlib.Path(tmp); fixtures(folder)
        if args.sing_box:
            for f in folder.glob('*.json'): subprocess.run([args.sing_box,'check','-c',str(f)],check=True)
