#!/bin/sh
set -eu

ROOT="${1:-/}"
[ "$ROOT" = "/" ] || ROOT="${ROOT%/}"
PFX="$ROOT"
[ "$PFX" = "/" ] && PFX=""

CTRL="$PFX/usr/lib/lua/luci/controller/fastacl252.lua"
VIEW="$PFX/usr/lib/lua/luci/view/fastacl252/console.htm"
CORE="$PFX/usr/bin/fastacl252"

for f in "$CTRL" "$VIEW" "$CORE"; do
  [ -f "$f" ] || { echo "[FAIL] missing: $f" >&2; exit 1; }
done

STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
BACKUP="$PFX/root/fastacl252-hotfix6-fast-switch-backup-$STAMP"
if [ -z "$PFX" ]; then BACKUP="/root/fastacl252-hotfix6-fast-switch-backup-$STAMP"; fi
mkdir -p "$BACKUP"
cp -af "$CTRL" "$VIEW" "$CORE" "$BACKUP/"
echo "[OK] backup: $BACKUP"

ROOT="$PFX" lua <<'LUA'
local root=os.getenv('ROOT') or ''
local ctrl=root..'/usr/lib/lua/luci/controller/fastacl252.lua'
local view=root..'/usr/lib/lua/luci/view/fastacl252/console.htm'
local core=root..'/usr/bin/fastacl252'

local function read(path)
  local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close(); return s
end
local function write(path,s)
  local tmp=path..'.hotfix6.tmp'
  local f=assert(io.open(tmp,'wb')); assert(f:write(s)); f:close()
  assert(os.rename(tmp,path))
end
local function swap(path, old, new, marker, label)
  local s=read(path)
  if marker and s:find(marker,1,true) then
    io.stdout:write('[SKIP] '..label..' already installed\n')
    return
  end
  local a,b=s:find(old,1,true)
  assert(a, 'HOTFIX-6 marker not found for '..label..' in '..path)
  s=s:sub(1,a-1)..new..s:sub(b+1)
  write(path,s)
  io.stdout:write('[OK] '..label..'\n')
end

local old_apply=[=[local function apply_async()
  local fs=require 'nixio.fs'; local sys=require 'luci.sys'
  fs.mkdir('/tmp/fastacl252')
  fs.writefile('/tmp/fastacl252/apply.result','pending')
  sys.call("( /usr/bin/fastacl252 apply > /tmp/fastacl252/apply.log 2>&1; rc=$?; echo $rc > /tmp/fastacl252/apply.result ) </dev/null >/dev/null 2>&1 &")
end]=]
local new_apply=[=[local function apply_async()
  local fs=require 'nixio.fs'; local sys=require 'luci.sys'
  fs.mkdir('/tmp/fastacl252')
  fs.writefile('/tmp/fastacl252/apply.result','pending')
  fs.writefile('/tmp/fastacl252/apply.log','')
  fs.writefile('/tmp/fastacl252/ui-apply.pending',tostring(os.time()))
  sys.call([[(
    i=0
    while [ -d /tmp/fastacl252-apply.lock ] && [ "$i" -lt 6 ]; do i=$((i+1)); sleep 1; done
    if [ -d /tmp/fastacl252-apply.lock ]; then
      echo '等待上一次 FastACL 应用结束超时' > /tmp/fastacl252/apply.log
      echo 75 > /tmp/fastacl252/apply.result
      rm -f /tmp/fastacl252/ui-apply.pending
      exit 0
    fi
    /usr/bin/fastacl252 apply > /tmp/fastacl252/apply.log 2>&1
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q 'Another apply is running' /tmp/fastacl252/apply.log 2>/dev/null; then
      sleep 1
      /usr/bin/fastacl252 apply > /tmp/fastacl252/apply.log 2>&1
      rc=$?
    fi
    echo "$rc" > /tmp/fastacl252/apply.result
    rm -f /tmp/fastacl252/ui-apply.pending
  ) </dev/null >/dev/null 2>&1 &]])
end]=]
swap(ctrl,old_apply,new_apply,'ui-apply.pending','queued apply / lock retry')

local old_reply="  reply({ok=true,version='2.5.2-dev.2'"
local new_reply="  local joblog=fs.readfile('/tmp/fastacl252/apply.log') or ''\n  if #joblog>2000 then joblog=joblog:sub(-2000) end\n  reply({ok=true,version='2.5.2-hotfix.6'"
swap(ctrl,old_reply,new_reply,'local joblog=fs.readfile','status apply log')

local old_job="job=fs.readfile('/tmp/fastacl252/apply.result'),subscription_running="
local new_job="job=fs.readfile('/tmp/fastacl252/apply.result'),job_log=joblog,apply_pending=fs.access('/tmp/fastacl252/ui-apply.pending') or false,subscription_running="
swap(ctrl,old_job,new_job,'job_log=joblog','status apply details')

