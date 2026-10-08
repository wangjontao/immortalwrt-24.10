"""Policy regressions for the actual Mihomo compiler, plus native core validation."""
import base64,argparse,copy,json,pathlib,subprocess,unittest
from lupa.lua51 import LuaRuntime
ROOT=pathlib.Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path='+json.dumps(str(ROOT/'root/usr/lib/lua/?.lua').replace('\\','/'))+"..';'..package.path")
lua.globals().pyencode=lambda v:json.dumps(from_lua(v))
lua.globals().pyb64encode=lambda v:base64.b64encode(v.encode()).decode()
lua.execute("package.preload['luci.jsonc']=function() return {stringify=pyencode} end;package.preload['nixio']=function() return {bin={b64encode=pyb64encode}} end")
policy=lua.eval("require('fastacl252')")
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
    return a,b
class Tests(unittest.TestCase):
    def test_device_rules(self):
        a,b=compile(config());self.assertIn("sip(192.168.7.101/32) -> must_exit_us",a);self.assertIn('fallback: must_direct',a);self.assertFalse(b['devices'])
    def test_shared_nodes(self):
        c=config();c['devices'][1]['node']='us';a,b=compile(c);self.assertEqual(a.count('policy: fixed(0)'),1)
    def test_private_dns_isolation(self):
        c=config();c['dns_policy']='private';a,b=compile(c);self.assertNotEqual(b['devices']['192.168.7.101'],b['devices']['192.168.7.102']);self.assertNotIn('192.168.7.103',b['devices'])
    def test_chain(self):
        c=config();c['devices'][0]['preproxy']='front';a,b=compile(c);self.assertIn('socks5://a:secret@proxy.example.com:1080 -> vless://',a)
    def test_guards_and_dns(self):
        a=from_lua(policy.firewall(to_lua(config()),'nft'))['nft'];self.assertIn('redirect to :12553',a);self.assertNotIn('tproxy ip to',a)
    def test_duplicate_binding(self):
        c=config();c['devices'][1]['ip']=c['devices'][0]['ip'];self.assertRaises(Exception,compile,c)
    def test_empty_direct(self):
        c=config();c['devices']=[];a,b=compile(c);self.assertIn('fallback: must_direct',a)
    def test_unknown_native_option_rejected(self):
        c=config();c['nodes']['us']['outbound']=dict(type='socks',server='1.2.3.4',server_port=1080,unexpected=True);self.assertRaises(Exception,compile,c)
    def test_lua_syntax(self):
        for p in (ROOT/'root').rglob('*.lua'):lua.execute('assert(loadstring(...))',p.read_text(encoding='utf-8'))
def fixtures(core,helper):
    out=ROOT/'test-results';out.mkdir(exist_ok=True)
    for name in ['direct','private','chain','empty']:
        c=config()
        if name=='private':c['dns_policy']='private'
        if name=='chain':c['devices'][0]['preproxy']='front'
        if name=='empty':c['devices']=[]
        a,b=compile(c);p=out/(name+'.dae');p.write_text(a,encoding='utf8');p.chmod(0o600)
        q=out/(name+'-dns.json');q.write_text(json.dumps(b),encoding='utf8');q.chmod(0o600)
        if core:subprocess.run([core,'validate','-c',str(p)],check=True)
        if helper:subprocess.run([helper,'-check','-config',str(q)],check=True)
if __name__=='__main__':
    args=argparse.ArgumentParser();args.add_argument('--core');args.add_argument('--helper');opts,argsleft=args.parse_known_args()
    result=unittest.main(argv=['test']+argsleft,exit=False).result
    if not result.wasSuccessful():raise SystemExit(1)
    fixtures(opts.core,opts.helper)
