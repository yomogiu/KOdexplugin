-- Verify that local troubleshooting can capture controls only, never content.
local files,metadata,crops = {},nil,{}
local screen={night_mode=true}
function screen:getWidth()return 1404 end
function screen:getHeight()return 1872 end
function screen:scaleBySize(n)return n end
screen.bb={viewport=function(_,x,y,w,h)
 crops[#crops+1]={x=x,y=y,w=w,h=h}
 return{copy=function()return{
  invert=function()end,free=function()end,
  writePNG=function(_,path)files[path]='CONTROL_PIXELS_ONLY'end,
 }end}
end}
local device={screen=screen}
package.preload.device=function()return device end
local ui={}
package.preload['ui/uimanager']=function()return ui end
package.preload.lfs=function()return{mkdir=function()return true end}end
package.preload.json=function()return{encode=function(value)metadata=value;return 'SANITIZED_GEOMETRY'end}end
local open,remove=io.open,os.remove
io.open=function(path)
 return{write=function(_,text)assert(type(text)=='string');files[path]=text end,close=function()end}
end
os.remove=function(path)files[path]=nil end
local function box(x,y,w,h)return{dimen={x=x,y=y,w=w,h=h}}end
local panel={pen_mode=true,layout_screen_width=1404,layout_screen_height=1872,layout_generation=1,
 button_table=box(10,50,1384,60),ink_buttons=box(10,800,1384,60),
 _input_widget=box(10,120,1384,80),transcript_holder=box(10,210,1384,580),
 ink_widget=box(10,870,1384,900),
 -- These values must never be read, encoded, photographed, or sent anywhere.
 input='PRIVATE_DRAFT_CANARY',conversation_text='PRIVATE_CHAT_CANARY',
 ink_data={strokes={'PRIVATE_INK_CANARY'}},connection={token='PRIVATE_TOKEN_CANARY'},
}
local D=dofile('kobocodex.koplugin/displaydiagnostics.lua')
assert(D.capture(panel,'before-clear'))
assert(#crops==2 and crops[1].y==50 and crops[1].h==60 and crops[2].y==800)
assert(crops[1].w==1404 and metadata.rows[1].captured and metadata.rows[2].captured)
local allowed={schema=true,phase=true,width=true,height=true,layout_width=true,layout_height=true,generation=true,night_mode=true,rows=true}
for key in pairs(metadata)do assert(allowed[key],'metadata may contain geometry only')end
for path,value in pairs(files)do
 assert(not value:find('PRIVATE_') and path:find('/display%-diagnostics/'))
end
-- A stale row overlapping even one content region must not be captured.
panel.button_table.dimen.y=140;crops={}
assert(D.capture(panel,'before-clear'))
assert(#crops==1 and not metadata.rows[1].captured and metadata.rows[2].captured)
-- Missing dynamic bounds means no image, even if the other bounds look safe.
panel._input_widget.dimen=nil;crops={}
assert(D.capture(panel,'after-clear'));assert(#crops==0)
-- A popup, a closed chat, or an invalid phase must cause no writes/captures.
ui.getTopmostVisibleWidget=function()return{}end
assert(not D.capture(panel,'before-clear'));ui.getTopmostVisibleWidget=nil
panel.dismissed=true;assert(not D.capture(panel,'before-clear'));panel.dismissed=nil
assert(not D.capture(panel,'../../connection.json'))
io.open,os.remove=open,remove
print('Local display diagnostics checks passed: controls-only crops, geometry-only metadata, overlap/missing-bound refusal, stale-image removal, popup/close safety and fixed output paths')
