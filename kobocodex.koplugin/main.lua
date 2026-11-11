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
local Background = dofile(plugin_dir .. "/background.lua")
local Selection = dofile(plugin_dir .. "/selection.lua")
local DocumentScope = dofile(plugin_dir .. "/docscope.lua")
local KoboCodex = WidgetContainer:extend{ name = "kobocodex", is_doc_only = false }

function KoboCodex:init()
    self.ui.menu:registerToMainMenu(self)
    self.poll = function() self:refresh() end
    self.ocr_poll = function() self:recognitionStatus() end
    self.auto = true
    self.state = { active=false, messages={}, notice="" }
    self:onDispatcherRegisterActions()
    if self.ui.registerPostInitCallback then
        self.ui:registerPostInitCallback(function() self:registerSelectionActions() end)
    else self:registerSelectionActions() end
end

function KoboCodex:onDispatcherRegisterActions()
    require("dispatcher"):registerAction("kobocodex_resume",{
        category="none",event="ResumeCodex",title="Resume Codex chat",general=true,
    })
end
function KoboCodex:onResumeCodex()
    if self.reader_closing then return true end
    self:render()
    local panel=self.viewer
    NetworkMgr:runWhenConnected(function()
        if self.viewer==panel and not self.reader_closing then self:refresh(true) end
    end)
    return true
end

function KoboCodex:registerSelectionActions()
    local highlight=self.ui.highlight
    if self.reader_closing or not self.ui.document or not highlight or not highlight.addToHighlightDialog or self.selection_highlight==highlight then return end
    self.selection_highlight=highlight
    for _,entry in ipairs({{"05_kobocodex_1_explain","Explain",true},{"05_kobocodex_2_ask","Ask Codex",false}}) do
        local explain,label=entry[3],entry[2]
        highlight:addToHighlightDialog(entry[1],function(reader)
            local selected=reader.selected_text
            local has_text=selected and type(selected.text)=="string" and selected.text:match("%S")~=nil
            return {text=label,enabled=has_text and (not explain or
                (not self.state.active and not self.recognition_job and
                 (not self.network_kind or self.network_kind=="refreshing"))) or false,
                callback=function() self:openSelection(reader,explain) end}
        end)
    end
end
function KoboCodex:onReaderReady() self:registerSelectionActions() end

function KoboCodex:saveReaderLocation()
    local engine=self.ui.paging or self.ui.rolling
    if not self.ui.document or not engine or not engine.getBookLocation then return end
    local ok,location=pcall(engine.getBookLocation,engine)
    if ok and location then return {document=self.ui.document,engine=engine,location=location,paging=self.ui.paging~=nil} end
end
function KoboCodex:restoreReaderLocation(saved)
    if not saved or self.reader_closing or self.ui.document~=saved.document then return end
    local ok,current=pcall(saved.engine.getBookLocation,saved.engine)
    if ok and Selection.sameLocation(current,saved.location) then return end
    -- Paging preserves zoom/pan/scroll context. Rolling's getBookLocation()
    -- returns an xpointer string, which onGotoXPointer accepts directly.
    if saved.paging and saved.engine.onRestoreBookLocation then
        pcall(saved.engine.onRestoreBookLocation,saved.engine,saved.location)
    elseif not saved.paging and saved.engine.onGotoXPointer then
        pcall(saved.engine.onGotoXPointer,saved.engine,saved.location)
    end
end

function KoboCodex:openSelection(reader,explain)
    local document=self.ui.document
    if not document or self.reader_closing then return end
    local context,err=Selection.capture(reader.selected_text,document)
    if not context then self:message(err);return end
    local ticket={}
    self.selection_open_ticket=ticket
    -- Close only the selection menu, as KOReader does for dictionary lookup.
    -- Preserve its existing temporary mark behind the note and on return;
    -- KOReader still owns selection cleanup on later reader interactions.
    reader:onClose(true)
    UIManager:nextTick(function()
        if self.selection_open_ticket~=ticket or self.ui.document~=document or self.reader_closing then return end
        self.selection_open_ticket=nil
        self.selection_context=context
        if self.viewer then self.viewer:setSelectionContext(context,Selection.label(context)) end
        self:render()
        if explain then self:explainSelection()
        elseif not self.viewer.pen_mode then self.viewer:onSwitchFocus(self.viewer._input_widget) end
    end)
