# Source provenance

This repository originated from the Kobo Codex prototype. Earlier development
artifacts and import inventories remain available in Git history. Current source,
tests, and documentation are maintained directly in this repository.

`reference/app-server-schema/` contains generated schemas used to verify app-server interfaces. `reference/koreader-v2026.07.1/` contains selected unmodified upstream sources extracted from the official Kobo release used for the device update, with the upstream COPYING file. These are reference material, not replacement KOReader core modules. Official archive SHA-256: `0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f`.

Private profiles, pairing files, certificates/keys, installation records, rollback
archives, captured images, books, build outputs, and dependencies are excluded from
Git. The root MIT license covers this project; upstream reference sources retain
their own license in `reference/koreader-v2026.07.1/COPYING`.

## Upstream references

Resume and selection integration use the official v2026.07.1 sources: `frontend/dispatcher.lua` (`registerAction`), `frontend/ui/menusorter.lua` (`sorting_hint` and Tools placement), and `ReaderHighlight:onClose(keep_highlight)`. Keyboard-visible painting uses the vendored UIManager's `getTopmostVisibleWidget` and `topdown_widgets_iter`, plus the native VirtualKeyboard instance's painted frame bounds; it never permits arbitrary topmost popups based on a widget name alone.

Selection integration was checked against the v2026.07.1 primary sources: [ReaderHighlight](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerhighlight.lua) (`addToHighlightDialog`, factory arguments, `selected_text`, `onClose`), [ReaderUI](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/readerui.lua) (post-init and document-close lifecycle), [ReaderPaging](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerpaging.lua) (view-context save/restore), [ReaderRolling](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/apps/reader/modules/readerrolling.lua) (xpointer save/goto), [NetworkMgr](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/network/manager.lua) (`runWhenConnected` for the local bridge), and [TextViewer](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/ui/widget/textviewer.lua) (local quote preview). These checks establish API contracts, not on-device rendering or PDF selection-order correctness.

Background transport APIs were checked against KOReader v2026.07.1's pinned base submodule, commit [`6e4bc81af4e04f78d81677a323a780a71b29702a`](https://github.com/koreader/koreader-base/blob/6e4bc81af4e04f78d81677a323a780a71b29702a/ffi/util.lua): `runInSubProcess`, `getNonBlockingReadSize`, `isSubProcessDone`, and `terminateSubProcess`. Standby locking is covered by the existing UIManager reference. The new worker uses these APIs directly so background requests do not install a modal `TrapWidget`.

- Codex app-server: https://developers.openai.com/codex/app-server
- KOReader release: https://github.com/koreader/koreader/releases/tag/v2026.07.1
- Native PDF stylus annotation request: https://github.com/koreader/koreader/issues/8537
- Selected pen input API source: https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/input.lua

Upstream feature status is time-sensitive; recheck before planning an upgrade. The pen API enables the plugin's writing pad; it does not add native PDF drawing.
