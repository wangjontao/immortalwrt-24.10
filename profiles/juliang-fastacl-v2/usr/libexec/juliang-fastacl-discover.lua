local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local uci = require("luci.model.uci").cursor()

local function split_words(v)
  local out = {}
  if type(v) == "table" then
    for _, x in ipairs(v) do
      if x and x ~= "" then out[#out + 1] = x end
    end
  elseif type(v) == "string" then
    for x in v:gmatch("%S+") do out[#out + 1] = x end
  end
  return out
end

local function ip_to_num(ip)
  local a,b,c,d = tostring(ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if not a or a>255 or b>255 or c>255 or d>255 then return nil end
  return ((a*256+b)*256+c)*256+d
end

local function num_to_ip(n)
  local a = math.floor(n / 16777216) % 256
  local b = math.floor(n / 65536) % 256
  local c = math.floor(n / 256) % 256
  local d = n % 256
  return string.format("%d.%d.%d.%d", a,b,c,d)
end

local function mask_to_prefix(mask)
  if not mask or mask == "" then return 24 end
  local p = tonumber(mask)
  if p and p >= 0 and p <= 32 then return p end
  local n = ip_to_num(mask)
  if not n then return nil end
  local bits = 0
  local seen_zero = false
  for i = 31, 0, -1 do
    local bit = math.floor(n / (2^i)) % 2
    if bit == 1 then
      if seen_zero then return nil end
      bits = bits + 1
    else
      seen_zero = true
    end
  end
  return bits
end

local function cidr_from(ip, mask)
  if not ip or ip == "" then return nil end
  local bare, slash = tostring(ip):match("^([^/]+)/(%d+)$")
  if bare then
    ip = bare
    mask = slash
  end
  local n = ip_to_num(ip)
  local p = mask_to_prefix(mask)
  if not n or not p then return nil end
  local block = 2^(32-p)
  local net = math.floor(n / block) * block
  return num_to_ip(net) .. "/" .. tostring(p)
end

local function network_ipv4(net)
  local ip = uci:get("network", net, "ipaddr")
  local mask = uci:get("network", net, "netmask")
  if type(ip) == "table" then ip = ip[1] end
  local cidr = cidr_from(ip, mask)
  if cidr then return cidr, tostring(ip):match("^([^/]+)") end

  local raw = sys.exec("ubus call network.interface." .. string.format("%q", net) .. " status 2>/dev/null")
  if raw and raw ~= "" then
    local ok, st = pcall(jsonc.parse, raw)
    if ok and type(st) == "table" and type(st["ipv4-address"]) == "table" then
      local a = st["ipv4-address"][1]
      if a and a.address and a.mask then
        return cidr_from(a.address, a.mask), a.address
      end
    end
  end
  return nil
end

local lan_cidr = nil
do
  local ip = uci:get("network", "lan", "ipaddr")
  local mask = uci:get("network", "lan", "netmask")
  if type(ip) == "table" then ip = ip[1] end
  lan_cidr = cidr_from(ip, mask)
end

local ignore = {
  lan=true, wan=true, wan6=true, loopback=true, wwan=true
}

local by_net = {}
uci:foreach("wireless", "wifi-iface", function(s)
  if tostring(s.disabled or "0") ~= "1" and tostring(s.mode or "ap") == "ap" then
    local ssid = s.ssid or s[".name"] or "WiFi"
    for _, net in ipairs(split_words(s.network)) do
      if not ignore[net] then
        local cidr, router_ip = network_ipv4(net)
        if cidr and cidr ~= lan_cidr then
          local item = by_net[net]
          if not item then
            item = {
              network = net,
              subnet = cidr,
              router_ip = router_ip or "",
              ssids = {}
            }
            by_net[net] = item
          end
          local found=false
          for _,v in ipairs(item.ssids) do if v == ssid then found=true break end end
          if not found then item.ssids[#item.ssids+1]=ssid end
        end
      end
    end
  end
end)

local items = {}
for _, item in pairs(by_net) do
  item.ssid = table.concat(item.ssids, " / ")
  item._sort = ip_to_num((item.subnet or ""):match("^([^/]+)$") or (item.subnet or ""):match("^([^/]+)/")) or 0
  items[#items+1] = item
end

table.sort(items, function(a,b)
  if a._sort == b._sort then return a.network < b.network end
  return a._sort < b._sort
end)

local old = {}
uci:foreach("juliang_fastacl", "ap", function(s)
  local key = (s.network and ("net:" .. s.network)) or (s.subnet and ("subnet:" .. s.subnet))
  if key then old[key] = s.node end
end)

-- Remove only AP slot sections; keep main and other future settings.
local dels = {}
uci:foreach("juliang_fastacl", "ap", function(s) dels[#dels+1]=s[".name"] end)
for _,name in ipairs(dels) do uci:delete("juliang_fastacl", name) end

for i,item in ipairs(items) do
  local sec = "ap" .. i
  uci:section("juliang_fastacl", "ap", sec, {
    slot = tostring(i),
    network = item.network,
    ssid = item.ssid,
    subnet = item.subnet,
    router_ip = item.router_ip or "",
    socks_port = tostring(13100+i),
    preproxy_port = tostring(14100+i)
  })
  local node = old["net:"..item.network] or old["subnet:"..item.subnet]
  if node and node ~= "" then uci:set("juliang_fastacl", sec, "node", node) end
end
uci:set("juliang_fastacl", "main", "ap_count", tostring(#items))
uci:commit("juliang_fastacl")

io.write(jsonc.stringify({ ok = (#items > 0), count = #items, aps = items }, true))
