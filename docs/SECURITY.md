# Security and privacy

KOdex sends explicitly submitted questions and selected passages through a Mac bridge
to Codex. The optional Obsidian companion imports explicitly chosen saved conversations.
The controls below describe the current implementation for local power users; they are
not an independent security certification or protection against software controlling
your Mac account or Kobo.

## Connections and permissions

| Connection | Boundary |
| --- | --- |
| Kobo → Mac | TLS with an exact certificate pin checked before the device token or prompt is sent. Bind to a specific private IPv4 address; no plaintext or redirect fallback. |
| Mac → Codex process | Local stdio with a dedicated profile, empty temporary workspace, restricted environment, and mandatory macOS sandbox. |
| Codex → OpenAI | Authenticated loopback CONNECT proxy carrying upstream TLS. Only the configured official hosts on port 443 are permitted; private/reserved addresses are rejected. |
| Handwriting → recognizer | Bounded vectors sent to a separate Mac-local Apple Vision worker with no network access or Codex-profile access. |
| Obsidian → bridge | Authenticated HTTP on 127.0.0.1:9444 with a separate companion credential; no LAN-facing Obsidian service or model RPC. |

The egress allowlist is `chatgpt.com`, `auth.openai.com`, and `api.openai.com`.
The proxy refuses other hosts, plaintext forwarding, alternate ports, and upstream
proxy chaining. It carries encrypted TLS rather than decrypting model traffic.

The Codex process cannot directly read the library, vault, chat archives, or export
queue. Shell and app tools, browser/computer use, image reading, web search, host skill
discovery, memories, and telemetry exporters are disabled by this bridge's settings.
Unexpected tool/approval requests are refused, and startup rejects exposed MCP servers
or unsafe model sandbox settings. Startup has no unrestricted fallback.

The Node bridge itself runs as the user and is trusted host-side code. The Obsidian
plugin inherits Obsidian's permissions; using the Vault API does not sandbox other
plugins. These controls do not isolate a compromised local user account.

## Credentials and local records

| Data | Location and handling |
| --- | --- |
| Kobo pairing | `connection.json` on the reader; device token and certificate fingerprint. Keep it private. |
| Bridge settings, TLS key/certificate, dedicated Codex profile | Mac runtime `.private/`; copy only the reader pairing file to Kobo. |
| Saved chats and export queue | Mac runtime `.private/`; private plaintext, bounded storage. |
| Companion credential | `~/Library/Application Support/KOdex/companion-pairings/<destination-id>/obsidian-companion.json`. |
| Companion connection settings and delivery receipts | `~/Library/Application Support/KOdex-Obsidian/`; outside the vault. |
| Imported notes | Selected folder in the Obsidian vault; accessible to its plugins, sharing, sync, and backups. |

Private directories/files use owner-only permissions. Reads reject unsafe file types,
symlinks, and invalid schemas; companion configuration also rejects hardlinks. These
permissions are not encryption and do not stop other software running as the same user.
Credentials, local operational records, books, generated outputs, and dependencies are
excluded from Git. Ignore rules do not prevent manual copying or uploading elsewhere.

Companion pairing is bound to a destination and a canonical vault identity. Its token
is distinct from the Kobo token and authorizes export operations, not Codex prompts.
The bridge keeps a nonsecret location pointer in its private runtime. Credential
migration preserves destination identity, binding, and pending exports, then removes
the former credential file. The plugin refuses legacy Documents paths before accessing
the filesystem and resolves migrated credentials in Application Support.

Use `npm run pair:obsidian -- revoke` to disable companion authorization, or `-- rotate`
to renew and re-enable it. Disconnect in Obsidian pauses delivery locally and retains
notes/receipts; it does not revoke the token. A vault move needs an explicit migration
flow, which is not implemented yet. See the [companion guide](../obsidian-kodex/README.md).

Anyone obtaining the Kobo token can access that bridge's book chats and consume model
allowance while it runs. Stop the bridge and deliberately rotate/reinstall reader
pairing if compromised. Do not expose the reader port through the router to the Internet.

