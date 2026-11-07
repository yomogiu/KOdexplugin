-- Local display troubleshooting only. Never read draft, transcript, strokes,
-- connection settings, or network APIs. At most two control rows per phase.
local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local json = require("json")
local lfs = require("lfs")
local directory = debug.getinfo(1,"S").source:sub(2):match("^(.*)/[^/]+$").."/display-diagnostics"
local Diagnostics = {}

local function rect(value)
    if type(value) ~= "table" then return end
    local out = {}
    for _, key in ipairs({"x", "y", "w", "h"}) do
        local n = value[key]
        if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n ~= math.floor(n) then return end
        out[key] = n
    end
    if out.w <= 0 or out.h <= 0 then return end
    return out
end
local function overlaps(a,b)
    return a.x < b.x+b.w and b.x < a.x+a.w and a.y < b.y+b.h and b.y < a.y+a.h
end

function Diagnostics.capture(panel, phase)
    if phase ~= "before-clear" and phase ~= "after-clear" then return false end
    if panel.dismissed or not panel.pen_mode then return false end
    if UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget() ~= panel then return false end
    return pcall(function()
        lfs.mkdir(directory)
        local width,height = Screen:getWidth(),Screen:getHeight()
        local metadata = {schema=1,phase=phase,width=width,height=height,
            layout_width=panel.layout_screen_width,layout_height=panel.layout_screen_height,
            generation=panel.layout_generation,night_mode=Screen.night_mode==true,rows={}}
        if Screen.bb then
            if Screen.bb.getWidth then metadata.framebuffer_width=Screen.bb:getWidth() end
            if Screen.bb.getHeight then metadata.framebuffer_height=Screen.bb:getHeight() end
            if Screen.bb.getRotation then metadata.buffer_rotation=Screen.bb:getRotation() end
        end
        -- All dynamic-content rectangles must be known before any screenshot
        -- is permitted. A stale/overlapping/out-of-bounds row is never captured.
        local excluded = {
            rect(panel._input_widget and panel._input_widget.dimen),
            rect(panel.transcript_holder and panel.transcript_holder.dimen),
            rect(panel.ink_widget and panel.ink_widget.dimen),
        }
        local complete = excluded[1] and excluded[2] and excluded[3]
        for _, entry in ipairs({{"toolbar",panel.button_table},{"pad-controls",panel.ink_buttons}}) do
            local name,widget = entry[1],entry[2]
            local bounds = rect(widget and widget.dimen)
            local record = {name=name,bounds=bounds,captured=false}
            metadata.rows[#metadata.rows+1] = record
            local filename = directory.."/"..phase.."-"..name..".png"
            -- Remove an older image even if this capture must be skipped.
            os.remove(filename)
            if complete and bounds then
                local crop = {x=0,y=bounds.y,w=width,h=bounds.h}
                local safe = crop.y >= 0 and crop.y+crop.h <= height and crop.h <= Screen:scaleBySize(100)
                for _,dynamic in ipairs(excluded) do if overlaps(crop,dynamic) then safe=false end end
                if safe and Screen.bb then
                    local buffer = Screen.bb:viewport(crop.x,crop.y,crop.w,crop.h):copy()
                    local ok = pcall(function()
                        if Screen.night_mode then buffer:invert() end
                        buffer:writePNG(filename,Device.hasBGRFrameBuffer and Device:hasBGRFrameBuffer() or false)
                    end)
                    buffer:free()
                    record.captured = ok
                    if not ok then os.remove(filename) end
                end
            end
        end
        local f = assert(io.open(directory.."/"..phase..".json","wb"))
        f:write(json.encode(metadata));f:close()
    end)
end
return Diagnostics
