-- Curate the JuLiang OS menu without changing installed services.
local fs = require 'nixio.fs'
local json = require 'luci.jsonc'

for name in fs.dir('/usr/share/luci/menu.d') do
	if name:match('%.json$') then
		local path = '/usr/share/luci/menu.d/' .. name
		local obj = json.parse(fs.readfile(path) or '')
		local changed = false

		if type(obj) == 'table' then
			for k in pairs(obj) do
				if k == 'admin/nas' or k:match('^admin/nas/') or
				   k == 'admin/statistics' or k:match('^admin/statistics/') then
					obj[k] = nil
					changed = true
				end
			end
			if obj['admin/services'] then
				obj['admin/services'].title = nil
				changed = true
			end
			for _, key in ipairs({
				'admin/services/ddns',
				'admin/services/wol',
				'admin/services/ksmbd',
				'admin/status',
				'admin/system/package-manager',
				'admin/system/startup',
				'admin/system/crontab',
				'admin/system/mounts',
				'admin/system/commands',
				'admin/network/routes',
				'admin/network/diagnostics'
			}) do
				if obj[key] then
					obj[key].title = nil
					changed = true
				end
			end
			if obj['admin/services/upnp'] then
				obj['admin/network/upnp'] = obj['admin/services/upnp']
				obj['admin/services/upnp'] = nil
				obj['admin/network/upnp'].order = 75
				changed = true
			end
			if changed then
				fs.writefile(path, next(obj) and json.stringify(obj) or '{}')
				fs.chmod(path, '644')
			end
		end
	end
end

-- Preserve the installed NPS service, changing only its LuCI routes.
local nps = '/usr/lib/lua/luci/controller/nps.lua'
if fs.access(nps) then
	local controller = assert(
		fs.readfile('/usr/libexec/juliang-nps-controller.lua'),
		'Missing NPS menu payload'
	)
	assert(fs.writefile(nps, controller), 'Cannot relocate NPS menu')
	fs.chmod(nps, '644')
end

for path in fs.glob('/tmp/luci-indexcache*') do
	fs.remove(path)
end