## Submitted content and exports

Ask composition, attachment preview, and handwriting preview do not submit model turns.
Send submits typed/recognized text and its attached quotation; Explain submits its
preset request immediately. No whole book, surrounding pages, PDF image, or library
index is automatically uploaded. Handwriting rasterization stays in memory on the Mac.

A conservative prompt guard rejects recognizable credentials, private-key text, configured
sensitive values, private paths, local hostnames, and internal IP addresses. Replayed
archive context is checked too. This is pattern matching, not a complete detector of
sensitive information. Book/model content is treated as untrusted data, not authority
to execute tools or change bridge policy.

Companion requests require authentication and vault binding, reject browser-origin and
forwarded traffic, and are bounded in size/rate. Archive catalog responses contain
metadata only. Listing archives does not export them; the user chooses a conversation
and confirms import, including retained submitted passage context.

Exports are immutable snapshots. The bridge persists them before acknowledging queueing;
the companion records its planned filename/hash before note creation and marks the receipt
written before acknowledging delivery. Conflicting or edited notes are preserved rather
than overwritten. Literal fenced rendering keeps submitted HTML, remote images, and vault
transclusions from becoming active markup. Generated metadata is validated and quoted.
A local vault save does not confirm that cloud sync has delivered the note elsewhere.

## Retention and remaining limits

Working chats remain in bridge memory. Explicit archives survive restarts and contain
reader questions, submitted context, and assistant responses. Model runtime logs/state
use a private temporary directory removed on clean shutdown; a forced exit can leave
private temporary files. Authentication remains in the dedicated profile. See
[chats and archives](CHATS.md) for retention and capacity limits.

The export queue and local receipts are bounded; delivered records remain stored until
managed explicitly. There is no automatic retention/cleanup UI yet. No limit silently
evicts existing work. Exported notes inherit whatever cloud sync, publishing, backups,
and third-party plugins the user has configured for the vault.

OpenAI receives submitted text, supplied conversation context, account authentication,
and ordinary service/network metadata. Provider retention follows the account/workspace
settings. Local OCR is not a promise that a subsequent submitted prompt stays on-device.
This app cannot promise zero provider retention or control unrelated firmware/services.

Ordinary path checks reject existing unsafe links, but path-based operations are not
proof against hostile concurrent directory swaps. That stronger writer and Obsidian
publisher-signature verification are deferred for this local power-user scope. App
bundle-ID detection is a convenience, not proof of publisher authenticity. OS launch
protections are not bypassed.

## Verification

With Node 22, install the companion build dependency and run the source tests:

```sh
npm ci --prefix obsidian-kodex
npm test
```

Node tests cover authentication, restricted RPC/settings, secret guards, archive and
queue recovery, vault isolation, revocation, unsafe files, and bundled plugin loading.
Lua/LuaJIT checks cover pin-before-token transport, routing, lifecycle, and rendering
contracts; the [README](../README.md) lists commands.

Additional Mac checks require Apple command-line tools and permission to create actual
macOS sandboxes. `node test/macos-sandbox.mjs` compiles a synthetic canary probe;
`--no-network` exercises the network-denied variant. `node test/local-ocr.mjs` requires
a built `.private/ocr-worker` and checks synthetic strokes under the recognizer sandbox.

`node test/live-wire.mjs PATH_TO_LOCAL_LUA_MODULES` requires a running configured bridge,
its `.private/connection.json`, LuaJIT, and locally available LuaSocket/LuaSec 1.3.2. It
checks authenticated state, rejection of an invalid token/certificate, and absence of
plaintext markers in captured wire bytes. It does not submit a valid model prompt.
Keep these dependencies and any captured private data outside shared source.

Host tests do not establish physical e-ink rendering, handwriting quality, or protection
against every provider/platform change. Keep tests and pinned reference files when
changing security or transport behavior; do not weaken restrictions to make startup pass.
