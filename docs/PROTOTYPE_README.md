# Kobo Codex — private app-server companion

Version 0.3.5 is a security-hardened prototype for KOReader
v2025.04 (keyboard) and v2026.07.1 (handwriting) on Kobo Elipsa 2E. It keeps the conversation and a permanent composer on one screen. Sending and
reply updates preserve the editor and keyboard. Keys shows/hides the keyboard;
More provides Refresh, Pause updates, Latest message, and New chat. It supports
typed prompts, follow-up chat, incremental replies, and Stop. In Pen mode, controls stay above the writing pad; palm gestures are suppressed while writing and briefly after pen-up. Menu dismissal refreshes the entire screen. Open chats rebuild their controls on screen rotation while preserving drafts and ink. Pen-mode entry also performs a later redraw after button feedback and the first display update. Optional stylus handwriting uses a Mac-local Apple Vision recognizer. See HANDWRITING.md; KOReader 2026.07 or newer is required for the pen API.

## Connections and trust boundaries

- **Kobo → Mac:** TLS 1.2 with AES-GCM and an exact SHA-256 server-certificate
  pin checked before sending the device token or prompt. No plaintext fallback,
  redirects, trust-on-first-use, or automatic book/notebook uploads.
- **Mac bridge → Codex:** local stdio. The app-server has no network listener.
- **Codex → local egress tunnel:** authenticated HTTP CONNECT over loopback only.
  This local hop is not a LAN-facing HTTP service. The tunnel carries the
  upstream TLS connection without decrypting it.
- **Tunnel → OpenAI:** end-to-end TLS, verified by Codex against the system CA
  bundle. Only `chatgpt.com`, `auth.openai.com`, and `api.openai.com` on port 443
  are permitted. Private, loopback, link-local, mapped, and reserved resolved
  addresses are rejected. Unknown hosts, plaintext HTTP forwarding, alternate
  ports, and upstream-proxy chaining are refused.

Codex runs under a mandatory macOS process sandbox. File content is restricted
to system runtime files, its own native executable, the dedicated Codex profile,
and an empty temporary workspace. Other-process inspection, subprocesses,
direct Internet access, LAN access, and unrelated localhost ports are denied.
The bridge has no unrestricted fallback if sandbox startup fails. The Node
bridge itself remains a trusted component running as your account; this is not
whole-machine isolation, a VM, or an independent security certification.

The app-server receives a constructed environment rather than your shell's
credentials, SSH agent, user name, proxy settings, debug settings, or custom CAs.
Shell, browser, computer-use, image reading, apps, web search, Code Mode, host
skill discovery, memories, and feedback are disabled. Unexpected requests cannot
receive tool or permission approval. Startup refuses any exposed MCP servers.
Telemetry exporters, analytics, and prompt telemetry are disabled; runtime logs
and SQLite state are placed in a private temporary directory removed on clean
shutdown. The separate login persists in the private profile.

The API accepts only prompt, state, stop, and reset operations. It does not expose
arbitrary RPC, files, paths, tools, approval answers, or desktop conversations.
Browser-origin and forwarded requests are refused. Bodies, responses, timeouts,
connections, and request rate are bounded. Errors do not echo internal paths.

Before a prompt reaches Codex, a conservative guard rejects recognizable keys,
private keys, credential assignments, device-token values, private paths, local
hostnames, and internal IP addresses. This is a useful pattern check, not a
complete secret classifier. Do not intentionally send confidential material.

## What privacy this does not promise

OpenAI still receives prompts you explicitly send, the responses/conversation
context needed to answer, account authentication, your public source IP, and
normal protocol metadata. DNS providers can observe the allowed host lookups;
network observers can see connection timing, endpoints, and TLS metadata.
Account-side retention is governed by your OpenAI account/workspace settings.
This application cannot promise zero leakage, zero provider retention, or the
privacy of unrelated Kobo firmware, Wi-Fi, cloud sync, and other plugins.

The Kobo stores the device token as a local file on unencrypted storage. Anyone
who obtains it can access this bridge's conversation and consume its allowance.
It is separate from your OpenAI credentials. Stop the bridge to revoke access;
rotate the token and reinstall pairing if the device is lost. The bridge must
remain on a private LAN; do not expose or forward its port to the Internet.

## Installed setup