local old_store="async function store(data){if(busy)return;busy=true;try{const j=await api('save',{data:JSON.stringify(data)});message(j.message||'已保存');await load();if(state.enabled)pollJob();}catch(e){message(e.message,true);}finally{busy=false;}}"
local new_store="async function store(data){if(busy)return;busy=true;try{await api('save',{data:JSON.stringify(data)});message('配置已保存，正在切换节点…');await load();if(state.enabled)await pollJob();else message('配置已保存。');}catch(e){message(e.message,true);}finally{busy=false;}}"
swap(view,old_store,new_store,"配置已保存，正在切换节点",'device switch waits for result')

local old_wifi="async function wifiAction(data){if(busy)return;busy=true;try{const j=await api('wifi',{data:JSON.stringify(data)});message(j.message||'WiFi 已保存');await load();if(state.enabled)pollJob();}catch(e){message(e.message,true);}finally{busy=false;}}"
local new_wifi="async function wifiAction(data){if(busy)return;busy=true;try{const j=await api('wifi',{data:JSON.stringify(data)});message(j.message||'WiFi 已保存，正在应用…');await load();if(state.enabled)await pollJob();}catch(e){message(e.message,true);}finally{busy=false;}}"
swap(view,old_wifi,new_wifi,'WiFi 已保存，正在应用','WiFi switch waits for result')

local old_poll="async function pollJob(){for(let i=0;i<75;i++){await new Promise(r=>setTimeout(r,1000));try{const j=await api('status');if(j.job&&j.job.trim()!=='pending'){message(j.job.trim()==='0'?'配置已应用。':'配置已保存，但 dae 应用失败；代理流量保持断网保护。',j.job.trim()!=='0');state=j;render();return;}}catch(e){message(e.message,true);return;}}message('应用仍在进行，请稍后刷新。',true);}"
local new_poll="async function pollJob(){for(let i=0;i<30;i++){await new Promise(r=>setTimeout(r,500));try{const j=await api('status');const job=(j.job||'').trim();if(job&&job!=='pending'){const ok=job==='0',detail=(j.job_log||'').trim();message(ok?'节点切换成功，配置已生效。':'节点切换失败（RC='+job+'）。'+(detail?'\\n'+detail:'\\n代理流量保持断网保护。'),!ok);state=j;render();return ok;}if(i===3||i===11||i===21)message('正在切换节点… '+Math.ceil((i+1)/2)+' 秒');}catch(e){message(e.message,true);return false;}}message('切换超过 15 秒，页面已停止等待；后台不会继续卡住。请点“刷新”查看状态。',true);return false;}"
swap(view,old_poll,new_poll,'节点切换失败（RC=','15-second UI result')

local old_guard=[=[  guard)
    while [ "$(uci -q get fastacl252.main.enabled)" = 1 ]; do
      /usr/bin/fastacl252 apply >"$R/guard.log" 2>&1 || true
      if [ ! -d /tmp/fastacl252-subscribe.lock ]; then lua /usr/libexec/fastacl252-subscribe.lua due >"$R/subscribe.log" 2>&1 & fi
      sleep 15
    done;;]=]
local new_guard=[=[  guard)
    while [ "$(uci -q get fastacl252.main.enabled)" = 1 ]; do
      job="$(cat "$R/apply.result" 2>/dev/null || true)"
      [ "$job" = pending ] || rm -f "$R/ui-apply.pending"
      if [ ! -e "$R/ui-apply.pending" ]; then
        port="$(uci -q get fastacl252.main.port)"
        if ! alive || ! dns_alive || ! ip netns exec daens ss -lntu 2>/dev/null | grep -q ":$port "; then
          /usr/bin/fastacl252 apply >"$R/guard.log" 2>&1 || true
        fi
      fi
      if [ ! -d /tmp/fastacl252-subscribe.lock ]; then lua /usr/libexec/fastacl252-subscribe.lua due >"$R/subscribe.log" 2>&1 & fi
      sleep 15
    done;;]=]
swap(core,old_guard,new_guard,'ui-apply.pending','guardian no longer races normal switches')
LUA

chmod 0755 "$CORE"
chmod 0644 "$CTRL" "$VIEW"

sh -n "$CORE"
lua -e "assert(loadfile('$CTRL'))"

grep -q '2.5.2-hotfix.6' "$CTRL"
grep -q '节点切换失败（RC=' "$VIEW"
grep -q 'ui-apply.pending' "$CORE"

echo '[OK] HOTFIX-6 source patch validation passed'

if [ -z "${FASTACL252_BOOT:-}" ] && [ -z "$PFX" ]; then
  rm -f /tmp/luci-indexcache
  rm -rf /tmp/luci-modulecache/* 2>/dev/null || true

  # Do not stop dae/DNS. Only recycle the guardian shell so the new no-race loop is loaded.
  for pid in $(ps w 2>/dev/null | awk '/[f]astacl252 guard/ {print $1}'); do kill "$pid" 2>/dev/null || true; done
  sleep 1
  /etc/init.d/fastacl252 start >/dev/null 2>&1 || true

  # Reload LuCI controller/view code. Existing proxy runtime remains untouched.
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  echo '[OK] LuCI cache/reload complete; dae runtime was not stopped'
  echo '[INFO] browser: Ctrl+F5, then switch one device node again'
  /usr/bin/fastacl252 status 2>/dev/null || true
fi

echo "[DONE] FastACL 2.5.2 HOTFIX-6 fast switch installed"
