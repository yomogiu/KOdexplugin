-- TLS 1.2 with an out-of-band SHA-256 certificate pin, checked BEFORE
-- sending HTTP headers or the device token. No redirects, shell, or plaintext.
local Transport = {}
local function normalize(s) return (s:gsub(":", ""):lower()) end

function Transport.request(config, method, path, body)
    assert(type(config) == "table", "Missing connection.json")
    assert(type(config.host) == "string" and config.host:match("^[%w][%w%.%-]*$"), "Invalid host")
    assert(type(config.port) == "number" and config.port % 1 == 0 and config.port > 0 and config.port < 65536, "Invalid port")
    assert(type(config.token) == "string" and #config.token == 64 and config.token:match("^[a-f0-9]+$"), "Invalid device token")
    assert(type(config.fingerprint) == "string" and #config.fingerprint == 64 and config.fingerprint:match("^[a-f0-9]+$"), "Invalid certificate pin")
    assert((method == "GET" and (path == "/v1/state" or path == "/v1/recognize")) or
        (method == "POST" and (path == "/v1/prompt" or path == "/v1/stop" or path == "/v1/reset" or path == "/v1/recognize")), "Invalid operation")
    body = body or ""
    assert(#body <= (path == "/v1/recognize" and 800000 or 70000), "Request is too large")
    local socket = require("socket")
    local ssl = require("ssl")
    local conn
    local ok, result = pcall(function()
        conn = assert(socket.tcp())
        conn:settimeout(3)
        assert(conn:connect(config.host, config.port))
        -- Trust is the exact USB-installed certificate pin, not the CA store.
        conn = assert(ssl.wrap(conn, { mode = "client", protocol = "tlsv1_2", verify = "none", options = "all",
            ciphers = "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384" }))
        conn:settimeout(3)
        assert(conn:dohandshake())
        local cert = assert(conn:getpeercertificate(), "Missing server certificate")
        local digest = normalize(assert(cert:digest("sha256"), "SHA-256 certificate pinning is unavailable"))
        assert(digest == config.fingerprint, "Server certificate mismatch. No token or prompt was sent.")
        -- Nothing application-level has been transmitted before this point.
        local request = method .. " " .. path .. " HTTP/1.1\r\nHost: " .. config.host .. ":" .. config.port ..
            "\r\nAuthorization: Bearer " .. config.token .. "\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
        local deadline = socket.gettime() + 8
        local function budget()
            local remaining = deadline - socket.gettime()
            assert(remaining > 0, "Bridge request timed out")
            conn:settimeout(math.min(3, remaining))
        end
        local i = 1
        while i <= #request do
            budget()
            local last = assert(conn:send(request, i))
            assert(last >= i, "Incomplete send")
            i = last + 1
        end
        local header_bytes = 0
        local function line()
            local chars = {}
            while true do
                budget()
                local ch = assert(conn:receive(1))
                header_bytes = header_bytes + 1
                assert(header_bytes <= 8192, "Response headers too large")
                if ch == "\n" then return table.concat(chars):gsub("\r$", "") end
                chars[#chars + 1] = ch
            end
        end
        local status = tonumber(line():match("^HTTP/1%.[01] (%d%d%d)"))
        assert(status, "Invalid HTTP response")
        local headers = {}
        while true do
            local s = line()
            if s == "" then break end
            local k, v = s:match("^([^:]+):%s*(.-)%s*$")
            assert(k and not headers[k:lower()], "Invalid or duplicate response header")
            headers[k:lower()] = v
        end
        assert(not headers["transfer-encoding"], "Unexpected transfer encoding")
        local len = tonumber(headers["content-length"])
        assert(len and len >= 0 and len % 1 == 0 and len <= 3000000, "Invalid response size")
        local chunks, size = {}, 0
        while size < len do
            budget()
            local chunk = assert(conn:receive(math.min(8192, len - size)))
            size = size + #chunk; chunks[#chunks + 1] = chunk
        end
        return { status = status, body = table.concat(chunks) }
    end)
    if conn then pcall(function() conn:close() end) end
    if not ok then error(result, 0) end
    return result
end
return Transport
