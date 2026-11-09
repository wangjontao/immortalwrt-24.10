module("luci.controller.juliang_dashboard", package.seeall)

local fs = require "nixio.fs"
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local util = require "luci.util"
local uci = require "luci.model.uci".cursor()

local TRAFFIC_STATE = "/etc/juliang-dashboard/traffic.json"
local EGRESS_CACHE = "/tmp/juliang-dashboard-egress.state"

function index()
	local home = entry({"admin", "home"}, template("juliang_dashboard/home"), _("首页"), 5)
	home.leaf = true

	local status = entry({"admin", "home_status"}, call("dashboard_status"), nil)
	status.leaf = true
end

local function number_file(path)
	local value = tonumber(fs.readfile(path) or "")
	return value and value >= 0 and value or nil
end

local function read_temperature()
	for index = 0, 7 do
		local base = "/sys/class/thermal/thermal_zone" .. index
		local value = tonumber(fs.readfile(base .. "/temp") or "")
		if value and value > 0 then
			if value > 1000 then
				value = value / 1000
			end
			return math.floor(value * 10 + 0.5) / 10
		end
	end
	return nil
end

local function read_traffic_state()
	local state = jsonc.parse(fs.readfile(TRAFFIC_STATE) or "") or {}
	return {
		day_rx = tonumber(state.day_rx) or 0,
		day_tx = tonumber(state.day_tx) or 0,
		month_rx = tonumber(state.month_rx) or 0,
		month_tx = tonumber(state.month_tx) or 0,
		total_rx = tonumber(state.total_rx) or 0,
		total_tx = tonumber(state.total_tx) or 0,
		updated = tonumber(state.updated) or 0
	}
end

local function wired_ports()
	local board = jsonc.parse(fs.readfile("/etc/board.json") or "") or {}
	local network = board.network or {}
	local rows = {}
	local seen = {}

	local function add(device, role)
		if type(device) ~= "string" or not device:match("^[%w_.%-]+$") or seen[device] then
			return
		end

		local base = "/sys/class/net/" .. device .. "/"
		local carrier = number_file(base .. "carrier")
		if carrier == nil then
			return
		end
		seen[device] = true

		local speed = number_file(base .. "speed")
		if speed and speed <= 0 then
			speed = nil
		end
		rows[#rows + 1] = {
			device = device,
			role = role,
			connected = carrier == 1,
			speed = speed,
			duplex = (fs.readfile(base .. "duplex") or ""):match("%S+") or "unknown",
			rx_bytes = number_file(base .. "statistics/rx_bytes") or 0,
			tx_bytes = number_file(base .. "statistics/tx_bytes") or 0
		}
	end

	add("eth0", "2.5G")

	local wan = network.wan or {}
	if type(wan.ports) == "table" then
		for _, device in ipairs(wan.ports) do
			add(device, "WAN")
		end
	else
		add(wan.device, "WAN")
	end

	local lan = network.lan or {}
	if type(lan.ports) == "table" then
		for index, device in ipairs(lan.ports) do
			add(device, "LAN " .. index)
		end
	else
		add(lan.device, "LAN")
	end

	add("eth1", "WAN")
	return rows
end

local function read_egress_cache()
	local cached = {}
	for key, value in (fs.readfile(EGRESS_CACHE) or ""):gmatch("([^=\r\n]+)=([^\r\n]+)") do
		cached[key] = value
	end
	return cached
end

local function cached_egress(cached, key, label)
	return {
		label = label,
		ip = cached[key .. ".ip"] or "",
		country = cached[key .. ".country"] or "",
		colo = cached[key .. ".colo"] or "",
		updated = tonumber(cached[key .. ".updated"]) or 0
	}
end

local function aggregate_egress(primary, items)
	return {
		label = primary.label,
		ip = primary.ip,
		country = primary.country,
		colo = primary.colo,
		updated = primary.updated,
		mode = primary.mode,
		node = primary.node,
		source = primary.source,
		items = items
	}
end

