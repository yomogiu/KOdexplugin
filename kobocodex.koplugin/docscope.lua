-- Opaque conversation identity in KOReader's ordinary per-book settings.
-- Never reads/copies a book or sends a folder path/fingerprint to the bridge.
local Scope = {}
local KEY = "kobocodex_chat_scope"

function Scope.name(document)
    local file=document and document.file
    if type(file)~="string" then return end
    local name=file:match("([^/\\]+)$")
    if name and #name<=240 and name:match("%S") and not name:find("%c") and name~="." and name~=".." then return name end
end

function Scope.valid(id)
    return type(id)=="string" and #id==32 and id:match("^[a-f0-9]+$")~=nil
end

local function entropy()
    local file=assert(io.open("/dev/urandom","rb"),"Cannot create document conversation identity")
    local bytes=file:read(16);file:close()
    assert(bytes and #bytes==16,"Cannot create document conversation identity")
    return bytes
end

function Scope.id(settings,random_bytes)
    assert(settings and settings.readSetting and settings.saveSetting,
        "Book settings are unavailable; cannot safely separate this document's chat")
    -- KOReader already computes this bounded fingerprint. It is only a local
    -- invalidation hint, not an imported/indexed PDF or a content-verified ID.
    local fingerprint=settings:readSetting("partial_md5_checksum")
    if not Scope.valid(fingerprint) then fingerprint=nil end
    local record=settings:readSetting(KEY)
    if type(record)=="table" and Scope.valid(record.id) and record.fingerprint==fingerprint then return record.id end
    local bytes=(random_bytes or entropy)()
    assert(type(bytes)=="string" and #bytes==16,"Invalid document identity entropy")
    local id=bytes:gsub(".",function(c)return string.format("%02x",c:byte())end)
    settings:saveSetting(KEY,{id=id,fingerprint=fingerprint})
    return id
end

function Scope.isChat(path)
    return path=="/v1/state" or path=="/v1/prompt" or path=="/v1/stop" or path=="/v1/reset" or
        path=="/v1/history" or path=="/v1/reopen"
end

function Scope.path(path,id)
    if not Scope.isChat(path) or id==nil then return path end
    assert(Scope.valid(id),"Invalid document conversation identity")
    return "/v1/documents/"..id..path:sub(4)
end

return Scope
