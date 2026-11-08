# Obsidian integration design

Updated 2026-11-08. The Mac bridge remains central. The preferred Obsidian path
is a desktop companion installed in the destination vault; ordinary Markdown
folder export remains an optional future delivery method.

## Architecture and responsibilities

```text
KOReader ↔ pinned TLS Mac bridge ↔ restricted Codex process
                      ↓
             private durable export queue
                      ↓ loopback authenticated pull
             Obsidian companion → Vault API → notes
```

Questions and answers never pass through Obsidian. Closing Obsidian, disabling its
plugin, or omitting the integration does not change reading chat. The bridge owns
Codex authentication, conversation archives, export identities, and delivery state.
The companion owns vault-relative placement and note creation. The model receives
no additional filesystem access, tools, or vault content.

## Implemented development preview

The `obsidian-kodex/` plugin source builds a manually installed macOS desktop preview 0.1.2.
It provides pairing, destination-folder settings, a connection sample, explicit
archive selection/import, queued delivery, status, and opening the last imported
note. The release bundles local modules into `main.js` using esbuild; the installed
plugin needs no additional modules or build step. See the
[companion installation guide](../obsidian-kodex/README.md).

`companion.mjs` adds a separate authenticated HTTP listener on `127.0.0.1:9444`
only when companion pairing has been configured. It provides claim, status,
archive catalog, explicit export/sample enqueue, pending record, and acknowledge
operations. It exposes no model RPC, arbitrary paths, or public LAN service.
Listener startup failure is isolated from the reading-chat service.

This preview exports immutable saved chat archives, including submitted context
where available. It does not yet export an active chat or individual answer from
the Kobo. The bridge retains working chats in memory as before; pairing does not
make those conversations persistent automatically.

## Pairing and first use

1. A user with Obsidian installs the companion in their chosen vault. The active
   vault is the destination; discovery of other vaults is unnecessary.
2. On the configured Mac, run `npm run pair:obsidian`. This creates a separate
   private credential in `~/Library/Application Support/KOdex/companion-pairings/<destination-id>/obsidian-companion.json`; it never prints the
   token. Restart the bridge if its companion listener is not running, preserving
   current work by archiving chats before restart.
3. Choose Connect this vault in Obsidian, enter the local pairing file path, and
   review the destination folder and privacy notice. No credential is copied into
   the vault or plugin data.
4. The companion claims the destination using a hash of the canonical vault path.
   Another vault cannot claim it with the same pairing. One paired destination is
   supported initially. The hash is an identity, not an additional secret.
5. Send a connection sample to verify queueing, Vault API creation, and acknowledgment.
6. Choose an archive from the metadata catalog and explicitly confirm import.
   Listing archives does not enqueue them. Questions, answers, and retained
   submitted passage context are included in the selected snapshot.

Companion credentials are distinct from Kobo credentials. Plugin connection paths,
folder settings, and delivery receipts live under the user's private
`~/Library/Application Support/KOdex-Obsidian/`, keyed by vault identity. Reading
credentials stay only in the dedicated Application Support pairing file and are
revalidated per request. The bridge runtime stores a nonsecret location pointer;
the queue and chat archives stay in its private runtime.
Nothing sensitive is saved through Obsidian plugin data, which may sync elsewhere.

For older installations, `npm run pair:obsidian -- migrate` moves the credential,
preserving identity, binding, and queue. It verifies/commits the new location before
removing the original file. The plugin resolves the new file by its saved destination
ID, updates its local settings and preserves receipts, without reading, resolving,
or falling back to the former Documents path. Explicit pairing paths outside the
dedicated Application Support tree are rejected before filesystem access. Neither
Documents permission nor Full Disk Access is required for this pairing flow.

Rotation/revocation is performed with `npm run pair:obsidian -- rotate` or
`-- revoke`. It preserves destination identity and existing exports. Disconnect in
Obsidian pauses local receipt while preserving notes and delivery receipts; it
is not server-side credential revocation. Vault moves and pending-work reassignment
need an explicit future migration flow and are not silently inferred.

## Experimental folder setup for developers

`npm run setup:obsidian` is an experimental developer command, not part of normal
installation. It
can locate Obsidian, suggest known vaults, select an ordinary Markdown folder,
create a reading folder, and write a setup sample. A new folder is registered
through Obsidian's own Open folder as vault flow when the user is ready.