local function read_egress()
	local cached = read_egress_cache()
	local config
	if sys.call("pidof sing-box >/dev/null 2>&1") == 0 and
	   fs.access("/tmp/fastacl252/singbox.json") then
		config = jsonc.parse(fs.readfile("/tmp/fastacl252/singbox.json") or "")
	end

	if not config then
		local item = cached_egress(cached, "direct", "主网络")
		item.mode = "direct"
		item.node = ""
		return aggregate_egress(item, { item })
	end

	local settings = uci:get_all("fastacl252") or {}
	local wifi_labels = {}
	local node_names = {}
	for name, section in pairs(settings) do
		if type(section) == "table" and section[".type"] == "wifi" then
			if section.subnet and section.ssid then
				wifi_labels[section.subnet] = section.ssid
			end
		elseif type(section) == "table" and section[".type"] == "node" then
			node_names[name] = section.name or name
		end
	end

	local by_outbound = {}
	local routes = config.route and config.route.rules or {}
	for _, rule in ipairs(routes) do
		local outbound = rule.outbound
		if type(outbound) == "string" and outbound:match("^node%-[%w_%.%-]+$") then
			local item = by_outbound[outbound] or {
				outbound = outbound,
				sources = {}
			}
			for _, cidr in ipairs(rule.source_ip_cidr or {}) do
				item.sources[#item.sources + 1] = cidr
			end
			by_outbound[outbound] = item
		end
	end

	local items = {}
	for outbound, item in pairs(by_outbound) do
		local label
		for _, cidr in ipairs(item.sources) do
			if wifi_labels[cidr] then
				label = wifi_labels[cidr]
				break
			end
		end
		label = label or "主网络"
		local result = cached_egress(cached, outbound, label)
		local id = outbound:gsub("^node%-", "")
		result.node = node_names[id] or id
		result.mode = "proxy"
		result.source = table.concat(item.sources, ", ")
		result.priority = label == "主网络" and 0 or 1
		items[#items + 1] = result
	end

	table.sort(items, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.label < b.label
	end)

	if #items == 0 then
		local item = cached_egress(cached, "direct", "主网络")
		item.mode = "direct"
		item.node = ""
		return aggregate_egress(item, { item })
	end

	local primary = items[1]
	return aggregate_egress(primary, items)
end

local function reply(payload)
	local http = require "luci.http"
	http.prepare_content("application/json")
	http.write(jsonc.stringify(payload))
end

function dashboard_status()
	local info = util.ubus("system", "info") or {}
	local board = util.ubus("system", "board") or {}
	local cpu_rpc = util.ubus("luci", "getCPUUsage") or {}
	local wan = jsonc.parse(sys.exec("ubus call network.interface.wan status 2>/dev/null") or "") or {}

	local cpu_usage = tonumber(tostring(cpu_rpc.cpuusage or ""):match("(%d+)")) or 0
	local memory = info.memory or {}
	local memory_total = tonumber(memory.total) or 0
	local memory_available = tonumber(memory.available) or 0
	local memory_used = math.max(0, memory_total - memory_available)
	local memory_percent = memory_total > 0 and math.floor(memory_used / memory_total * 100 + 0.5) or 0

	local wan_ip = ""
	for _, address in ipairs(wan["ipv4-address"] or {}) do
		if address.address then
			wan_ip = address.address
			break
		end
	end
	local wan_gateway = ""
	if type(wan.route) == "table" and wan.route[1] then
		wan_gateway = wan.route[1].nexthop or ""
	end

	local device = wan.l3_device or wan.device or ""
	local traffic = {
		device = device,
		rx_bytes = 0,
		tx_bytes = 0,
		timestamp = tonumber((fs.readfile("/proc/uptime") or ""):match("^([%d%.]+)")) or 0
	}
	local wan_speed = nil
	if device:match("^[%w_.%-]+$") then
		traffic.rx_bytes = number_file("/sys/class/net/" .. device .. "/statistics/rx_bytes") or 0
		traffic.tx_bytes = number_file("/sys/class/net/" .. device .. "/statistics/tx_bytes") or 0
		wan_speed = number_file("/sys/class/net/" .. device .. "/speed")
	end

	reply({
		ok = true,
		hostname = "JuLiang OS",
		model = board.model or "",
		firmware = "JuLiang OS",
		uptime = tonumber(info.uptime) or 0,
		load = info.load or {0, 0, 0},
		cpu = cpu_usage,
		memory = {
			total = memory_total,
			used = memory_used,
			available = memory_available,
			percent = memory_percent
		},
		temperature = read_temperature(),
		wan = {
			up = wan.up == true,
			ip = wan_ip,
			gateway = wan_gateway,
			device = device,
			proto = wan.proto or "",
			uptime = tonumber(wan.uptime) or 0,
			speed = wan_speed
		},
		traffic = traffic,
		ports = wired_ports(),
		stats = read_traffic_state(),
		egress = read_egress()
	})
end
