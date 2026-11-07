# Handwriting prompts — version 0.3.5

Installed diagnostic update: plugin version 0.3.5 and KOReader v2026.07.1.
The Mac recognizer and encrypted recognition path are tested. Eject and restart
KOReader after installation for the physical stylus/visual check.

## Workflow

1. Open Kobo Codex and tap **Pen**.
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

The first release uses a fixed pen width and a stylus-only writing surface.
Finger touches do not draw. Controls sit above the pad in Pen mode, away from
the resting hand. Touch gestures are ignored during pen contact and for 600 ms
after pen-up; lift your hand briefly before tapping a control. Use Undo/Clear
rather than the stylus eraser button. Menus have bounded widths, and closing a
menu redraws the whole screen to clear stale right-edge content.
Recognition quality on actual cursive handwriting and drawing latency still
need checking on the physical device. English and French are currently configured.

## Required KOReader update

Our confirmed device build, v2025.04, has no supported stylus callback API.
The official Kobo v2026.07.1 package contains the pen API and Elipsa 2E support.
The Kobo 4.x package was downloaded and matched the release's SHA-256 digest:

`0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f`

This is an application update, not a Kobo firmware or launcher change. Before
installation, back up the current KOReader folder. The prepared updater retains
personal settings, history, custom defaults, and pairing, and copies only the
verified official application files plus our plugin. No third-party pen plugin
or replacement input.lua is installed. The official update includes the new
input implementation as part of KOReader itself.

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

- 18 Node tests passed, including stroke/size/schema limits and proof that the
  recognition API does not call app-server.
- Lua/LuaJIT tests cover the existing composer and the handwriting review flow:
  one-tap local OCR/Send, optional preview, preserving drafts, clearing after an accepted Send, pen
  hook cleanup, finger exclusion, bounds, rotation, and point limits.
- The actual offline helper recognized synthetic HELLO pen strokes while under
  the final no-network sandbox.
- The kernel-level sandbox probe denied the OCR worker's localhost proxy, LAN,
  direct Internet, outside synthetic files, and other-process inspection.
- Actual LuaSec 1.3.2 sent pen vectors through the pinned TLS bridge, received a
  HELLO draft, and passed the encrypted-wire check. Captured bytes contained no
  plaintext token, authorization header, stroke JSON marker, or request line.
- The official KOReader archive was hash-verified and checked for device support,
  the required pen API, and absence of personal settings/history files.

These checks do not replace the on-device stylus/visual test after installation.

## Build and reproduce on a Mac

The current Mac helper is already built, and the bridge recognizes the local
API. On another configured Mac, use Node 22 to run `node build-recognizer.mjs`,
then restart the bridge. The helper uses the installed macOS SDK and frameworks.
No Apple/OpenAI API key is needed for recognition.

Run `node test/local-ocr.mjs` and `node test/macos-sandbox.mjs --no-network` with
permission to create a real macOS sandbox. The ordinary suite is `npm test`,
`lua test/ui_2025_test.lua`, and `lua test/transport_test.lua`.

Sources: [official KOReader release](https://github.com/koreader/koreader/releases/tag/v2026.07.1),
[official pen callback API](https://github.com/koreader/koreader/blob/v2026.07.1/frontend/device/input.lua),
and [Apple Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

Installation verification: 1,044 official application files and five plugin
source files checked. Personal settings, history, custom defaults, and pairing
were preserved. A fresh private pre-update backup is recorded locally.

Version 0.3.3 handles screen-size changes while the same chat remains open.
It rebuilds all controls together on the next UI tick and requests a full
refresh. Draft, cursor, ink, and scroll position are retained. A photo of the
reported right-edge bar motivated this repair, but on-device confirmation
is still needed; a solid bar can have other causes.

Version 0.3.4 addresses the reported Pen-entry trigger: pressing Pen defers
the mode switch until button feedback completes. After the first Pen frame, a
follow-up redraw waits for the previous display update and repaints the whole
chat without clearing handwriting. This follows the observed Clear-pad recovery
without invoking Clear. Active strokes/popups defer the redraw; stale layouts
and closed chats cancel it. The additional redraw occurs once per Pen layout,
not during every stroke. Physical confirmation of the black-bar repair is pending.

Version 0.3.5 gathers local display evidence when Clear pad is tapped. When
the bar is visible, tap Clear pad once, then reconnect by USB so the control-row
crops and dimensions can be inspected. Chat, draft and ink regions are excluded
from images; ambiguous bounds cause image capture to be skipped. No networking
is involved. The black-bar cause remains unresolved.

Additional 0.3.5 repair after the report that writing also triggers the bar:
regional stroke updates now write only the affected pad pixels, without
repainting unrelated controls. Full chat paints request full-screen refresh
coverage. Transport, local recognition, pairing, and prompt handling are unchanged.
