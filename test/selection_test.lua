local Selection=dofile('kobocodex.koplugin/selection.lua')
local document={is_pdf=true,file='/private/reader/NEVER_SEND.pdf'}
local selected={text='« Déjà vu »\n中文 — العربية 🌿\nColumn one.\nColumn two.',
 pos0={page=12,x=10,y=20},pos1={page=13,x=40,y=50},
 metadata='NEVER_SEND_METADATA',pboxes={{x=10,y=20}},file=document.file}
local context=assert(Selection.capture(selected,document))
assert(context.text==selected.text and context.first_page==12 and context.last_page==13)
selected.text='Reused selection table';selected.pos0.page=99
assert(context.text~='Reused selection table'and context.first_page==12,'capture must survive native selection cleanup/mutation')
local prompt=Selection.prompt('What does this mean?',context)
assert(prompt:find(context.text,1,true)and prompt:find('PDF physical page 12–13 (1-based)',1,true))
assert(not prompt:find('NEVER_SEND',1,true)and not context.metadata and not context.pboxes)
assert(Selection.source(context):find('physical',1,true)and Selection.label(context):find('12–13',1,true))
context.sent=true;assert(Selection.prompt('Follow-up',context)=='Follow-up','do not resend the same quote on every turn')
assert(Selection.prompt('General question',nil)=='General question')
for _,text in ipairs({'',' \n\t',string.rep('x',12001)})do assert(not Selection.capture({text=text},document))end
assert(not Selection.capture(nil,document))
assert(Selection.capture({text=string.rep('é',6000)},document))
assert(not Selection.capture({text=string.rep('é',6001)},document),'selection cap must count UTF-8 bytes')
for _,bad in ipairs({0,-1,1.5,math.huge,'12'})do
 local c=assert(Selection.capture({text='Passage',pos0={page=bad}},document))
 assert(not c.first_page and Selection.source(c):find('unavailable',1,true))
end
local c=assert(Selection.capture({text='Reversed',pos0={page=8},pos1={page=7}},document))
assert(c.first_page==7 and c.last_page==8)
c=assert(Selection.capture({text='EPUB quotation',pos0='/body/DocFragment[1]/p[7]',pos1='/body/DocFragment[1]/p[8]'},{}))
assert(not c.first_page and not Selection.prompt('Explain',c):find('/body/',1,true),'xpointer must stay local')
assert(Selection.sameLocation({{page=12,zoom=2,offset={x=4,y=8}}},{{page=12,zoom=2,offset={x=4,y=8}}}))
assert(not Selection.sameLocation({{page=12}},{{page=13}}))
print('Selection checks passed: exact Unicode/multicolumn text, detached capture, numeric physical-page provenance, no paths/boxes/metadata/xpointers in prompts, byte bounds, follow-up deduplication, view-context comparison')
