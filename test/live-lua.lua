-- Actual LuaSocket/LuaSec transport test. No token is printed or put in argv.
package.path = arg[1] .. "/share/lua/5.1/?.lua;" .. package.path
package.cpath = arg[1] .. "/lib/lua/5.1/?.so;" .. package.cpath
local file = assert(io.open(arg[2], "rb")); local raw = file:read("*a"); file:close()
local config = {
    host = assert(raw:match('"host"%s*:%s*"([%w%.%-]+)"')),
    port = assert(tonumber(raw:match('"port"%s*:%s*(%d+)'))),
    token = assert(raw:match('"token"%s*:%s*"([a-f0-9]+)"')),
    fingerprint = assert(raw:match('"fingerprint"%s*:%s*"([a-f0-9]+)"')),
}
local transport = dofile(arg[3])
if arg[4] then config.host = "127.0.0.1"; config.port = tonumber(arg[4]) end
if arg[5] == "wrong-server" then
    local ok, err = pcall(transport.request, config, "GET", "/v1/state")
    assert(not ok and tostring(err):find("certificate mismatch"))
    print("Real LuaSec rejected a different certificate before HTTP")
    return
end
if arg[5] == "recognize" then
    local source=assert(io.open(arg[6],"rb"));local ink=source:read("*a");source:close()
    local started=transport.request(config,"POST","/v1/recognize",ink)
    assert(started.status==200)
    local id=assert(started.body:match('"jobId"%s*:%s*"([%w%-]+)"'))
    local complete=false
    for _=1,100 do
        local state=transport.request(config,"GET","/v1/recognize")
        assert(state.status==200 and state.body:find(id,1,true))
        if state.body:match('"status"%s*:%s*"complete"') then
            assert(state.body:match('"text"%s*:%s*"HELLO"'));complete=true;break
        end
        assert(not state.body:match('"status"%s*:%s*"failed"'))
        require("socket").sleep(0.1)
    end
    assert(complete)
    print("Real Lua transport: encrypted pen strokes → Mac-local OCR → HELLO draft")
    return
end
local response = transport.request(config, "GET", "/v1/state")
assert(response.status == 200)
config.token = string.rep("c", 64)
local rejected = transport.request(config, "POST", "/v1/prompt",
    '{"text":"KOBO_SYNTHETIC_WIRE_CANARY_948213","requestId":"wire-audit-001"}')
assert(rejected.status == 401)
config.fingerprint = string.rep("f", 64)
local ok, err = pcall(transport.request, config, "GET", "/v1/state")
assert(not ok and tostring(err):find("certificate mismatch"))
assert(require("ssl")._VERSION == "1.3.2")
print("Real LuaSec 1.3.2: pinned TLS, authenticated state, rejected token and mismatched pin passed")
