# Project handoff — 2026-11-07

## User's objective

Build a private Kobo Elipsa 2E productivity/reading companion using KOReader and Codex app-server. The user distrusts opaque pen plugins, wants their own reviewable code, local OCR, secure transport, no secret/private-network leakage, and a usable stylus interface.

The current request is to consolidate this work into KOdexplugin. A PDF-integrated assistant is the desired next project direction, not authorization to silently import books, upload documents, or expand Codex's permissions.

## Implemented and exercised

- Dependency-free Node 22 HTTPS bridge to a dedicated Codex app-server over stdio.
- Kobo LuaSec transport checks an exact SHA-256 certificate pin before transmitting the bearer token or HTTP application data. No plaintext fallback or redirects.
- Dedicated computer-side Codex authentication. The Kobo does not sign into OpenAI and holds only its device pairing.
- Persistent chat/composer; sending/reply updates preserve draft/editor state. Reply polling and Stop.
- Official KOReader update from v2025.04 to v2026.07.1, with settings/history/pairing preserved and private rollback backups.
- Stylus-only vector pad, Undo/Clear, rotation/bounds limits, hook restoration, palm-touch suppression, controls above the writing area.
- Send triggers local handwriting recognition on the Mac and then submits only text. Optional preview, cancel, duplicate suppression, retry IDs, draft/ink preservation on errors.
- Apple Vision accurate revision-3 English/French CPU OCR in a separate no-network sandbox. Vector-only input; in-memory rasterization; no book/chat screenshots in the OCR path.
- Version 0.3.5: bounded pad-only live stroke blits, matching whole-screen refresh for whole-chat painting, and local display diagnostics.

## Current unresolved issue

An intermittent black/blank bar covers the right side of controls. The user reproduced it by tapping the Pen button and intermittently while writing; Clear pad restores the section. A user photo showed More/Close and Clear-pad controls obscured at the same edge. Earlier refresh, width, rotation and delayed-settle changes did not eliminate it.

Version 0.3.5 fixed a verified paint/refresh mismatch: a tiny stroke refresh previously dirtied and repainted the entire chat. The repair has been installed and source/hash-verified, but the user has not confirmed its hardware outcome. Do not report this defect as resolved.

If it returns, the instructed sequence is: while visible, tap Clear pad once, reconnect USB, inspect `kobocodex.koplugin/display-diagnostics/`. Captures include controls only, never chat/draft/ink; invalid or overlapping bounds are refused. See DISPLAY-ISSUE.md.

## Proposed next feature

Select PDF text and invoke Explain selection or Ask Codex; preserve reading position, attach page references, and continue a conversation with selected passages. Then add explicit Mac-local PDF import, per-page extraction/indexing and local retrieval across the entire document. The bridge supplies retrieved text to Codex; Codex does not receive general filesystem tools. A separate whole-document summarization workflow would traverse every section. Scanned-PDF OCR is separate from the existing handwriting OCR.

## Important operational facts

The bridge has stopped during development; `transport.lua:22: connection refused` was resolved by restarting the original configured launcher and verifying pinned TLS/authenticated state. This error is distinct from the display bar. Keep the Mac awake and use the configured private LAN connection. No new device sign-in is required simply because the bridge restarted.

No runtime secrets were copied into this project. The active private profile, certificates, token and rollback archives remain in the original workspace. `.local/OPERATIONS.md` gives local pointers; never commit it. Historical installers depend on the original workspace layout and must be adapted before reuse.

## Evidence and limits

Node security/bridge/recognition suites, real LuaSec ciphertext and pin-before-token tests, local synthetic OCR, and actual macOS sandbox probes were run during development. Dates/version-specific reports are preserved in docs/history. Recent Lua/LuaJIT contracts cover OCR-on-Send, errors/cancel/close, keyboard and live rotation, pen-entry timing, paint/refresh bounds, and diagnostic crop exclusions. These do not reproduce the e-ink controller or constitute independent security certification.

The user confirmed conversational use works, but handwriting accuracy/latency and display reliability still require device testing. No PDF reading integration or annotation mode has been built.
