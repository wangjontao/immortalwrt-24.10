module("luci.controller.juliang_egress",package.seeall)
local http=require "luci.http"
local json=require "luci.jsonc"
local sys=require "luci.sys"
local function reply(d) http.prepare_content("application/json");http.write(json.stringify(d)) end
function index()
 local p=entry({"admin","juliang_egress"},call("api_egress"),nil)
 p.leaf=true;p.dependent=false;p.acl_depends={"juliang-operator-home"}
end
function api_egress()
    local fs = require "nixio.fs"
    local cache = "/tmp/juliang-egress.json"
    local cached = json.parse(fs.readfile(cache) or "")
    if cached and cached.checked_at and os.time() - cached.checked_at >= 0 and os.time() - cached.checked_at < 60 then
        reply(cached); return
    end
    local raw = sys.exec("curl -4 -fsS --connect-timeout 4 --max-time 10 https://ipwho.is/ 2>/dev/null | head -c 16384")
    local data = json.parse(raw or "")
    if not data or data.success ~= true or type(data.ip) ~= "string" or not data.ip:match("^%d+%.%d+%.%d+%.%d+$") then
        reply({ok=false,error="出口检测失败，请稍后重试"}); return
    end
    local result = {ok=true,ip=data.ip,country=data.country or "",country_code=data.country_code or "",region=data.region or "",city=data.city or "",isp=(data.connection or {}).isp or "",source="ipwho.is",scope="router",checked_at=os.time()}
    fs.writefile(cache,json.stringify(result))
    reply(result)
end
