from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime()
original='<div class="login-page" data-login-style="{{ login_style }}"><a class="brand"><span class="brand-text">{{ hostname }}</span></a></div>'
login_form='<form method="post" action="{{ http.getenv(\"REQUEST_URI\") }}"><input name="luci_username" value="{{ entityencode(duser, true) }}"><input name="luci_password" type="password"></form>'
path='/usr/share/ucode/luci/template/themes/argon/sysauth.ut';form_path='/usr/share/ucode/luci/template/themes/argon/login_form.ut';files={path:original,form_path:login_form}
lua.globals().read=lambda p:files.get(p)
lua.globals().write=lambda p,s:files.__setitem__(p,s) or True
lua.globals().exists=lambda p:p in files
lua.globals().rename=lambda a,b:files.__setitem__(b,files.pop(a)) or True
lua.execute("package.loaded['nixio.fs']={readfile=read,writefile=write,access=exists,rename=rename,chmod=function()end}")
script=(ROOT/'root/usr/libexec/juliang-login-theme.lua').read_text(encoding='utf-8')
lua.execute(script);after=files.copy();lua.execute(script);assert files==after
changed=files[path];form=files[form_path]
assert changed.count('id="juliang-login-style"')==1 and 'JuLiang 网络服务' in changed
assert 'class="login-page juliang-login"' in changed
assert form==login_form.replace('value="{{ entityencode(duser, true) }}"','value=""')
assert 'name="luci_username" value=""' in form
assert files[path+'.before-juliang-login']==original
css=(ROOT/'root/www/luci-static/argon/css/juliang-login.css').read_text(encoding='utf-8')
assert '.login-form .brand{' in css and 'linear-gradient(135deg,#eaf3ff' in css
print('PASS login theme idempotence and blank username and unchanged authentication handler')
