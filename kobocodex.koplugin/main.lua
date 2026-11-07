local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local json = require("json")
local NetworkMgr = require("ui/network/manager")
local plugin_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$")
local Transport = dofile(plugin_dir .. "/transport.lua")
local ChatPanel = dofile(plugin_dir .. "/chatpanel.lua")
local KoboCodex = WidgetContainer:extend{ name = "kobocodex", is_doc_only = false }

function KoboCodex:init()
    self.ui.menu:registerToMainMenu(self)
    self.poll = function() self:refresh() end
    self.ocr_poll = function() self:recognitionStatus() end
    self.auto = true
end
function KoboCodex:addToMainMenu(items)
    items.kobocodex = { text = "Kobo Codex", callback = function()
        NetworkMgr:runWhenOnline(function() self:refresh(true) end)
    end }
end
function KoboCodex:message(text)
    self:showOverlay(InfoMessage, { text = text })
end
function KoboCodex:showOverlay(widget_class, options)
    local Screen = require("device").screen
    -- Reserve space for popup borders/scrollbars in either orientation.
    options.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.85)
    local widget = widget_class:new(options)
    local on_close = widget.onCloseWidget
    widget.onCloseWidget = function(w)
        if on_close then on_close(w) end
        -- Refresh beyond the popup's cached rectangle so edges cannot linger.
        UIManager:setDirty("all", "flashui")
    end
    UIManager:show(widget)
    return widget