end

function KoboCodex:previewSelection()
    local context=self.selection_context
    if not context then return end
    local status=context.sent and "This passage was sent in this conversation. Detaching it does not erase chat history." or
        "This passage and its page reference will be sent with your question when you tap Send or Explain."
    self:showOverlay(require("ui/widget/textviewer"),{title=Selection.source(context),
        text=status.."\n\n"..context.text,show_menu=false})
end
function KoboCodex:detachSelection()
    self.selection_context=nil
    if self.viewer then self.viewer:setSelectionContext(nil) end
end
function KoboCodex:submit(text,options)
    local panel,context,document=self.viewer,self.selection_context,self.ui.document
    if not panel then return end
    local called=false
    -- Only LAN connectivity is needed to reach the paired Mac. A delayed
    -- Wi-Fi callback must not submit after Close, edits, or context changes.
    NetworkMgr:runWhenConnected(function()
        if called then return end
        called=true
        if self.viewer~=panel or self.selection_context~=context or self.ui.document~=document or self.reader_closing then return end
        if not (options and options.preserve_composer) and panel:getInputText()~=text then return end
        self:send(text,options)
    end)
end
function KoboCodex:explainSelection()
    if self.selection_context then self:submit(Selection.EXPLAIN,{preserve_composer=true}) end
end
function KoboCodex:addToMainMenu(items)
    items.kobocodex = { text = "Kobo Codex",sorting_hint="tools",
        callback = function() return self:onResumeCodex() end }
end
function KoboCodex:updateNetworkControls()
    if self.viewer then self.viewer:setNetworkStatus(self.network_kind) end
end
function KoboCodex:requestAsync(method, path, body, kind, callback)
    -- Resolve/save the book ID in the parent, before forking. A settings write
    -- in the worker would only modify its private copy of KOReader's tables.
    local document_id
    if self.ui.document and DocumentScope.isChat(path) then
        local ok,value=pcall(DocumentScope.id,self.ui.doc_settings,self.document_entropy)
        if not ok then callback(false,value);return true end
        document_id=value
    end
    -- Commands supersede a read. Its late result must never overwrite the
    -- state returned by Send/Stop/reset. At most one worker is kept alive.
    if self.network_kind then
        if self.network_kind ~= "refreshing" or method == "GET" then return false end
        self.network_job:cancel()
    end
    local ticket = {}
    self.network_ticket = ticket
    self.network_kind = kind
    self:updateNetworkControls()
    local ok, job = pcall(self.run_background or Background.run, function()
        return self:request(method, path, body,document_id)
    end, function(success, data)
        if self.network_ticket ~= ticket then return end
        self.network_job=nil; self.network_kind=nil; self.network_ticket=nil
        if self.viewer then self.viewer.network_kind=nil end
        callback(success, data)
        self:updateNetworkControls()
    end)
    if ok then
        if self.network_ticket==ticket then self.network_job=job end
    else
        self.network_kind=nil; self.network_ticket=nil
        if self.viewer then self.viewer.network_kind=nil end
        callback(false, job)
        self:updateNetworkControls()
    end
    return true
end
function KoboCodex:requestError(data)
    -- Never open a popup over the book after the chat was dismissed.
    if self.viewer then self:message(tostring(data)) end
end
function KoboCodex:message(text)
    self:showOverlay(InfoMessage, { text = text })
