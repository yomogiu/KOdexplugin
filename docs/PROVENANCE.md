# Source provenance

This repository originated from the Kobo Codex prototype. SOURCE-MANIFEST.json
and TRANSFER-MANIFEST.json retain original import hashes for source and reference
files still present in the repository. They are historical provenance records,
not current release checksums. Entries for removed development artifacts have
been pruned; Git history preserves the original inventories and files. The
shareable ZIP's explicit file allowlist seeded the transfer; additional test
documents were included separately.

`reference/app-server-schema/` contains generated schemas used to verify app-server interfaces. `reference/koreader-v2026.07.1/` contains selected unmodified upstream sources extracted from the official Kobo release used for the device update, with the upstream COPYING file. These are reference material, not replacement KOReader core modules. Official archive SHA-256: `0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f`.

The transfer excludes the original `.private` tree, connection.json, installation.json, certificates/keys/auth, rollback archives, captured images, PDFs, Swift/build caches, compiled OCR/transport binaries, Node modules and the official KOReader archive itself. Third-party annotation plugins are not part of this source bundle.

## Upstream references

The 0.5.1 resume/selection fixes were verified against the mounted official v2026.07.1 sources: `frontend/dispatcher.lua` (`registerAction`), `frontend/ui/menusorter.lua` (`sorting_hint` and Tools placement), and `ReaderHighlight:onClose(keep_highlight)`. Keyboard-visible painting uses the vendored UIManager's `getTopmostVisibleWidget` and `topdown_widgets_iter`, plus the native VirtualKeyboard instance's painted frame bounds; it never permits arbitrary topmost popups based on a widget name alone.

Selection integration was checked against the v2026.07.1 primary sources: [ReaderHighlight](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerhighlight.lua) (`addToHighlightDialog`, factory arguments, `selected_text`, `onClose`), [ReaderUI](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/readerui.lua) (post-init and document-close lifecycle), [ReaderPaging](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerpaging.lua) (view-context save/restore), [ReaderRolling](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerrolling.lua) (xpointer save/goto), [NetworkMgr](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/network/manager.lua) (`runWhenConnected` for the local bridge), and [TextViewer](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/widget/textviewer.lua) (local quote preview). These checks establish API contracts, not on-device rendering or PDF selection-order correctness.

Background transport APIs were checked against KOReader v2026.07.1's pinned base submodule, commit [`6e4bc81af4e04f78d81677a323a780a71b29702a`](https://github.com/koreader/koreader-base/blob/6e4bc81af4e04f78d81677a323a780a71b29702a/ffi/util.lua): `runInSubProcess`, `getNonBlockingReadSize`, `isSubProcessDone`, and `terminateSubProcess`. Standby locking is covered by the existing UIManager reference. The new worker uses these APIs directly so background requests do not install a modal `TrapWidget`.

- Codex app-server: https://developers.openai.com/codex/app-server
- KOReader release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- Native PDF stylus annotation request: https://github.com/koreader/koreader/issues/8537
- Selected pen input API source: https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/input.lua

Upstream feature status is time-sensitive; recheck before planning an upgrade. The current prototype's pen API enables our pad; it does not add native PDF drawing.
