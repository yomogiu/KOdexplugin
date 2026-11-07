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
local plugin_dir = debug.getinfo(1,"S").source:sub(2):match("^(.*)/[^/]+$")

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
    self.layout_generation = (self.layout_generation or 0) + 1
    self.pen_redraw_pending = self.pen_mode and true or false
    -- InputContainer caches geometry across reinit/keyboard/rotation changes.
    self.dimen = nil
    self.width = Screen:getWidth()
    self.layout_screen_width = self.width
    self.layout_screen_height = Screen:getHeight()
    self.text_height = Screen:scaleBySize(76)
    self.orig_text_height = self.text_height
    self.buttons = self.buttons or {{
        { text = "Keys", id = "keyboard", callback = function()
            if self.ink_busy then return end
            if self.pen_mode then self:setPenMode(false) end
            self:toggleKeyboard()
        end },
        { text = "Pen", id = "pen", callback = function() self:queuePenMode(not self.pen_mode) end },
        { text = "Send", id = "send", callback = function() self.on_send(self:getInputText()) end },
        { text = "Stop", id = "stop", callback = function() self.on_stop() end },
        { text = "More", callback = function() self.on_more() end },
        { text = "Close", id = "close", callback = function() UIManager:close(self) end },
    }}
    InputDialog.init(self)
    local keyboard_height = self.keyboard_visible and self._input_widget:getKeyboardDimen().h or 0
    local available = Screen:getHeight() - keyboard_height - self.dialog_frame:getSize().h
    local padding = Screen:scaleBySize(10)
    self.transcript_width = self.width - 2 * padding
    self.transcript_height = math.max(Screen:scaleBySize(36), available - 2 * padding)
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
                if self.ink_unreviewed~=dirty then
                    self:updateControls();UIManager:setDirty(self,"ui")
                end
                if self.on_ink_change then self.on_ink_change() end
            end,
            on_limit=function() self.on_notice("The pad is full. Tap Send, undo, or clear it before writing more.") end,
        }
        self.ink_data=self.ink_widget.state
        self.transcript=self:newTranscript()
        self.transcript_holder=FrameContainer:new{padding=0,margin=0,bordersize=0,self.transcript}
        group=VerticalGroup:new{self.transcript_holder,self.ink_buttons,self.ink_widget}
    else
        self.ink_widget=nil; self.ink_buttons=nil
        self.transcript=self:newTranscript()
        self.transcript_holder=FrameContainer:new{padding=0,margin=0,bordersize=0,self.transcript}
        group=self.transcript_holder
    end
    self.transcript_frame = FrameContainer:new{
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
    else
        table.insert(self.vgroup, 2, self.transcript_frame)
    end
    self.vgroup:resetLayout()
    self:restoreTranscriptPosition()
    self:updateControls()
    -- A tap is routed through onSwitchFocus, which safely resizes next tick.
    if not self.keyboard_visible then self:lockKeyboard(true) end
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
    return InputDialog.handleEvent(self, event)
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
    -- We advertise covers_fullscreen: paint the entire opaque surface, including
    -- edges uncovered when keyboard/layout/menu dimensions change.
    bb:paintRect(x, y, Screen:getWidth(), Screen:getHeight(), BB.COLOR_WHITE)
    InputDialog.paintTo(self, bb, x, y)
    -- This paints an entire opaque screen, even when a child requested only a
    -- regional refresh. Keep display and framebuffer coverage consistent.
    -- nil queues a refresh without dirtying/repainting this widget again.
    UIManager:setDirty(nil, "ui")
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
    UIManager:setDirty(self, "flashui")
end

function ChatPanel:newTranscript()
    local restoring = self.restoring_position
    self.restoring_position = true
    local widget = ScrollTextWidget:new{
        text = self.conversation_text or "",
        face = Font:getFace("x_smallinfofont", 20),
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
    self.restoring_position = true
    if self.follow_tail then
        self.transcript:scrollToBottom()
    elseif self.reading_char then
        self.transcript:moveCursorToCharPos(self.reading_char, 0)
    end
    self.restoring_position = false
end

function ChatPanel:updateControls()
    local send = self.button_table:getButtonById("send")
    local stop = self.button_table:getButtonById("stop")
    local unreviewed = self.pen_mode and self.ink_data and #self.ink_data.strokes>0 and self.recognized_version~=self.ink_data.version
    self.ink_unreviewed=unreviewed and true or false
    if self.reply_active or self.ink_busy then send:disable() else send:enable() end
    if self.reply_active or (self.ink_busy and self.ocr_auto_send) then stop:enable() else stop:disable() end
    if stop.setText then stop:setText(self.ink_busy and self.ocr_auto_send and "Cancel" or "Stop",stop.width) end
    if self.ink_buttons then
        for _,id in ipairs({"undo","clear"}) do
            local button=self.ink_buttons:getButtonById(id)
            if self.ink_busy then button:disable() else button:enable() end
        end
    end
    if self.title_bar.setTitle then
        self.title_bar:setTitle(self.ink_busy and "Kobo Codex — recognizing locally…" or (self.reply_active and "Kobo Codex — replying…" or "Kobo Codex"), true)
    end
end

function ChatPanel:updateConversation(text, active)
    local changed = text ~= self.conversation_text
    local controls_changed = active ~= self.reply_active
    self.reply_active = active
    if changed then
        self:rememberTranscriptPosition()
        self.conversation_text = text
        local old = self.transcript
        self.transcript = self:newTranscript()
        self.transcript_holder[1] = self.transcript
        old:free()
        self:restoreTranscriptPosition()
        UIManager:setDirty(self, "partial", self.transcript_holder.dimen)
    end
    if controls_changed then
        self:updateControls()
        UIManager:setDirty(self, "ui")
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
    end
    self.pen_mode=enabled
    self:reinit()
end
function ChatPanel:setRecognizing(value,auto_send)
    self.ink_busy=value
    self.ocr_auto_send=value and auto_send or false
    if self.ink_widget then self.ink_widget.enabled=not value end
    self:updateControls();UIManager:setDirty(self,"ui")
end

function ChatPanel:latest()
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
    if self.ink_widget then self.ink_widget:detach() end
    local draft = self:getInputText()
    InputDialog.onCloseWidget(self)
    UIManager:setDirty("all", "flashui")
    if self.on_dismiss then self.on_dismiss(draft) end
end

return ChatPanel
