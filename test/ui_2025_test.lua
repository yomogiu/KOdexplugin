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
function ui:scheduleIn(_,f)self.scheduled[f]=true end
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
function Buttons:getSize()return{h=60,w=self.width}end
function Buttons:getButtonById(id)
 for _,row in ipairs(self.buttons)do for _,b in ipairs(row)do if b.id==id then
  function b:enable()self.enabled=true end
  function b:disable()self.enabled=false end
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
package.preload['ui/font']=function()return{getFace=function()return{}end}end
local Frame=class()
function Frame:getSize()
 local s=self[1].getSize and self[1]:getSize() or {w=self[1].width,h=self[1].height}
 return{w=s.w+2*self.padding,h=s.h+2*self.padding}
end
package.preload['ui/widget/container/framecontainer']=function()return Frame end
local Scroll=class()
function Scroll:init()self.scroll_callback(0,0.2)end
function Scroll:getSize()return{w=self.width,h=self.height}end
function Scroll:free()self.freed=true end
function Scroll:scrollToBottom()self.bottom=true;self.scroll_callback(0.8,1)end
function Scroll:getCharPosAtXY()return 45 end
function Scroll:moveCursorToCharPos(p)self.anchor=p end
package.preload['ui/widget/scrolltextwidget']=function()return Scroll end
local instances=0
local Input=class()
function Input:init()
 instances=instances+1
 self._input_widget={text=self.input or '',cursor=self._charpos or #(self.input or '')}
 function self._input_widget:getKeyboardDimen()return{h=600}end
 local function box(w,h)return{getSize=function()return{w=w,h=h}end}end
 self.vgroup=Group:new{box(self.width,50),box(0,0),box(self.width,self.text_height),box(0,0),box(self.width,60)}
 self.dialog_frame={getSize=function()return{h=50+self.text_height+60}end}
 self.button_table={getButtonById=function(_,id)
  for _,row in ipairs(self.buttons)do for _,b in ipairs(row)do if b.id==id then
   function b:enable()self.enabled=true end
   function b:disable()self.enabled=false end
   return b
  end end end
 end}
 self.title_bar={setTitle=function(_,t)self.display_title=t end}
end
function Input:getInputText()return self._input_widget.text end
function Input:setInputText(t)self._input_widget.text=t;self._input_widget.cursor=#t end
function Input:isKeyboardVisible()return self.keyboard_visible end
function Input:lockKeyboard()end
function Input:toggleKeyboard(force)
 self.input=self:getInputText();self._charpos=self._input_widget.cursor
 if force==nil then self.keyboard_visible=not self.keyboard_visible else self.keyboard_visible=force end
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
package.preload['ui/network/manager']=function()return{}end
local Plugin=dofile('kobocodex.koplugin/main.lua')
local registered
local plugin=setmetatable({ui={menu={registerToMainMenu=function(_,p)registered=p end}}},{__index=Plugin})
plugin:init();assert(registered==plugin)
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
state.messages[2].text='A streamed reply';plugin:refresh(true)
assert(panel._input_widget==composer and instances==count,'reply update must not recreate input')
assert(panel:getInputText()=='Follow-up draft'and composer.cursor==7 and panel.keyboard_visible)
panel.follow_tail=false;state.messages[2].text='A longer reply';plugin:refresh(true)
assert(panel.transcript.anchor==45,'preserve reading anchor')
panel:latest();assert(panel.follow_tail and panel.transcript.bottom)
state.active=false;plugin:refresh(true)
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
