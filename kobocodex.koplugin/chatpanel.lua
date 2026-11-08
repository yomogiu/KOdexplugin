-- One persistent chat/composer surface, using KOReader v2025.04's InputDialog
-- for cursor/keyboard lifecycle. Transcript updates never rebuild the editor.
local InputDialog = require("ui/widget/inputdialog")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local Screen = require("device").screen
local time = require("ui/time")
local BB = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local plugin_dir = debug.getinfo(1,"S").source:sub(2):match("^(.*)/[^/]+$")
local validRegion

local Transcript = ScrollTextWidget:extend{}
function Transcript:paintTo(bb,x,y)
    ScrollTextWidget.paintTo(self,bb,x,y)
    local text=self.text_widget
    if not self.response_ranges or not text or not text.vertical_string_list or not text.dimen then return end
    -- Use KOReader's own shaped glyph rectangles so Unicode/RTL answers are
    -- highlighted by character range, never by guessing text from labels.
    local rects_for=text.use_xtext and text.getXtextHighlightRects or text.getNonXtextHighlightRects
    if not rects_for then return end
    local first=text.virtual_line_num
    local last=math.min(#text.vertical_string_list,first+text:getVisLineCount()-1)
    for _,range in ipairs(self.response_ranges) do
        for _,r in ipairs(rects_for(text,range.first,range.last,first,last)) do
            local left=math.max(0,r.x);local top=math.max(0,r.y)
            local right=math.min(text.dimen.w,r.x+r.w)
            local bottom=math.min(text.dimen.h,r.y+r.h)
            if right>left and bottom>top then
                bb:darkenRect(text.dimen.x+left,text.dimen.y+top,right-left,bottom-top,0.16)
            end
        end
    end
end
function Transcript:updateScrollBar(is_partial)
    local low, high = self.prev_low, self.prev_high
    -- Suppress only ScrollTextWidget's parent dirty request. Its normal ratio,
    -- scrollbar and callback logic still runs; the TextBox remains renderable.
    local measurement = self.for_measurement_only
    self.for_measurement_only = true
    ScrollTextWidget.updateScrollBar(self, is_partial)
    self.for_measurement_only = measurement
    if (low ~= self.prev_low or high ~= self.prev_high) and
        not self.dialog.restoring_position then
        self.dialog:queueChatPaint("transcript")
    end
end

function Transcript:restoreReadingChar(char)
    -- This is read-only text. Cursor restoration would draw a cursor and
    -- enqueue its own parent refresh, even while restoring a new widget.
    local line = self:getCharPosLineNum(char)
    self.text_widget:scrollLines(line-1)
    self:updateScrollBar()
end

local ChatPanel = InputDialog:extend{
    title = "Kobo Codex",
    fullscreen = false,
    condensed = true,
    is_movable = false,
    border_size = 0,
    covers_fullscreen = true,
    keyboard_visible = false,
    deny_keyboard_hiding = true,
    allow_newline = true,
    input_hint = "Write a message…",
    follow_tail = true,
}

function ChatPanel:init()
    self.initializing = true
    self:cancelChatPaint()
    self.paint_regions = nil
    self.control_title = nil
    self.control_stop_text = nil
    self.control_send_text = nil
    self.layout_generation = (self.layout_generation or 0) + 1
    self.pen_redraw_pending = self.pen_mode and true or false
    -- InputContainer caches geometry across reinit/keyboard/rotation changes.
    self.dimen = nil
    self.compact=self.note_mode and not self.expanded and not self.pen_mode or false
    self.covers_fullscreen=not self.compact
    self.border_size=self.compact and Screen:scaleBySize(1) or 0
    self.width = self.compact and math.floor(math.min(Screen:getWidth(),Screen:getHeight())*0.86) or Screen:getWidth()
    self.layout_screen_width = Screen:getWidth()
    self.layout_screen_height = Screen:getHeight()
    self.text_height = Screen:scaleBySize(self.compact and 64 or 76)
    self.orig_text_height = self.text_height
    self.input_face=Font:getFace("x_smallinfofont",self.note_mode and 18 or 20)
    self.buttons = {{
        { text = "Keys", id = "keyboard", callback = function()
            if self.ink_busy then return end
            if self.pen_mode then self:setPenMode(false) end
            self:toggleKeyboard()
        end },
        { text = "Pen", id = "pen", callback = function() self:queuePenMode(not self.pen_mode) end },
        { text = "Send", id = "send", callback = function()
            if self.compact and (self.reply_active or self.network_kind=="sending" or (self.ink_busy and self.ocr_auto_send)) then self.on_stop()
            else self.on_send(self:getInputText()) end
        end },
        { text = "Stop", id = "stop", callback = function() self.on_stop() end },
        { text = "More", callback = function() self.on_more() end },
        { text = "Close", id = "close", callback = function() UIManager:close(self) end },
    }}
    if self.note_mode then
        local row=self.buttons[1]
        local expand={text=self.compact and "Expand" or "Compact",id="expand",callback=function() self:queueExpanded(self.compact) end}
        if self.compact then self.buttons={{row[6],row[1],expand,row[3]}}
        else self.buttons={{row[1],row[2],row[3],row[4]},{row[5],expand,row[6]}} end
    end
    -- InputDialog backs up button definitions; mode switches replace them.
    self._buttons_backup_done=false;self._buttons_backup=nil
    for _,row in ipairs(self.buttons) do
        for _,button in ipairs(row) do
            if button.id=="close" then button.text=self.return_to_reading and "Read" or "Close" end
        end
    end
    self.input_hint=self.selection_context and "Ask about the selected passage…" or "Write a message…"
    InputDialog.init(self)
    local keyboard_height = self.keyboard_visible and self._input_widget:getKeyboardDimen().h or 0
    local screen_available=Screen:getHeight()-keyboard_height
    local target_height=self.compact and math.min(math.floor(Screen:getHeight()*0.55),math.floor(screen_available*0.78)) or screen_available
    local available = target_height - self.dialog_frame:getSize().h
    local padding = Screen:scaleBySize(10)
    self.transcript_width = self.width - 2*self.border_size - 2 * padding
    self.selection_buttons=nil
    if self.selection_context then
        local ButtonTable = require("ui/widget/buttontable")
        local buttons={{
            {text=self.selection_label or "Selected passage",id="selection_preview",callback=self.on_selection_preview},
            {text="Detach",id="selection_detach",callback=self.on_selection_detach},
        }}
        if self.compact then table.remove(buttons[1],2) end
        self.selection_buttons=ButtonTable:new{width=self.transcript_width,show_parent=self,buttons=buttons}
        available=available-self.selection_buttons:getSize().h
    end
    self.transcript_height = math.max(Screen:scaleBySize(36), available - 2 * padding)
    self.show_transcript=not self.compact or self.note_has_history
    local group
    if self.pen_mode then
        local ButtonTable = require("ui/widget/buttontable")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local InkPad = dofile(plugin_dir.."/inkpad.lua")
        self.ink_buttons = ButtonTable:new{ width=self.transcript_width, buttons={{
            {text="Undo",id="undo",callback=function() self.ink_widget:undo() end},
            {text="Clear pad",id="clear",callback=function()
                self:saveDisplayDiagnostic("before-clear")
                self.ink_widget:clear()
                local generation = self.layout_generation
                UIManager:tickAfterNext(function()
                    if not self.dismissed and generation == self.layout_generation then
                        self:saveDisplayDiagnostic("after-clear")
                    end
                end)
            end},
        }},show_parent=self }
        local total = self.transcript_height
        self.transcript_height = math.floor(total*0.32)
        self.ink_widget = InkPad:new{
            width=self.transcript_width,height=total-self.transcript_height-self.ink_buttons:getSize().h,
            state=self.ink_data,dialog=self,enabled=not self.ink_busy,
            on_change=function()
                self.recognized_version=nil
                local dirty=#self.ink_data.strokes>0
                if self.ink_unreviewed~=dirty then self:updateControls() end
                if self.on_ink_change then self.on_ink_change() end
            end,
            on_limit=function() self.on_notice("The pad is full. Tap Send, undo, or clear it before writing more.") end,
        }
        self.ink_data=self.ink_widget.state
        self.transcript=self:newTranscript()
        self.transcript_holder=FrameContainer:new{padding=0,margin=0,bordersize=0,self.transcript}
        group=VerticalGroup:new{self.transcript_holder,self.ink_buttons,self.ink_widget}
    elseif self.show_transcript then
        self.ink_widget=nil; self.ink_buttons=nil
        self.transcript=self:newTranscript()
        self.transcript_holder=FrameContainer:new{padding=0,margin=0,bordersize=0,self.transcript}
        group=self.transcript_holder
    else
        self.ink_widget=nil;self.ink_buttons=nil
        self.transcript=nil;self.transcript_holder=nil
    end
    self.transcript_frame = group and FrameContainer:new{
        padding = padding, margin = 0, bordersize = 0,
        group,
    }
    -- Base InputDialog's stable layout is title, spacing, input, spacing, buttons.
    -- Insert conversation ABOVE the composer, rather than opening another dialog.
    if self.pen_mode then
        -- Keep every control above the writing surface, away from the palm.
        local actions = table.remove(self.vgroup)
        table.insert(self.vgroup, 2, actions)
        table.insert(self.vgroup, self.transcript_frame)
    elseif self.show_transcript then
        table.insert(self.vgroup, 2, self.transcript_frame)
    end
    if self.selection_buttons then table.insert(self.vgroup,self.pen_mode and 3 or 2,self.selection_buttons) end
    self.vgroup:resetLayout()
    self:restoreTranscriptPosition()
    self:updateControls()
    -- A tap is routed through onSwitchFocus, which safely resizes next tick.
    if not self.keyboard_visible then self:lockKeyboard(true) end
    self.initializing = nil
end

function ChatPanel:queueExpanded(enabled)
    if self.ink_busy or self.expand_queued then return end
    self.expand_queued=true
    UIManager:nextTick(function()
        self.expand_queued=nil
        if self.dismissed then return end
        self.expanded=enabled
        if not enabled then self.pen_mode=false end
        self:reinit()
        if self.compact then self:onSwitchFocus(self._input_widget) end
        UIManager:setDirty("all","ui")
    end)
end

function ChatPanel:setSelectionContext(context,label)
    self.selection_context=context
    self.selection_label=label
    self:reinit()
    UIManager:setDirty(self,"ui")
end

function ChatPanel:cancelChatPaint()
    if self.chat_paint_task then UIManager:unschedule(self.chat_paint_task) end
    self.chat_paint_task = nil
    self.chat_dirty = nil
end

function ChatPanel:canPaintChat()
    if not UIManager.getTopmostVisibleWidget then return true end
    local top=UIManager:getTopmostVisibleWidget()
    if top==self then return true end
    local keyboard=self._input_widget and self._input_widget.keyboard
    if not keyboard or top~=keyboard or not UIManager.topdown_widgets_iter then return false end
    if not validRegion(keyboard.dimen) then return false end
    -- Our own keyboard is a separate modal window, but leaves the note above
    -- it visible. Check the whole stack so a popup between the two cannot be
    -- overwritten just because the keyboard happens to be topmost.
    for widget in UIManager:topdown_widgets_iter() do
        if widget==self then return true,keyboard.dimen end
        if not widget.invisible and widget~=keyboard then return false end
    end
    return false
end

function ChatPanel:queueChatPaint(part)
    if self.initializing or self.dismissed then return end
    self.chat_dirty = self.chat_dirty or {}
    self.chat_dirty[part] = true
    if self.chat_paint_task then return end
    local generation = self.layout_generation
    local task
    task = function()
        if self.chat_paint_task ~= task or self.dismissed or generation ~= self.layout_generation then return end
        -- Do not draw through a popup or into a frame the stylus is using.
        if not self:canPaintChat() or
            (self.ink_widget and self.ink_widget.contact_owned) or
            (self.pen_touch_until and time.now() < self.pen_touch_until) then
            UIManager:scheduleIn(0.25, task)
            return
        end
        self.chat_paint_task = nil
        self:flushChatPaint()
    end
    self.chat_paint_task = task
    UIManager:nextTick(task)
end

validRegion=function(r)
    return r and type(r.x)=="number" and type(r.y)=="number" and
        type(r.w)=="number" and type(r.h)=="number" and
        r.x>=0 and r.y>=0 and r.w>0 and r.h>0 and
        r.x+r.w<=Screen:getWidth() and r.y+r.h<=Screen:getHeight()
end

function ChatPanel:paintWidgets()
    return {transcript=self.transcript_holder, title=self.title_bar,
        actions=self.button_table, ink_actions=self.ink_buttons}
end

function ChatPanel:rememberPaintRegions()
    self.paint_regions = {}
    for part, widget in pairs(self:paintWidgets()) do
        local r = widget.dimen
        if validRegion(r) then self.paint_regions[part]=Geom:new{x=r.x,y=r.y,w=r.w,h=r.h} end
    end
end

function ChatPanel:flushChatPaint()
    local dirty = self.chat_dirty
    self.chat_dirty = nil
    if not dirty or self.dismissed then return end
    local widgets, regions = self:paintWidgets(), self.paint_regions
    local ready = not self:screenSizeChanged() and regions and
        UIManager.widgetRepaint and UIManager.getTopmostVisibleWidget
    local visible,keyboard_region=self:canPaintChat()
    if not visible then
        self.chat_dirty=dirty
        for part in pairs(dirty) do self:queueChatPaint(part) end
        return
    end
    -- Validate every region before touching the framebuffer. Layout changes
    -- use the opaque whole-chat paint and its matching screen-wide refresh.
    for part in pairs(dirty) do
        local widget, r = widgets[part], regions and regions[part]
        local size = widget and widget.getSize and widget:getSize()
        if not validRegion(r) or not size or size.w~=r.w or size.h~=r.h then ready=false end
        if keyboard_region and (not validRegion(keyboard_region) or not validRegion(r) or
            (r.x<keyboard_region.x+keyboard_region.w and r.x+r.w>keyboard_region.x and
             r.y<keyboard_region.y+keyboard_region.h and r.y+r.h>keyboard_region.y)) then ready=false end
    end
    if not ready then
        UIManager:setDirty(self,function() return "ui",self.compact and self.dialog_frame.dimen or nil end)
        return
    end
    Screen:beforePaint()
    local combined
    for part in pairs(dirty) do
        local r = regions[part]
        -- Erase the entire old region, including text/scrollbars that shrank.
        Screen.bb:paintRect(r.x,r.y,r.w,r.h,BB.COLOR_WHITE)
        UIManager:widgetRepaint(widgets[part],r.x,r.y)
        if not combined then combined=Geom:new{x=r.x,y=r.y,w=r.w,h=r.h}
        else
            local right=math.max(combined.x+combined.w,r.x+r.w)
            local bottom=math.max(combined.y+combined.h,r.y+r.h)
            combined.x=math.min(combined.x,r.x);combined.y=math.min(combined.y,r.y)
            combined.w=right-combined.x;combined.h=bottom-combined.y
        end
    end
    -- One refresh covers every write in this pass. Never dirty the parent
    -- here: it would repaint a whole screen behind a regional refresh.
    UIManager:setDirty(nil,"ui",combined)
end

function ChatPanel:saveDisplayDiagnostic(phase)
    -- Diagnostics must never prevent the normal Clear action on failure.
    pcall(function() dofile(plugin_dir.."/displaydiagnostics.lua").capture(self,phase) end)
end

function ChatPanel:handleEvent(event)
    if self:screenSizeChanged() then
        self:queueScreenResize()
        -- Don't send a touch to controls at their old orientation's coordinates.
        if event.handler == "onGesture" then return true end
    end
    -- Intercept before children: a button would otherwise consume the palm tap.
    local pad = self.ink_widget
    if self.pen_mode and pad and event.handler == "onGesture" and
        (pad.contact_owned or (self.pen_touch_until and time.now() < self.pen_touch_until)) then
        return true
    end
    local handled=InputDialog.handleEvent(self, event)
    -- The book is visible, but this remains a modal note. Background taps or
    -- swipes must not turn pages underneath an active question/editor.
    if self.compact and event.handler=="onGesture" then return true end
    return handled
end

function ChatPanel:screenSizeChanged()
    return self.layout_screen_width ~= Screen:getWidth() or
        self.layout_screen_height ~= Screen:getHeight()
end

function ChatPanel:queueScreenResize()
    if self.resize_queued or self.dismissed or not self:screenSizeChanged() then return end
    self.resize_queued = true
    -- Never free the widget tree in the middle of painting/event propagation.
    UIManager:nextTick(function()
        self.resize_queued = nil
        if self.dismissed or not self:screenSizeChanged() then return end
        self:reinit()
        UIManager:setDirty("all", "full")
    end)
end
ChatPanel.onSetDimensions = ChatPanel.queueScreenResize
ChatPanel.onScreenResize = ChatPanel.queueScreenResize

function ChatPanel:paintTo(bb, x, y)
    -- Rotation may be handled by the reader beneath this dialog, without the
    -- resize event reaching us. Catch that before reusing portrait geometry.
    self:queueScreenResize()
    -- Expanded mode owns the screen; note mode paints only its opaque frame
    -- and leaves the reader beneath it intact.
    if not self.compact then bb:paintRect(x, y, Screen:getWidth(), Screen:getHeight(), BB.COLOR_WHITE) end
    InputDialog.paintTo(self, bb, x, y)
    self:cancelChatPaint()
    self:rememberPaintRegions()
    -- Match refresh coverage to the actual write: whole screen when expanded,
    -- frame only when compact. nil avoids repainting the parent a second time.
    UIManager:setDirty(nil, "ui", self.compact and self.dialog_frame.dimen or nil)
    self:queuePenRedraw()
end

function ChatPanel:queuePenMode(enabled)
    if self.ink_busy or self.pen_mode_queued then return end
    self.pen_mode_queued = true
    -- Let the tapped button finish its feedback before replacing its tree.
    UIManager:nextTick(function()
        self.pen_mode_queued = nil
        if not self.dismissed then self:setPenMode(enabled) end
    end)
end

function ChatPanel:queuePenRedraw()
    if not self.pen_redraw_pending or self:screenSizeChanged() then return end
    self.pen_redraw_pending = false
    local generation = self.layout_generation
    -- The first frame must reach the display before requesting the follow-up.
    UIManager:tickAfterNext(function()
        if self.dismissed or not self.pen_mode or generation ~= self.layout_generation then return end
        if (UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget() ~= self) or
            (self.ink_widget and self.ink_widget.contact_owned) then
            -- Retry on a later paint, after the popup/stroke has finished.
            self.pen_redraw_pending = true
            return
        end
        UIManager:waitForVSync()
        -- Clear pad's later repaint restores the affected controls on-device.
        -- Repaint the whole chat without calling clear() or changing its data.
        UIManager:setDirty(self, "partial")
    end)
end

function ChatPanel:onShow()
    if self.compact then
        UIManager:setDirty(self,function() return "ui",self.dialog_frame.dimen end)
        self:onSwitchFocus(self._input_widget)
    else UIManager:setDirty(self, "flashui") end
end

function ChatPanel:newTranscript()
    local restoring = self.restoring_position
    self.restoring_position = true
    local widget = Transcript:new{
        text = self.conversation_text or "",
        face = Font:getFace("x_smallinfofont", self.note_mode and 18 or 20),
        response_ranges=self.response_ranges,
        editable=false,highlight_text_selection=false,
        width = self.transcript_width, height = self.transcript_height,
        dialog = self, scroll_by_pan = true, auto_para_direction = true,
        scroll_callback = function(_, high)
            if not self.restoring_position then self.follow_tail = high >= 0.98 end
        end,
    }
    self.restoring_position = restoring
    return widget
end

function ChatPanel:rememberTranscriptPosition()
    if self.transcript and not self.follow_tail then
        self.reading_char = self.transcript:getCharPosAtXY(0, 0)
    end
end

function ChatPanel:restoreTranscriptPosition()
    if not self.transcript then return end
    self.restoring_position = true
    if self.follow_tail then
        local ranges=self.response_ranges or {}
        if self.note_mode and not self.reply_active and ranges[#ranges] then
            -- A long completed answer should open at its beginning, rather
            -- than making the reader scroll back up from its last sentence.
            self.transcript:restoreReadingChar(math.max(1,ranges[#ranges].first-6))
        else self.transcript:scrollToBottom() end
    elseif self.reading_char then
        self.transcript:restoreReadingChar(self.reading_char)
    end
    self.restoring_position = false
end

function ChatPanel:updateControls()
    local send = self.button_table:getButtonById("send")
    local stop = self.button_table:getButtonById("stop")
    local unreviewed = self.pen_mode and self.ink_data and #self.ink_data.strokes>0 and self.recognized_version~=self.ink_data.version
    self.ink_unreviewed=unreviewed and true or false
    local command_busy = self.network_kind and self.network_kind ~= "refreshing"
    local function enabled(button, value, part)
        if not button then return end
        value = value and true or false
        if button.enabled == value then return end
        if value then button:enable() else button:disable() end
        self:queueChatPaint(part)
    end
    local can_stop=self.reply_active or self.network_kind=="sending" or (self.ink_busy and self.ocr_auto_send)
    enabled(send, self.compact and can_stop or not (self.reply_active or self.ink_busy or command_busy), "actions")
    enabled(stop, self.reply_active or self.network_kind=="sending" or (self.ink_busy and self.ocr_auto_send), "actions")
    local stop_text = self.ink_busy and self.ocr_auto_send and "Cancel" or "Stop"
    if stop_text ~= self.control_stop_text then
        self.control_stop_text=stop_text
        if stop and stop.setText then stop:setText(stop_text,stop.width) end
        if stop then self:queueChatPaint("actions") end
    end
    local send_text=self.compact and can_stop and stop_text or "Send"
    if send_text~=self.control_send_text then
        self.control_send_text=send_text
        if send.setText then send:setText(send_text,send.width) end
        self:queueChatPaint("actions")
    end
    if self.ink_buttons then
        for _,id in ipairs({"undo","clear"}) do
            local button=self.ink_buttons:getButtonById(id)
            enabled(button, not self.ink_busy, "ink_actions")
        end
    end
    if self.title_bar.setTitle then
        local title = "Kobo Codex"
        if self.ink_busy then title=title.." — recognizing locally…"
        elseif self.network_kind=="sending" then title=title.." — sending…"
        elseif self.network_kind=="stopping" then title=title.." — stopping…"
        elseif self.network_kind=="resetting" then title=title.." — starting new chat…"
        elseif self.network_kind=="history" then title=title.." — loading history…"
        elseif self.network_kind=="reopening" then title=title.." — reopening…"
        elseif self.reply_active then title=title.." — replying…" end
        if title ~= self.control_title then
            self.control_title=title
            self.title_bar:setTitle(title, true)
            self:queueChatPaint("title")
        end
    end
end

function ChatPanel:setNetworkStatus(kind)
    self.network_kind=kind
    -- updateControls compares visible values; unchanged polls do no UI work.
    self:updateControls()
end

function ChatPanel:updateConversation(text, active, ranges, has_history)
    local changed = text ~= self.conversation_text
    local controls_changed = active ~= self.reply_active
    self.reply_active = active
    self.response_ranges=ranges or self.response_ranges
    if has_history~=nil and has_history~=self.note_has_history then
        self.note_has_history=has_history
        if self.compact then
            self.conversation_text=text
            self:reinit()
            return
        end
    end
    if changed then
        if not self.transcript then
            self.note_has_history=true;self.conversation_text=text;self:reinit();return
        end
        self:rememberTranscriptPosition()
        self.conversation_text = text
        local old = self.transcript
        self.transcript = self:newTranscript()
        self.transcript_holder[1] = self.transcript
        old:free()
        self:restoreTranscriptPosition()
        self:queueChatPaint("transcript")
    end
    if controls_changed then
        self:updateControls()
    end
end

function ChatPanel:setPenMode(enabled)
    if self.ink_busy then return end
    if enabled then
        local InkPad=dofile(plugin_dir.."/inkpad.lua")
        if not InkPad.supported() then
            self.on_notice("Pen input needs KOReader 2026.07 or newer. Keyboard input is still available.");return
        end
        if self:isKeyboardVisible() then self:toggleKeyboard(false) end
        if self.note_mode then self.expanded=true end
    end
    self.pen_mode=enabled
    self:reinit()
end
function ChatPanel:setRecognizing(value,auto_send)
    self.ink_busy=value
    self.ocr_auto_send=value and auto_send or false
    if self.ink_widget then self.ink_widget.enabled=not value end
    self:updateControls()
end

function ChatPanel:latest()
    if not self.transcript then return end
    self.follow_tail = true
    self.transcript:scrollToBottom()
end

function ChatPanel:toggleKeyboard(force)
    self:rememberTranscriptPosition()
    if self.ink_widget then self.ink_widget:detach() end
    self.resizing = true
    -- Base preserves draft, cursor, and editor scroll position during resize.
    InputDialog.toggleKeyboard(self, force)
    self.resizing = nil
    if self.note_mode then UIManager:setDirty("all","ui") end
end

function ChatPanel:reinit()
    self:rememberTranscriptPosition()
    if self.ink_widget then self.ink_widget:detach() end
    self.resizing = true
    InputDialog.reinit(self)
    self.resizing = nil
end
ChatPanel.onKeyboardHeightChanged = ChatPanel.reinit

function ChatPanel:onSwitchFocus(input)
    input.focused = true
    if self.ink_busy then return end
    if not self:isKeyboardVisible() and not self.opening_keyboard then
        self.opening_keyboard = true
        -- Do not free the input while its tap handler is still using its cursor.
        UIManager:nextTick(function()
            self.opening_keyboard = nil
            if not self.dismissed then self:toggleKeyboard(true) end
        end)
    end
end

function ChatPanel:onKeyboardClosed()
    if self.keyboard_visible and not self:isKeyboardVisible() and not self.dismissed and not self.resizing then
        self:reinit()
    end
end

function ChatPanel:onCloseWidget()
    self.dismissed = true
    self:cancelChatPaint()
    if self.ink_widget then self.ink_widget:detach() end
    local draft = self:getInputText()
    InputDialog.onCloseWidget(self)
    UIManager:setDirty("all", "flashui")
    if self.on_dismiss then self.on_dismiss(draft) end
end

return ChatPanel
