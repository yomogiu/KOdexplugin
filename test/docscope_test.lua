local Scope=dofile('kobocodex.koplugin/docscope.lua')
assert(Scope.name({file='/mnt/onboard/Books/Private/Example 中文.pdf'})=='Example 中文.pdf')
assert(Scope.name({file='C:\\Books\\Example.pdf'})=='Example.pdf')
for _,file in ipairs({'','/','..','bad\nname.pdf',string.rep('a',241)})do assert(not Scope.name({file=file}))end
assert(not Scope.name(nil))
local function settings()
 local data={partial_md5_checksum=string.rep('a',32)}
 return {data=data,readSetting=function(_,key)return data[key]end,saveSetting=function(_,key,value)data[key]=value end}
end
local a,b=settings(),settings()
local first=Scope.id(a,function()return string.rep('\1',16)end)
local second=Scope.id(b,function()return string.rep('\2',16)end)
assert(Scope.valid(first)and Scope.valid(second)and first~=second)
assert(Scope.id(a,function()error('must reuse persisted identity')end)==first)
local reopened={readSetting=a.readSetting,saveSetting=a.saveSetting}
assert(Scope.id(reopened,function()error('must survive reader instance recreation')end)==first)
a.data.partial_md5_checksum=string.rep('b',32)
local changed=Scope.id(a,function()return string.rep('\3',16)end)
assert(changed~=first,'changed native book fingerprint must receive a fresh conversation identity')
assert(not pcall(Scope.id,nil),'missing book metadata must fail closed rather than use shared chat')
assert(not pcall(Scope.id,settings(),function()return 'short'end))
assert(Scope.path('/v1/state',changed)=='/v1/documents/'..changed..'/state')
assert(Scope.path('/v1/prompt',changed)=='/v1/documents/'..changed..'/prompt')
assert(Scope.path('/v1/stop',changed)=='/v1/documents/'..changed..'/stop')
assert(Scope.path('/v1/reset',changed)=='/v1/documents/'..changed..'/reset')
assert(Scope.path('/v1/history',changed)=='/v1/documents/'..changed..'/history')
assert(Scope.path('/v1/reopen',changed)=='/v1/documents/'..changed..'/reopen')
assert(Scope.path('/v1/recognize',changed)=='/v1/recognize','OCR worker is not a document file endpoint')
assert(Scope.path('/v1/state',nil)=='/v1/state','file-manager/general chat remains explicit')
for _,bad in ipairs({'','book.pdf','/mnt/onboard/book.pdf','../state',string.rep('a',31),string.rep('A',32)})do
 assert(not Scope.valid(bad));assert(not pcall(Scope.path,'/v1/state',bad))
end
print('Document scope checks passed: distinct opaque IDs, per-book metadata reuse, native-fingerprint invalidation, safe chat routes, OCR/general separation, missing-settings and malformed-ID refusal; no book reads or copies')
