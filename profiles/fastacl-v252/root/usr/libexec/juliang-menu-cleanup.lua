-- Hide unneeded menu trees without changing the underlying NAS services.
local fs=require'nixio.fs';local json=require'luci.jsonc'
for name in fs.dir('/usr/share/luci/menu.d') do
 if name:match('%.json$') then
  local path='/usr/share/luci/menu.d/'..name;local obj=json.parse(fs.readfile(path) or '');local changed=false
  if type(obj)=='table' then
   for k in pairs(obj) do if k=='admin/nas' or k:match('^admin/nas/') or k=='admin/statistics' or k:match('^admin/statistics/') then obj[k]=nil;changed=true end end
   if obj['admin/services'] then obj['admin/services'].title=nil;changed=true end
   for _,key in ipairs({'admin/services/ddns','admin/services/wol','admin/services/ksmbd'}) do
    if obj[key] then obj[key].title=nil;changed=true end
   end
   if obj['admin/services/upnp'] then
    obj['admin/network/upnp']=obj['admin/services/upnp'];obj['admin/services/upnp']=nil
    obj['admin/network/upnp'].order=75;changed=true
   end
   if changed then fs.writefile(path,next(obj) and json.stringify(obj) or '{}');fs.chmod(path,'644') end
  end
 end
end
-- Preserve the installed NPS package/service, changing only its LuCI routes.
local nps='/usr/lib/lua/luci/controller/nps.lua'
if fs.access(nps) then
 local controller=assert(fs.readfile('/usr/libexec/juliang-nps-controller.lua'),'Missing NPS menu payload')
 assert(fs.writefile(nps,controller),'Cannot relocate NPS menu');fs.chmod(nps,'644')
end
fs.remove('/tmp/luci-indexcache')

-- LuCI caches menus per login in sessionStorage, independently of server caches.
-- Invalidate only that menu once when this UI revision is first loaded.
local marker='juliang-menu-revision'
local script=[=[<script id="juliang-menu-revision">(function(){try{var k='luci-session-store',d=JSON.parse(sessionStorage.getItem(k)||'{}'),r='267-management-1';for(var s in d){if(d[s]&&typeof d[s]==='object'&&d[s].juliangMenuRevision!==r){delete d[s].menu;d[s].juliangMenuRevision=r}}sessionStorage.setItem(k,JSON.stringify(d))}catch(e){}})();</script>]=]
local brand_css=[=[<style id="juliang-brand-gradient">
#mainmenu .sidenav-header .juliang-brand-card{display:flex!important;flex:0 1 188px;flex-direction:column;align-items:stretch;justify-content:center;box-sizing:border-box;width:188px;min-width:0;max-width:calc(100% - 54px);margin:10px 0 10px 8px;padding:10px 14px 11px;overflow:hidden;color:#fff!important;text-decoration:none;border:1px solid rgba(255,255,255,.62);border-radius:10px;background:radial-gradient(circle at 8% 0%,rgba(255,255,255,.32),rgba(255,255,255,0) 44%),linear-gradient(132deg,#1769e0 0%,#2497ea 45%,#2cbdb3 72%,#7b79e8 100%);box-shadow:inset 0 1px 0 rgba(255,255,255,.38),0 7px 18px rgba(31,91,166,.2)}
#mainmenu .sidenav-header .juliang-brand-card>.juliang-brand-name{display:block;width:100%;white-space:nowrap;text-align:center;color:inherit!important;letter-spacing:0;text-shadow:0 1px 3px rgba(7,42,91,.26)}
#mainmenu .sidenav-header .juliang-brand-card>.juliang-brand-name:first-child{line-height:1.2;font-weight:700}
#mainmenu .sidenav-header .juliang-brand-card>.juliang-brand-name:last-child{line-height:1.4}
@media(forced-colors:active){ #mainmenu .sidenav-header .juliang-brand-card{color:CanvasText!important;background:Canvas;border-color:CanvasText;box-shadow:none}}
</style>]=]
for _,path in ipairs({'/usr/share/ucode/luci/template/themes/argon/header.ut','/usr/lib/lua/luci/view/themes/argon/header.htm'}) do
 local text=fs.readfile(path)
 if text then
  text=text:gsub('JuLtiang','JuLiang')
  -- Keep the brand on two deliberate lines at every sidebar width.
  local brand='<span class="juliang-brand-name">JuLiang</span><span class="juliang-brand-name">网络服务</span>'
  for _,label in ipairs({'控制中心','监测中心','网络服务','控制面板'}) do
   text=text:gsub('>JuLiang%s*'..label..'</a>', '>'..brand..'</a>')
   text=text:gsub('><span[^>]*>JuLiang</span><span[^>]*>'..label..'</span></a>', '>'..brand..'</a>')
  end
  text=text:gsub('(<a class="brand)(")', '%1 juliang-brand-card%2')
  text=text:gsub('<script id="juliang%-menu%-revision">.-</script>','')
  text=text:gsub('<style id="juliang%-brand%-gradient">[%s%S]-</style>','')
  local updated,n=text:gsub('<head>',function() return '<head>\n'..script end,1)
  if n>0 then
   updated,n=updated:gsub('<head>',function() return '<head>\n'..brand_css end,1)
   assert(n>0,'Cannot locate theme head')
   assert(fs.writefile(path,updated));fs.chmod(path,'644')
  end
 end
end
for path in fs.glob('/tmp/luci-indexcache*') do fs.remove(path) end

-- Persist footer visibility after theme migration.
local fs=require'nixio.fs'
local css='<style id="juliang-hide-footer">footer .footer-content{display:none!important}</style>'
for _,p in ipairs({'/usr/share/ucode/luci/template/themes/argon/header.ut','/usr/lib/lua/luci/view/themes/argon/header.htm'})do
 local s=fs.readfile(p)
 if s then
  if not fs.access(p..'.before-hide-footer') then assert(fs.writefile(p..'.before-hide-footer',s));fs.chmod(p..'.before-hide-footer','600') end
  s=s:gsub('<style id="juliang%-hide%-footer">.-</style>','')
  local t,n=s:gsub('<head>',function()return '<head>\n'..css end,1);assert(n==1,'Cannot locate theme head')
  assert(fs.writefile(p..'.new',t));fs.chmod(p..'.new','644');assert(fs.rename(p..'.new',p))
 end
end
