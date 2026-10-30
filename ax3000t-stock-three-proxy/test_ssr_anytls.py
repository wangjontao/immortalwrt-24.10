from pathlib import Path
import json,sys
from lupa.lua51 import LuaRuntime

inbound_type=sys.argv[3] if len(sys.argv)>3 else 'redirect'
is_server=inbound_type=='server'
local_port=1234 if inbound_type=='redirect' else 301
socks_port=1080 if inbound_type=='redirect' else 0
testdata=Path(sys.argv[4]).resolve() if len(sys.argv)>4 else Path(__file__).resolve().parent/'testdata'
lua=LuaRuntime(unpack_returned_tuples=True)
if is_server:
    server=lua.table_from({
        'type':'anytls',
        'server_port':'9443',
        'anytls_password':'test-only-password',
        'anytls_padding':'stop=8\n0=30-30',
        'tls_certificateFile':str(testdata/'anytls-test-cert.pem'),
        'tls_keyFile':str(testdata/'anytls-test-key.pem'),
    })
else:
    server=lua.table_from({
        'type':'v2ray',
        'v2ray_protocol':'anytls',
        'server':'127.0.0.1',
        'server_port':'443',
        'password':'test-only-password',
        'tls':'1',
        'tls_host':'example.com',
        'tls_alpn':'h2,http/1.1',
        'anytls_idle_session_check_interval':'30',
        'anytls_idle_session_timeout':'45',
        'anytls_min_idle_session':'2',
    })
lua.globals().server_fixture=server
lua.execute("""
luci={sys={exec=function(cmd) return '' end}}
package.preload['luci.sys']=function() return luci.sys end
package.preload['luci.model.uci']=function() return {cursor=function() return {
 get_all=function(self,config,section) if section=='fixture' then return server_fixture end return {} end,
 get_first=function(self,config,section,key,default) return default end
} end} end
package.preload['luci.jsonc']=function() return {
 stringify=function(t) result=t;return '' end
} end
print=function() end
""")
lua.globals().arg=lua.table()
lua.globals().arg[1]='fixture'
lua.globals().arg[2]=str(local_port)
lua.globals().arg[3]=str(socks_port)
lua.globals().arg[4]=inbound_type
lua.execute('\n'.join(Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()[1:]))

def conv(value):
    if not hasattr(value,'keys'):
        return value
    keys=list(value.keys())
    if keys and all(isinstance(key,(int,float)) for key in keys):
        return [conv(value[key]) for key in sorted(keys)]
    return {str(key):conv(value[key]) for key in keys}

result=conv(lua.globals().result)
assert result, 'Sing-box AnyTLS generator returned no config'
if is_server:
    inbound=result['inbounds'][0]
    assert inbound['type']=='anytls', inbound
    assert inbound['listen_port']==9443, inbound
    assert inbound['users']==[{'name':'user','password':'test-only-password'}], inbound
    assert inbound['padding_scheme']==['stop=8','0=30-30'], inbound
    assert inbound['tls']=={
        'enabled':True,
        'certificate_path':str((testdata/'anytls-test-cert.pem').resolve()),
        'key_path':str((testdata/'anytls-test-key.pem').resolve()),
    }, inbound['tls']
    assert result['outbounds'][0]['type']=='direct', result
    Path(sys.argv[2]).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print('SSR Plus+ generated Sing-box AnyTLS server config verified.')
    raise SystemExit(0)
assert result['inbounds'][0]['type']==inbound_type, result
assert result['inbounds'][0]['listen_port']==local_port, result
if inbound_type=='redirect':
    assert result['inbounds'][1]['type']=='socks', result
else:
    assert result['inbounds'][0]['network']=='udp', result
    assert len(result['inbounds'])==1, result
outbound=result['outbounds'][0]
assert outbound['type']=='anytls', outbound
assert outbound['server']=='127.0.0.1' and outbound['server_port']==443, outbound
assert outbound['password']=='test-only-password', outbound
assert outbound['idle_session_check_interval']=='30s', outbound
assert outbound['idle_session_timeout']=='45s', outbound
assert outbound['min_idle_session']==2, outbound
assert outbound['tls']=={
    'enabled':True,
    'server_name':'example.com',
    'insecure':False,
    'alpn':['h2','http/1.1'],
}, outbound['tls']
Path(sys.argv[2]).write_text(json.dumps(result,indent=2),encoding='utf-8')
print('SSR Plus+ generated Sing-box AnyTLS config verified.')
