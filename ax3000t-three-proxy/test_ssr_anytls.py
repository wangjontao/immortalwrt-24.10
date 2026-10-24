from pathlib import Path
import json,sys
from lupa.lua51 import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
server=lua.table_from({'type':'v2ray','v2ray_protocol':'anytls','server':'127.0.0.1','server_port':'443','password':'test-only-password','tls':'1','tls_host':'example.com','transport':'raw'})
lua.globals().server_fixture=server
lua.execute("""
nixio={bin={b64decode=function(x) return x end,b64encode=function(x) return x end}}
luci={sys={exec=function(cmd) if cmd:find('version',1,true) then return 'Xray 26.10.21' end return '/usr/bin/xray' end}}
package.preload['luci.sys']=function() return luci.sys end
package.preload['luci.model.uci']=function() return {cursor=function() return {
 get_all=function(self,config,section) if section=='fixture' then return server_fixture end return {} end,
 get_first=function(self,config,kind,key,default) return default end
} end} end
package.preload['luci.jsonc']=function() return {stringify=function(t) result=t;return '{}' end,parse=function() return {} end} end
arg={[1]='fixture',[2]='tcp',[3]='1234',[4]='0',[5]='0'}
print=function() end
""")
lua.execute('\n'.join(Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()[1:]))
def conv(v):
 if not hasattr(v,'keys'):return v
 keys=list(v.keys())
 if keys and all(isinstance(k,(int,float)) for k in keys):return [conv(v[k]) for k in sorted(keys)]
 return {str(k):conv(v[k]) for k in keys}
result=conv(lua.globals().result)
assert result and any(x.get('protocol')=='anytls' for x in result.get('outbounds',[])),result
Path(sys.argv[2]).write_text(json.dumps(result,indent=2),encoding='utf-8')
print('SSR Plus+ generated AnyTLS config verified.')
