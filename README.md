# KOdexplugin

Ask Codex about what you’re reading in KOReader on a Kobo. Select a passage to
get an explanation or ask a question, continue the conversation in a reading
note, and return to your book. You can type questions or use a supported stylus
with handwriting recognition that runs locally on your Mac.

The setup has two parts: a **KOReader plugin on the Kobo** and a **bridge running
on your Mac**. The Kobo connects to the Mac over your private Wi-Fi network;
the Mac sends the questions you submit to Codex.

## What you need

- A Kobo with KOReader already installed. This project has been used with a
  **Kobo Elipsa 2E and KOReader v2026.07.1**. Handwriting needs a compatible
  stylus and KOReader **2026.07 or newer**.
- A Mac with **Node.js 22**, **OpenSSL**, macOS `sandbox-exec`, and a native
  **Codex CLI** installed and available on your `PATH`. The CLI version used
  during development was **0.160.0**; compatibility with other versions may vary.
- A Codex account you can sign into through the CLI.
- A USB cable for installing and pairing the plugin, and a private network that
  lets the Kobo reach the Mac.
- For handwriting, Apple’s command-line developer tools (`swiftc` and the macOS
  SDK). You can install them with `xcode-select --install`.

No `npm install` is needed. The bridge uses Node’s built-in modules.

## Set up the Mac

Run these commands from your checkout of this repository. If you already have a
working installation, use its existing bridge launcher and pairing; a new
checkout does not inherit its configuration. The steps below are for a fresh
installation.

### 1. Create the pairing

Find the Mac’s private IPv4 address in **System Settings → Network → your active
connection → Details → TCP/IP**. Use an address such as `192.168.1.42`, replacing
the example below with your own:

```sh
node --version
node setup.mjs 192.168.1.42
```

The Node version must start with `v22.`. Setup requires a specific private IPv4
address, rather than a hostname or `0.0.0.0`. A DHCP reservation on your router
helps keep the Mac’s address stable.

Setup creates a private `.private/` directory containing the bridge settings,
TLS certificate and key, device pairing token, and a dedicated Codex profile.
It refuses to overwrite an existing `.private/` directory. If you have multiple
Codex installations, select the intended executable when running setup:

```sh
CODEX_BIN=/absolute/path/to/codex node setup.mjs 192.168.1.42
```

### 2. Sign in

```sh
./sign-in.command
```

Follow the displayed device-authentication instructions in your browser. This
signs into the dedicated profile through the restricted login launcher; it does
not copy your normal Codex login. You can also double-click `sign-in.command`
in Finder.

### 3. Enable handwriting (optional)

```sh
node build-recognizer.mjs
```

This builds the local Apple Vision recognizer. You can skip it for keyboard-only
use. If you build it while the bridge is running, restart the bridge afterward.

### 4. Start the bridge

```sh
./start-bridge.command
```

You should see `Restricted Kobo bridge listening over TLS on port 9443.` Leave
this terminal open and keep the Mac awake while using the plugin. Press
**Ctrl-C** to stop the bridge. You can also double-click `start-bridge.command`
in Finder. No background service or automatic startup is installed.

If macOS asks about incoming network connections, allow the bridge’s Node
executable on your private network. The Kobo needs to reach the Mac on TCP port
**9443**. Do not forward this port through your router to the Internet.

## Install and pair the Kobo

1. Connect the Kobo by USB and choose **Connect** on the device.
2. Copy the entire `kobocodex.koplugin` folder from this repository into
   `.adds/koreader/plugins/` on the Kobo. In Finder, **Command-Shift-.** shows
   hidden folders such as `.adds`.
3. Copy the generated `.private/connection.json` from the Mac into the plugin
   folder on the Kobo. The resulting layout should be:

   ```text
   .adds/koreader/plugins/kobocodex.koplugin/
     _meta.lua
     main.lua
     …other plugin files…
     connection.json
   ```

4. Safely eject the Kobo and restart KOReader.
5. Connect the Kobo to the same private network as the Mac, keep the bridge
   running, and open KOReader’s main menu → **Kobo Codex**.
6. Type a short question and tap **Send** to check the connection.

Copy **only `connection.json`** from `.private/` to the Kobo. The server key,
Codex profile, and OpenAI credentials stay on the Mac. The pairing file contains
a secret token; keep it private.

## Use it while reading

- **Explain a passage:** select text in your book and tap **Explain** in
  KOReader’s selection menu. This immediately submits the selected text with a
  preset explanation request.
