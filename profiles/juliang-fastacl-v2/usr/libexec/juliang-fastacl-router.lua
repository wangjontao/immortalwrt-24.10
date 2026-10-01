local jsonc = require "luci.jsonc"
local uci = require("luci.model.uci").cursor()
local cfg = "juliang_fastacl"
local port = tonumber(uci:get(cfg, "main", "tproxy_port") or "12345")
local dns_addr = uci:get(cfg, "main", "dns_server") or "1.1.1.1"

local outbounds = { { type = "direct", tag = "direct" } }
local route_rules = {}
local dns_servers = {}
local dns_rules = {}

for i = 1, 20 do
  local s = "ap" .. i
  local subnet = uci:get(cfg, s, "subnet") or string.format("172.16.%d.0/24", i)
  local sport = tonumber(uci:get(cfg, s, "socks_port") or tostring(13100 + i))
  local tag = "ap" .. i
  outbounds[#outbounds + 1] = {
    type = "socks",
    tag = tag,
    server = "127.0.0.1",
    server_port = sport,
    version = "5"
  }
  dns_servers[#dns_servers + 1] = {
    type = "tcp",
    tag = "dns-" .. tag,
    server = dns_addr,
    server_port = 53,
    detour = tag
  }
  dns_rules[#dns_rules + 1] = {
    source_ip_cidr = { subnet },
    action = "route",
    server = "dns-" .. tag
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { subnet },
    port = { 53 },
    action = "hijack-dns"
  }
  route_rules[#route_rules + 1] = {
    source_ip_cidr = { subnet },
    action = "route",
    outbound = tag
  }
end

local conf = {
  log = { level = "warn", timestamp = true },
  dns = {
    servers = dns_servers,
    rules = dns_rules,
    final = "dns-ap1"
  },
  inbounds = {
    {
      type = "tproxy",
      tag = "jfa-tproxy",
      listen = "0.0.0.0",
      listen_port = port
    }
  },
  outbounds = outbounds,
  route = {
    rules = route_rules,
    final = "direct"
  }
}

io.write(jsonc.stringify(conf, true))
