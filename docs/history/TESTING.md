# Local device test status

KOReader v2025.04 and firmware 4.38.23552 were read from the connected Kobo.
Our four installed files are source-checked and paired to the hardened bridge.
The device token was rotated after the initial prototype tests. No firmware,
launcher, books, notebooks, or other plugins were changed.

The original `.adds/` tree is backed up in the neighboring `kobo-backups` folder:
`kobo-adds-before-codex-20261107T124139Z.tar.gz` (448,542,723 bytes), with a manifest
for 2,356 archived files. This is an application/settings backup, not a full
image of all Kobo storage. Both archive and manifest are locally private.

The final bridge runs as a foreground test process and requires the recorded
Node 22 runtime. A newer PATH-selected Node runtime stalled in the live TLS test;
the launcher now selects the verified runtime from private configuration.

Completed: unit tests, real macOS isolation probes, actual LuaSec encrypted-wire
tests, upstream public-CA TLS verification, authentication rejection, and a
source-verified copy to Kobo. These are host-side tests of the actual transport
and policy, not a claim that the Kobo UI has been exercised.

The separate Codex sign-in completed successfully. The hardened bridge was
restarted, and an authenticated test prompt returned exactly:
`Kobo connection test successful.` No sandbox, proxy, or TLS controls were relaxed.

The Kobo's reported pre-restart sign-in error also confirmed that its installed
UI could reach the bridge and submit a request. The next device test is to retry
Send or Refresh after the restart.

After sign-in and a verified host-side reply, eject KOBOeReader in Finder, open
KOReader, enable Wi-Fi on the same private network, and open Kobo Codex → Reply.
Send a harmless greeting. This final on-device UI test requires someone at the
Kobo screen; the USB-mounted device cannot simultaneously run that interface.

UI update 0.2.1: installed a persistent chat/composer panel. Send no longer opens
a separate prompt dialog or returns to another pane. Lua/LuaJIT lifecycle tests
cover draft, cursor, keyboard, scrolling, and viewport sizing. Actual device
visual inspection is pending. Transport and pairing hashes are unchanged.

Handwriting installation complete: KOReader v2026.07.1 and plugin 0.3.0.
Verified 1,044 core files, five plugin sources, and the unchanged pairing.
Rollback archive: koreader-before-handwriting-20261107T161652Z.tar.gz.
Physical stylus/visual check remains pending after safe ejection and restart.

UI 0.3.1 installed and hash-verified: Send now performs local OCR before text
submission. Optional preview moved to More. Lua/LuaJIT tests cover duplicates,
failed OCR, rejected prompts, edits, close/cancel, mixed typed/ink input, and pen
hook cleanup. Recognition engine, bridge, transport, and pairing are unchanged.

UI 0.3.2 installed and all three changed files hash-verified. Pairing, transport, and metadata unchanged. Lua and LuaJIT checks pass for
controls above the pad, suppression before child button handling, 600 ms recovery,
non-touch lifecycle events, stale geometry reset, opaque full-screen painting,
bounded popup widths, and full refresh on dismissal. Existing automatic OCR and
transport checks pass. Physical palm behavior and right-edge rendering need
checking on the device. No transport, OCR worker, or bridge changes.

UI 0.3.3 installed: both changed sources hash-verified; pairing, transport, pen module, and metadata unchanged. Added hot portrait/landscape round-trip
checks on the same open chat (previous tests only opened fresh panels). Checks
cover resize-event forwarding, paint fallback, deferred/coalesced rebuild,
stale-touch rejection, text/cursor/ink/scroll retention, keyboard resizing,
full refresh, and safe close before a queued rebuild. Reported black-bar
resolution remains unconfirmed on the physical Kobo.

UI 0.3.4 installed: chatpanel source hash-verified; pairing, transport, pen module, and metadata unchanged. Lua/LuaJIT tests verify a deferred Pen-button
transition, a post-frame display fence before the one-shot whole-chat redraw,
unchanged draft/editor/ink/version, deferral during strokes and popups, no
repaint loop, and cancellation for replaced/closed panels. Existing composer,
OCR, rotation and transport checks pass. These contract tests do not reproduce
the Kobo display-controller artifact; the hardware repair remains unconfirmed.

UI 0.3.5 diagnostic update installed: three UI sources hash-verified; pairing, transport, main module, and metadata unchanged. Version 0.3.4 did not
resolve the intermittent bar. Added bounded local-only control-row captures
before/after Clear pad; tests verify overlap/missing-bound refusal, no dynamic
content access, fixed output paths, popup/close safety, and preserved normal
Clear behavior. Hardware resolution remains unconfirmed.

UI 0.3.5 also repairs paint/refresh coverage. Lua/LuaJIT tests verify exact
stroke blit/refresh bounds, pad-only pen-up, no parent dirtying for live strokes,
and whole-screen refresh coverage for a whole-chat paint without a repaint
loop. This replaces the earlier whole-chat repaint with a tiny refresh region.
