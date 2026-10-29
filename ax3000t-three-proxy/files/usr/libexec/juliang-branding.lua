#!/usr/bin/lua
local fs = require('nixio.fs')
local json = require('luci.jsonc')
local path = '/etc/board.json'
local data = json.parse(fs.readfile(path) or '') or {}
if type(data.model) ~= 'table' then
  data.model = { id = data.model or 'xiaomi,mi-router-ax3000t-ubootmod' }
end
data.model.name = 'JuLiang OS'
assert(fs.writefile(path .. '.juliang', json.stringify(data)))
assert(fs.rename(path .. '.juliang', path))
