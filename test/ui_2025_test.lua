-- v2025.04 API/lifecycle contract checks; no claim of a real device render.
local function class(base)
 local c={};c.__index=c;setmetatable(c,{__index=base})
 function c:extend(t) local n=class(self);for k,v in pairs(t)do n[k]=v end;return n end
 function c:new(t) local n=setmetatable(t or {},self);if n.init then n:init()end;return n end
 return c
end
local ui={shown={},scheduled={},ticks={},dirty={}}
function ui:show(w)self.shown[#self.shown+1]=w end
function ui:close(w)if w.onCloseWidget then w:onCloseWidget()end end
function ui:unschedule(f)self.scheduled[f]=nil end
function ui:scheduleIn(delay,f)self.scheduled[f]=true;self.delays=self.delays or {};self.delays[f]=delay end
function ui:nextTick(f)self.ticks[#self.ticks+1]=f end
function ui:tickAfterNext(f)self:nextTick(function()self:nextTick(f)end)end
function ui:waitForVSync()self.vsync_waits=(self.vsync_waits or 0)+1 end
function ui:setDirty(widget,mode,region)self.dirty[#self.dirty+1]={widget=widget,mode=mode,region=region}end
package.preload['ui/uimanager']=function()return ui end
local now=0
package.preload['ui/time']=function()return{now=function()return now end,ms=function(n)return n end}end
package.preload['ui/widget/container/widgetcontainer']=function()return class()end
local screen={w=1404,h=1872}
function screen:getWidth()return self.w end
function screen:getHeight()return self.h end
function screen:scaleBySize(n)return n end
screen.ink_blits={}
function screen:beforePaint()self.before_paint=(self.before_paint or 0)+1 end
screen.bb={blitFrom=function(_,buffer,x,y,ox,oy,w,h)
 screen.ink_blits[#screen.ink_blits+1]={x=x,y=y,ox=ox,oy=oy,w=w,h=h}
end}
local device={screen=screen,input={}}
function device.input:registerStylusCallback(callback)self.stylus_callback=callback end
function device.input:unregisterStylusCallback()self.stylus_callback=nil end
package.preload.device=function()return device end
package.preload['ui/widget/container/inputcontainer']=function()
 local c=class();function c:getSize()return self.dimen end;return c
end
package.preload['ui/geometry']=function()return{new=function(_,t)return t end}end
package.preload['ui/gesturerange']=function()return{new=function(_,t)return t end}end
local bb={TYPE_BB8=1,COLOR_BLACK=0,COLOR_WHITE=255,COLOR_LIGHT_GRAY=230}
function bb.new(w,h)
 return{fill=function()end,free=function()end,paintRect=function(_,x,y,ww,hh)assert(x>=0 and y>=0 and x+ww<=w and y+hh<=h)end}
end
package.preload['ffi/blitbuffer']=function()return bb end
local Buttons=class()
function Buttons:getSize()return{h=60*#self.buttons,w=self.width}end
function Buttons:getButtonById(id)
 for _,row in ipairs(self.buttons)do for _,b in ipairs(row)do if b.id==id then
  function b:enable()self.enabled=true end
  function b:disable()self.enabled=false end
  function b:setText(text)self.text=text end
  return b
 end end end
end
package.preload['ui/widget/buttontable']=function()return Buttons end
local Group=class()
function Group:getSize()
 local w,h=0,0
 for _,child in ipairs(self)do local s=child:getSize();w=math.max(w,s.w);h=h+s.h end
 return{w=w,h=h}
end
function Group:resetLayout()end
package.preload['ui/widget/verticalgroup']=function()return Group end
package.preload['ui/font']=function()return{getFace=function(_,name,size)return{name=name,size=size}end}end
local Frame=class()
function Frame:getSize()
 local s=self[1].getSize and self[1]:getSize() or {w=self[1].width,h=self[1].height}
 return{w=s.w+2*self.padding,h=s.h+2*self.padding}
end
package.preload['ui/widget/container/framecontainer']=function()return Frame end
local Scroll=class()
local transcript_instances=0
function Scroll:init()
 transcript_instances=transcript_instances+1;self.low=0;self.high=0.2
 self.text_widget={scrollLines=function(_,lines)self.anchor=lines+1 end}
 self:updateScrollBar()
end
function Scroll:updateScrollBar()
 if self.prev_low~=self.low or self.prev_high~=self.high then
  self.prev_low=self.low;self.prev_high=self.high
  -- Mirror the native widget's parent dirty request, so the optimized
  -- Transcript must suppress it during construction, restore, and scrolling.
  if not self.for_measurement_only then ui:setDirty(self.dialog,'ui',self.dimen)end
  self.scroll_callback(self.low,self.high)
 end
end
function Scroll:getSize()return{w=self.width,h=self.height}end
function Scroll:free()self.freed=true end
function Scroll:scrollToBottom()self.bottom=true;self.low=0.8;self.high=1;self:updateScrollBar()end
function Scroll:getCharPosAtXY()return 45 end
function Scroll:getCharPosLineNum(char)return char end
function Scroll:moveCursorToCharPos(p)self.anchor=p end
function Scroll:paintTo(_,x,y)
 self.dimen={x=x,y=y,w=self.width,h=self.height}
 if self.text_widget.dimen then self.text_widget.dimen.x=x;self.text_widget.dimen.y=y end
end
package.preload['ui/widget/scrolltextwidget']=function()return Scroll end
local instances=0
local Input=class()
function Input:init()
 instances=instances+1
 self._input_widget={text=self.input or '',cursor=self._charpos or #(self.input or '')}
 function self._input_widget:getKeyboardDimen()return{h=600}end
 local function box(w,h)return{getSize=function()return{w=w,h=h}end}end
 self.vgroup=Group:new{box(self.width,50),box(0,0),box(self.width,self.text_height),box(0,0),box(self.width,60*#self.buttons)}
 self.dialog_frame={getSize=function()
  local s=self.vgroup:getSize();return{w=s.w+2*(self.border_size or 0),h=s.h+2*(self.border_size or 0)}
 end}
 self.button_table={width=self.width,getSize=function()return{w=self.width,h=60*#self.buttons}end,getButtonById=function(_,id)
  for _,row in ipairs(self.buttons)do for _,b in ipairs(row)do if b.id==id then
   function b:enable()self.enabled=true end
   function b:disable()self.enabled=false end
   function b:setText(text)self.text=text end
   return b
  end end end
 end}
 self.title_bar={setTitle=function(_,t)self.display_title=t;self.title_sets=(self.title_sets or 0)+1 end}
end
function Input:getInputText()return self._input_widget.text end
function Input:setInputText(t)self._input_widget.text=t;self._input_widget.cursor=#t end
function Input:isKeyboardVisible()return self.keyboard_visible end
function Input:lockKeyboard()end
function Input:toggleKeyboard(force)
 self.input=self:getInputText();self._charpos=self._input_widget.cursor
 if force==false then self._keyboard_was_visible=self.keyboard_visible==true end
 if force~=nil then self.keyboard_visible=force
 elseif self._keyboard_was_visible~=nil then self.keyboard_visible=self._keyboard_was_visible;self._keyboard_was_visible=nil
 else self.keyboard_visible=not self.keyboard_visible end
 self:init()
end
function Input:reinit()self.input=self:getInputText();self._charpos=self._input_widget.cursor;self:init()end
function Input:onCloseWidget()self.keyboard_visible=false end
function Input:handleEvent(event)self.forwarded_event=event;return 'forwarded' end
function Input:paintTo()self.painted=true end
package.preload['ui/widget/inputdialog']=function()return Input end
for _,name in ipairs({'infomessage','buttondialog','confirmbox'})do
 package.preload['ui/widget/'..name]=function()return class()end
end
package.preload.json=function()return{encode=function(t)return t end}end
local network={runWhenConnected=function(_,callback)callback()end}
package.preload['ui/network/manager']=function()return network end
local dispatcher={actions={}}
function dispatcher:registerAction(id,action)if not self.actions[id]then self.actions[id]=action end end
package.preload.dispatcher=function()return dispatcher end
local function bookSettings()
 local data={partial_md5_checksum=string.rep('a',32)}
 return{data=data,readSetting=function(_,key)return data[key]end,saveSetting=function(_,key,value)data[key]=value end}
end
local Plugin=dofile('kobocodex.koplugin/main.lua')
local registered
local plugin=setmetatable({ui={menu={registerToMainMenu=function(_,p)registered=p end}}},{__index=Plugin})
plugin:init();assert(registered==plugin)
local deferred=false
local workers={}
plugin.run_background=function(task,callback)
 local job={task=task,callback=callback}
 function job:cancel()self.cancelled=true end
 if deferred then workers[#workers+1]=job
 else local ok,data=pcall(task);callback(ok,data) end
 return job
end
local state={active=false,messages={},notice=''}
local requests={};local fail=false
local scanStatus,scanText='complete','HELLO'
function plugin:request(method,path,body)
 requests[#requests+1]={method=method,path=path,body=body}
 if path=='/v1/recognize'then return {jobId='local-test-job',status=method=='POST' and 'running' or scanStatus,text=scanText} end
 if path=='/v1/prompt'then
  if fail then error('Synthetic rejected prompt')end
  state={active=true,messages={{role='user',text=body.text},{role='assistant',text=''}},notice=''}
 elseif path=='/v1/reset'then state={active=false,messages={},notice=''}end
 return state
end
plugin:refresh(true)
local panel=plugin.viewer
assert(panel and panel.transcript.bottom,'initial conversation must follow latest')
local tall=panel.transcript_height
panel:setInputText('Draft message')
local original=panel._input_widget
panel:onSwitchFocus(original)
assert(panel._input_widget==original,'tap must finish before relayout')
original.cursor=4;ui.ticks[1]()
assert(panel.keyboard_visible and panel:getInputText()=='Draft message'and panel._input_widget.cursor==4)
assert(panel.transcript_height==tall-600,'transcript must shrink by keyboard height')
local composer=panel._input_widget;local shown=#ui.shown
plugin:send(panel:getInputText())
assert(plugin.viewer==panel and panel._input_widget==composer,'send must preserve panel and composer')
assert(panel.keyboard_visible and panel:getInputText()=='','send must clear input and retain keys')
assert(#ui.shown==shown,'send must not create a second dialog')
assert(ui.scheduled[plugin.poll])
panel:setInputText('Follow-up draft');composer.cursor=7
local count=instances
local waiting_transcript=panel.transcript
local waiting_dirty=#ui.dirty
state.messages[2].text='A streamed reply';plugin:refresh(true)
assert(panel._input_widget==composer and instances==count,'reply update must not recreate input')
assert(panel:getInputText()=='Follow-up draft'and composer.cursor==7 and panel.keyboard_visible)
panel.follow_tail=false;state.messages[2].text='A longer reply';plugin:refresh(true)
assert(panel.transcript==waiting_transcript and #ui.dirty==waiting_dirty,'in-progress deltas must not rebuild or repaint the transcript')
assert(not panel.conversation_text:find('A longer reply',1,true),'unfinished answer must stay hidden')
assert(panel.reply_active and panel.button_table:getButtonById('stop').enabled,'Stop must remain available while waiting')
state.active=false;plugin:refresh(true)
assert(panel.transcript~=waiting_transcript and panel.conversation_text:find('A longer reply',1,true),'completed answer must appear at once')
assert(panel.transcript.anchor==45,'preserve reading anchor when completed answer arrives')
local completed_transcript=panel.transcript
plugin:refresh(true)
assert(panel.transcript==completed_transcript,'unchanged completed answer must not render again')
panel:latest();assert(panel.follow_tail and panel.transcript.bottom)
fail=true;plugin:send('Rejected draft')
assert(plugin.viewer==panel and panel:getInputText()=='Follow-up draft')
local id=plugin.request_id;plugin:send('Rejected draft');assert(plugin.request_id==id)
fail=false;plugin:action('/v1/reset')
assert(plugin.viewer==panel and panel:getInputText()=='Follow-up draft')
plugin:hide();assert(plugin.viewer==nil and plugin.draft=='Follow-up draft'and not ui.scheduled[plugin.poll])
local Panel=dofile('kobocodex.koplugin/chatpanel.lua')
for _,shape in ipairs({{1404,1872},{1872,1404}})do
 screen.w,screen.h=shape[1],shape[2]
 for _,visible in ipairs({false,true})do
  local p=Panel:new{input='',conversation_text='text',keyboard_visible=visible,on_send=function()end,on_stop=function()end,on_more=function()end}
  local used=p.transcript_height+20+50+p.text_height+60+(visible and 600 or 0)
  assert(used==screen.h and p.transcript_width==screen.w-20,'viewport must fit')
 end
end
print('Persistent composer checks passed: same pane/editor on send and updates, keyboard/draft/cursor retention, reading anchor, retry ID, close, portrait/landscape sizing')

-- Manual preview stays available, while Send now recognizes and sends once.
screen.w,screen.h=1404,1872
plugin:refresh(true)
local function sentCount()local n=0;for _,r in ipairs(requests)do if r.path=='/v1/prompt'then n=n+1 end end;return n end
local function scanCount()local n=0;for _,r in ipairs(requests)do if r.path=='/v1/recognize'and r.method=='POST'then n=n+1 end end;return n end
local function prepare(draft)
 state={active=false,messages={},notice=''};fail=false;scanStatus,scanText='complete','HELLO'
 plugin.recognition_job=nil
 panel=plugin.viewer
 panel:setRecognizing(false)
 if not panel.pen_mode then panel:setPenMode(true)end
 panel.ink_widget:clear();panel:setInputText(draft or '')
 plugin:refresh(true)
 panel.ink_widget:paintTo({blitFrom=function()end},10,100)
 panel.ink_widget:pen(device.input,{id=1,tool=1,x=50,y=150})
 panel.ink_widget:pen(device.input,{id=-1,tool=1,x=50,y=150})
end
prepare()
local before=sentCount()
plugin:recognize(false);assert(panel.ink_busy and plugin.recognition_job)
plugin:recognitionStatus()
assert(panel:getInputText()=='HELLO'and not panel.ink_busy and sentCount()==before)
plugin:send(panel:getInputText());assert(sentCount()==before+1 and #panel.ink_data.strokes==0)
-- Raw ink with an empty text box takes one Send action, then submits only text.
prepare()
before=sentCount();local scans=scanCount();local editor=panel._input_widget
assert(panel.button_table:getButtonById('send').enabled)
plugin:send('');assert(panel.ink_busy and plugin.recognition_job.auto_send)
plugin:send('');assert(scanCount()==scans+1 and sentCount()==before,'duplicate taps must not start duplicate work')
plugin:recognitionStatus()
assert(sentCount()==before+1 and requests[#requests].body.text=='HELLO')
assert(panel._input_widget==editor and #panel.ink_data.strokes==0 and panel:getInputText()=='')
-- Typed prefix and handwriting are combined once.
prepare('Please answer:')
plugin:send(panel:getInputText());plugin:recognitionStatus()
assert(requests[#requests].body.text=='Please answer:\nHELLO')
-- Switching to Keys for a prefix must not silently drop pending handwriting.
prepare('Typed prefix')
panel:setPenMode(false)
plugin:send(panel:getInputText());plugin:recognitionStatus()
assert(requests[#requests].body.text=='Typed prefix\nHELLO'and #panel.ink_data.strokes==0)
-- OCR failure or empty output must never submit a prompt or destroy the ink.
for _,status in ipairs({'failed','complete'})do
 prepare('Keep this draft');before=sentCount();scanStatus=status;scanText=''
 plugin:send(panel:getInputText());plugin:recognitionStatus()
 assert(sentCount()==before and panel:getInputText()=='Keep this draft'and #panel.ink_data.strokes==1)
end
-- Server rejection (including sensitive-text blocking) keeps text and ink to fix.
prepare();plugin:send('');before=sentCount();fail=true
plugin:recognitionStatus()
assert(panel:getInputText()=='HELLO'and #panel.ink_data.strokes==1)
local id=plugin.request_id;scans=scanCount()
plugin:send(panel:getInputText());assert(plugin.request_id==id and scanCount()==scans)
-- Editing while recognition runs cancels automatic submission.
prepare('Original');before=sentCount();plugin:send('Original')
panel:setInputText('Edited');plugin:recognitionStatus()
assert(sentCount()==before and panel:getInputText()=='Edited\nHELLO')
-- Closing cancels automatic sending; reopening can still recover the draft.
prepare();before=sentCount();plugin:send('');plugin:hide()
assert(not plugin.recognition_job.auto_send)
plugin:refresh(true);panel=plugin.viewer;plugin:recognitionStatus()
assert(sentCount()==before and panel:getInputText()=='HELLO')
-- Cancel during OCR leaves a preview draft, without a model request.
prepare();before=sentCount();plugin:send('');panel.on_stop();plugin:recognitionStatus()
assert(sentCount()==before and panel:getInputText()=='HELLO')
plugin:hide();assert(device.input.stylus_callback==nil)
print('Automatic local OCR-on-Send checks passed: one submission, empty/prefixed drafts, duplicate taps, failures, rejected text, edits, close, cancel, optional preview')
-- Stroke capture safety: fingers never draw, buffer writes stay in bounds,
-- slots are rotated, limits are enforced, and another plugin's hook is restored.
local Pad=dofile('kobocodex.koplugin/inkpad.lua')
local previous=function()return false end
device.input.stylus_callback=previous
local pad=Pad:new{width=100,height=100,dialog={}}
pad:paintTo({blitFrom=function()end},10,20)
local hook=device.input.stylus_callback
assert(hook~=previous)
hook(device.input,{id=1,tool=0,x=20,y=30});assert(#pad.state.strokes==0)
hook(device.input,{id=1,tool=2,x=20,y=30});assert(#pad.state.strokes==0)
hook(device.input,{id=1,tool=1,x=10,y=20})
hook(device.input,{id=1,tool=1,x=109,y=119})
hook(device.input,{id=-1,tool=1,x=109,y=119})
assert(#pad.state.strokes==1 and #pad.state.strokes[1]==2)
assert(pad.state.strokes[1][1][1]==0 and pad.state.strokes[1][2][1]==99)
pad:undo();assert(#pad.state.strokes==0)
pad.enabled=false;hook(device.input,{id=2,tool=1,x=20,y=30});assert(#pad.state.strokes==0)
pad.enabled=true;pad.count=20000
local limits=0;pad.on_limit=function()limits=limits+1 end
hook(device.input,{id=3,tool=1,x=20,y=30});hook(device.input,{id=3,tool=1,x=20,y=30})
assert(#pad.state.strokes==0 and limits==1)
pad:clear()
screen.getTouchRotation=function()return 1 end
hook(device.input,{id=4,tool=1,x=40,y=screen.w-40})
assert(pad.state.strokes[1][1][1]==30 and pad.state.strokes[1][1][2]==20)
screen.getTouchRotation=nil
pad:free();assert(device.input.stylus_callback==previous)
print('Stylus safety checks passed: finger/eraser exclusion, clipped pixels, bounds, capture freeze, limits, rotation, prior-hook restoration')

-- Palm protection happens before child buttons can consume a gesture.
plugin:refresh(true);panel=plugin.viewer
panel:setPenMode(true)
assert(panel.vgroup[2]~=panel.transcript_frame and panel.vgroup[#panel.vgroup]==panel.transcript_frame,
 'pen controls must be above the pad, not below the resting hand')
local viewport=panel.vgroup:getSize()
assert(viewport.w==screen.w and viewport.h==screen.h,'pen layout must fit both screen edges exactly')
panel.ink_widget:paintTo({blitFrom=function()end},10,100)
local gesture={handler='onGesture'}
local other={handler='onSuspend'}
now=1000
panel.ink_widget:pen(device.input,{id=1,tool=1,x=50,y=150})
assert(panel:handleEvent(gesture)==true and not panel.forwarded_event)
assert(panel:handleEvent(other)=='forwarded','non-touch lifecycle events must not be blocked')
panel.ink_widget:pen(device.input,{id=-1,tool=1,x=50,y=150})
now=1599;assert(panel:handleEvent(gesture)==true,'ignore delayed palm releases')
now=1601;assert(panel:handleEvent(gesture)=='forwarded','deliberate touches must recover')
panel.dimen={w=42,h=42};panel:reinit();assert(panel.dimen==nil,'reinit must discard stale screen bounds')
local painted
panel:paintTo({paintRect=function(_,x,y,w,h,color)painted={x,y,w,h,color}end},0,0)
assert(painted[3]==screen.w and painted[4]==screen.h and painted[5]==bb.COLOR_WHITE)
assert(panel.painted,'base chat and editor must still paint after edge clear')
for _,shape in ipairs({{1404,1872},{1872,1404}})do
 screen.w,screen.h=shape[1],shape[2]
 plugin:more();local menu=ui.shown[#ui.shown]
 assert(menu.width<=math.min(screen.w,screen.h)*0.85,'popup must leave space for frame and scrollbar')
 ui:close(menu);local refresh=ui.dirty[#ui.dirty]
 assert(refresh.widget=='all'and refresh.mode=='flashui'and refresh.region==nil,'menu dismissal must repaint all edges')
 plugin:message('Synthetic notice');local notice=ui.shown[#ui.shown]
 assert(notice.width==menu.width);ui:close(notice)
end
panel:setPenMode(false)
assert(panel:handleEvent(gesture)=='forwarded','Keys mode must retain normal touch behavior')
plugin:hide()
print('Palm/layout checks passed: actions above pad, pre-child touch suppression and recovery, lifecycle delivery, stale geometry reset, opaque screen edges, bounded popups and full dismissal refresh')

-- Rotate the SAME live chat, rather than constructing a fresh dialog for each
-- shape: the old checks missed cached portrait controls on a landscape screen.
screen.w,screen.h=1404,1872
plugin:refresh(true);panel=plugin.viewer
panel:setPenMode(true);panel:setInputText('Preserve through rotation')
panel.ink_widget:clear()
panel._input_widget.cursor=5;panel.follow_tail=false
panel.ink_widget:paintTo({blitFrom=function()end},10,100)
panel.ink_widget:pen(device.input,{id=1,tool=1,x=50,y=150})
panel.ink_widget:pen(device.input,{id=-1,tool=1,x=50,y=150})
for _,shape in ipairs({{1872,1404},{1404,1872},{1872,1404}})do
 screen.w,screen.h=shape[1],shape[2]
 local old=panel._input_widget;local ticks=#ui.ticks
 plugin:onSetDimensions();panel:onScreenResize();panel:queueScreenResize()
 assert(#ui.ticks==ticks+1 and panel._input_widget==old,'resize must be deferred and coalesced')
 assert(panel:handleEvent({handler='onGesture'})==true,'stale coordinates must not trigger a control')
 ui.ticks[#ui.ticks]()
 assert(panel.width==screen.w and panel.layout_screen_height==screen.h)
 assert(panel.transcript_width==screen.w-20 and panel.ink_widget.width==screen.w-20)
 local size=panel.vgroup:getSize();assert(size.w==screen.w and size.h==screen.h)
 assert(panel:getInputText()=='Preserve through rotation'and panel._input_widget.cursor==5)
 assert(#panel.ink_data.strokes==1 and not panel.follow_tail and panel.transcript.anchor==45)
 local refresh=ui.dirty[#ui.dirty];assert(refresh.widget=='all'and refresh.mode=='full')
end
-- Painting is a fallback when the reader handled rotation without broadcasting.
screen.w,screen.h=1404,1872
local ticks=#ui.ticks
panel:paintTo({paintRect=function()end},0,0)
assert(#ui.ticks==ticks+1);ui.ticks[#ui.ticks]();assert(panel.width==screen.w)
-- The keyboard/editor must resize together, without dropping the draft/cursor.
panel:setPenMode(false);panel:toggleKeyboard(true)
panel._input_widget.cursor=8
screen.w,screen.h=1872,1404;panel:onScreenResize();ui.ticks[#ui.ticks]()
assert(panel.keyboard_visible and panel._input_widget.cursor==8 and panel.width==1872)
assert(panel:getInputText()=='Preserve through rotation')
local keyboard_layout=panel.vgroup:getSize()
assert(keyboard_layout.w==screen.w and keyboard_layout.h+600==screen.h)
-- A queued resize must never resurrect a dismissed chat.
screen.w,screen.h=1404,1872;panel:queueScreenResize();local old=panel._input_widget
plugin:hide();ui.ticks[#ui.ticks]();assert(panel._input_widget==old and plugin.viewer==nil)
print('Live rotation checks passed: portrait/landscape round trips, deduplicated deferred layout, stale touch rejection, paint fallback, draft/cursor/ink/scroll retention, full refresh and close safety')

-- Pen entry must settle after its first frame, just as the user's later Clear
-- pad tap restores controls, without actually deleting or rescaling the ink.
screen.w,screen.h=1404,1872
plugin:refresh(true);panel=plugin.viewer
panel:setPenMode(false);panel:setInputText('Retain this draft')
local editor=panel._input_widget
panel.button_table:getButtonById('pen').callback()
assert(not panel.pen_mode and panel._input_widget==editor,'Pen must not free the tapped button tree during feedback')
ui.ticks[#ui.ticks]();assert(panel.pen_mode)
panel.ink_widget:clear()
panel.ink_widget:paintTo({blitFrom=function()end},10,100)
panel.ink_widget:pen(device.input,{id=1,tool=1,x=50,y=150})
panel.ink_widget:pen(device.input,{id=-1,tool=1,x=50,y=150})
local ink=panel.ink_data;local version=ink.version
editor=panel._input_widget
local ticks=#ui.ticks;local waits=ui.vsync_waits or 0
panel:paintTo({paintRect=function()end},0,0)
assert(#ui.ticks==ticks+1 and (ui.vsync_waits or 0)==waits,'follow-up must wait until after the first painted frame')
ui.ticks[#ui.ticks]();assert((ui.vsync_waits or 0)==waits)
ui.ticks[#ui.ticks]()
local refresh=ui.dirty[#ui.dirty]
assert(ui.vsync_waits==waits+1 and refresh.widget==panel and refresh.mode=='partial'and refresh.region==nil)
assert(panel.ink_data==ink and #ink.strokes==1 and ink.version==version,'settling must never clear or mutate handwriting')
assert(panel._input_widget==editor and panel:getInputText()=='Retain this draft')
ticks=#ui.ticks;panel:paintTo({paintRect=function()end},0,0)
assert(#ui.ticks==ticks,'settled paints must not create an endless redraw loop')
-- An active stroke defers the settling pass instead of interrupting writing.
panel.pen_redraw_pending=true;panel.ink_widget.contact_owned=true
panel:paintTo({paintRect=function()end},0,0);ui.ticks[#ui.ticks]();ui.ticks[#ui.ticks]()
assert(panel.pen_redraw_pending and ui.vsync_waits==waits+1)
panel.ink_widget.contact_owned=nil
panel:paintTo({paintRect=function()end},0,0);ui.ticks[#ui.ticks]();ui.ticks[#ui.ticks]()
assert(ui.vsync_waits==waits+2)
-- A popup must finish before the settling pass; never paint through its menu.
ui.getTopmostVisibleWidget=function()return{}end
panel.pen_redraw_pending=true;waits=ui.vsync_waits
panel:paintTo({paintRect=function()end},0,0);ui.ticks[#ui.ticks]();ui.ticks[#ui.ticks]()
assert(panel.pen_redraw_pending and ui.vsync_waits==waits)
ui.getTopmostVisibleWidget=nil
panel:paintTo({paintRect=function()end},0,0);ui.ticks[#ui.ticks]();ui.ticks[#ui.ticks]()
assert(ui.vsync_waits==waits+1)
-- Old callbacks must not repaint a closed or replaced layout.
panel.pen_redraw_pending=true
panel:paintTo({paintRect=function()end},0,0);ui.ticks[#ui.ticks]();local settle=ui.ticks[#ui.ticks]
panel:setPenMode(false);waits=ui.vsync_waits;settle();assert(ui.vsync_waits==waits)
panel:setPenMode(true);panel:paintTo({paintRect=function()end},0,0)
ui.ticks[#ui.ticks]();settle=ui.ticks[#ui.ticks];plugin:hide();settle()
assert(ui.vsync_waits==waits)
print('Pen-entry redraw checks passed: deferred mode switch, post-frame display fence, one follow-up redraw, ink/draft preservation, active-stroke deferral, no loop, stale-layout and close safety')

-- A pen movement writes only its bounded ink rectangle and does not schedule
-- a parent repaint with a mismatched refresh rectangle.
local pad=Pad:new{width=100,height=100,dialog={}}
pad:paintTo({blitFrom=function()end},10,20)
local blits=#screen.ink_blits
pad:pen(device.input,{id=1,tool=1,x=30,y=40})
local refresh=ui.dirty[#ui.dirty];local blit=screen.ink_blits[#screen.ink_blits]
assert(#screen.ink_blits==blits+1 and refresh.widget==nil and refresh.mode=='fast')
assert(blit.x>=10 and blit.y>=20 and blit.x+blit.w<=110 and blit.y+blit.h<=120)
assert(blit.ox==blit.x-10 and blit.oy==blit.y-20)
assert(refresh.region.x==blit.x and refresh.region.w==blit.w)
pad:pen(device.input,{id=-1,tool=1,x=30,y=40})
refresh=ui.dirty[#ui.dirty]
assert(refresh.widget==nil and refresh.mode=='partial'and refresh.region==pad.dimen)
pad:free()
local p=Panel:new{input='',conversation_text='',on_send=function()end,on_stop=function()end,on_more=function()end}
p:paintTo({paintRect=function()end},0,0)
refresh=ui.dirty[#ui.dirty]
assert(refresh.widget==nil and refresh.mode=='ui'and refresh.region==nil,
 'a whole-chat paint must refresh the whole screen without causing another parent paint')
print('Paint/refresh coverage checks passed: bounded stroke blits, pad-only pen-up, no stroke-driven parent repaint, whole-chat refresh coverage without a dirty loop')

-- Real callbacks are delayed: exercise input/close/race behavior independently
-- from the immediate transport double used by the older lifecycle checks.
deferred=true
local function complete(job)
 local ok,data=pcall(job.task);job.callback(ok,data)
end
local function fresh()
 plugin:hide();plugin.recognition_job=nil;plugin.ink_data=nil;plugin.pen_mode=false
 state={active=false,messages={},notice=''};plugin.state=state
 plugin.network_kind=nil;plugin.network_job=nil;plugin.network_ticket=nil
 plugin.draft=nil;fail=false
end
fresh()
local before_requests=#requests
plugin:refresh(true);panel=plugin.viewer
local read=workers[#workers]
assert(panel and #requests==before_requests,'open must show cached chat before network work')
panel:setInputText('Question');plugin:send('Question')
local write=workers[#workers]
assert(read.cancelled and write~=read,'Send must supersede an in-flight state poll')
assert(panel:getInputText()=='Question'and panel.display_title:find('sending',1,true))
assert(not panel.button_table:getButtonById('send').enabled and panel.button_table:getButtonById('stop').enabled)
plugin:send('Question');assert(workers[#workers]==write,'duplicate Send must not start another worker')
panel:setInputText('Newer draft');panel._input_widget.cursor=3
local sending_titles=panel.title_sets
complete(write)
assert(panel.title_sets==sending_titles+1 and panel.display_title:find('replying',1,true),'Send acknowledgment must transition straight to replying without an idle-title rebuild')
assert(panel:getInputText()=='Newer draft'and panel._input_widget.cursor==3,'acknowledgment must preserve edits made during Send')
plugin.state.longPoll=true
plugin:schedulePoll()
assert(ui.delays[plugin.poll]==0.05,'capable bridges must repoll promptly')
plugin.state.longPoll=nil
plugin:schedulePoll()
assert(ui.delays[plugin.poll]==3,'older bridges retain their polling interval')
local accepted=plugin.state
read.callback(true,{active=false,messages={},notice='stale'})
assert(plugin.state==accepted,'late superseded poll must not overwrite accepted Send')
-- Polling stays silent, including when the user is typing.
local dirty=#ui.dirty
plugin.last_edit=os.time();plugin:refresh()
read=workers[#workers]
assert(plugin.network_kind=='refreshing'and #ui.dirty==dirty,'polling must not redraw status or wait for typing to stop')
local shown=#ui.shown
plugin:hide();complete(read)
assert(not plugin.viewer and #ui.shown==shown,'late poll must not reopen chat')

-- Close/reopen during Send retains the draft until acknowledgment, then
-- clears only the acknowledged text. A late failure preserves retry identity.
fresh();plugin:render();panel=plugin.viewer
panel:setInputText('Close while sending');plugin:send(panel:getInputText());write=workers[#workers]
plugin:hide();plugin:refresh(true);panel=plugin.viewer
assert(panel:getInputText()=='Close while sending'and plugin.network_kind=='sending')
complete(write);assert(panel:getInputText()=='','acknowledged saved draft must clear after reopen')
fresh();plugin:render();panel=plugin.viewer
panel:setInputText('Keep on failure');plugin:send(panel:getInputText());write=workers[#workers]
local retry_id=plugin.request_id
plugin:hide();shown=#ui.shown
write.callback(false,'Synthetic timeout')
assert(not plugin.viewer and #ui.shown==shown and plugin.draft=='Keep on failure'and plugin.request_id==retry_id)
plugin:render();plugin:send(plugin.viewer:getInputText())
assert(plugin.request_id==retry_id,'retry after uncertain Send must reuse request ID')
complete(workers[#workers])

-- Stop during submission is queued until the bridge has acknowledged a turn.
fresh();plugin:render();panel=plugin.viewer
panel:setInputText('Stop this');plugin:send(panel:getInputText());write=workers[#workers]
panel.on_stop();assert(plugin.stop_after_send and workers[#workers]==write)
complete(write)
assert(plugin.network_kind=='stopping'and workers[#workers]~=write)
complete(workers[#workers]);assert(requests[#requests].path=='/v1/stop')

-- OCR submission itself is now asynchronous too. Close before its ack must
-- cancel automatic sending; reopening can recover a preview safely.
fresh();plugin:render();panel=plugin.viewer
panel:setPenMode(true)
panel.ink_data.strokes={{{1,1},{2,2}}};panel.ink_data.version=panel.ink_data.version+1
plugin:send('');write=workers[#workers]
assert(panel.ink_busy and plugin.recognition_job and not plugin.recognition_job.id)
plugin:hide();complete(write)
assert(not plugin.recognition_job.auto_send and not plugin.viewer)
plugin:render();panel=plugin.viewer
plugin:recognitionStatus();read=workers[#workers]
assert(panel.ink_busy,'recognition polling must return before completion')
complete(read);assert(panel:getInputText()=='HELLO'and not panel.ink_busy and not plugin.state.active)
plugin:refresh();read=workers[#workers];plugin:onExit()
assert(read.cancelled and not plugin.viewer,'exit must cancel and release outstanding worker')
print('Asynchronous UI checks passed: immediate open, editable pending Send, duplicate suppression, stale poll rejection, silent polling, close/reopen, retry ID, queued Stop, OCR close/preview, exit cleanup')

-- Rendering contracts: simulate stable, painted geometry and explicitly log
-- subwidget writes. These are not an e-ink controller or pixel rendering test.
local paints, erases={},{}
function ui:widgetRepaint(widget,x,y)
 paints[#paints+1]=widget
 widget:paintTo(screen.bb,x,y)
end
function screen.bb:paintRect(x,y,w,h)
 erases[#erases+1]={x=x,y=y,w=w,h=h}
end
local top
ui.getTopmostVisibleWidget=function()return top end
local function renderingPanel(pen,note_mode,keys)
 local p=Panel:new{input='Keep draft',conversation_text='Old answer',reply_active=true,
  pen_mode=pen,note_mode=note_mode,note_has_history=true,keyboard_visible=keys,
  on_send=function()end,on_stop=function()end,on_more=function()end}
 top=p
 -- The real InputDialog computes these coordinates during painting. Use
 -- deterministic non-overlapping coordinates to exercise the paint planner.
 p.title_bar.width=p.width;p.title_bar.height=50
 p.title_bar.getSize=function(w)return{w=w.width,h=w.height}end
 p.button_table.width=p.width;p.button_table.height=60
 p.button_table.getSize=function(w)return{w=w.width,h=w.height}end
 local y={title=0,actions=50,transcript=110,ink_actions=110+p.transcript_height}
 for part,w in pairs(p:paintWidgets())do
  local size=w:getSize()
  w.dimen={x=part=='transcript'and 10 or 0,y=y[part],w=size.w,h=size.h}
  w.paintTo=function(widget,_,x,yy)
   widget.dimen.x=x;widget.dimen.y=yy
   if part=='transcript'then widget.painted_text=widget[1].text end
  end
 end
 p:rememberPaintRegions()
 return p
end
local p=renderingPanel(false)
local old=p.transcript;local editor=p._input_widget
local dirty=#ui.dirty;local before=#paints
p:setNetworkStatus('sending')
p.network_kind=nil;p:updateConversation('The whole completed answer',false)
local task=p.chat_paint_task
assert(task and #ui.dirty==dirty and #paints==before,'related updates must wait for one coalesced paint')
task()
assert(#ui.dirty==dirty+1 and ui.dirty[#ui.dirty].widget==nil,'completed answer/control update must enqueue one refresh without dirtying the parent')
assert(#paints==before+3 and old.freed and p.transcript_holder.painted_text=='The whole completed answer')
assert(p._input_widget==editor and p:getInputText()=='Keep draft','regional reply paint must leave the editor alone')
local region=ui.dirty[#ui.dirty].region
for i=#erases-2,#erases do
 local r=erases[i]
 assert(r.x>=region.x and r.y>=region.y and r.x+r.w<=region.x+region.w and r.y+r.h<=region.y+region.h,
  'refresh must cover every framebuffer write')
end
local builds=transcript_instances;local titles=p.title_sets;dirty=#ui.dirty;before=#paints
for _=1,10 do p:setNetworkStatus('refreshing');p:setNetworkStatus(nil);p:updateConversation(p.conversation_text,false)end
assert(not p.chat_paint_task and transcript_instances==builds and p.title_sets==titles and #ui.dirty==dirty and #paints==before,
 'unchanged polling must not re-layout text, reset titles, paint, or refresh')
-- A text-only update repaints and refreshes only the transcript rectangle.
p:updateConversation('A shorter answer',false);p.chat_paint_task()
assert(paints[#paints]==p.transcript_holder and #ui.dirty==dirty+1)
region=ui.dirty[#ui.dirty].region
assert(region.x==p.paint_regions.transcript.x and region.y==p.paint_regions.transcript.y and region.h==p.paint_regions.transcript.h)

-- Run the actual pinned upstream updateScrollBar implementation through our
-- Transcript override, verifying that it cannot dirty the parent implicitly.
for _,name in ipairs({'ui/bidi','optmath'})do package.preload[name]=function()return{}end end
for _,name in ipairs({'ui/widget/horizontalgroup','ui/widget/horizontalspan','ui/widget/verticalscrollbar'})do
 package.preload[name]=function()return class()end
end
package.preload['ui/widget/textboxwidget']=function()return class()end
local NativeScroll=dofile('reference/koreader-v2026.07.1/ui/widget/scrolltextwidget.lua')
local mock_update_scrollbar=Scroll.updateScrollBar
Scroll.updateScrollBar=NativeScroll.updateScrollBar
local w=p.transcript
w.text_widget={getVisibleHeightRatios=function()return 0.2,0.5 end}
w.v_scroll_bar={set=function(_,low,high)assert(low==0.2 and high==0.5)end}
dirty=#ui.dirty;before=#paints
w:updateScrollBar(true)
assert(#ui.dirty==dirty and p.chat_paint_task and not p.follow_tail,'native scroll must schedule a regional paint and preserve scroll-back intent')
p.chat_paint_task();assert(#paints==before+1 and paints[#paints]==p.transcript_holder and ui.dirty[#ui.dirty].widget==nil)
Scroll.updateScrollBar=mock_update_scrollbar

-- A popup or stylus contact holds paints; a later whole paint consumes them.
p=renderingPanel(true);p:updateConversation('Completed while writing',false)
task=p.chat_paint_task;before=#paints;dirty=#ui.dirty
p.ink_widget.contact_owned=true;task()
assert(#paints==before and #ui.dirty==dirty and p.chat_paint_task==task)
p.ink_widget.contact_owned=nil;top={};task()
assert(#paints==before and p.chat_paint_task==task,'popup must not be overwritten')
top=p;task()
assert(#paints>before and ui.dirty[#ui.dirty].widget==nil)
local pad_top=110+p.transcript_height+p.ink_buttons:getSize().h
region=ui.dirty[#ui.dirty].region
assert(region.y+region.h<=pad_top,'reply/control update must not refresh the writing pad')
p:updateConversation('New complete answer',false);task=p.chat_paint_task
p:paintTo({paintRect=function()end},0,0);before=#paints;dirty=#ui.dirty;task()
assert(#paints==before and #ui.dirty==dirty,'whole paint must consume pending regional work')
-- Missing or changed geometry falls back before any subwidget writes.
p=renderingPanel(false);p.paint_regions.transcript.w=p.paint_regions.transcript.w-1
p:updateConversation('Geometry fallback',false);before=#paints;p.chat_paint_task()
assert(#paints==before and ui.dirty[#ui.dirty].widget==p and ui.dirty[#ui.dirty].region==nil)
p=renderingPanel(false);p:updateConversation('Rotation pending',false);task=p.chat_paint_task
screen.w,screen.h=screen.h,screen.w;before=#paints;task()
assert(#paints==before and ui.dirty[#ui.dirty].widget==p,'rotation must not reuse cached regional geometry')
screen.w,screen.h=screen.h,screen.w
p=renderingPanel(false);p:updateConversation('Relayout pending',false);task=p.chat_paint_task
p:reinit();dirty=#ui.dirty;before=#paints;task()
assert(#paints==before and #ui.dirty==dirty,'reinit must discard paint callbacks from the old layout')
p=renderingPanel(false);p:updateConversation('Close before paint',false);task=p.chat_paint_task
p:onCloseWidget();dirty=#ui.dirty;before=#paints;task()
assert(#paints==before and #ui.dirty==dirty,'closed panel must discard pending paint')

-- Visible transcript strings are cached independently of hidden deltas.
plugin.state={active=true,messages={{role='user',text='Question'},{role='assistant',text='Partial'}},notice=''}
local text=plugin:conversationText();local cache=plugin.text_cache
plugin.state.messages[2].text='A longer hidden partial'
assert(plugin:conversationText()==text and plugin.text_cache==cache,'hidden output must not format or join the transcript again')
plugin.state.active=false
assert(plugin:conversationText():find('A longer hidden partial',1,true)and plugin.text_cache~=cache)
print('Rendering checks passed: one combined refresh for completed reply/control changes, transcript-only writes, idle no-ops, native scroll suppression, draft retention, pen/popup deferral, geometry fallback, whole-paint/close cancellation, visible-text cache')

-- Selection menu -> attachment -> explicit send -> return-to-reader contract.
package.loaded['ui/widget/textviewer']=nil
package.preload['ui/widget/textviewer']=function()return class()end
local document={is_pdf=true,file='/private/NEVER_SEND_BOOK.pdf'}
local reader={document=document,doc_settings=bookSettings(),post={},location={page=12,zoom=2,x=17,y=31},restores=0}
reader.menu={registerToMainMenu=function()end}
function reader:registerPostInitCallback(fn)self.post[#self.post+1]=fn end
reader.highlight={buttons={builtin=function()return{text='Keep builtin'}end}}
function reader.highlight:addToHighlightDialog(id,factory)self.buttons[id]=factory end
function reader.highlight:removeFromHighlightDialog(id)self.buttons[id]=nil end
function reader.highlight:onClose(keep)
 self.closed=(self.closed or 0)+1;self.keep_highlight=keep
 if not keep then self.selected_text=nil end
end
reader.paging={}
function reader.paging:getBookLocation()
 local l=reader.location;return{{page=l.page,zoom=l.zoom,x=l.x,y=l.y}}
end
function reader.paging:onRestoreBookLocation(saved)
 local l=saved[1];reader.location={page=l.page,zoom=l.zoom,x=l.x,y=l.y};reader.restores=reader.restores+1
end
-- Keep the established full-panel contracts as regression coverage; compact
-- note mode is exercised separately below with the actual reading default.
local rp=setmetatable({ui=reader,note_mode=false},{__index=Plugin});rp:init()
assert(not reader.highlight.buttons['05_kobocodex_1_explain'])
for _,fn in ipairs(reader.post)do fn()end
rp:onReaderReady()
assert(reader.highlight.buttons.builtin and reader.highlight.buttons['05_kobocodex_1_explain']and reader.highlight.buttons['05_kobocodex_2_ask'])
local reader_requests={}
local reader_state={active=false,messages={},notice=''}
local pending_worker
rp.run_background=function(task,callback)
 pending_worker={task=task,callback=callback,cancel=function()end};return pending_worker
end
function rp:request(method,path,body)
 reader_requests[#reader_requests+1]={method=method,path=path,body=body}
 if path=='/v1/prompt'then
  reader_state={active=true,messages={{role='user',text=body.text},{role='assistant',text=''}},notice=''}
 elseif path=='/v1/reset'then
  reader_state={active=false,messages={},notice=''}
 end
 return reader_state
end
local function finish_reader_request()
 local worker=pending_worker;pending_worker=nil
 local ok,data=pcall(worker.task);worker.callback(ok,data)
end
local quotation='Une idée précise.\n中文 🌿\nFirst column.\nSecond column.'
local function select_action(explain)
 reader.highlight.selected_text={text=quotation,pos0={page=12,x=1},pos1={page=12,x=20},secret='NEVER_SEND_METADATA'}
 local key=explain and '05_kobocodex_1_explain'or'05_kobocodex_2_ask'
 local action=reader.highlight.buttons[key](reader.highlight)
 assert(action.enabled);action.callback()
 local open=ui.ticks[#ui.ticks];open()
 return rp.viewer
end
rp.draft='Existing unsent question'
local reading_panel=select_action(false)
assert(reading_panel and not pending_worker and #reader_requests==0,'Ask must open locally without sending or importing anything')
assert(reader.highlight.keep_highlight==true and reader.highlight.selected_text.text==quotation and rp.selection_context.text==quotation,
 'Ask must preserve the visible native selection while capturing its text')
assert(reading_panel:getInputText()=='Existing unsent question'and reading_panel.selection_buttons)
assert(reading_panel.button_table:getButtonById('close').text=='Read')
local viewport=reading_panel.vgroup:getSize()
assert(viewport.h==screen.h and viewport.w==screen.w,'selection band must fit the existing viewport')
reading_panel.selection_buttons:getButtonById('selection_preview').callback()
local preview=ui.shown[#ui.shown]
assert(preview.text:find(quotation,1,true)and preview.text:find('will be sent',1,true)and #reader_requests==0)
ui:close(preview)
reading_panel:setInputText('What is the central idea?');reading_panel.on_send(reading_panel:getInputText())
assert(pending_worker and not rp.selection_context.sent and #reader_requests==0)
local attached=rp.selection_context
finish_reader_request()
local payload=reader_requests[#reader_requests].body
assert(payload.text:find(quotation,1,true)and payload.text:find('PDF physical page 12 (1-based)',1,true))
assert(payload.text:find('What is the central idea?',1,true)and not payload.text:find('NEVER_SEND',1,true))
assert(payload.requestId and not payload.documentId and not payload.path and attached.sent)
assert(payload.documentName=='NEVER_SEND_BOOK.pdf'and not payload.text:find(payload.documentName,1,true),'send only basename as separate display/archive metadata, never the file path or model prompt')
assert(reading_panel.conversation_text:find('What is the central idea?',1,true)and
 not reading_panel.conversation_text:find(quotation,1,true)and not reading_panel.conversation_text:find('BEGIN SELECTED',1,true),
 'question display must stay short; the complete quotation belongs in the attachment preview')
assert(reading_panel:getInputText()=='','acknowledged question should clear normally')
-- Return to reading without a gratuitous page jump; recover exact zoom/pan
-- if a layout change has altered the reader beneath the dialog.
reading_panel.button_table:getButtonById('close').callback()
assert(not rp.viewer and reader.location.page==12 and reader.location.zoom==2 and reader.restores==0)
local menu_items={};rp:addToMainMenu(menu_items)
assert(menu_items.kobocodex.sorting_hint=='tools'and dispatcher.actions.kobocodex_resume.event=='ResumeCodex')
local attached_before=rp.selection_context
local requests_before=#reader_requests
assert(menu_items.kobocodex.callback()==true);reading_panel=rp.viewer
assert(reading_panel and rp.selection_context==attached_before and reader.highlight.selected_text.text==quotation,
 'Tools entry must resume chat without requiring or replacing a selection')
finish_reader_request()
assert(#reader_requests==requests_before+1 and reader_requests[#reader_requests].path=='/v1/state',
 'resuming must only fetch state, never send another quotation or reset the conversation')
reader.location={page=13,zoom=1,x=0,y=0};rp:hide()
assert(reader.location.page==12 and reader.location.zoom==2 and reader.location.x==17 and reader.location.y==31 and reader.restores==1)
-- Follow-up uses the same conversation without repeating the quotation.
reader_state.active=false;rp.state=reader_state;rp:render();reading_panel=rp.viewer
reading_panel:setInputText('Give an example');reading_panel.on_send(reading_panel:getInputText());finish_reader_request()
assert(reader_requests[#reader_requests].body.text=='Give an example')

-- Explain preserves existing text/ink and avoids the handwriting OCR path.
reader_state={active=false,messages={},notice=''};rp.state=reader_state;rp:hide()
rp.draft='Keep this independent draft';rp.pen_mode=true
rp.ink_data={width=100,height=100,version=4,strokes={{{10,10},{20,20}}}}
reading_panel=select_action(true)
assert(reading_panel and reading_panel.ink_data and #reading_panel.ink_data.strokes==1 and pending_worker)
finish_reader_request()
assert(reader_requests[#reader_requests].path=='/v1/prompt'and reader_requests[#reader_requests].body.text:find('Explain this passage',1,true))
assert(reading_panel:getInputText()=='Keep this independent draft'and #reading_panel.ink_data.strokes==1)
local old_editor=reading_panel._input_widget;old_editor.cursor=5
reading_panel.selection_buttons:getButtonById('selection_detach').callback()
assert(not rp.selection_context and not reading_panel.selection_buttons and reading_panel:getInputText()=='Keep this independent draft')
assert(reading_panel._input_widget.cursor==5 and #reading_panel.ink_data.strokes==1,'detaching must preserve cursor and ink through layout change')
rp:hide()

-- Closing while Wi-Fi connects cancels the deferred Explain, even after
-- reopening the chat. A plain Ask draft likewise survives cancel/return.
reader_state={active=false,messages={},notice=''};rp.state=reader_state;rp.pen_mode=false;rp.ink_data=nil
local wifi_callback
network.runWhenConnected=function(_,callback)wifi_callback=callback end
reading_panel=select_action(true)
local before=#reader_requests
assert(wifi_callback and not pending_worker)
rp:hide();rp:render();wifi_callback()
assert(not pending_worker and #reader_requests==before,'late Wi-Fi callback must not send after Close/reopen')
network.runWhenConnected=function(_,callback)callback()end
rp:hide();reading_panel=select_action(false)
reading_panel:setInputText('Unsent selection question');rp:hide();rp:render()
assert(rp.viewer:getInputText()=='Unsent selection question'and rp.viewer.selection_buttons)
-- Oversized selection is rejected intact; no silent truncation or send.
local prior=rp.selection_context
reader.highlight.selected_text={text=string.rep('x',12001)}
rp:openSelection(reader.highlight,false)
assert(rp.selection_context==prior and #reader_requests==before)
-- A rejected/uncertain send leaves the exact attachment and retry ID intact.
reading_panel=rp.viewer
reading_panel.on_send(reading_panel:getInputText())
local retry=rp.request_id;local failed_worker=pending_worker;pending_worker=nil
failed_worker.callback(false,'Synthetic send failure')
assert(not rp.selection_context.sent and reading_panel:getInputText()=='Unsent selection question')
reading_panel.on_send(reading_panel:getInputText())
assert(rp.request_id==retry);finish_reader_request()
assert(reader_requests[#reader_requests].body.requestId==retry and reader_requests[#reader_requests].body.text:find(quotation,1,true))
reader_state.active=false;rp.state=reader_state
rp:action('/v1/reset');finish_reader_request()
assert(not rp.selection_context.sent,'reset must reattach the passage for the new conversation')
reading_panel:setInputText('Question after reset');reading_panel.on_send(reading_panel:getInputText());finish_reader_request()
assert(reader_requests[#reader_requests].body.text:find(quotation,1,true))
-- The attachment band fits both orientations, keyboard states and pen mode.
for _,shape in ipairs({{1404,1872},{1872,1404}})do
 screen.w,screen.h=shape[1],shape[2]
 for _,keys in ipairs({false,true})do for _,pen in ipairs({false,true})do
  local pane=Panel:new{input='',conversation_text='',selection_context=prior,selection_label='Passage · PDF p. 12',
   keyboard_visible=keys,pen_mode=pen,on_send=function()end,on_stop=function()end,on_more=function()end}
  local size=pane.vgroup:getSize()
  assert(size.w==screen.w and size.h+(keys and 600 or 0)==screen.h,'selection layout must fit orientation/keyboard/pen combinations')
 end end
end
screen.w,screen.h=1404,1872
-- Closing the document unregisters only our menu entries and never navigates
-- into an old document. Already submitted work must not reopen the reader.
local restores=reader.restores
reader.highlight.selected_text={text=quotation,pos0={page=12},pos1={page=12}}
reader.highlight.buttons['05_kobocodex_2_ask'](reader.highlight).callback()
local pending_open=ui.ticks[#ui.ticks]
rp:onCloseDocument()
pending_open()
assert(not rp.viewer and not rp.selection_context and reader.restores==restores and reader.highlight.buttons.builtin)
assert(not reader.highlight.buttons['05_kobocodex_1_explain']and not reader.highlight.buttons['05_kobocodex_2_ask'])
rp:onReaderReady();assert(not reader.highlight.buttons['05_kobocodex_1_explain'])
-- Rolling documents use the native xpointer API, never a guessed page jump.
local rolling={xpointer='book-location-1',restores=0}
function rolling:getBookLocation()return self.xpointer end
function rolling:onGotoXPointer(xp)self.xpointer=xp;self.restores=self.restores+1 end
local ebook={document={},doc_settings=bookSettings(),rolling=rolling,menu={registerToMainMenu=function()end}}
local ep=setmetatable({ui=ebook},{__index=Plugin});ep:init();ep:render()
rolling.xpointer='book-location-2';ep:hide()
assert(rolling.xpointer=='book-location-1'and rolling.restores==1)
ep:render();ebook.document={};rolling.xpointer='another-book';ep:hide()
assert(rolling.xpointer=='another-book'and rolling.restores==1,'return must not navigate into a different document')
print('Selection-first UI checks passed: supported menu hooks, local Ask/preview, explicit bounded text/page payload, one-tap Read, zoom/pan restoration, follow-up reuse, Explain draft/ink preservation, detach, deferred Wi-Fi cancellation, unsent recovery, document cleanup')

-- Compact note mode is the actual default while a document is open.
local note_reader={document={},doc_settings=bookSettings(),menu={registerToMainMenu=function()end}}
local np=setmetatable({ui=note_reader},{__index=Plugin});np:init()
local note_worker,posted,stops
np.run_background=function(task,callback)
 note_worker={task=task,callback=callback,cancel=function()end};return note_worker
end
function np:request(_,path,body)
 if path=='/v1/stop'then stops=(stops or 0)+1;return self.state end
 posted=body.text
 return{active=true,messages={{role='user',text=posted},{role='assistant',text=''}},notice=''}
end
local function finish_note()
 local job=note_worker;note_worker=nil
 local ok,data=pcall(job.task);job.callback(ok,data)
end
np:render();local note=np.viewer
assert(note.note_mode and note.compact and not note.covers_fullscreen)
assert(note:handleEvent({handler='onGesture'})==true,'visible book must not receive taps/swipes through the note')
assert(note.width<screen.w and note.dialog_frame:getSize().h<screen.h/2 and not note.show_transcript)
assert(note.input_face.size==18 and not note.transcript,'empty note must not allocate an invisible transcript')
assert(#note.buttons==1 and #note.buttons[1]==4 and note.button_table:getButtonById('expand')and not note.button_table:getButtonById('stop'))
note:onShow();ui.ticks[#ui.ticks]()
assert(note.keyboard_visible and note._input_widget.focused~=false,'note must open with the native composer focused and keyboard ready')
note:setInputText('Question with 中文 and the word Codex')
note.button_table:getButtonById('send').callback()
assert(note_worker and note.button_table:getButtonById('send').text=='Stop','Send must become Stop in the same position')
note.button_table:getButtonById('send').callback()
assert(np.stop_after_send,'compact Stop must queue an interrupt during submission')
note:setInputText('Follow-up draft');note._input_widget.cursor=4
finish_note()
assert(note.show_transcript and note:getInputText()=='Follow-up draft'and note._input_widget.cursor==4)
assert(note.transcript.face.size==18)
assert(note_worker and np.network_kind=='stopping');finish_note();assert(stops==1)
local editing=note._input_widget;local waiting=note.transcript
np.state.messages[2].text='Unfinished output';np:render()
assert(note.transcript==waiting and not note.conversation_text:find('Unfinished output',1,true)and #note.response_ranges==0)
local answer='Réponse 中文 🌿\nA complete answer below the question.'
np.state.active=false;np.state.messages[2].text=answer;np:render()
assert(np.viewer==note and note._input_widget==editing and note:getInputText()=='Follow-up draft')
assert(note.transcript.editable==false and note.transcript.highlight_text_selection==false)
assert(note.button_table:getButtonById('send').text=='Send'and #note.response_ranges==1)
local range=note.response_ranges[1]
local chars={};for char in note.conversation_text:gmatch('[^\128-\191][\128-\191]*')do chars[#chars+1]=char end
assert(table.concat(chars,'',range.first,range.last)==answer,'only assistant body characters must be highlighted, including Unicode')
assert(note.transcript.anchor==range.first-6,'completed note must open at the answer header, not its final line')
assert(note.vgroup[2]==note.transcript_frame,'read-only question/answer history must sit directly above the composer')
local title_count=note.title_sets;local transcript=note.transcript
np:render();assert(note.transcript==transcript and note.title_sets==title_count,'unchanged note polls must stay idle')

-- Highlight rectangles come from KOReader's glyph layout, and are clipped to
-- the text bounds. They never alter the editor or the stored response text.
local shaded={}
local tw=note.transcript.text_widget
tw.dimen={x=0,y=0,w=100,h=40};tw.virtual_line_num=2;tw.vertical_string_list={{},{},{}}
tw.getVisLineCount=function()return 2 end
tw.use_xtext=true
tw.getXtextHighlightRects=function(_,first,last,line0,line1)
 assert(first==range.first and last==range.last and line0==2 and line1==3)
 return{{x=-2,y=-5,w=50,h=20},{x=5,y=25,w=200,h=30}}
end
note.transcript:paintTo({darkenRect=function(_,x,y,w,h,factor)
 assert(x>=10 and y>=20 and x+w<=110 and y+h<=60 and factor==0.16)
 shaded[#shaded+1]={x,y,w,h}
end},10,20)
assert(#shaded==2 and note:getInputText()=='Follow-up draft'and note.transcript.text==note.conversation_text)

-- Mode switches use the same panel and preserve cursor/draft/ink. Compact
-- has fewer controls; expanding exposes the existing keyboard/pen actions.
note._input_widget.cursor=3
note.button_table:getButtonById('expand').callback();ui.ticks[#ui.ticks]()
assert(np.viewer==note and not note.compact and note.covers_fullscreen and #note.buttons==2)
assert(note:getInputText()=='Follow-up draft'and note._input_widget.cursor==3 and note.button_table:getButtonById('keyboard'))
assert(not note.keyboard_visible and note.vgroup:getSize().h==screen.h,'Expand must give reading the full screen without keyboard')
local reading_height=note.transcript_height
note.button_table:getButtonById('keyboard').callback()
assert(note.keyboard_visible and note.transcript_height==reading_height-600,'Keys must restore keyboard and resize transcript')
note.button_table:getButtonById('keyboard').callback()
assert(not note.keyboard_visible and note.transcript_height==reading_height,'Keys must also hide keyboard after a forced hide')

-- More must finish its button event before hiding keys and creating a modal
-- popup. Pending composer focus cannot raise a keyboard above that popup.
note:onSwitchFocus(note._input_widget);local delayed_focus=ui.ticks[#ui.ticks]
local shown_before=#ui.shown
note.button_table:getButtonById('more').callback()
note.button_table:getButtonById('more').callback()
local more_task=ui.ticks[#ui.ticks]
delayed_focus();assert(not note.keyboard_visible,'More must cancel queued keyboard opening')
assert(#ui.shown==shown_before,'More must not rebuild inside button dispatch')
more_task()
local conversation=ui.shown[#ui.shown]
assert(#ui.shown==shown_before+1 and conversation.title=='Conversation')
assert(conversation.modal and conversation.stop_events_propagation and note.modal_overlay_count==1,'menu must stack above keyboard and block underlying events')
local forwarded=note.forwarded_event
assert(note:handleEvent({handler='onGesture'})==true and note.forwarded_event==forwarded,'covered Read/Compact controls must not receive gestures')
local tick_count=#ui.ticks
note:onSwitchFocus(note._input_widget)
assert(#ui.ticks==tick_count,'covered composer must not schedule a keyboard')
local back=conversation.buttons[#conversation.buttons][1]
assert(back.text=='Back to chat');back.callback()
assert(note.modal_overlay_count==0 and not note.keyboard_visible,'Back must release chat without restoring keyboard')
assert(note:getInputText()=='Follow-up draft'and note._input_widget.cursor==3)
-- Also enter More from an already visible keyboard, then dismiss outside
-- through the same close lifecycle used by ButtonDialog:onTapClose.
note.button_table:getButtonById('keyboard').callback()
assert(note.keyboard_visible)
note.button_table:getButtonById('more').callback();ui.ticks[#ui.ticks]()
assert(not note.keyboard_visible and note.transcript_height==reading_height)
conversation=ui.shown[#ui.shown];ui:close(conversation)
assert(note.modal_overlay_count==0 and not note.keyboard_visible)
-- Expand must win over focus callbacks queued earlier in the same UI tick.
note:onSwitchFocus(note._input_widget);delayed_focus=ui.ticks[#ui.ticks]
note:queueExpanded(true);local expand_task=ui.ticks[#ui.ticks]
delayed_focus();expand_task();assert(not note.keyboard_visible)
note:setPenMode(true)
assert(note.pen_mode and not note.compact)
note.ink_data.strokes={{{10,10},{20,20}}};note.ink_data.version=note.ink_data.version+1
note.button_table:getButtonById('expand').callback();ui.ticks[#ui.ticks]()
assert(note.compact and not note.pen_mode and #note.ink_data.strokes==1 and note:getInputText()=='Follow-up draft')
assert(note._input_widget.cursor==3 and not note.covers_fullscreen)

-- Simulate the native FrameContainer paint to verify that a compact repaint
-- writes/refreshes its frame, leaving book pixels outside it untouched.
local input_paint=Input.paintTo
Input.paintTo=function(panel,buffer,x,y)
 local s=panel.dialog_frame:getSize()
 local keyboard=panel.keyboard_visible and 600 or 0
 local r={x=x+math.floor((screen.w-s.w)/2),y=y+math.floor((screen.h-keyboard-s.h)/2),w=s.w,h=s.h}
 panel.dialog_frame.dimen=r
 buffer:paintRect(r.x,r.y,r.w,r.h,255)
end
local rectangles={}
note:paintTo({paintRect=function(_,x,y,w,h)rectangles[#rectangles+1]={x=x,y=y,w=w,h=h}end},0,0)
assert(#rectangles==1 and rectangles[1].w<screen.w and rectangles[1].h<screen.h)
assert(ui.dirty[#ui.dirty].widget==nil and ui.dirty[#ui.dirty].region==note.dialog_frame.dimen,
 'note repaint must refresh exactly its frame rather than the whole screen')
Input.paintTo=input_paint

-- Small initial note and bounded history view both fit above the keyboard in
-- either orientation, with and without a passage attachment.
for _,shape in ipairs({{1404,1872},{1872,1404}})do
 screen.w,screen.h=shape[1],shape[2]
 for _,keys in ipairs({false,true})do for _,history in ipairs({false,true})do for _,attached in ipairs({false,true})do
  local p=Panel:new{note_mode=true,note_has_history=history,keyboard_visible=keys,
   input='Question',conversation_text='Question\n\nCodex\nAnswer',reply_active=false,
   selection_context=attached and prior or nil,selection_label='Passage · PDF p. 12',
   on_send=function()end,on_stop=function()end,on_more=function()end}
  local size=p.dialog_frame:getSize()
  assert(p.compact and size.w<screen.w and size.h<screen.h-(keys and 600 or 0),'compact note must fit above keyboard with book visible')
  assert((p.show_transcript and true or false)==history and (not p.transcript or p.transcript.editable==false))
  if attached then assert(#p.selection_buttons.buttons[1]==1,'compact attachment should be one quiet preview line')end
 end end end
end
screen.w,screen.h=1404,1872
np:hide();assert(not np.viewer and np.draft=='Follow-up draft'and #np.ink_data.strokes==1)
print('Compact note checks passed: reading default, focused native editor, bounded dialog, four controls, inline read-only history, complete-only Unicode response shading, answer-start view, shared Send/Stop, draft/cursor/ink retention, expand/collapse, frame-only painting and orientation/keyboard/attachment sizing')

-- A native VirtualKeyboard is a separate topmost modal widget. It leaves the
-- compact transcript visible; native pan/swipe/scrollbar handlers must still
-- be able to refresh that area, without painting any keyboard or popup pixels.
local panel=renderingPanel(false,true,true)
local keyboard={name='VirtualKeyboard',visible=true,dimen={x=0,y=screen.h-600,w=screen.w,h=600}}
panel._input_widget.keyboard=keyboard
local stack={keyboard,panel}
ui.getTopmostVisibleWidget=function()return stack[1]end
function ui:topdown_widgets_iter()
 local i=0;return function()i=i+1;return stack[i]end
end
assert(panel.compact and panel:canPaintChat())
local scroll=panel.transcript
scroll.v_scroll_bar={set=function()end}
local line=1
package.loaded.optmath.round=function(n)return math.floor(n+0.5)end
scroll.getLineHeight=function()return 20 end
local lines={};for i=1,400 do lines[i]={}end
scroll.text_widget={virtual_line_num=1,vertical_string_list=lines,
 getVisLineCount=function()return 20 end,
 getVisibleHeightRatios=function()return(line-1)/400,(line+19)/400 end,
 scrollLines=function(t,n)line=math.max(1,line+n);t.virtual_line_num=line end,
 scrollDown=function(t)line=line+20;t.virtual_line_num=line end,
 scrollUp=function(t)line=math.max(1,line-20);t.virtual_line_num=line end,
 scrollToRatio=function(t,ratio)line=math.floor(ratio*400)+1;t.virtual_line_num=line end}
scroll.updateScrollBar=getmetatable(scroll).updateScrollBar
Scroll.updateScrollBar=NativeScroll.updateScrollBar
scroll.scrollText=NativeScroll.scrollText
local function assert_scroll_painted(before_line,gesture)
 local before=#paints;local dirty=#ui.dirty
 gesture()
 assert(line~=before_line and panel.chat_paint_task,'native scroll handler must change viewport and queue paint')
 panel.chat_paint_task()
 assert(#paints==before+1 and paints[#paints]==panel.transcript_holder,'own keyboard must not defer transcript painting')
 assert(#ui.dirty==dirty+1 and ui.dirty[#ui.dirty].widget==nil,'scroll must stay a regional refresh, without repainting parent or keyboard')
 local r=ui.dirty[#ui.dirty].region
 assert(r.y+r.h<=keyboard.dimen.y,'scroll refresh must remain above the keyboard')
end
assert_scroll_painted(line,function()
 NativeScroll.onPanText(scroll,nil,{direction='north',relative={x=0,y=-80}})
 NativeScroll.onPanReleaseText(scroll)
end)
assert_scroll_painted(line,function()NativeScroll.onScrollText(scroll,nil,{direction='north'})end)
assert_scroll_painted(line,function()NativeScroll.scrollToRatio(scroll,0.5,false)end)
assert(not panel.follow_tail,'reading older text must retain its scroll-back anchor')
-- Actual popups and keyboard key-popups still block direct paints, including
-- a popup underneath the keyboard but above the chat.
local popup={name='popup'}
stack={popup,keyboard,panel};panel:queueChatPaint('transcript')
local task=panel.chat_paint_task;local before=#paints;task()
assert(#paints==before and panel.chat_paint_task==task)
stack={keyboard,popup,panel};task()
assert(#paints==before and panel.chat_paint_task==task,'intervening popup must remain protected')
stack={keyboard,panel};task()
assert(#paints==before+1 and not panel.chat_paint_task)
local bounds=keyboard.dimen;keyboard.dimen=nil
panel:queueChatPaint('transcript');task=panel.chat_paint_task;before=#paints;task()
assert(#paints==before and panel.chat_paint_task==task,'wait until own keyboard has painted bounds')
keyboard.dimen=bounds;task();assert(#paints==before+1)
-- If a stale transcript rectangle overlaps the keyboard, let UIManager
-- repaint the stack normally, rather than blitting through the keyboard.
keyboard.dimen={x=0,y=100,w=screen.w,h=screen.h-100}
before=#paints;panel:queueChatPaint('transcript');panel.chat_paint_task()
assert(#paints==before and ui.dirty[#ui.dirty].widget==panel,'overlap must use the normal stacked repaint fallback')
Scroll.updateScrollBar=mock_update_scrollbar
print('Keyboard-visible scrolling checks passed: native pan, swipe and scrollbar change+paint, own-keyboard identity/stack check, refresh above keyboard, popup deferral, unknown bounds and overlap fallback')

-- Independent ReaderUI instances for A, B, then A again, with each native
-- per-book settings table retained across ordinary document close/reopen.
local document_history={}
local function scopedReader(settings,byte)
 local reader={document={file='/private/NEVER_SEND_DOCUMENT_'..byte..'.pdf'},doc_settings=settings,
  menu={registerToMainMenu=function()end}}
 local instance=setmetatable({ui=reader,document_entropy=function()return string.rep(string.char(byte),16)end},{__index=Plugin})
 instance:init()
 instance.jobs={};instance.calls={}
 instance.run_background=function(task,callback)
  local job={task=task,callback=callback,cancel=function()end};instance.jobs[#instance.jobs+1]=job;return job
 end
 function instance:request(method,path,body,id)
  assert(id and #id==32 and not id:find('NEVER_SEND',1,true))
  self.calls[#self.calls+1]={path=path,id=id,body=body}
  local state=document_history[id]or{active=false,messages={},notice='',documentId=id}
  if path=='/v1/prompt'then
   state={active=false,messages={{role='user',text=body.text},{role='assistant',text='Answer '..body.text}},notice='',documentId=id}
  elseif path=='/v1/reset'then state={active=false,messages={},notice='',documentId=id}end
  document_history[id]=state;return state
 end
 function instance:finish()
  local job=table.remove(self.jobs,1);local ok,data=pcall(job.task);job.callback(ok,data)
 end
 return instance
end
local settingsA,settingsB=bookSettings(),bookSettings()
local docA=scopedReader(settingsA,1);docA:render();docA.viewer:setInputText('Question A');docA:send('Question A')
local idA=settingsA.data.kobocodex_chat_scope.id
assert(#docA.calls==0 and idA,'document identity must be saved in parent before the worker runs')
docA:finish();docA:onCloseDocument()
local docB=scopedReader(settingsB,2);docB:onResumeCodex();docB:finish()
assert(#docB.state.messages==0,'new PDF must not show another PDF chat')
docB.viewer:setInputText('Question B');docB:send('Question B');docB:finish();docB:onCloseDocument()
local idB=settingsB.data.kobocodex_chat_scope.id
assert(idA~=idB)
local againA=scopedReader(settingsA,3);againA:onResumeCodex();againA:finish()
assert(againA.calls[1].id==idA and againA.viewer.conversation_text:find('Answer Question A',1,true))
assert(not againA.viewer.conversation_text:find('Question B',1,true))
againA:action('/v1/reset');againA:finish()
assert(#document_history[idA].messages==0 and #document_history[idB].messages==2,'New chat must reset only this document')
againA:onCloseDocument()
local missing=scopedReader(nil,4);local called=false
missing:requestAsync('GET','/v1/state',nil,'refreshing',function(ok,err)called=true;assert(not ok and tostring(err):find('Book settings',1,true))end)
assert(called and #missing.jobs==0,'a book without usable identity must not fall back to the general chat')

-- Exercise the actual client request/transport path, without a real pairing
-- file: synthetic I/O and TLS doubles verify scoped URLs and response IDs.
local io_open=io.open;local json_module=package.loaded.json;local decode=json_module.decode
local saved_socket,saved_ssl=package.loaded.socket,package.loaded.ssl
local config={host='bridge.example',port=9443,token=string.rep('b',64),fingerprint=string.rep('a',64)}
local response_data={documentId=idA,active=false,messages={},notice=''}
local status=200;local response,offset,request_line
local connection={}
function connection:settimeout()end
function connection:connect()return true end
function connection:dohandshake()return true end
function connection:getpeercertificate()return{digest=function()return config.fingerprint end}end
function connection:send(payload,first)request_line=payload:match('^(.-)\r\n');return #payload end
function connection:receive(n)local data=response:sub(offset,offset+n-1);offset=offset+n;return data end
function connection:close()end
package.loaded.socket={tcp=function()return connection end,gettime=function()return 1 end}
package.loaded.ssl={wrap=function(c)return c end}
io.open=function(path,mode)
 if path:match('/connection.json$')then return{read=function()return'SYNTHETIC_CONFIG'end,close=function()end}end
 return io_open(path,mode)
end
json_module.decode=function(raw)if raw=='SYNTHETIC_CONFIG'then return config else return response_data end end
local function actual_request(id)
 response='HTTP/1.1 '..status..' OK\r\nContent-Length: 2\r\n\r\n{}';offset=1
 return Plugin.request(againA,'GET','/v1/state',nil,id)
end
assert(actual_request(idA).documentId==idA and request_line=='GET /v1/documents/'..idA..'/state HTTP/1.1')
response_data={documentId=idB,active=false,messages={},notice=''}
assert(not pcall(actual_request,idA),'wrong-document response must be rejected')
status=404;response_data={error='Unknown endpoint'}
local ok,err=pcall(actual_request,idA);assert(not ok and tostring(err):find('Update the Mac bridge',1,true))
status=200;response_data={active=false,messages={},notice=''}
actual_request(nil);assert(request_line=='GET /v1/state HTTP/1.1','general chat remains separately addressable')
io.open=io_open;json_module.decode=decode;package.loaded.socket=saved_socket;package.loaded.ssl=saved_ssl
print('Per-document client checks passed: parent-side ID creation, independent reader instances, A/B/A resume, document-only reset, no missing-ID fallback, actual scoped TLS URLs, response identity check, legacy bridge refusal and general chat separation')

-- History uses the same background worker and reader-specific identity. Paging
-- reuses metadata locally; reopening preserves draft/ink and clears old context.
local archivedReader=scopedReader(bookSettings(),5)
archivedReader:render();local archivedPanel=archivedReader.viewer
archivedPanel:setInputText('Keep this draft')
archivedReader.pending_text='failed prior text';archivedReader.request_id='failed-prior-request'
archivedReader.selection_context={text='Previous attachment',document=archivedReader.ui.document}
archivedPanel:setSelectionContext(archivedReader.selection_context,'Old passage')
local inkBefore=archivedPanel.ink_data
local archives={}
for i=1,7 do archives[i]={id=string.rep(string.format('%x',i),32),title='Saved question '..i,createdAt='2026-11-07T20:00:00Z'}end
local failHistory,failReopen=false,false
function archivedReader:request(method,path,body,id)
 self.calls[#self.calls+1]={method=method,path=path,body=body,id=id}
 assert(id==self.ui.doc_settings.data.kobocodex_chat_scope.id)
 if path=='/v1/history'then
  if failHistory then error('History unavailable')end
  return{documentId=id,archives=archives}
 elseif path=='/v1/reopen'then
  if failReopen then error('Could not save current conversation')end
  return{documentId=id,active=false,messages={{role='user',text='Saved question'},{role='assistant',text='Saved answer'}},notice='Reopened'}
 end
 error('Unexpected operation')
end
local function button(dialog,label)
 for _,row in ipairs(dialog.buttons)do for _,item in ipairs(row)do if item.text==label then return item end end end
end
archivedReader:more();assert(button(ui.shown[#ui.shown],'Chat history'))
button(ui.shown[#ui.shown],'New chat').callback()
assert(ui.shown[#ui.shown].text:find('Archive this conversation',1,true))
local beforeHistory=#ui.shown
archivedReader:history()
assert(#ui.shown==beforeHistory and archivedReader.network_kind=='history','list network request must not block or create a premature menu')
assert(archivedPanel:getInputText()=='Keep this draft')
archivedReader:finish();local historyMenu=ui.shown[#ui.shown]
assert(historyMenu.title=='Chat history — 1/2 — NEVER_SEND_DOCUMENT_5.pdf'and #historyMenu.buttons==7)
assert(archivedReader.calls[#archivedReader.calls].path=='/v1/history')
local numberCalls=#archivedReader.calls
button(historyMenu,'Next').callback();historyMenu=ui.shown[#ui.shown]
assert(historyMenu.title=='Chat history — 2/2 — NEVER_SEND_DOCUMENT_5.pdf'and #archivedReader.calls==numberCalls,'history page changes must not request or redraw the chat')
button(historyMenu,'Previous').callback();historyMenu=ui.shown[#ui.shown]
historyMenu.buttons[1][1].callback();local confirmation=ui.shown[#ui.shown]
assert(confirmation.text:find('current chat will be archived',1,true))
failReopen=true;confirmation.ok_callback();archivedReader:finish()
assert(archivedReader.selection_context and archivedPanel:getInputText()=='Keep this draft','failed reopen preserves current attachment and draft')
assert(archivedReader.request_id=='failed-prior-request','failed reopen must preserve retry state')
failReopen=false;archivedReader:reopenChat(archives[1].id);archivedReader:finish()
assert(archivedReader.calls[#archivedReader.calls].body.archiveId==archives[1].id)
assert(archivedReader.viewer==archivedPanel and archivedPanel:getInputText()=='Keep this draft'and archivedPanel.ink_data==inkBefore)
assert(not archivedReader.selection_context and not archivedPanel.selection_context and not archivedPanel.selection_buttons,'reopen removes stale passage controls')
assert(not archivedReader.pending_text and not archivedReader.request_id)
assert(archivedPanel.conversation_text:find('Saved answer',1,true))
archivedReader.state.active=true;numberCalls=#archivedReader.calls
archivedReader:reopenChat(archives[2].id);assert(#archivedReader.jobs==0 and #archivedReader.calls==numberCalls,'cannot switch a running reply')
archivedReader.state.active=false;archivedReader:history();archivedReader:hide();beforeHistory=#ui.shown
archivedReader:finish();assert(#ui.shown==beforeHistory and not archivedReader.viewer,'late history result must not reopen a dismissed reader')
archivedReader:render();failHistory=true;archivedReader:history();archivedReader:finish()
assert(archivedReader.viewer:getInputText()=='Keep this draft')
archivedReader:showHistory({},1);assert(ui.shown[#ui.shown].title=='No saved chats — NEVER_SEND_DOCUMENT_5.pdf')
plugin:more();assert(not button(ui.shown[#ui.shown],'Chat history'),'file-manager/general chat has no book history')
print('Archive UI checks passed: document-only controls, non-blocking metadata load, five-entry local pagination, archive confirmation, scoped reopen, failure/draft/ink preservation, stale attachment/retry cleanup, busy refusal and close safety')
