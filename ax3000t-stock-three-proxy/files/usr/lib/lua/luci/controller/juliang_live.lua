module('luci.controller.juliang_live', package.seeall)

function index()
  local root = entry({'admin', 'juliang'}, firstchild(), _('JuLiang Live'), 0)
  root.dependent = false

  local home = entry({'admin', 'juliang', 'live'}, template('juliang_live/home'), _('JuLiang Live'), 1)
  home.leaf = true

  local status = entry({'admin', 'juliang', 'status'}, call('status'), nil)
  status.leaf = true

  local reboot = entry({'admin', 'juliang', 'reboot'}, post('reboot_action'), nil)
  reboot.leaf = true
end

local function reply(value)
  local http = require('luci.http')
  http.prepare_content('application/json')
  http.write(require('luci.jsonc').stringify(value))
end

function reboot_action()
  local http = require('luci.http')
  local sys = require('luci.sys')
  sys.call('(sleep 1; reboot) >/dev/null 2>&1 &')
  reply({ ok = true })
end

local function number_file(path)
  local text = require('nixio.fs').readfile(path) or ''
  local value = tonumber(text:match('^%s*([%d.]+)') or '')
  return value
end

local function wired_ports()
  local fs = require('nixio.fs')
  local json = require('luci.jsonc')
  local board = json.parse(fs.readfile('/etc/board.json') or '') or {}
  local result, seen = {}, {}
  local function add(device, role)
    if type(device) ~= 'string' or not device:match('^[%w_.-]+$') or seen[device] then
      return
    end
    seen[device] = true
    local base = '/sys/class/net/' .. device .. '/'
    local carrier = number_file(base .. 'carrier')
    local speed = number_file(base .. 'speed')
    result[#result + 1] = {
      device = device,
      role = role,
      connected = carrier == 1,
      speed = carrier == 1 and speed and speed > 0 and speed or nil
    }
  end
  for _, role in ipairs({'wan', 'lan'}) do
    local network = (board.network or {})[role] or {}
    if type(network.ports) == 'table' then
      for _, device in ipairs(network.ports) do
        add(device, role)
      end
    else
      add(network.device, role)
    end
  end
  return result
end

function status()
  local json = require('luci.jsonc')
  local sys = require('luci.sys')
  local fs = require('nixio.fs')
  local uci = require('uci').cursor()

  local wan = json.parse(sys.exec('ubus call network.interface.wan status 2>/dev/null')) or {}
  local wan_ip = ''
  for _, address in ipairs(wan['ipv4-address'] or {}) do
    if address.address then
      wan_ip = address.address
      break
    end
  end

  local wifi_count = 0
  uci:foreach('wireless', 'wifi-iface', function(section)
    if section.disabled ~= '1' then
      wifi_count = wifi_count + 1
    end
  end)

  local device = wan.l3_device or wan.device or ''
  local traffic = { device = device }
  if device:match('^[%w_.-]+$') then
    traffic.rx_bytes = number_file('/sys/class/net/' .. device .. '/statistics/rx_bytes')
    traffic.tx_bytes = number_file('/sys/class/net/' .. device .. '/statistics/tx_bytes')
  end
  traffic.timestamp = number_file('/proc/uptime')

  local meminfo = fs.readfile('/proc/meminfo') or ''
  local mem_total = tonumber(meminfo:match('MemTotal:%s*(%d+)') or '') or 0
  local mem_available = tonumber(meminfo:match('MemAvailable:%s*(%d+)') or '') or 0
  local load = (sys.exec('cat /proc/loadavg 2>/dev/null') or ''):match('^([%d.]+)')

  reply({
    ok = true,
    hostname = sys.hostname() or 'JuLiang',
    model = 'JuLiang OS',
    lan_ip = uci:get('network', 'lan', 'ipaddr') or '192.168.9.1',
    wan_up = wan.up == true,
    wan_ip = wan_ip,
    wan_device = device,
    uptime = tonumber(sys.exec('cut -d. -f1 /proc/uptime 2>/dev/null') or '0') or 0,
    load = tonumber(load or '') or 0,
    memory_total = mem_total,
    memory_available = mem_available,
    wifi_count = wifi_count,
    passwall2 = (uci:get('passwall2', '@global[0]', 'enabled') or '0') == '1',
    ssr_plus = (uci:get('shadowsocksr', '@global[0]', 'enabled') or '0') == '1',
    openclash = (uci:get('openclash', 'config', 'enable') or '0') == '1',
    ports = wired_ports(),
    traffic = traffic
  })
end
