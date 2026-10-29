module("luci.controller.nps",package.seeall)
function index()
if not nixio.fs.access("/etc/config/nps")then
return
end
local e
e=entry({"admin","system","nps"},cbi("nps"),_("JuLiang管理"),70)
e.i18n="nps"
e.dependent=true
e.acl_depends = { "luci-app-nps" }
local old=entry({"admin","services","nps"},alias("admin","system","nps"),nil);old.acl_depends={"luci-app-nps"}
local network=entry({"admin","network","nps"},alias("admin","system","nps"),nil);network.acl_depends={"luci-app-nps"}
local st=entry({"admin","services","nps","status"},call("status"));st.leaf=true;st.acl_depends={"luci-app-nps"}
local ns=entry({"admin","network","nps","status"},call("status"));ns.leaf=true;ns.acl_depends={"luci-app-nps"}
local ss=entry({"admin","system","nps","status"},call("status"));ss.leaf=true;ss.acl_depends={"luci-app-nps"}
end
function status()
local e={}
e.running=luci.sys.call("pgrep npc > /dev/null")==0
luci.http.prepare_content("application/json")
luci.http.write_json(e)
end
