"""Policy regressions for the actual Mihomo compiler, plus native core validation."""
import argparse,copy,json,pathlib,subprocess,unittest
from lupa.lua51 import LuaRuntime
ROOT=pathlib.Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path='+json.dumps(str(ROOT/'root/usr/lib/lua/?.lua').replace('\\','/'))+"..';'..package.path")
policy=lua.eval("require('fastacl251')")
def to_lua(v):
    if isinstance(v,dict):return lua.table_from({k:to_lua(x) for k,x in v.items()})
    if isinstance(v,list):return lua.table_from([to_lua(x) for x in v])
    return v
def from_lua(v):
    if hasattr(v,'keys'):
        k=list(v.keys())
        if k and all(isinstance(x,int) for x in k):return [from_lua(v[i]) for i in range(1,len(k)+1)]
        return {k:from_lua(v[k]) for k in k}
    return v
def config():
    return dict(network='lan',interface='br-lan',router_ip='192.168.7.1',netmask='255.255.255.0',port=12525,default_mode='direct',dns_policy='direct',dns_server='223.5.5.5',dns_name='dns.alidns.com',private_dns_server='9.9.9.9',private_dns_name='dns.quad9.net',nodes={
        'us':dict(protocol='socks',address='proxy.example.com',port='1080',username='a',password='secret'),
        'jp':dict(protocol='http',address='203.0.113.8',port='8080'),
        'front':dict(protocol='vless',outbound=dict(type='vless',server='203.0.113.9',server_port=443,uuid='00000000-0000-0000-0000-000000000001'))},devices=[
        dict(mac='02:00:00:00:00:01',ip='192.168.7.101',mode='proxy',node='us'),
        dict(mac='02:00:00:00:00:02',ip='192.168.7.102',mode='proxy',node='jp'),
        dict(mac='02:00:00:00:00:03',ip='192.168.7.103',mode='direct')])
def compile(c):
    a,b=policy.compile(to_lua(c));a,b=from_lua(a),from_lua(b)
    for k in ['proxies','listeners']:
        if a[k]=={}:a[k]=[]
    return a,b
class Tests(unittest.TestCase):
    def test_device_rules(self):
        a,b=compile(config());self.assertEqual(a['rules'],['SRC-IP-CIDR,192.168.7.101/32,node-us','SRC-IP-CIDR,192.168.7.102/32,node-jp','MATCH,DIRECT']);self.assertFalse(b['devices'])
    def test_shared_nodes(self):
        c=config();c['devices'][1]['node']='us';a,b=compile(c);self.assertEqual(len(a['proxies']),1)
    def test_private_dns_isolation(self):
        c=config();c['dns_policy']='private';a,b=compile(c);self.assertNotEqual(b['devices']['192.168.7.101'],b['devices']['192.168.7.102']);self.assertNotIn('192.168.7.103',b['devices']);self.assertTrue(all(x['listen']=='127.0.0.1' for x in a['listeners']))
    def test_private_shared_exit(self):
        c=config();c['dns_policy']='private';c['devices'][1]['node']='us';a,b=compile(c);self.assertEqual(len(a['listeners']),1)
    def test_encrypted_bootstrap(self):
        a,b=compile(config());self.assertEqual(a['dns']['proxy-server-nameserver'],['127.0.0.1:12553']);self.assertEqual(b['direct_ip'],'223.5.5.5')
    def test_chain(self):
        c=config();c['devices'][0]['preproxy']='front';a,b=compile(c);p=next(x for x in a['proxies'] if x['name']=='chain-us-front');self.assertEqual(p['dialer-proxy'],'node-front')
    def test_guards_and_dns(self):
        a=from_lua(policy.firewall(to_lua(config()),'nft'))['nft'];self.assertIn('redirect to :12553',a);self.assertIn('ip saddr != 192.168.7.101',a);self.assertIn('ether saddr 02:00:00:00:00:01 drop',a)
    def test_duplicate_binding(self):
        c=config();c['devices'][1]['ip']=c['devices'][0]['ip'];self.assertRaises(Exception,compile,c)
    def test_unknown_native_option_rejected(self):
        c=config();c['nodes']['us']['outbound']=dict(type='socks',server='1.2.3.4',server_port=1080,unexpected=True);self.assertRaises(Exception,compile,c)
    def test_empty_direct(self):
        c=config();c['devices']=[];a,b=compile(c);self.assertEqual(a['proxies'],[]);self.assertEqual(a['rules'],['MATCH,DIRECT'])
    def test_lua_syntax(self):
        for p in (ROOT/'root').rglob('*.lua'):lua.execute('assert(loadstring(...))',p.read_text(encoding='utf-8'))
def fixtures(core):
    out=ROOT/'test-results';out.mkdir(exist_ok=True)
    configs=[]
    for mode in ['direct','private']:
        c=config();c['dns_policy']=mode;configs.append((mode,c));d=copy.deepcopy(c);d['devices'][0]['preproxy']='front';configs.append((mode+'-chain',d))
    c=config();c['devices']=[];configs.append(('empty',c))
    from test_import import parser,from_lua as impfrom
    links=['sk5://a:b@1.2.3.4:1080','http://a:b@1.2.3.4:8080','vless://00000000-0000-0000-0000-000000000001@1.2.3.4:443?security=reality&pbk=o7cKgVp0NZVxlhML-QOiAB36drTGGWS8bOiX34bdzGw&sid=12&fp=chrome','trojan://password@1.2.3.4:443','ss://YWVzLTEyOC1nY206cGFzcw==@1.2.3.4:443','hysteria2://pass@1.2.3.4:443','tuic://00000000-0000-0000-0000-000000000001:pass@1.2.3.4:443']
    for i,link in enumerate(links):
        c=config();c['nodes']['us']=impfrom(parser.parse(link));configs.append(('protocol-'+str(i),c))
    for name,c in configs:
        a,b=compile(c);p=out/(name+'.json');p.write_text(json.dumps(a),encoding='utf-8');(out/(name+'-dns.json')).write_text(json.dumps(b),encoding='utf-8')
        if core:subprocess.run([core,'-t','-d',str(out),'-f',str(p)],check=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--core');a=p.parse_args();r=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));assert r.wasSuccessful();fixtures(a.core)
