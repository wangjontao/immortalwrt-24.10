"""Exercise the current DNS control client without a router socket."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "root/usr/libexec/fastacl252-control.lua"
).read_text(encoding="utf-8")


def run(operation="dns", path="/tmp/fastacl-dns", connected=True, response='{"ok":true,"revision":7}\n'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().arg = lua.table_from({1: operation, 2: path})
    lua.globals().connected = connected
    lua.globals().response = response
    lua.globals().printed = ""
    lua.globals().stderr = ""
    lua.globals().closed = False
    lua.globals().sent = ""
    lua.globals().connected_path = ""
    lua.execute(
        """
package.loaded['luci.jsonc'] = {
 parse = function(value)
  if value:find('"ok"%s*:%s*true') then return {ok=true,revision=7} end
  return {ok=false,error='rejected'}
 end
}
package.loaded['nixio.fs'] = {}
local sock = {}
function sock:setopt() return true end
function sock:connect(path) connected_path=path; return connected end
function sock:send(value) sent=value; return #value end
function sock:recv() local value=response; response=''; return value end
function sock:close() closed=true end
package.loaded.nixio = {socket=function() return sock end}
os.exit = function(code) error('EXIT:'..code,0) end
print = function(value) printed=value end
io.stderr = {write=function(_,value) stderr=stderr..value end}
"""
    )
    try:
        lua.execute(SOURCE)
        code = 0
    except Exception as exc:
        assert "EXIT:" in str(exc), exc
        code = int(str(exc).split("EXIT:", 1)[1].split()[0])
    return {
        "code": code,
        "printed": lua.globals().printed,
        "stderr": lua.globals().stderr,
        "closed": lua.globals().closed,
        "sent": lua.globals().sent,
        "connected_path": lua.globals().connected_path,
    }


ok = run()
assert ok["code"] == 0
assert ok["connected_path"] == "/tmp/fastacl-dns.sock"
assert ok["sent"] == "reload\n" and ok["closed"] is True
assert ok["printed"] == "DNS configuration reloaded 7"

unavailable = run(connected=False)
assert unavailable["code"] == 1 and "DNS control unavailable" in unavailable["stderr"]
rejected = run(response='{"ok":false,"error":"bad config"}\n')
assert rejected["code"] == 2 and "DNS reload rejected" in rejected["stderr"]
assert run(path="relative")["code"] == 1
assert run(operation="unknown")["code"] == 1
print("PASS current DNS control success, connect failure, rejection and action validation")
