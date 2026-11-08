-- Run blocking transport in a KOReader subprocess. No modal widgets, shell,
-- temporary files, or network work in the UI process. Pipe reads are bounded
-- to bytes already available, so a slow or stuck child cannot block input.
local Background = {}
local MAX_RESULT = 3100000
local READ_BUDGET = 65536

function Background.run(task, callback)
    local UIManager = require("ui/uimanager")
    local util = require("ffi/util")
    local ffi = require("ffi")
    local buffer = require("string.buffer")
    local deadline = util.getTimestamp() + 20
    local pid, fd = util.runInSubProcess(function(_, write_fd)
        local ok, value = pcall(task)
        local output = buffer.encode({ ok, ok and value or tostring(value) })
        if #output > MAX_RESULT then
            output = buffer.encode({ false, "Bridge response is too large" })
        end
        local ptr = ffi.cast("const char*", output)
        local sent = 0
        while sent < #output do
            local n = tonumber(ffi.C.write(write_fd, ptr + sent, #output - sent))
            if n <= 0 then break end
            sent = sent + n
        end
        ffi.C.close(write_fd)
    end, true)
    if not pid then error("Cannot start bridge worker: " .. tostring(fd)) end

    local job = { pid = pid, fd = fd, chunks = {}, size = 0 }
    local scratch = ffi.new("char[?]", READ_BUDGET)
    UIManager:preventStandby()
    local function reap()
        if not util.isSubProcessDone(pid) then UIManager:scheduleIn(0.25, reap) end
    end
    local function finish(ok, value, terminate)
        if job.finished then return end
        job.finished = true
        UIManager:unschedule(job.collect)
        if terminate then util.terminateSubProcess(pid); reap() end
        if job.fd then ffi.C.close(job.fd); job.fd = nil end
        job.chunks = nil
        UIManager:allowStandby()
        if callback then callback(ok, value) end
    end
    function job:cancel()
        -- Caller owns the UI state for an abandoned request.
        callback = nil
        finish(false, "Cancelled", true)
    end
    job.collect = function()
        if util.getTimestamp() >= deadline then
            finish(false, "Bridge request timed out. Your draft was kept.", true); return
        end
        local available = util.getNonBlockingReadSize(job.fd)
        if available == nil then
            finish(false, "Non-blocking pipe reads are unavailable", true); return
        end
        if available > 0 then
            local n = tonumber(ffi.C.read(job.fd, scratch, math.min(available, READ_BUDGET)))
            if n <= 0 then finish(false, "Cannot read bridge worker result", true); return end
            job.size = job.size + n
            if job.size > MAX_RESULT then finish(false, "Bridge response is too large", true); return end
            job.chunks[#job.chunks + 1] = ffi.string(scratch, n)
        end
        -- A child may block writing a large result: drain it over several UI
        -- ticks, and never call readAllFromFD (which waits for EOF).
        if util.isSubProcessDone(pid) and util.getNonBlockingReadSize(job.fd) == 0 then
            local ok, result = pcall(buffer.decode, table.concat(job.chunks))
            if not ok or type(result) ~= "table" or type(result[1]) ~= "boolean" then
                finish(false, "Bridge worker exited without a valid result")
            else
                finish(result[1], result[2])
            end
            return
        end
        UIManager:scheduleIn(0.05, job.collect)
    end
    UIManager:scheduleIn(0.05, job.collect)
    return job
end

return Background