The local installation is ready. Its machine-specific addresses and executable
paths live only in `.private/`, not in the shareable source bundle. Consult the
local `TESTING.md` and `SECURITY-REPORT.md` for installation evidence and pending
checks. They are intentionally excluded from the downloadable source ZIP.

Use **sign-in.command** to sign into the separate profile, then restart using
**start-bridge.command**. Sign-in also runs through the restricted tunnel and
process sandbox. Finish browser authentication yourself; the code never copies
your ordinary Codex login. Keep the Mac awake while testing. Press Ctrl-C in the
bridge terminal to stop it. No login item, daemon, or router rule is installed.

On Kobo, open KOReader's main menu → **Kobo Codex**, tap the message box, then **Send**. A missing sign-in
produces an explanation, not an attempted model turn. Closing the view stops
polling. Drafts are not saved across KOReader restarts.

## Fresh setup on another Mac

Requirements: tested Node.js **22**, OpenSSL, macOS `sandbox-exec`, and an installed
native Codex CLI. No `npm install` is needed. The installed CLI used for testing
was 0.160.0. This source resolves its native binary instead of executing a shell
or Node wrapper inside the Codex sandbox.

Run `node setup.mjs YOUR_MAC_LAN_IPV4` from this directory, substituting a specific
private LAN IPv4 address. Setup creates `.private/` with mode 0700 and secrets
with mode 0600. It refuses to overwrite existing pairing. It records the Node
and native Codex executable paths privately. `CODEX_BIN` can select the intended
installed Codex executable if your PATH has several installations.

Copy `kobocodex.koplugin/` to `.adds/koreader/plugins/` and copy only the generated
`.private/connection.json` into that plugin directory by USB. Never copy the
server key, Codex profile, or OpenAI credentials to Kobo. Safely eject and restart
KOReader. A new computer IP requires updating both local pairing configurations.
A replaced certificate requires deliberate re-pairing over USB.

## Reproducible checks

Run `npm test`, `lua test/transport_test.lua`, and `luajit test/ui_2025_test.lua`.
`node test/macos-sandbox.mjs` compiles a small synthetic canary probe and requires
permission to create an actual macOS sandbox. It never reads real secrets.

`node test/live-wire.mjs PATH_TO_LOCAL_LUA_MODULES` exercises the actual plugin
transport against a running bridge using LuaSocket and LuaSec 1.3.2 built locally
for the test machine. It verifies ciphertext contains no plaintext token/prompt,
an impostor receives zero HTTP bytes, and plaintext HTTP exposes no state. These
test dependencies are not installed on Kobo or globally on the Mac.

## References

- [Official Codex App Server](https://developers.openai.com/codex/app-server)
- [Official Codex configuration](https://developers.openai.com/codex/config-reference)
- [Official Codex authentication](https://developers.openai.com/codex/auth)
- [KOReader source](https://github.com/koreader/koreader)
- [LuaSec source](https://github.com/lunarmodules/luasec)

macOS sandbox profiles are a platform-specific interface. A future macOS or Codex
update can break compatibility; a refused startup must be investigated rather
than bypassed. On a crash or forced kill, temporary runtime files may remain
mode 0700 until removed. Local privileged software or an attacker controlling
your Mac account or Kobo remains outside these transport protections.

## Handwriting input

See HANDWRITING.md. Pen strokes go only to the Mac-local recognizer over the
existing pinned TLS connection. Its worker has no network permission or Codex
profile access. Send automatically recognizes the handwriting locally and submits only text,
with the same sensitive-text checks as keyboard prompts. Preview remains an
optional More-menu action; recognition errors keep the draft and ink.

## Temporary display troubleshooting

Version 0.3.5 adds local-only diagnostics for the unresolved right-edge bar.
Tapping Clear pad saves before/after geometry and crops of only the toolbar and
pad-controls rows in the plugin’s `display-diagnostics/` directory. Capture is
skipped if content bounds are missing or a row overlaps chat, draft, or ink.
These files are never uploaded or included in the source package. Repeated
captures overwrite fixed filenames; this is diagnostic instrumentation, not a
confirmed repair.

The same update corrects paint/refresh coverage: live strokes blit only their
bounded pad rectangle and request a refresh without dirtying the whole chat.
Any full chat repaint explicitly refreshes the whole screen. This repairs a
verified code-path mismatch; physical black-bar resolution is not yet confirmed.
