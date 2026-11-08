# Intermittent right-edge bar — open

Observed with Kobo Elipsa 2E and KOReader v2026.07.1. The hardware outcome of the paint/refresh fixes remains unverified; source checks alone do not establish a repair.

## Observations

A solid black/blank bar can hide the right side of the action row and Clear-pad controls. Pen entry and writing can trigger it intermittently; Clear pad has restored the obscured area. These symptoms alone do not establish a rotation or hardware fault.

## Work already attempted

- 0.3.2 moved controls above the pad, added touch suppression, bounded popups, opaque screen painting and dismissal redraws. Bar persisted.
- 0.3.3 corrected a real missing live-resize path, preserving draft/cursor/ink/scroll across portrait/landscape. This did not resolve the reported bar.
- 0.3.4 deferred Pen switching until button feedback finished and scheduled one post-frame, display-fenced follow-up repaint. Bar still appeared, including during writing.
- 0.3.5 repaired a verified mismatch: regional stroke refreshes previously dirtied and repainted the full chat. Live strokes now directly blit their bounded pad region and refresh without dirtying the parent; full-chat paints request full-screen refresh coverage. Includes diagnostics. Physical outcome remains unverified.

The earlier tests used mocked UI contracts, not a real KOReader renderer or e-ink device. Additional tests now cover same-live-panel rotation, exact stroke blit/refresh bounds, full-paint refresh coverage, deferred redraw order and cancellation, and diagnostic exclusions. None proves the artifact absent.

## Evidence collection

If the bar returns, tap Clear pad once while it is visible. The callback saves `before-clear` and, after the queued update, `after-clear` geometry JSON and up to two control-row PNG crops under `kobocodex.koplugin/display-diagnostics/`. Fixed filenames overwrite earlier captures; there is no background history or network transfer.

Image capture is refused when dynamic-content bounds are unknown, a row overlaps the draft/transcript/ink, the row is out of bounds/too tall, the panel is closed or another widget is on top. It captures the static toolbar/pad-control bands only, not full-screen/chat/book/ink data. Capture failures do not block Clear. Images and device/private paths are excluded from the shareable source archive and Git.

Reconnect by USB after capture, copy this directory to local gitignored storage, and inspect before/after crops and layout dimensions. If the framebuffer crop is intact while the camera shows the bar, investigate the refresh/controller path; if the crop itself is obscured, investigate drawing order/buffer writes/layout. This is a diagnostic distinction, not a confirmed diagnosis yet.
