# Reading chats and saved conversations

Each book has its own conversation. Switching books keeps their questions and
answers separate; reopening Tools → Kobo Codex resumes the current book's chat.
Replies appear when the turn finishes. Stop affects only that conversation.
The file manager has an independent general chat.

## Save and reopen a book conversation

1. Finish the reply or tap Stop.
2. In the expanded chat, choose More → New chat and confirm. The current nonempty
   book conversation is archived on the Mac before a blank chat starts.
3. To return to it, choose More → Chat history. The list contains only the current
   book's archives, newest first, with five entries per page.
4. Choose an entry and confirm. The current nonempty conversation is saved first,
   then the selected archive is reopened. The archive remains available.

Empty chats do not create archives. Drafts and unsent ink stay in the composer;
reopening an archive detaches the previous passage attachment. Failed saves or
reopens preserve the current state. Closing the note during history loading does
not reopen the UI when loading finishes.

General chat has no archive list: New chat clears it. These are KOdex conversations,
separate from other Codex or ChatGPT conversations.

## What survives a restart

| Data | Storage and lifetime |
| --- | --- |
| Working conversation | Mac bridge memory; lost when the bridge stops unless archived. |
| Saved book conversation | Private files on the Mac; retained across bridge restarts. |
| Draft, unsent ink, passage attachment | Reader-instance memory; not retained across KOReader restarts. |
| Book conversation identity | Native KOReader book settings; retained through normal book save/close. |

Archive working chats before restarting the bridge. Reopening a saved conversation
and adding follow-ups does not automatically save those new messages; use New chat
again when you want to archive them. Deleting a book's native KOReader settings can
also lose its route to the saved conversations, so preserve those settings.

Reopening displays saved text without a model request. The next explicit Send starts
a fresh restricted model thread and supplies up to 64000 recent characters of saved
context. Older context can be omitted. This restores reading context, not a previous
server-side model session. The sensitive-text guard checks replayed context too.

The Kobo displays the most recent 12 messages. Archives can contain older exchanges
within their storage bounds; browsing every archived message on the Kobo is not yet
supported. The Obsidian companion can import the complete saved snapshot within its
own export size limit. See the [companion guide](../obsidian-kodex/README.md).

## Storage and limits

Archives live in the configured Mac runtime's `.private/chat-archives/`. They contain
questions, submitted passage context, assistant responses, a title, and a timestamp.
They are plaintext local files with owner-only permissions, not encrypted backups.
The model cannot directly access this directory. Keep it out of shared source and
public backups; see [security and privacy](SECURITY.md).

Limits are 50 archives per book, 500 overall, 128 MiB overall, and 3 MB or 200 messages
per archive. Working chats reserve enough space for a reply before accepting another
question. Reaching a limit rejects new work rather than silently deleting archives.
There is no archive-deletion UI yet; selected archive files can be removed on the
Mac while the bridge is stopped, with a private backup if needed.

Writes use exclusive temporary files, file/directory fsync, and atomic rename. Per-book
locks prevent Send, New chat, and reopen from racing. Failed storage leaves the working
chat intact. A model-unsubscribe failure after a successful archive can leave an extra
saved copy. Reopening the same untouched archive is a no-op.

## Identity and API

The client creates an opaque 32-hex document ID in native book settings before starting
a network worker. A cached native fingerprint can invalidate it after a book changes;
this is not a content-verified document hash. Neither the fingerprint nor the book path
is sent for routing. Copied metadata can share an identity, so it is not an access-control
boundary. The Kobo pairing token authorizes all book chats and archives on that bridge.

Authenticated pinned-TLS routes are:

```text
GET  /v1/documents/<document-id>/state
POST /v1/documents/<document-id>/prompt
POST /v1/documents/<document-id>/stop
POST /v1/documents/<document-id>/reset
GET  /v1/documents/<document-id>/history
POST /v1/documents/<document-id>/reopen  {"archiveId":"<archive-id>"}
```

Document and archive IDs are 32 lowercase hex characters. Reset archives a nonempty
book chat before clearing it. History returns metadata only; state omits the separately
retained submitted-context wrapper. There are no unscoped history/reopen routes or
caller-selected model thread IDs. Older incompatible bridges are rejected without
falling back to shared chat.

The registry allows 32 document chats, 1000 aggregate remembered request IDs, and four
simultaneous model operations. It does not evict another book to admit new work.
General state exposes running-reply and pending-change counts for safe maintenance.

## Deployment and verification

Update the bridge and all plugin Lua files together, preserving pairing, archives,
and native book settings. Archive work before restarting the bridge and restart
KOReader after replacing client files. No book import, copying, or indexing is involved.

Node tests cover isolation, replay, persistence, bounds, storage failures, and local
HTTPS authentication. Lua/LuaJIT tests cover scoped routing, metadata reuse, history
pagination, stale callbacks, draft/ink preservation, and reader lifecycle behavior.
Physical acceptance should verify A/B/A book switching, save/reopen, unchanged reading
position, and archive recovery after a bridge restart. Test commands are in the
[README](../README.md).