end
function KoboCodex:request(method, path, body)
    local f = assert(io.open(plugin_dir .. "/connection.json", "rb"), "Install connection.json by USB first")
    local raw = f:read(8193); f:close()
    assert(raw and #raw <= 8192, "Invalid connection file")
    local config = json.decode(raw)
    local response = Transport.request(config, method, path, body)
    local data = json.decode(response.body)
    assert(response.status == 200, "Bridge: " .. tostring(data.error or response.status))
    return data
end
function KoboCodex:schedulePoll()
    UIManager:unschedule(self.poll)
    if self.viewer and self.state and self.state.active and self.auto then
        UIManager:scheduleIn(3, self.poll)
    end
end
function KoboCodex:refresh(open)
    UIManager:unschedule(self.poll)
    if not open and not self.viewer then return end
    -- Avoid interrupting an active typing burst with a blocking Wi-Fi request.
    if not open and self.last_edit and os.time() - self.last_edit < 2 then
        self:schedulePoll(); return
    end
    local ok, data = pcall(function() return self:request("GET", "/v1/state") end)
    if not ok then self:message(tostring(data)); return end
    self.state = data
    self:render()
    self:schedulePoll()
end
function KoboCodex:render()
    local parts = {}
    if self.state.notice and self.state.notice ~= "" then parts[#parts + 1] = self.state.notice end
    for _, m in ipairs(self.state.messages or {}) do
        parts[#parts + 1] = (m.role == "user" and "You\n" or "Codex\n") .. m.text
    end
    if #(self.state.messages or {}) == 0 then
        parts[#parts + 1] = "Your conversation will appear here.\n\nTap the message box below to write. Only messages you send leave the Kobo."
    end
    local text = table.concat(parts, "\n\n")
    if self.viewer then
        self.viewer:updateConversation(text, self.state.active)
        return
    end
    local panel
    panel = ChatPanel:new{
        input = self.draft or "", conversation_text = text, reply_active = self.state.active,
        pen_mode=self.pen_mode,ink_data=self.ink_data,
        on_send = function(value) self:send(value) end,
        on_stop = function()
            if self.recognition_job and self.recognition_job.auto_send then
                self.recognition_job.auto_send=false
                panel.ocr_auto_send=false;panel:updateControls();UIManager:setDirty(panel,"ui")
                self:message("Send cancelled. Local recognition will only fill the draft.")
            else self:action("/v1/stop") end
        end,
        on_more = function() self:more() end,
        on_notice = function(value) self:message(value) end,
        on_ink_change = function()
            self.last_edit=os.time()
            if panel.ink_data and #panel.ink_data.strokes==0 then self.last_recognition=nil end
        end,
        edited_callback = function(edited) if edited then self.last_edit = os.time() end end,
        on_dismiss = function(draft)
            if self.recognition_job then self.recognition_job.auto_send=false end
            self.draft = draft
            self.ink_data=panel.ink_data;self.pen_mode=panel.pen_mode
            if self.viewer == panel then self.viewer = nil end
            UIManager:unschedule(self.poll)
            UIManager:unschedule(self.ocr_poll)
        end,
    }
    self.viewer = panel
    UIManager:show(panel)
    if self.recognition_job then
        panel:setRecognizing(true,self.recognition_job.auto_send);UIManager:scheduleIn(1,self.ocr_poll)
    end
end
function KoboCodex:hide()
    UIManager:unschedule(self.poll)
    UIManager:unschedule(self.ocr_poll)
    if self.viewer then UIManager:close(self.viewer); self.viewer = nil end
end
function KoboCodex:action(path)
    if path=="/v1/reset" and self.recognition_job then self.recognition_job.auto_send=false end
    local ok, data = pcall(function() return self:request("POST", path, "{}") end)
    if not ok then self:message(tostring(data)); return end
    self.state = data; self:render(); self:schedulePoll()
end
function KoboCodex:send(text)
    if self.state and self.state.active then self:message("Wait for the reply or tap Stop first."); return end
    local panel=self.viewer
    if self.recognition_job or (panel and panel.ink_busy) then return end
    if panel and panel.ink_data and #panel.ink_data.strokes>0 and panel.recognized_version~=panel.ink_data.version then
        self:recognize(true);return
    end
    if not text:match("%S") then return end
    if #text > 16000 then self:message("Prompt limit: 16000 UTF-8 bytes on this client."); return end
    if text ~= self.pending_text or not self.request_id then
        self.request_id = tostring(os.time()) .. "_" .. tostring(math.random(100000000, 999999999))
    end
    self.draft = text; self.pending_text = text
    local ok, data = pcall(function()
        return self:request("POST", "/v1/prompt", json.encode({ text = text, requestId = self.request_id }))
    end)
    if not ok then self:message(tostring(data)); return end
    self.draft = nil; self.request_id = nil; self.pending_text = nil; self.last_edit = nil
    if self.viewer then
        self.viewer:setInputText("", false, false)
        self.last_recognition=nil
        if self.viewer.ink_widget then self.viewer.ink_widget:clear();self.last_edit=nil
        elseif self.viewer.ink_data then
            self.viewer.ink_data.strokes={};self.viewer.ink_data.version=self.viewer.ink_data.version+1
            self.viewer.recognized_version=nil
        end
        self.viewer.follow_tail = true
        UIManager:setDirty(self.viewer, "ui")
    end
    self.state = data; self:render(); self:schedulePoll()
end
function KoboCodex:recognize(auto_send)
    local panel=self.viewer
    if not panel or not panel.ink_data or panel.ink_busy then return end
    local ink={width=panel.ink_data.width,height=panel.ink_data.height,strokes=panel.ink_data.strokes}
    if #ink.strokes==0 then self:message("Write on the pad first.");return end
    panel:setRecognizing(true,auto_send==true)
    local ok,data=pcall(function() return self:request("POST","/v1/recognize",json.encode(ink)) end)
    if not ok then panel:setRecognizing(false);self:message(tostring(data));return end
    local draft=panel:getInputText()
    local base=draft
    if self.last_recognition and draft==self.last_recognition.text then base=self.last_recognition.base end
    self.recognition_job={id=data.jobId,version=panel.ink_data.version,draft=draft,base=base,auto_send=auto_send==true}
    UIManager:scheduleIn(1,self.ocr_poll)
end
function KoboCodex:recognitionStatus()
    UIManager:unschedule(self.ocr_poll)
    if not self.viewer or not self.recognition_job then return end
    local panel=self.viewer
    local ok,data=pcall(function() return self:request("GET","/v1/recognize") end)
    if not ok then
        panel:setRecognizing(false);self.recognition_job=nil;self:message(tostring(data));return
    end
    if data.jobId~=self.recognition_job.id then
        panel:setRecognizing(false);self.recognition_job=nil;self:message("Recognition expired. Tap Send to try again.");return
    end
    if data.status=="running" then UIManager:scheduleIn(1,self.ocr_poll);return end
    local job=self.recognition_job
    self.recognition_job=nil;panel:setRecognizing(false)
    if data.status~="complete" or not data.text or not data.text:match("%S") then
        self:message(data.error or "No text recognized. Try larger, clearer writing.");return
    end
    if not panel.ink_data or panel.ink_data.version~=job.version then
        self:message("The pad changed during recognition. Tap Send again to recognize the updated writing.");return
    end
    local existing=panel:getInputText()
    local draft_unchanged=existing==job.draft
    if existing==job.draft then existing=job.base end
    local combined=existing:match("%S") and (existing.."\n"..data.text) or data.text
    if #combined>16000 then self:message("Recognized text is too long for the current draft.");return end
    panel:setInputText(combined,false,false)
    panel.recognized_version=job.version;panel:updateControls()
    self.draft=combined
    self.last_recognition={text=combined,base=existing}
    UIManager:setDirty(panel,"ui")
    if job.auto_send then
        if draft_unchanged then self:send(combined)
        else self:message("The draft changed during recognition. Check the combined text and tap Send again.") end
    end
end
function KoboCodex:more()
    local menu
    local function choose(callback)
        return function() UIManager:close(menu); callback() end
    end
    menu = self:showOverlay(ButtonDialog, { title = "Conversation", buttons = {
        {{ text = "Preview handwriting",
            enabled=(self.viewer and self.viewer.ink_data and not self.viewer.ink_busy and #self.viewer.ink_data.strokes>0) and true or false,
            callback = choose(function() self:recognize(false) end) }},
        {{ text = "Refresh", callback = choose(function() self:refresh(true) end) }},
        {{ text = self.auto and "Pause reply updates" or "Resume reply updates", callback = choose(function()
            self.auto = not self.auto; self:schedulePoll()
            if self.auto then self:refresh(true) end
        end) }},
        {{ text = "Latest message", callback = choose(function() if self.viewer then self.viewer:latest() end end) }},
        {{ text = "New chat", callback = choose(function()
            self:showOverlay(ConfirmBox, { text = "Clear the conversation? Your unsent draft will be kept.",
                ok_callback = function() self:action("/v1/reset") end })
        end) }},
    }})
end
function KoboCodex:onCloseWidget() self:hide() end
function KoboCodex:onSetDimensions()
    if self.viewer then self.viewer:queueScreenResize() end
end
KoboCodex.onScreenResize = KoboCodex.onSetDimensions
return KoboCodex
