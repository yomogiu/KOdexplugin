# Per-book chat archives — 0.7.0

Version 0.6.0 clears history on New chat. Version 0.7.0 adds the archive
behavior below; both the plugin and bridge need updating.

## Kobo flow

- Expand → More → New chat confirms that the current book conversation will be
  archived before starting a blank one. Empty chats create no archive.
- Expand → More → Chat history lists only this book's saved conversations,
  newest first, with the first question as title and a UTC timestamp. Five
  entries appear per page; page changes use the loaded metadata locally.
- Choose an entry and confirm to reopen it. The current nonempty chat is saved
  first. The opened archive remains saved too; reopening does not consume it.
- Draft and unsent ink stay in the composer. A passage attached to the previous
  chat is detached on successful reopen. Failure preserves the current state.
- Finish or Stop an active reply before changing conversations. Closing the
  panel during history loading does not reopen it when the request finishes.

File-manager/general chat retains its previous clearing behavior and has no
book history list. Book identity still comes from native KOReader book settings;
deleting those settings also loses the book's normal route to its saved chats.

## Persistence and context

Explicit New chat and reopening another archive save conversations in the Mac
runtime's `.private/chat-archives/`. Files use random IDs and contain reader
messages, submitted quotation context, assistant responses, title and creation
time. They are plaintext private local files (directory 0700, files 0600), not
Git content or an encrypted backup. Existing sandbox rules keep the folder
outside the model process's accessible files. No PDF paths are added.

Archives survive a bridge restart. The working chat is still in memory: if it
has never been archived, restarting the bridge loses it. Reopening a saved chat
does not autosave subsequent changes; use New chat to save them. Conversations
previously cleared in 0.6.0 or earlier cannot be recovered by this feature.

Reopening displays saved text without a model call. A subsequent explicit Send
starts a fresh ephemeral, read-only model thread and supplies up to 64000 recent
characters of saved conversation as quoted context, followed by the question.
Original selection wrappers are retained separately from concise display text.
The outbound sensitive-text guard checks replayed context too. Older context
may be omitted; a reopened chat is not a restored server-side model thread.
No new file tools, network access or thread/resume permissions are added.

Archives retain the transcript up to the bounds below, including exchanges
older than the UI's existing 12-message snapshot. The Kobo still shows the latest
12 messages when reopening; browsing earlier messages within one long conversation
is not added here. Replies continue to appear at once.

## Bounds and failure behavior

Limits are 50 archives per book, 500 overall, 128 MiB overall and 3 MB/200 messages
per archive. A working chat refuses another prompt before exceeding its archival
budget, reserving worst-case answer/JSON space and asking the reader to start
New chat. Limits never silently delete or evict saved conversations. Capacity
management currently requires removing selected archive files on the Mac while
the bridge is stopped; there is no Delete button on the Kobo yet.

Writes use exclusive temporary files, fsync, atomic rename and directory fsync.
Saving must finish before the current model thread/history is cleared. Failed
writes or limits leave the working chat intact. Per-book change locks prevent
Send/New chat/reopen races during async disk operations. Failed model unsubscribe
after a successful save can leave an extra saved copy; it does not remove the
working conversation. Repeated reopen of the same untouched archive is a no-op.

Paths derive only from validated opaque IDs. Reads reject symlinks, loose modes,
mismatched identities and malformed records. History responses contain metadata
only; normal state omits stored wire quotation text. The pairing token authorizes
access to all books' chats and archives on this bridge.

## API and deployment

```text
GET  /v1/documents/<32-hex-book-id>/history
POST /v1/documents/<32-hex-book-id>/reopen  {"archiveId":"<32-hex-archive-id>"}
POST /v1/documents/<32-hex-book-id>/reset   {}
```

Reset now archives nonempty document chats before clearing. General reset is
unchanged. No unscoped history/reopen, arbitrary path or model thread ID is
accepted. Older bridges reject the new routes. General authenticated state
adds `pendingConversationChanges` for safe operational idle checks.

Install all nine plugin Lua files plus `bridge.mjs`, `server.mjs`, new
`archives.mjs` and package metadata. Preserve private pairing, native book
settings and the archive directory. Both ends need updating and the bridge
needs restarting. No PDF import, copying or indexing is introduced.

## Verification

Node tests cover persistence across fresh registries, PDF isolation, saving the
displaced chat, metadata-only lists, transcript retention beyond the visible
snapshot, replay bounds/guards, active/concurrent changes, failed writes, storage
limits, permissions, corruption, symlinks and authenticated local HTTPS routes.
Lua/LuaJIT checks cover scoped routing, endpoint/method allowlists, non-blocking
history loading, pagination, reopen confirmation, draft/ink preservation,
attachment/retry cleanup, failures and dismissal.

Hardware acceptance remains pending: save distinct A/B conversations, reopen
each via its history, confirm no mixing or lost reading position, then restart
the bridge and verify saved entries still open and accept follow-ups.

Validation completed with the configured Node 22.22.0 binary: all 31 Node tests
pass. Lua and LuaJIT scope, transport, UI, selection and display-diagnostic suites
pass, as does the LuaJIT subprocess/pipe background suite. These checks do not establish deployment or live-model behavior.
