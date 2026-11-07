# KOdexplugin

A private KOReader companion for Codex, with a local Mac bridge and local handwriting recognition. The next proposed feature is PDF-grounded conversation.

Start with [the handoff](docs/HANDOFF.md), [architecture](docs/ARCHITECTURE.md), and [roadmap](docs/ROADMAP.md). The original technical README is preserved in [docs/PROTOTYPE_README.md](docs/PROTOTYPE_README.md).

## Current state

Plugin/bridge package version **0.3.5**. Installed on Kobo Elipsa 2E with firmware **4.38.23552** and official **KOReader v2026.07.1**. Typed chat, persistent conversation/composer, stylus prompt input and Mac-local OCR-on-Send are implemented. The user confirmed live Codex conversation works.

The intermittent right-side black bar is **not confirmed fixed**. Version 0.3.5 repairs paint/refresh coverage and includes local, controls-only display diagnostics. The device copy was verified and safely ejected; the user's next hardware result is pending. See [the display issue](docs/DISPLAY-ISSUE.md).

**PDF selection actions, PDF import/indexing/retrieval, document-linked conversations, and PDF handwriting annotation are not implemented.** Architecture documents describe proposed work, not existing capabilities.

## Files

- `kobocodex.koplugin/`: KOReader Lua client, pen pad, pinned TLS transport, local display diagnostics.
- `server.mjs`, `bridge.mjs`: HTTPS bridge and app-server client.
- `security.mjs`, `egress.mjs`: process sandbox, prompt guard and restricted upstream proxy.
- `recognition.mjs`, `ocr/Recognizer.swift`: asynchronous local OCR worker.
- `test/`: Node, Lua, live transport and macOS sandbox checks.
- `reference/`: generated app-server schemas and selected upstream KOReader sources used during implementation.
- `legacy-work/installers/`: historical installers tied to the original workspace; reference material, not ready-to-run project installers.

## PDF library and Kobo sync folder

Place PDFs in [`library/pdfs/`](library/pdfs/). The entire `library/` directory is
gitignored, including reader metadata and future extracted text/indexes. The
intended USB counterpart is `Books/KOdex/` on the Kobo drive, visible to KOReader
as `/mnt/onboard/Books/KOdex`. See [library layout and sync conventions](docs/LIBRARY.md).
These folders are prepared locally; automatic sync, indexing, and PDF import
into Codex are not enabled.

## Running and private state

This project intentionally contains **no pairing token, certificate/private key, Codex sign-in profile, connection.json, device backup, PDF, or index**. Copying the code does not move the running bridge or its configuration. Local-only operational pointers are in `.local/OPERATIONS.md` (gitignored). Continue using the original configured launcher until runtime migration is explicitly handled.

For a fresh installation, follow `docs/PROTOTYPE_README.md`; use Node 22, build the local OCR worker, create a dedicated profile and pair by USB. Do not run setup merely to develop this copy: that would create a separate pairing.

## Verification

`lua test/ui_2025_test.lua`, `luajit test/ui_2025_test.lua`, `lua test/display_diagnostics_test.lua`, and `lua test/transport_test.lua` exercise client contracts. `node --test test/*.test.mjs` requires Node 22. Live TLS/OCR/kernel sandbox checks require configured private state, macOS, and their documented prerequisites. Passing mocked UI checks does not demonstrate e-ink rendering correctness.
