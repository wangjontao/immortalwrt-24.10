local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local node = arg[1] or ""
local port = tonumber(arg[2] or "0")
local outfile = arg[3] or ""
if node == "" or port == 0 or outfile == "" then os.exit(2) end
local n = uci:get_all("passwall2", node)
if not n then os.exit(3) end
local t = string.lower(n.type or "")
local out
if t == "socks" then
  out = {
    type = "socks", tag = "proxy", server = n.address, server_port = tonumber(n.port), version = "5",
    username = n.username, password = n.password
  }
elseif t == "http" then
  out = {
    type = "http", tag = "proxy", server = n.address, server_port = tonumber(n.port),
    username = n.username, password = n.password
  }
else
  os.exit(4)
end
local conf = {
  log = { level = "error" },
  inbounds = { { type = "socks", tag = "in", listen = "127.0.0.1", listen_port = port } },
  outbounds = { out },
  route = { final = "proxy" }
}
local f = assert(io.open(outfile, "w"))
f:write(jsonc.stringify(conf, true))
f:close()
