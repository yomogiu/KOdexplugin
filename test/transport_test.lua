-- Unit tests for the actual Lua transport, with deterministic socket/TLS doubles.
local sent, closed, pin = "", false, string.rep("a", 64)
local response, offset
local clock = 0
local conn = {}
function conn:settimeout() end
function conn:connect() return true end
function conn:dohandshake() return true end
function conn:getpeercertificate() return { digest = function(_, algo) assert(algo == "sha256"); return pin end } end
function conn:send(s, first)
    local last = math.min(first + 6, #s) -- exercise partial sends
    sent = sent .. s:sub(first, last); return last
end
function conn:receive(n)
    if offset + n - 1 > #response then return nil, "closed" end
    local s = response:sub(offset, offset + n - 1); offset = offset + n; return s
end
function conn:close() closed = true end
package.preload.socket = function() return { tcp = function() return conn end, gettime = function() clock = clock + 0.00001; return clock end } end
package.preload.ssl = function() return { wrap = function(c, opts) assert(opts.protocol == "tlsv1_2"); return c end } end
local transport = dofile("kobocodex.koplugin/transport.lua")
local config = { host = "192.168.1.10", port = 9443, token = string.rep("b", 64), fingerprint = string.rep("a", 64) }
local function reset(payload)
    response = payload or 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}'
    offset = 1; sent = ""; closed = false; clock = 0
end
reset()
local r = transport.request(config, "GET", "/v1/state")
assert(r.status == 200 and r.body == "{}" and closed)
assert(sent:find("Authorization: Bearer " .. config.token, 1, true))
reset(); pin = string.rep("c", 64)
local ok, err = pcall(transport.request, config, "POST", "/v1/prompt", '{"text":"private"}')
assert(not ok and tostring(err):find("certificate mismatch") and sent == "" and closed)
pin = config.fingerprint
for _, payload in ipairs({
    'HTTP/1.1 302 Found\r\nLocation: http://evil/\r\n\r\n',
    'HTTP/1.1 200 OK\r\nContent-Length: 999999999\r\n\r\n',
    'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n{}',
    'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}',
}) do
    reset(payload); assert(not pcall(transport.request, config, "GET", "/v1/state")); assert(closed)
end
reset(); assert(not pcall(transport.request, config, "POST", "/command/exec", "{}")); assert(sent == "")
local id=string.rep('a',32)
for _,operation in ipairs({'state','prompt','stop','reset','history','reopen'})do
    reset()
    local path='/v1/documents/'..id..'/'..operation
    local method=(operation=='state'or operation=='history')and'GET'or'POST'
    assert(transport.request(config,method,path,'{}').status==200)
    assert(sent:find(method..' '..path..' HTTP/1.1',1,true)and closed)
end
for _,path in ipairs({'/v1/documents/'..id..'/recognize','/v1/documents/'..id..'/state?file=book',
    '/v1/documents/'..id..'a/state','/v1/documents/'..string.rep('A',32)..'/state',
    '/v1/documents/../../book/state','/v1/documents/'..id..'/exec'})do
    reset();assert(not pcall(transport.request,config,'GET',path));assert(sent==''and not closed)
end
for _,bad in ipairs({{'POST','/v1/documents/'..id..'/history'},{'GET','/v1/documents/'..id..'/reopen'},{'GET','/v1/history'},{'POST','/v1/reopen'}})do
    reset();assert(not pcall(transport.request,config,bad[1],bad[2],'{}'));assert(sent=='')
end
reset();pin=string.rep('c',64)
assert(not pcall(transport.request,config,'POST','/v1/documents/'..id..'/prompt','{}')and sent==''and closed)
pin=config.fingerprint
print("Lua transport checks passed: pin-before-token, partial sends, bounds, no redirects, endpoint allowlist")
reset()
transport.request(config,'GET','/v1/state',nil,'revision-1',true)
assert(sent:find('\r\nX-Kodex-Wait: 1\r\n',1,true))
assert(sent:find('\r\nX-Kodex-Revision: revision-1\r\n',1,true))
reset()
assert(not pcall(transport.request,config,'POST','/v1/prompt','{}','revision-1',true))
assert(sent=='')
print('Long-poll transport checks passed: explicit state-only wait header')