Its version 1 `.private/obsidian.json` is separate from companion pairing. The
runtime does not consume this folder configuration yet: connecting a folder does
not activate export delivery. No automatic switch between folder and companion
delivery is allowed. Future folder delivery must reuse the queue/identity contract
and make an explicit destination choice; both writers must not consume one export.

## Snapshot records and ownership

Protocol version 1 records contain an opaque export ID, destination ID, ISO UTC
creation time, title, source kind, and ordered messages with stable IDs. Archive
sources retain document and archive/conversation IDs. Message IDs derive from
immutable source identity and ordinal; submitted context remains separate from
the visible question. Missing book title, author, or structured page metadata is
not invented. Live-chat identity and structured selection provenance remain work
for Kobo export actions.

Archive export IDs derive from destination plus immutable document/archive identity.
Retries and reimports reuse the same ID. Sample requests carry explicit IDs.
Exports are snapshots, not replacements of existing notes. Generated filenames
include the full export ID. The companion never overwrites an occupied file with
different contents or sends user-edited note contents to Codex.

Untrusted book/model text is rendered literally in fenced blocks with fences
longer than any embedded fence. Frontmatter is generated from validated fields,
with quoted text values. Remote embeds, HTML, and vault transclusions in submitted
content do not become active markup. Rich formatting can be added later with an
explicit rendering policy.

## Durable delivery and recovery

The bridge persists the bounded export before returning pending/queued status.
Delivery requires Obsidian and the companion to be loaded. Closing Obsidian leaves
exports queued on the Mac. The plugin polls every 15 seconds or on a manual
Receive queued notes action, fetching one pending record at a time.

Before note creation, the companion durably records its planned relative path and
content hash outside the vault. After creation through the Vault API, it marks the
receipt written, then acknowledges the bridge. Lost acknowledgements are retried.
A crash after note creation but before completing the receipt is reconciled by
comparing the deterministic filename and generated content hash. A completed
receipt permits acknowledgement without replacing later user edits or deletions.
No exactly-once guarantee is claimed for all external filesystem operations.

Changing the configured subfolder affects new plans. Existing plans retain their
original paths. Disconnect retains receipts so reconnect cannot silently move a
partly completed import. Note-opening failures do not undo completed delivery.
A saved note means local vault creation, not confirmation of cloud/mobile sync.

Limits: 64 pending exports, 500 total queue records, 8 MiB queue storage, 512 KiB
per record, and 500 local receipts. A full queue rejects new work and retains
existing exports. Delivered records remain private and bounded. Cleanup/retention
controls are not yet implemented; no automatic deletion occurs in this preview.

## Practical security scope

Target local power users. Retain separate credentials, private file permissions,
loopback binding, browser-origin rejection, bounded and strict requests, no-clobber
writes, ordinary symlink checks, and explicit content/destination selection.
Vault plugins, sharing, sync, and backups may access the imported notes.

Publisher signature verification and a writer proof against hostile concurrent
directory swaps are deferred, not release blockers for this scope. The companion
uses Obsidian's supported Vault API rather than a custom bridge vault writer.
Do not claim that this confines arbitrary third-party plugins or same-user malware.
See [security and privacy](SECURITY.md) for current controls and limits.

## Remaining work and acceptance

- Desktop pairing and connection-sample delivery have been verified. Complete
  archive-picker, note-rendering, status, unload/reload, and restart acceptance
  in Obsidian desktop.
- Add Kobo save actions only after defining active conversation/message identity,
  selected-answer scope, structured passage provenance, and truthful delivery status.
- Add destination migration, explicit pending-work management, and retention controls.
- Add optional plain-folder delivery without changing the central bridge route.
- Keep tests for cross-vault isolation, revocation, queue bounds, crash recovery,
  user edits, conflicting filenames, and absence of model RPC on export routes.

## Official interfaces

- [Obsidian Vault API](https://github.com/obsidianmd/obsidian-developer-docs/blob/main/en/Plugins/Vault.md)
- [Obsidian API definitions](https://github.com/obsidianmd/obsidian-api/blob/master/obsidian.d.ts)
- [Plugin security](https://obsidian.md/help/plugin-security)
- [Vault management](https://obsidian.md/help/manage-vaults)
