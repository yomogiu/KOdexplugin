local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local BB = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local time = require("ui/time")

local InkPad = InputContainer:extend{}
function InkPad.supported()
    return Device.input and type(Device.input.registerStylusCallback) == "function"
end
function InkPad:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.state = self.state or { width = self.width, height = self.height, strokes = {}, version = 0 }
    if self.state.width ~= self.width or self.state.height ~= self.height then
        local scale = math.min(self.width / self.state.width, self.height / self.state.height)
        for _, stroke in ipairs(self.state.strokes) do
            for _, p in ipairs(stroke) do p[1] = math.floor(p[1]*scale); p[2] = math.floor(p[2]*scale) end
        end
        self.state.width, self.state.height = self.width, self.height
    end
    self.buffer = BB.new(self.width, self.height, BB.TYPE_BB8)
    self.count = 0
    self:redraw()
    self.ges_events = {}
    for _, name in ipairs({ "tap", "double_tap", "hold", "pan", "swipe", "multiswipe" }) do
        self.ges_events["IgnoreFinger"..name] = {
            GestureRange:new{ ges = name, range = function() return self.dimen end },
        }
        self["onIgnoreFinger"..name] = function() return true end
    end
end
function InkPad:dot(x, y)
    local r = math.max(1, Screen:scaleBySize(1))
    local left, top = math.max(0,x-r), math.max(0,y-r)
    local right, bottom = math.min(self.width,x+r+1), math.min(self.height,y+r+1)
    self.buffer:paintRect(left,top,right-left,bottom-top,BB.COLOR_BLACK)
end
function InkPad:segment(a,b)
    local steps = math.max(math.abs(b[1]-a[1]),math.abs(b[2]-a[2]))
    if steps == 0 then self:dot(a[1],a[2]); return end
    for i=0,steps do
        self:dot(math.floor(a[1]+(b[1]-a[1])*i/steps+0.5), math.floor(a[2]+(b[2]-a[2])*i/steps+0.5))
    end
end
function InkPad:redraw()
    self.buffer:fill(BB.COLOR_WHITE)
    for y=Screen:scaleBySize(45),self.height-1,Screen:scaleBySize(45) do
        self.buffer:paintRect(0,y,self.width,1,BB.COLOR_LIGHT_GRAY or BB.COLOR_WHITE)
    end
    self.count = 0
    for _, stroke in ipairs(self.state.strokes) do
        self.count = self.count + #stroke
        for i,p in ipairs(stroke) do if i==1 then self:dot(p[1],p[2]) else self:segment(stroke[i-1],p) end end
    end
end
function InkPad:changed()
    self.state.version = self.state.version + 1
    if self.on_change then self.on_change() end
end
function InkPad:refreshInk(mode, region)
    region = region or self.dimen
    -- A regional stroke update must not dirty the top-level chat: that would
    -- repaint controls into the framebuffer without refreshing those controls.
    Screen:beforePaint()
    Screen.bb:blitFrom(self.buffer,region.x,region.y,
        region.x-self.dimen.x,region.y-self.dimen.y,region.w,region.h)
    UIManager:setDirty(nil,mode,region)
end
function InkPad:pen(input, slot)
    if UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget()~=self.dialog then
        self.current=nil;self.contact_owned=nil;return false
    end
    if not self.dimen.x or not slot.x or not slot.y then return false end
    local x,y = slot.x,slot.y
    local rotation = Screen.getTouchRotation and Screen:getTouchRotation() or 0
    if rotation == 1 then x,y = Screen:getWidth()-y,x
    elseif rotation == 2 then x,y = Screen:getWidth()-x,Screen:getHeight()-y
    elseif rotation == 3 then x,y = y,Screen:getHeight()-x end
    x,y = math.floor(x-self.dimen.x+0.5),math.floor(y-self.dimen.y+0.5)
    local inside = x>=0 and y>=0 and x<self.width and y<self.height
    if inside or self.contact_owned then
        self.dialog.pen_touch_until = time.now() + time.ms(600)
    end
    if slot.id == -1 then
        local drawing = self.current ~= nil or self.contact_owned; self.current = nil; self.contact_owned=nil
        if drawing then self:refreshInk("partial") end
        return drawing or inside
    end
    if not inside then self.current = nil; return self.contact_owned and true or false end
    if type(slot.id)~="number" or slot.id<0 then return true end
    if self.enabled == false then return true end
    -- Only the actual pen tool draws. Palms/fingers/eraser aliases never draw.
    if slot.tool ~= 1 then return true end
    if self.count >= 20000 or (not self.current and #self.state.strokes >= 1000) then
        if not self.full then self.full=true; if self.on_limit then self.on_limit() end end
        return true
    end
    local point = { x,y }
    if not self.current then
        self.contact_owned=true
        self.current = {}; self.state.strokes[#self.state.strokes+1] = self.current
    end
    local previous = self.current[#self.current]
    if previous and previous[1]==x and previous[2]==y then return true end
    self.current[#self.current+1] = point; self.count = self.count+1
    if previous then self:segment(previous,point) else self:dot(x,y) end
    self:changed()
    local a=previous or point
    local radius=math.max(2,Screen:scaleBySize(2))
    local left=math.max(0,math.min(a[1],x)-radius)
    local top=math.max(0,math.min(a[2],y)-radius)
    local right=math.min(self.width,math.max(a[1],x)+radius+1)
    local bottom=math.min(self.height,math.max(a[2],y)+radius+1)
    self:refreshInk("fast",Geom:new{
        x=self.dimen.x+left,y=self.dimen.y+top,w=right-left,h=bottom-top,
    })
    return true
end
function InkPad:attach()
    if self.callback or not self.supported() then return end
    self.previous = Device.input.stylus_callback
    self.callback = function(input,slot) return self:pen(input,slot) end
    Device.input:registerStylusCallback(self.callback)
end
function InkPad:detach()
    if self.callback and Device.input.stylus_callback == self.callback then
        if self.previous then Device.input:registerStylusCallback(self.previous)
        else Device.input:unregisterStylusCallback() end
    end
    self.callback=nil
end
function InkPad:paintTo(bb,x,y)
    self.dimen.x,self.dimen.y=x,y
    bb:blitFrom(self.buffer,x,y,0,0,self.width,self.height)
    self:attach()
end
function InkPad:undo()
    self.current=nil; table.remove(self.state.strokes);self.full=nil;self:redraw();self:changed()
    UIManager:setDirty(self.dialog,"partial",self.dimen)
end
function InkPad:clear()
    self.current=nil;self.state.strokes={};self.full=nil;self:redraw();self:changed()
    UIManager:setDirty(self.dialog,"partial",self.dimen)
end
function InkPad:payload()
    return { width=self.width, height=self.height, strokes=self.state.strokes }
end
function InkPad:free()
    self:detach()
    if self.buffer then self.buffer:free();self.buffer=nil end
end
return InkPad
