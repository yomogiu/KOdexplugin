# Separate document chats — 0.6.0

Version 0.6.0 introduces document-scoped conversations. Real-device rendering and live-model performance require separate acceptance checks.

Version 0.7.0 adds durable archives and a per-book history list; see
[chat archives](CHAT-ARCHIVES.md). The description below records the 0.6.0
in-memory conversation behavior.

## Reading behavior

Each PDF or other book has a separate model thread and visible history. Opening
Tools → Kobo Codex resumes the open book's chat without selecting another
passage. Switching A → B → A returns to A's conversation. Stop and More → New
chat affect only the current book. File-manager chat and legacy unscoped API
clients use an independent general conversation. Old shared history is not
automatically assigned to any book.

Replies still appear all at once; network calls remain non-blocking. Opening
Ask or previewing a passage does not submit it. Optional bounded `displayText`
preserves a concise question/page label in bridge snapshots, while only the
full `text` prompt goes into the model turn.

## Identity and lifetime

Before starting a network worker, the client reads or creates
`kobocodex_chat_scope = {id, fingerprint}` in KOReader's normal book settings.
The ID is 16 random bytes from `/dev/urandom`, encoded as 32 lowercase hex
characters. Native settings save it through KOReader's normal book save/close
lifecycle. Missing settings or entropy fails without falling back to general
chat.

An already cached native `partial_md5_checksum`, when available, is only a local
invalidation hint. The plugin does not compute a book hash or read the PDF.
Neither checksum nor filename/path is sent to the bridge or model. This is not
content-verified identity: copying book metadata can share its identity, deleting
metadata creates a new identity, and undetected replacements can reuse it.

All model threads are ephemeral and bridge histories stay in RAM. Book switching
and reopening in another reader instance resume history while the same bridge
is running. Restarting the bridge clears every history; the book ID alone does
not recover it. Drafts, ink and passage attachments remain local to the reader
instance and are not durable chat storage.

## Transport and resource limits

Pinned-TLS authenticated routes are:

```text
GET  /v1/documents/<32-hex-id>/state
POST /v1/documents/<32-hex-id>/prompt
POST /v1/documents/<32-hex-id>/stop
POST /v1/documents/<32-hex-id>/reset
```

The client checks the returned document ID. An older bridge's 404 causes an
upgrade error, never a retry through shared chat. Recognition routes remain
independent. No arbitrary paths, file URLs, app-server RPC or caller-specified
model thread IDs are accepted. Existing pin-before-token and prompt guards apply.
IDs separate histories; the pairing token authorizes access to the whole bridge.

One registry routes app-server notifications to the matching thread. Limits are
32 document chats, 1000 aggregate remembered request IDs and 4 simultaneous
operations/replies. Existing chats are not evicted; reaching a limit gives an
explicit error. New chat frees that document's slot and remembered requests.
Authenticated general state includes `runningDocumentReplies` for operational
idle checks without exposing document histories.

## No PDF import or indexing

This feature does not download another PDF, copy it into the repository, extract
pages or build an index. `library/indexes/` remains a reserved folder convention.
The model knows only explicitly submitted text and its own document conversation.
It cannot search the whole PDF. Import/retrieval needs separate implementation.

## Verification and deployment

Node tests exercise separate threads/history/retries, A/B resume, isolated
Stop/reset, concise display versus model context, bounds, authentication and
real local HTTPS routes. Lua/LuaJIT checks cover metadata reuse/invalidation,
parent-side identity creation before fork, A/B/A reader instances, route
allowlists, response identity, old-bridge refusal and unchanged TLS pinning.
These do not establish real Kobo rendering or live-model performance.

Deployment must include all nine plugin Lua files (including `docscope.lua`)
and the updated bridge, server and package metadata. Restarting the bridge is
required and clears existing conversation history. Preserve pairing, native
book settings and private credentials. Device acceptance should open two PDFs,
ask different questions, switch back, reopen KOReader, and verify that New chat
in one PDF leaves the other intact. Test bridge restart separately with the
expected empty histories.