- **Ask about a passage:** select text and tap **Ask Codex**. Tap **Passage** to
  preview the attachment or detach it, type your question, then tap **Send**.
  Opening Ask or previewing a passage does not submit it.
- **Continue the conversation:** type a follow-up below the answer. Replies
  appear when the turn finishes. Use **Stop** to interrupt a response.
- **Return to the book:** tap **Read**. A question already submitted can finish
  while the note is closed.
- **Write a question:** tap **Expand**, then **Pen**, write on the pad, and tap
  **Send**. Handwriting is recognized on the Mac before the resulting text is
  submitted. **More → Preview handwriting** lets you review it first.
- **Start over:** in the expanded view, choose **More → New chat**. The bridge
  uses one shared conversation; it does not automatically start a separate chat
  for each book.

Reading interactions open in a compact note. **Expand** opens the full controls
and writing pad; **Compact** returns to the note. Drafts and unsent ink are not
saved across KOReader restarts.

## Books and privacy

Open your books normally in KOReader. For an optional PDF folder convention,
see [the library guide](docs/LIBRARY.md): keep local PDFs in `library/pdfs/` and
copy them by USB to `Books/KOdex/` on the Kobo. The local `library/` tree is
ignored by Git; create it yourself on a fresh checkout if you want to use it.

The plugin sends the selected text, your question, and available numeric page
references when you explicitly tap **Send** or **Explain**. It does not upload
the whole book. Whole-document search, automatic PDF sync, scanned-page OCR,
and handwriting annotations on PDF pages are not available.

The Kobo-to-Mac connection uses pinned TLS and a device token. Handwriting
strokes go to the Mac’s local recognizer; submitted text and conversation
context go to OpenAI. Provider retention follows your account or workspace
settings. Keep `.private/` and `connection.json` out of shared files and backups
you intend to publish. Anyone with the device token can access this bridge’s
conversation while it is running. The bridge includes a sensitive-text filter,
but you should still avoid sending secrets.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Kobo Codex is missing from the menu | Check that `kobocodex.koplugin` is directly inside `.adds/koreader/plugins/`, then restart KOReader. |
| “Install connection.json by USB first” | Copy `.private/connection.json` into the installed plugin folder and restart KOReader. |
| The Kobo cannot connect | Keep the Mac awake and the bridge running. Check both devices’ network, the Mac’s current IPv4 address, firewall access to port 9443, and whether guest Wi-Fi isolates devices. |
| The bridge asks you to sign in | Stop it, run `./sign-in.command`, finish authentication, then restart it. |
| Setup says `.private` already exists | Use the existing pairing if this is a configured installation. Do not delete it just to retry setup; it contains credentials and pairing state. |
| The Mac’s IP address changed | Update `host` in both `.private/bridge.json` on the Mac and `connection.json` on the Kobo to the new private IPv4 address. Preserve the token and fingerprint, then restart the bridge and KOReader. |
| Certificate or pin verification fails | Check that the Kobo’s pairing file belongs to this bridge. If the certificate was replaced, transfer the matching pairing file deliberately over USB. |
| Pen input is unavailable | Check stylus support and KOReader 2026.07 or newer. Build the Mac recognizer and restart the bridge. Keyboard input remains available. |
| A right-edge black bar appears | This is an unresolved display issue. See [display troubleshooting](docs/DISPLAY-ISSUE.md). |
| Restricted Codex startup fails | Check Node 22 and the configured native Codex executable. macOS or CLI updates can affect sandbox compatibility; retain the sandbox restrictions when investigating. |

## Development and technical details

For contributors, [architecture](docs/ARCHITECTURE.md),
[handoff notes](docs/HANDOFF.md), and the [roadmap](docs/ROADMAP.md) contain
implementation history and outstanding work. Detailed behavior is documented in
[selection flow](docs/SELECTION-FLOW.md), [reading note UI](docs/NOTE-UI.md), and
[handwriting](HANDWRITING.md). The [original technical README](docs/PROTOTYPE_README.md)
contains the fuller security model and transport checks.

Run the Node checks with Node 22:

```sh
npm test
```

Lua client checks include `lua test/selection_test.lua`,
`luajit test/ui_2025_test.lua`, and `lua test/transport_test.lua`.
Live transport, OCR, and macOS sandbox checks have additional prerequisites
described in the technical documentation. Local UI tests do not verify physical
e-ink rendering.