end
function KoboCodex:showOverlay(widget_class, options)
    local Screen = require("device").screen
    -- VirtualKeyboard is modal too: overlays must stack above it and consume
    -- unhandled input before InputDialog's always-active controls see it.
    options.modal=true
    options.stop_events_propagation=true
    -- Reserve space for popup borders/scrollbars in either orientation.
    options.width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.85)
    local widget = widget_class:new(options)
    local panel=self.viewer
    if panel then
        panel:cancelKeyboardOpening()
        panel.modal_overlay_count=(panel.modal_overlay_count or 0)+1
    end
    local on_close = widget.onCloseWidget
    local closed=false
    widget.onCloseWidget = function(w)
        if closed then return end
        closed=true
        if on_close then on_close(w) end
        if panel then panel.modal_overlay_count=math.max(0,(panel.modal_overlay_count or 1)-1) end
        -- Refresh beyond the popup's cached rectangle so edges cannot linger.
        UIManager:setDirty("all", "flashui")
    end
    UIManager:show(widget)
    return widget
end
function KoboCodex:request(method, path, body,document_id)
    local f = assert(io.open(plugin_dir .. "/connection.json", "rb"), "Install connection.json by USB first")
    local raw = f:read(8193); f:close()
    assert(raw and #raw <= 8192, "Invalid connection file")
    local config = json.decode(raw)
    local response = Transport.request(config, method, DocumentScope.path(path,document_id), body)
    local data = json.decode(response.body)
    if document_id and response.status==404 then error("Update the Mac bridge to use this chat feature") end
    assert(response.status == 200, "Bridge: " .. tostring(data.error or response.status))
    if document_id then assert(data.documentId==document_id,"Document conversation mismatch; update the Mac bridge before sending") end
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
    if open then self:render() end
    if self.network_kind then self:schedulePoll(); return end
    self:requestAsync("GET", "/v1/state", nil, "refreshing", function(ok, data)
        if not ok then self:requestError(data); return end
        self.state = data
        if self.selection_context and #(data.messages or {})==0 and not data.active then self.selection_context.sent=false end
        if self.viewer then self:render() end
        self:schedulePoll()
    end)
end
function KoboCodex:rememberPrompt(wire_text,question,context)
    if wire_text==question then return end
    self.display_prompts=self.display_prompts or {}
    self.display_prompt_order=self.display_prompt_order or {}
    if not self.display_prompts[wire_text] then
        table.insert(self.display_prompt_order,wire_text)
        if #self.display_prompt_order>12 then
            self.display_prompts[table.remove(self.display_prompt_order,1)]=nil
        end
    end
    local name=DocumentScope.name(self.ui.document)
    self.display_prompts[wire_text]=question.."\n\nPassage: "..Selection.source(context)..(name and "\n\nDocument: "..name or "")
end
function KoboCodex:conversationText()
    local cached = self.text_cache or {messages={}}
    local messages = self.state.messages or {}
    local visible_count = #messages
    if self.state.active and messages[visible_count] and messages[visible_count].role=="assistant" then
        visible_count=visible_count-1
    end
    local notice = self.state.notice or ""
    local empty = #messages==0
    local changed = cached.notice~=notice or cached.empty~=empty or #cached.messages~=visible_count
    local formatted = {}
    for i=1,visible_count do
        local m, old = messages[i], cached.messages[i]
        local display=m.role=="user" and self.display_prompts and self.display_prompts[m.text] or m.text
        if old and old.role==m.role and old.text==m.text and old.display==display then formatted[i]=old
        else
            formatted[i]={role=m.role,text=m.text,display=display,formatted=(m.role=="user" and "You\n" or "Codex\n")..display}
            changed=true
        end
    end
    if not changed then return cached.text,cached.response_ranges end
    local parts = {}
    if notice~="" then parts[#parts+1]=notice end
    local ranges={}
    local function charCount(value)
        local _,count=value:gsub("[^\128-\191]","")
        return count
    end
    local offset=notice~="" and charCount(notice) or 0
    for _,m in ipairs(formatted) do
        if #parts>0 then offset=offset+2 end
        if m.role=="assistant" and m.display~="" then
            ranges[#ranges+1]={first=offset+charCount("Codex\n")+1,last=offset+charCount(m.formatted)}
        end
        parts[#parts+1]=m.formatted
        offset=offset+charCount(m.formatted)
    end
    if empty then
        parts[#parts + 1] = "Your conversation will appear here.\n\nTap the message box below to write. Only messages you send leave the Kobo."
    end
    local text = table.concat(parts, "\n\n")
    self.text_cache={messages=formatted,notice=notice,empty=empty,text=text,response_ranges=ranges}
    return text,ranges
end
function KoboCodex:render()
    local text,ranges = self:conversationText()
    local has_history=#(self.state.messages or {})>0 or (self.state.notice or "")~=""
    if self.viewer then
        self.viewer:updateConversation(text, self.state.active,ranges,has_history)
        return
    end
    local panel
    local reader_location=self:saveReaderLocation()
    panel = ChatPanel:new{
        input = self.draft or "", conversation_text = text, reply_active = self.state.active,
        response_ranges=ranges,note_has_history=has_history,
        note_mode=self.note_mode~=false and self.ui.document~=nil,
        pen_mode=self.pen_mode,ink_data=self.ink_data,
        selection_context=self.selection_context,
        selection_label=self.selection_context and Selection.label(self.selection_context),
        return_to_reading=self.ui.document~=nil,
        on_selection_preview=function() self:previewSelection() end,
        on_selection_detach=function() self:detachSelection() end,
        on_send = function(value) self:submit(value) end,
        on_stop = function()
            if self.recognition_job and self.recognition_job.auto_send then
                self.recognition_job.auto_send=false
                panel.ocr_auto_send=false;panel:updateControls()
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
            self:restoreReaderLocation(reader_location)
        end,
    }
    self.viewer = panel
    UIManager:show(panel)
    self:updateNetworkControls()
    if self.recognition_job then
        panel:setRecognizing(true,self.recognition_job.auto_send);UIManager:scheduleIn(1,self.ocr_poll)
    end
end
function KoboCodex:hide()
    self.selection_open_ticket=nil
    UIManager:unschedule(self.poll)
    UIManager:unschedule(self.ocr_poll)
    if self.viewer then UIManager:close(self.viewer); self.viewer = nil end
end
function KoboCodex:action(path)
    if path=="/v1/stop" and self.network_kind=="sending" then
        self.stop_after_send=true; return
    end
    if self.network_kind and self.network_kind~="refreshing" then return end
    if path=="/v1/reset" and self.recognition_job then self.recognition_job.auto_send=false end
    self:requestAsync("POST", path, "{}", path=="/v1/stop" and "stopping" or "resetting", function(ok, data)
        if not ok then self:requestError(data); return end
        if path=="/v1/reset" then
            if self.selection_context then self.selection_context.sent=false end
            self.display_prompts=nil;self.display_prompt_order=nil
            self.pending_text=nil;self.request_id=nil;self.stop_after_send=nil
        end
        self.state = data
        if self.viewer then self:render() end
        self:schedulePoll()
    end)
end
function KoboCodex:send(text,options)
    local preserve=options and options.preserve_composer
    if self.network_kind and self.network_kind~="refreshing" then return end
    if self.state and self.state.active then self:message("Wait for the reply or tap Stop first."); return end
    local panel=self.viewer
    if self.recognition_job or (panel and panel.ink_busy) then return end
    if not preserve and panel and panel.ink_data and #panel.ink_data.strokes>0 and panel.recognized_version~=panel.ink_data.version then
        self:recognize(true);return
    end
    if not text:match("%S") then return end
    local context=self.selection_context
    if context and context.document~=self.ui.document then
        self:message("This passage belongs to another document. Detach it or select a passage from the current document.");return
    end
    local request_text=Selection.prompt(text,context)
    if #request_text > 16000 then self:message("The question and attached passage exceed 16000 UTF-8 bytes. Shorten the question or detach the passage."); return end
    if request_text ~= self.pending_text or not self.request_id then
        self.request_id = tostring(os.time()) .. "_" .. tostring(math.random(100000000, 999999999))
    end
    if not preserve then self.draft=text end
    self.pending_text=request_text
    if panel then panel.follow_tail=true end
    local ink_version = panel and panel.ink_data and panel.ink_data.version
    local prompt_body={text=request_text,requestId=self.request_id}
    prompt_body.documentName=DocumentScope.name(self.ui.document)
    if request_text~=text then prompt_body.displayText=text.."\n\nPassage: "..Selection.source(context) end
    self:requestAsync("POST", "/v1/prompt", json.encode(prompt_body), "sending", function(ok, data)
        local stop = self.stop_after_send
        self.stop_after_send=nil
        if not ok then self:requestError(data); return end
        self:rememberPrompt(request_text,text,context)
        self.request_id=nil; self.pending_text=nil
        -- Input remains editable while sending. Clear only the acknowledged
        -- draft/ink, never a newer edit, including one saved by Close/reopen.
        if not preserve and self.draft==text then self.draft=nil end
        local current=self.viewer
        if not preserve and current and current:getInputText()==text then
            current:setInputText("", false, false)
            self.last_edit=nil
        end
        local ink=current and current.ink_data or self.ink_data
        if not preserve and ink and ink.version==ink_version then
            self.last_recognition=nil
            if current and current.ink_widget then current.ink_widget:clear()
            else ink.strokes={};ink.version=ink.version+1 end
            if current then current.recognized_version=nil end
        end
        if context then context.sent=true end
        if current then UIManager:setDirty(current,function() return "ui",current.compact and current.dialog_frame.dimen or nil end) end
        self.state=data
        if current then self:render() end
        self:schedulePoll()
        if stop and data.active then self:action("/v1/stop") end
    end)
end
function KoboCodex:recognize(auto_send)
    if self.network_kind and self.network_kind~="refreshing" then return end
    local panel=self.viewer
    if not panel or not panel.ink_data or panel.ink_busy then return end
    local ink={width=panel.ink_data.width,height=panel.ink_data.height,strokes=panel.ink_data.strokes}
    if #ink.strokes==0 then self:message("Write on the pad first.");return end
    panel:setRecognizing(true,auto_send==true)
    local draft=panel:getInputText()
    local base=draft
    if self.last_recognition and draft==self.last_recognition.text then base=self.last_recognition.base end
    local job={version=panel.ink_data.version,draft=draft,base=base,auto_send=auto_send==true}
    self.recognition_job=job
    self:requestAsync("POST","/v1/recognize",json.encode(ink),"recognizing",function(ok,data)
        if self.recognition_job~=job then return end
        if not ok then
            self.recognition_job=nil
            if self.viewer then self.viewer:setRecognizing(false) end
            self:requestError(data);return
        end
        job.id=data.jobId
        if self.viewer then UIManager:scheduleIn(1,self.ocr_poll) end
    end)
end
function KoboCodex:recognitionStatus()
    UIManager:unschedule(self.ocr_poll)
    if not self.viewer or not self.recognition_job then return end
    if self.network_kind or not self.recognition_job.id then
        UIManager:scheduleIn(1,self.ocr_poll);return
    end
    local panel=self.viewer
    local expected_job=self.recognition_job
    self:requestAsync("GET","/v1/recognize",nil,"recognizing",function(ok,data)
        if self.recognition_job~=expected_job then return end
        if self.viewer~=panel then
            if self.viewer then UIManager:scheduleIn(1,self.ocr_poll) end
            return
        end
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
    end)
end
function KoboCodex:history(page)
    if not self.ui.document or not self.viewer or self.reader_closing then return end
    if self.network_kind and self.network_kind~="refreshing" then return end
    if self.state.active or self.recognition_job then self:message("Wait for the reply or tap Stop before opening history.");return end
    self:requestAsync("GET","/v1/history",nil,"history",function(ok,data)
        if not self.viewer or self.reader_closing then return end
        if not ok then self:requestError(data);return end
        self:showHistory(data.archives or {},page or 1)
    end)
end
function KoboCodex:showHistory(archives,page)
    if not self.viewer or self.reader_closing then return end
    local pages=math.max(1,math.ceil(#archives/5))
    page=math.max(1,math.min(page,pages))
    local menu,buttons=nil,{}
    for i=(page-1)*5+1,math.min(page*5,#archives) do
        local entry=archives[i]
        if DocumentScope.valid(entry.id) then
            local id=entry.id
            local date=tostring(entry.createdAt or ""):sub(1,16):gsub("T"," ")
            table.insert(buttons,{{text=tostring(entry.title or "Conversation").." — "..date.." UTC",text_font_size=18,callback=function()
                UIManager:close(menu)
                self:showOverlay(ConfirmBox,{text="Reopen this saved conversation? Your current chat will be archived first. Your unsent draft will be kept.",
                    ok_callback=function()self:reopenChat(id)end})
            end}})
        end
    end
    local navigation={}
    if page>1 then table.insert(navigation,{text="Previous",callback=function()UIManager:close(menu);self:showHistory(archives,page-1)end}) end
    if page<pages then table.insert(navigation,{text="Next",callback=function()UIManager:close(menu);self:showHistory(archives,page+1)end}) end
    if #navigation>0 then table.insert(buttons,navigation) end
    table.insert(buttons,{{text="Back to chat",callback=function()UIManager:close(menu)end}})
    local name=DocumentScope.name(self.ui.document)
    menu=self:showOverlay(ButtonDialog,{title=(#archives==0 and "No saved chats" or ("Chat history — "..page.."/"..pages))..(name and " — "..name or " for this book"),buttons=buttons})
end
function KoboCodex:reopenChat(id)
    if not self.ui.document or not self.viewer or self.reader_closing or not DocumentScope.valid(id) then return end
    if self.recognition_job or (self.network_kind and self.network_kind~="refreshing") then return end
    if self.state.active then self:message("Wait for the reply or tap Stop first.");return end
    self:requestAsync("POST","/v1/reopen",json.encode({archiveId=id}),"reopening",function(ok,data)
        if not ok then self:requestError(data);return end
        -- A passage captured for the previous conversation must not silently
        -- enter the reopened one. Draft and ink stay in the same composer.
        self.selection_context=nil;self.display_prompts=nil;self.display_prompt_order=nil
        self.pending_text=nil;self.request_id=nil;self.stop_after_send=nil
        self.state=data
        if self.viewer then self.viewer:setSelectionContext(nil);self:render() end
        self:schedulePoll()
    end)
end
function KoboCodex:more()
    local menu
    local function choose(callback)
        return function() UIManager:close(menu); callback() end
    end
    local buttons = {
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
            self:showOverlay(ConfirmBox, { text = self.ui.document and "Archive this conversation and start a new chat? Your unsent draft will be kept." or "Clear the general conversation? Your unsent draft will be kept.",
                ok_callback = function() self:action("/v1/reset") end })
        end) }},
    }
    if self.ui.document then table.insert(buttons,{{text="Chat history",enabled=not self.state.active,
        callback=choose(function()self:history()end)}}) end
    if self.selection_context then table.insert(buttons,1,{{text="Explain selected passage",enabled=not self.state.active,
        callback=choose(function() self:explainSelection() end)}}) end
    table.insert(buttons,{{text="Back to chat",callback=choose(function() end)}})
    menu = self:showOverlay(ButtonDialog, { title = "Conversation", buttons = buttons })
end
function KoboCodex:onCloseWidget() self:hide() end
function KoboCodex:onCloseDocument()
    self.reader_closing=true
    self.selection_open_ticket=nil
    if self.selection_highlight and self.selection_highlight.removeFromHighlightDialog then
        self.selection_highlight:removeFromHighlightDialog("05_kobocodex_1_explain")
        self.selection_highlight:removeFromHighlightDialog("05_kobocodex_2_ask")
    end
    self.selection_highlight=nil
    self:hide()
    self.selection_context=nil
end
function KoboCodex:onExit()
    self:onCloseDocument()
    self.network_ticket=nil
    if self.network_job then self.network_job:cancel() end
    self.network_job=nil; self.network_kind=nil
end
function KoboCodex:onSetDimensions()
    if self.viewer then self.viewer:queueScreenResize() end
end
KoboCodex.onScreenResize = KoboCodex.onSetDimensions
return KoboCodex
