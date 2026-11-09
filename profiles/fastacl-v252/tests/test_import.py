import base64, json, unittest, yaml
from test_support import ROOT, LuaRuntime, from_lua, config, compile

runtime=LuaRuntime(unpack_returned_tuples=True)
def table(value):
    if isinstance(value,dict):return runtime.table_from({k:table(v) for k,v in value.items()})
    if isinstance(value,list):return runtime.table_from([table(v) for v in value])
    return value
runtime.globals().pyjson=lambda s:table(json.loads(s))
runtime.globals().pyyaml=lambda s:table(yaml.safe_load(s))
runtime.globals().pyb64=lambda s:base64.b64decode(s,validate=True).decode()
runtime.execute("package.path="+json.dumps(str(ROOT/'root/usr/lib/lua/?.lua').replace('\\','/'))+"..';'..package.path")
runtime.execute("package.preload['luci.jsonc']=function() return {parse=pyjson} end; package.preload['nixio']=function() return {bin={b64decode=pyb64}} end; package.preload['lyaml']=function() return {load=pyyaml} end")
parser=runtime.eval("require('fastacl252_import')")
exporter=runtime.eval("require('fastacl252_uri')")
def parse(s):return from_lua(parser.parse(s))
def export(node):return from_lua(exporter.node(table(node)))
UUID='00000000-0000-0000-0000-000000000001'
class ImportTests(unittest.TestCase):
    def test_sk5_colon_password(self):
        n=parse('sk5://example.com:1080:user:a:b#测试'); self.assertEqual(n['outbound']['password'],'a:b')
    def test_ipv6_percent_credentials(self):
        n=parse('socks5://user:p%40ss%2Bword@[2001:db8::1]:1080#IPv6'); self.assertEqual(n['outbound']['server'],'2001:db8::1'); self.assertEqual(n['outbound']['password'],'p@ss+word')
    def test_base64_credentials(self):
        auth=base64.b64encode(b'user:secret').decode(); n=parse('socks5://'+auth+'@proxy.example:1080'); self.assertEqual(n['outbound']['username'],'user')
    def test_https(self):
        n=parse('https://user:secret@proxy.example:443?sni=tls.example'); self.assertEqual(n['outbound']['tls']['server_name'],'tls.example'); self.assertNotIn('insecure',n['outbound']['tls'])
    def test_vless_ws_tls(self):
        n=parse('vless://'+UUID+'@proxy.example:443?security=tls&type=ws&path=%2Fws&host=ws.example&sni=tls.example#VLESS'); self.assertEqual(n['outbound']['transport']['path'],'/ws'); self.assertEqual(n['outbound']['tls']['server_name'],'tls.example')
    def test_singbox_native_transports(self):
        cases=(
            ('http','&path=%2Fh2&host=h2.example&method=GET',{'type':'http','path':'/h2','host':['h2.example'],'method':'GET'}),
            ('httpupgrade','&path=%2Fup&host=up.example',{'type':'httpupgrade','path':'/up','host':'up.example'}),
            ('quic','',{'type':'quic'}),
            ('raw','',None),
            ('tcp','',None),
        )
        for kind,params,want in cases:
            with self.subTest(kind=kind):
                n=parse('vless://'+UUID+'@proxy.example:443?security=tls&type='+kind+params)
                self.assertEqual(n['outbound'].get('transport'),want)
    def test_unsupported_transports_explain_singbox_limit(self):
        for kind,word in [('xhttp','XHTTP'),('mkcp','mKCP')]:
            with self.subTest(kind=kind):
                with self.assertRaisesRegex(Exception,word):parse('vless://'+UUID+'@proxy.example:443?security=tls&type='+kind)
    def test_tls_versions_and_alpn(self):
        n=parse('vless://'+UUID+'@proxy.example:443?security=tls&type=http&minVersion=1.2&maxVersion=1.3&alpn=h2%2Chttp%2F1.1')
        self.assertEqual(n['outbound']['tls']['min_version'],'1.2')
        self.assertEqual(n['outbound']['tls']['max_version'],'1.3')
        self.assertEqual(n['outbound']['tls']['alpn'],['h2','http/1.1'])
    def test_transport_uri_roundtrip(self):
        for transport in (
            {'type':'http','path':'/h2','host':['h2.example'],'method':'GET'},
            {'type':'httpupgrade','path':'/up','host':'up.example'},
            {'type':'quic'},
            {'type':'grpc','service_name':'TunService'},
        ):
            with self.subTest(transport=transport['type']):
                outbound={'type':'vless','server':'proxy.example','server_port':443,'uuid':UUID,'tls':{'enabled':True,'server_name':'proxy.example'},'transport':transport}
                link=export({'name':'test','protocol':'vless','outbound':outbound})
                self.assertEqual(parse(link)['outbound'].get('transport'),transport)
    def test_vmess(self):
        v=dict(add='proxy.example',port='443',id=UUID,aid='0',net='ws',path='/ws',tls='tls',sni='proxy.example',ps='VMess')
        n=parse('vmess://'+base64.b64encode(json.dumps(v).encode()).decode()); self.assertEqual(n['outbound']['type'],'vmess')
    def test_trojan_ss_hy2_tuic(self):
        for link,t in [('trojan://pass@proxy.example:443?sni=proxy.example','trojan'),('ss://'+base64.b64encode(b'aes-128-gcm:secret').decode()+'@proxy.example:443','shadowsocks'),('hy2://pass@proxy.example:443?sni=proxy.example','hysteria2'),('tuic://'+UUID+':pass@proxy.example:443','tuic')]:
            with self.subTest(protocol=t):self.assertEqual(parse(link)['outbound']['type'],t)
    def test_base64_subscription(self):
        text='socks5://user:pass@proxy.example:1080#US\nhttp://proxy.example:8080#JP'
        nodes=from_lua(parser.subscription(base64.b64encode(text.encode()).decode())); self.assertEqual(len(nodes),2)
    def test_singbox_json(self):
        text=json.dumps({'outbounds':[{'type':'direct','tag':'direct'},{'type':'socks','tag':'US','server':'proxy.example','server_port':1080,'detour':'old'}]})
        nodes=from_lua(parser.subscription(text)); self.assertEqual(len(nodes),1); self.assertNotIn('detour',nodes[0]['outbound'])
    def test_clash_yaml(self):
        text='proxies:\n  - name: US\n    type: socks5\n    server: proxy.example\n    port: 1080\n  - name: JP\n    type: trojan\n    server: jp.example\n    port: 443\n    password: secret\n    sni: tls.example\n'
        nodes=from_lua(parser.subscription(text)); self.assertEqual(len(nodes),2); self.assertEqual(nodes[1]['outbound']['tls']['server_name'],'tls.example')
    def test_clash_http2_transport(self):
        text='proxies:\n  - name: H2\n    type: vless\n    server: proxy.example\n    port: 443\n    uuid: '+UUID+'\n    tls: true\n    network: h2\n    h2-opts:\n      host:\n        - h2.example\n      path: /h2\n'
        nodes=from_lua(parser.subscription(text)); self.assertEqual(nodes[0]['outbound']['transport'],{'type':'http','path':'/h2','host':['h2.example']})
    def test_invalid_batch_not_partially_imported(self):
        with self.assertRaises(Exception):parser.batch('socks5://proxy.example:1080\nunknown://host:443')
    def test_invalid_ports_tls_transport(self):
        for link in ('sk5://host:70000','socks5://host:1080?tls=1','vless://'+UUID+'@host:443?type=unknown','ss://'+base64.b64encode(b'aes-128-gcm:secret').decode()+'@host:443?plugin=unknown'):
            with self.subTest(link=link):
                with self.assertRaises(Exception):parser.parse(link)

def fixtures(folder):
    links=['socks5://user:pass@proxy.example:1080','https://user:pass@proxy.example:443','vless://'+UUID+'@proxy.example:443?security=tls&type=ws&path=%2Fws','trojan://pass@proxy.example:443','hy2://pass@proxy.example:443','tuic://'+UUID+':pass@proxy.example:443','ss://'+base64.b64encode(b'aes-128-gcm:secret').decode()+'@proxy.example:443']
    v=dict(add='proxy.example',port='443',id=UUID,aid='0',net='ws',path='/ws',tls='tls',ps='VMess'); links.append('vmess://'+base64.b64encode(json.dumps(v).encode()).decode())
    for i,line in enumerate(links):
        c=config(); c['devices']=c['devices'][:1]; c['nodes']={'us':parse(line)}; out,_=compile(c); p=folder/f'import-{i}.json';p.write_text(json.dumps(from_lua(out)),encoding='utf-8');p.chmod(0o600)

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ImportTests))
    if not result.wasSuccessful():raise SystemExit(1)
    folder=ROOT/'test-results'; folder.mkdir(exist_ok=True); fixtures(folder)
