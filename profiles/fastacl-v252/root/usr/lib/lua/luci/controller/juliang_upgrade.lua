module('luci.controller.juliang_upgrade', package.seeall)

function index()
	local page = entry(
		{'admin', 'juliang', 'upgrade'},
		template('juliang_center/upgrade'),
		_('在线升级'),
		9
	)
	page.leaf = true
	page.acl_depends = {'juliang-center'}

	local status = entry(
		{'admin', 'juliang', 'upgrade_status'},
		call('upgrade_status'),
		nil
	)
	status.leaf = true
	status.acl_depends = {'juliang-center'}

	local action = entry(
		{'admin', 'juliang', 'upgrade_action'},
		post('upgrade_action'),
		nil
	)
	action.leaf = true
	action.acl_depends = {'juliang-center'}
end

local function reply(value)
	local http = require 'luci.http'
	http.prepare_content('application/json')
	http.write(require('luci.jsonc').stringify(value))
end

local function current_version()
	local cursor = require('uci').cursor()
	return cursor:get('fastacl252', 'main', 'version') or ''
end

local function current_board()
	local json = require 'luci.jsonc'
	local sys = require 'luci.sys'
	local board = json.parse(sys.exec('ubus call system board 2>/dev/null')) or {}
	return board.board_name or ''
end

local function pending_status()
	local cursor = require('uci').cursor()
	local pending = cursor:get('fastacl-upgrade', 'settings', 'upgrade_pending') or '0'
	local target = cursor:get('fastacl-upgrade', 'settings', 'target_version') or ''
	local previous = cursor:get('fastacl-upgrade', 'settings', 'previous_version') or ''
	if pending ~= '1' then
		return nil
	end
	if current_version() == target and target ~= '' then
		cursor:set('fastacl-upgrade', 'settings', 'upgrade_pending', '0')
		cursor:commit('fastacl-upgrade')
		return {
			state = 'success',
			version = target,
			previous_version = previous
		}
	end
	return {
		state = 'rebooting',
		latest_version = target,
		previous_version = previous
	}
end

local function read_status()
	local fs = require 'nixio.fs'
	local result = {}
	local content = fs.readfile('/tmp/fastacl-upgrade/status')
	if content then
		for line in content:gmatch('[^\r\n]+') do
			local key, value = line:match('^([%w_]+)=(.*)$')
			if key then
				result[key] = value
			end
		end
	end
	return result
end

function upgrade_status()
	local status = pending_status() or read_status()
	status.ok = true
	status.current_version = current_version()
	status.board = current_board()
	reply(status)
end

local function set_channel(channel)
	if channel ~= 'stable' and channel ~= 'beta' then
		return false
	end
	local cursor = require('uci').cursor()
	cursor:set('fastacl-upgrade', 'settings', 'channel', channel)
	return cursor:commit('fastacl-upgrade')
end

function upgrade_action()
	local action = require('luci.http').formvalue('action') or ''
	local channel = require('luci.http').formvalue('channel') or 'stable'
	if not set_channel(channel) then
		reply({ok = false, error = '无效的更新通道'})
		return
	end
	if action ~= 'check' and action ~= 'install' then
		reply({ok = false, error = '无效的升级操作'})
		return
	end

	local worker = '/usr/libexec/fastacl-upgrade-worker'
	local fs = require 'nixio.fs'
	if not fs.access(worker, 'x') then
		reply({ok = false, error = '升级程序不存在'})
		return
	end

	local command = string.format('%s launch %s >/dev/null 2>&1', worker, action)
	local result = require('luci.sys').call(command)
	if result ~= 0 then
		reply({ok = false, error = '无法启动升级任务'})
		return
	end
	reply({ok = true})
end
