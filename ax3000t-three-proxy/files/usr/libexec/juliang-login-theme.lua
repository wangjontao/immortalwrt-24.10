#!/usr/bin/lua
local fs = require('nixio.fs')
local link = '<link id="juliang-login-style" rel="stylesheet" href="/luci-static/argon/css/juliang-login.css?v=juliang-live-1">'
local fields = [=[<script id="juliang-login-fields">(function(){var u=document.querySelector('input[name="luci_username"]'),p=document.querySelector('input[name="luci_password"]');if(u)u.placeholder='请输入用户名';if(p)p.placeholder='请输入密码'})();</script>]=]

for _, path in ipairs({
  '/usr/share/ucode/luci/template/themes/argon/sysauth.ut',
  '/usr/lib/lua/luci/view/themes/argon/sysauth.htm'
}) do
  local original = fs.readfile(path)
  if original then
    local text = original:gsub('class="login%-page"', 'class="login-page juliang-login"', 1)
    text = text:gsub('(<span class="brand%-text">)[^<]*(</span>)', '%1JuLiang 网络服务%2', 1)
    text = text:gsub('<script id="juliang%-login%-fields">.-</script>', '')
    if not text:find('id="juliang-login-style"', 1, true) then
      text = text:gsub('(<div class="login%-page[^"]*">)', function(tag)
        return link .. '\n' .. tag
      end, 1)
    end
    text = text:gsub('</form>', '</form>\n' .. fields, 1)
    assert(text:find('id="juliang-login-style"', 1, true), 'Cannot locate Argon login container')
    assert(text:find('JuLiang 网络服务', 1, true), 'Cannot locate Argon brand text')
    assert(text:find('id="juliang-login-fields"', 1, true), 'Cannot locate Argon login form')
    if text ~= original then
      local backup = path .. '.before-juliang-login'
      if not fs.access(backup) then
        assert(fs.writefile(backup, original))
        fs.chmod(backup, '600')
      end
      assert(fs.writefile(path .. '.juliang-new', text))
      fs.chmod(path .. '.juliang-new', '644')
      assert(fs.rename(path .. '.juliang-new', path), 'Cannot install JuLiang login template')
    end
  end
end
