-- Hide unneeded menu trees without changing the underlying NAS services.
local fs=require'nixio.fs';local json=require'luci.jsonc'
for name in fs.dir('/usr/share/luci/menu.d') do
 if name:match('%.json$') then
  local path='/usr/share/luci/menu.d/'..name;local obj=json.parse(fs.readfile(path) or '');local changed=false
  if type(obj)=='table' then
   for k in pairs(obj) do if k=='admin/nas' or k:match('^admin/nas/') or k=='admin/statistics' or k:match('^admin/statistics/') then obj[k]=nil;changed=true end end
   if changed then fs.writefile(path,next(obj) and json.stringify(obj) or '{}');fs.chmod(path,'644') end
  end
 end
end
fs.remove('/tmp/luci-indexcache')
