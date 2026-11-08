# Device testing guide

## Host-side checks

Use Node 22 for the Node suite. The launchers select the runtime recorded during
setup; a different Node version can affect TLS behavior. Test commands and
prerequisites are documented in the [README](../../README.md),
[technical README](../PROTOTYPE_README.md), and [handwriting guide](../../HANDWRITING.md).

Transport and sandbox tests use synthetic fixtures. They cover authentication,
certificate pinning before token transmission, encrypted-wire behavior, local
OCR, and process/network restrictions. UI contract tests cover draft/cursor/ink
preservation, scrolling, rotation, delayed requests, cancellation, refresh
bounds, and diagnostic crop exclusions. Passing these checks does not establish
physical stylus or display behavior.

## Device acceptance

1. Install compatible bridge/plugin versions, preserve pairing and reader
   settings, safely eject the Kobo, and restart KOReader.
2. Keep the Mac awake with the bridge running. Enable Kobo Wi-Fi on the same
   private network, open Kobo Codex, and send a harmless question.
3. Verify reply completion, Stop, follow-ups, close/reopen, and draft retention.
4. In a book, test Explain/Ask, passage preview/detach, reader-position
   restoration, compact scrolling with the keyboard visible, and rotation.
5. With a supported stylus, test Pen entry, writing, Undo/Clear, OCR preview,
   Send, cancellation, and keyboard/pen switching. Check recognition accuracy,
   palm suppression, latency, and refresh artifacts.
6. Test separate book conversations and archive behavior using the acceptance
   checks in the corresponding feature guides.

A USB-mounted Kobo cannot simultaneously exercise its normal KOReader Wi-Fi
interface. Host-side replies and file verification are separate from device
acceptance. For the unresolved control-row artifact, follow the
[display diagnostic procedure](../DISPLAY-ISSUE.md).
