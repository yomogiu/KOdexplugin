# KOdex Companion for Obsidian

Development preview 0.1.2 for Obsidian on macOS desktop. The Mac bridge remains
the center of the system: Kobo questions go directly to the bridge and Codex.
This companion receives explicitly queued notes and creates them in its own vault.

## Install and pair

1. Set up the KOdex Mac bridge using its repository README. Use Node 22 for bridge
   commands. Preserve an existing installation's pairing and private state.
2. For a source checkout, install the build dependency once with
   `npm ci --prefix obsidian-kodex`, then run `npm run package:obsidian`.
   Extract
   `.local/releases/kodex-companion.zip` into your vault's plugins directory
   (by default `.obsidian/plugins/`). The result must include
   `kodex-companion/main.js` and `manifest.json`.
   The archive also includes this README and the MIT license. The distributed
   `main.js` bundles the local modules; do not install the source directory directly.
3. Enable community plugins in Obsidian, reload if needed, and enable KOdex
   Companion. This is a manual development install, not a published directory entry.
4. In the bridge repository run `npm run pair:obsidian`. It creates a dedicated
   private pairing file and prints its absolute path without displaying its token.
   Restart the bridge to activate the optional loopback service if needed. Account
   for working chats held in memory before restarting: archive them first.
5. In Obsidian's KOdex Companion settings, choose **Connect this vault**. Paste the
   Application Support pairing path and choose a notes folder (default
   `Reading/KOdex`). Do not copy the pairing file into the vault. The companion
   does not need access to the bridge's Documents folder.
6. Choose **Send connection sample**. A note should appear in the selected folder.

Obsidian 1.5.0 or newer is declared in the manifest. The code uses the supported
Vault, settings, modal, and command APIs; acceptance in the actual desktop UI
remains to be verified. Installing the ZIP requires no Node dependencies or build
step. Developers use esbuild to produce the single-file plugin entry point.

For Finder installation, `npm run build:obsidian` prepares
`outputs/obsidian-install/kodex-companion/`. Replace `main.js` and `manifest.json`
with the files from that generated folder when upgrading from 0.1.0. Existing
pairing and notes are unaffected.

## Import saved conversations

Choose **Import a saved conversation** in the command palette or the plugin's
settings. Select an archive, review its title/message count and destination, then
choose Import. The bridge exposes a metadata catalog; listing it does not export
conversation text. The chosen export includes questions, assistant answers, and
submitted passage context when retained in the archive.

To create an archive from the Kobo, finish a book chat and choose New chat in
the expanded chat menu. Existing chat archive behavior remains unchanged. This
preview imports saved archives only; exporting the active chat or selecting an
individual answer directly on the Kobo is future work.

The plugin checks for queued exports every 15 seconds while loaded. Use Receive
queued notes to retry immediately. Open last imported note opens the most recent
note received in the current session. When Obsidian is closed, delivery waits on
the Mac; reading questions continue to work normally.

## Ownership and recovery

Exports are snapshots, never synchronized replacements of user-edited notes.
Filenames contain the stable export ID. Reimporting the same immutable archive
does not create a new export. Local delivery receipts recover lost acknowledgements;
an occupied filename with different content stops delivery and preserves both the
existing note and queued export. No files are silently overwritten or deleted.

Changing the notes folder affects exports not yet started. An import already
planned retains its original destination. Disconnect pauses imports and retains
notes and delivery receipts. Reconnecting the same pairing resumes pending work.

The bridge permits one paired vault per destination in this preview, bound to
the canonical vault path on this Mac. A moved vault needs manual re-pairing support,
which is not implemented yet; do not edit private state to silently redirect work.
Use a stable vault location for this preview.

## Privacy and local configuration

The plugin connects only to `127.0.0.1:9444`. No Obsidian-facing listener is exposed
to the LAN. It has a separate credential from the Kobo and cannot send prompts to
Codex through this service. Only explicitly requested archives and connection
samples are queued. It does not retrieve or upload unrelated vault notes.

Credentials live in
`~/Library/Application Support/KOdex/companion-pairings/<destination-id>/obsidian-companion.json`,
with owner-only file and directory permissions. The bridge's private runtime holds
only a nonsecret location pointer for the pairing. A local
connection path and delivery receipts are stored per vault under
`~/Library/Application Support/KOdex-Obsidian/`, using private directories/files.
No credentials or machine-specific settings are written to the vault's plugin data.
The selected notes and their metadata are normal vault files: other plugins,
sync, sharing, and backups can access them. Exported text is rendered literally
inside fenced blocks to prevent model/book text from introducing active embeds.

Run `npm run pair:obsidian -- revoke` on the Mac to disable the integration.
`npm run pair:obsidian -- rotate` renews and re-enables the credential, preserving
destination/vault binding; the plugin reads the renewed file on subsequent requests.
Existing queued exports and notes remain. No listener restart is needed for
rotation/revocation when it is already running.

For installations created before 0.1.2, run
`npm run pair:obsidian -- migrate` from the configured Mac runtime. This preserves
the token, destination identity, vault binding, and export queue, commits the new
location, then removes the former credential file from Documents. Update/restart
the bridge once when upgrading its source. After replacing the installed plugin
with 0.1.2, reload it: saved connections migrate to the new path by destination ID
without inspecting the old Documents path. Receipts and folder preferences remain.
If migration is missing or conflicts, the plugin stops with setup guidance rather
than falling back to Documents access. No Documents or Full Disk Access permission
needs to be granted for pairing. This does not change Obsidian's access to the
vault location you selected.

Queue limits are 64 pending exports, 500 total records, 8 MiB total, and 512 KiB
per export. Delivered records and receipts remain private and bounded; this preview
does not provide an automatic retention or queue-cleanup UI. A full queue stops
new exports rather than discarding earlier ones. Contact the project maintainer
for recovery rather than deleting the private queue or receipt files.

Local power-user scope: ordinary permissions, path validation, symlink checks,
loopback authentication, bounded requests, and no-clobber writes are included.
This is not a sandbox against malicious software running under your own account
or concurrent hostile directory swaps. It inherits Obsidian's plugin permissions.
