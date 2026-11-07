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
print("Lua transport checks passed: pin-before-token, partial sends, bounds, no redirects, endpoint allowlist")
