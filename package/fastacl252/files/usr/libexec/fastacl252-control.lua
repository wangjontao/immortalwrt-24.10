-- Lightweight client for the DNS helper control protocol.
local nx=require'nixio'
local fs=require'nixio.fs'
local function fail(message,code) io.stderr:write(message..'\n');os.exit(code or 1) end
local function dns(file)
 if not file or file:sub(1,1)~='/' then fail('Invalid DNS configuration path') end
 local sock=assert(nx.socket('unix','stream'))
 sock:setopt('socket','sndtimeo',5);sock:setopt('socket','rcvtimeo',5)
 if not sock:connect(file..'.sock') then sock:close();fail('DNS control unavailable') end
 if sock:send('reload\n')~=7 then sock:close();fail('DNS control request failed') end
 local data=''
 while #data<8192 and not data:find('\n',1,true) do
  local chunk=sock:recv(8192-#data);if not chunk or chunk=='' then break end
  data=data..chunk
 end
 sock:close()
 local result=require('luci.jsonc').parse(data)
 if type(result)~='table' or result.ok~=true then fail('DNS reload rejected',2) end
 print('DNS configuration reloaded '..tostring(result.revision or ''))
end
if arg[1]=='dns' then dns(arg[2]) else fail('Unknown control operation') end
