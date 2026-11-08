# Intermittent right-edge bar — open

Observed with Kobo Elipsa 2E and KOReader v2026.07.1. The hardware outcome of the paint/refresh fixes remains unverified; source checks alone do not establish a repair.

## Observations

A solid black/blank bar can hide the right side of the action row and Clear-pad controls. Pen entry and writing can trigger it intermittently; Clear pad has restored the obscured area. These symptoms alone do not establish a rotation or hardware fault.

## Current rendering safeguards

Controls sit above the pad, touch suppression protects pen input, popups are bounded,
and dismissal redraws obscured areas. Live resizing preserves draft, cursor, ink,
and scroll state. Pen entry is deferred until button feedback finishes and includes
a post-frame repaint. Regional pen strokes blit only their affected pixels; full
chat paints advertise full-screen refresh coverage.

These safeguards and their regression tests do not establish that the hardware
artifact is fixed. The UI suites check rotation, paint/refresh bounds, deferred
redraw order, cancellation, and diagnostic exclusions rather than simulating the
actual e-ink controller. Use the evidence procedure below if the bar returns.

## Evidence collection

If the bar returns, tap Clear pad once while it is visible. The callback saves `before-clear` and, after the queued update, `after-clear` geometry JSON and up to two control-row PNG crops under `kobocodex.koplugin/display-diagnostics/`. Fixed filenames overwrite earlier captures; there is no background history or network transfer.

Image capture is refused when dynamic-content bounds are unknown, a row overlaps the draft/transcript/ink, the row is out of bounds/too tall, the panel is closed or another widget is on top. It captures the static toolbar/pad-control bands only, not full-screen/chat/book/ink data. Capture failures do not block Clear. Images and device/private paths are excluded from the shareable source archive and Git.

Reconnect by USB after capture, copy this directory to local gitignored storage, and inspect before/after crops and layout dimensions. If the framebuffer crop is intact while the camera shows the bar, investigate the refresh/controller path; if the crop itself is obscured, investigate drawing order/buffer writes/layout. This is a diagnostic distinction, not a confirmed diagnosis yet.
