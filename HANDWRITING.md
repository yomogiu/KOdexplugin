# Handwriting prompts

Handwriting requires a supported stylus, KOReader 2026.07 or newer, and the Mac-local recognizer.

## Workflow

1. Open Kobo Codex, tap **Expand** if needed, then **Pen**.
2. Write on the pad, then tap **Send**.
3. The Mac recognizes the writing locally and the plugin sends the text through
   the existing sensitive-text guard. The pad clears only after acceptance.

No separate Recognize action is required. Typed text can be combined with the
handwriting. **More → Preview handwriting** remains available
if you want to inspect or correct recognition before submitting.

A failed/empty recognition or blocked/rejected prompt preserves the ink and
draft. **Cancel** during recognition prevents automatic sending and leaves a
preview draft. Closing the chat also cancels the pending automatic send. If the
draft changes during recognition, the combined text is kept for an explicit Send.

The writing pad uses a fixed pen width and a stylus-only surface.
Finger touches do not draw. Controls sit above the pad in Pen mode, away from
the resting hand. Touch gestures are ignored during pen contact and for 600 ms
after pen-up; lift your hand briefly before tapping a control. Use Undo/Clear
rather than the stylus eraser button. Menus have bounded widths, and closing a
menu redraws the whole screen to clear stale right-edge content.
Recognition quality on actual cursive handwriting and drawing latency still
need checking on the physical device. English and French are currently configured.

## Required KOReader update

KOReader v2025.04 has no supported stylus callback API.
The official Kobo v2026.07.1 package contains the pen API and Elipsa 2E support.
The Kobo 4.x release archive has SHA-256 digest:

`0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f`

This is an application update, not a Kobo firmware or launcher change. Before
installation, back up the current KOReader folder. Preserve settings, history,
custom defaults, and pairing during an upgrade.
Use the official KOReader package; the pen API is part of KOReader itself.

## Local recognition and privacy

Only vector pen strokes from our pad are submitted—not a screenshot of the
conversation, book, or whole screen. They travel to the Mac over the same pinned
TLS connection and device-token authentication as the chat.

A small Swift helper rasterizes the vectors in memory and runs Apple Vision's
on-device text recognition. Its separate macOS sandbox denies all networking,
including access to the local OpenAI proxy, and excludes the Codex profile and
other user-file contents. There is no cloud OCR provider or downloaded model.
Only the helper's own executable is staged in its private temporary runtime.
The generated image is not written to disk.

The asynchronous recognition API accepts only bounded canvas dimensions and
numeric pen strokes. It cannot fetch URLs, open arbitrary files, or call Codex.
Only one job runs at a time; it has a 30-second limit. A completed result is kept
in Mac memory for up to five minutes and is returned only to an authenticated
client. The user’s Send tap authorizes local recognition followed by text submission.
The same sensitive-text guard checks the text before it reaches Codex. Preview
mode does not submit a prompt.

The provider can receive the recognized prompt after Send, as it receives typed
prompts. Local/physical access and provider-side retention have the same limits
explained in README.md. These tests are not a universal zero-leakage guarantee.

## Verification

The Node tests cover stroke/size/schema limits and separation of recognition from
model requests. Lua/LuaJIT contracts cover local OCR-on-Send, optional preview,
draft/ink preservation, pen-hook cleanup, finger exclusion, rotation, and point bounds.

Optional native Mac checks exercise synthetic HELLO strokes under the no-network
recognizer sandbox. The sandbox probe tests denied file/process/network access;
the live LuaSec test checks encrypted transport when its dependencies are available.
These are separate from physical stylus accuracy, latency, palm behavior, and e-ink
acceptance. See the [security guide](docs/SECURITY.md) for prerequisites and limits.

## Build and reproduce on a Mac

After Mac setup, use Node 22 to run `node build-recognizer.mjs`,
then restart the bridge. The helper uses the installed macOS SDK and frameworks.
No Apple/OpenAI API key is needed for recognition.

Run `node test/local-ocr.mjs` and `node test/macos-sandbox.mjs --no-network` with
permission to create a real macOS sandbox. The ordinary checks are listed in the
[README](README.md); the UI suite runs with LuaJIT because it exercises pinned
native scrolling code.

Sources: [official KOReader release](https://github.com/koreader/koreader/releases/tag/v2026.07.1),
[official pen callback API](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/input.lua),
and [Apple Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

For the unresolved right-edge artifact, rendering repairs, and controls-only
diagnostic captures, see [display troubleshooting](docs/DISPLAY-ISSUE.md).
