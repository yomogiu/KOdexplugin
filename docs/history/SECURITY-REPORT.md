# Kobo Codex security test report

Historical baseline: version 0.2.0. Scope: our plugin, bridge, local app-server,
and upstream connection restrictions. This is a first-party implementation
review with executable checks, not independent certification or a zero-leakage
claim.

## Security controls

- Added a mandatory macOS process sandbox around Codex. Direct network access,
  LAN access, unrelated loopback ports, outside file contents, subprocesses, and
  other-process inspection are restricted. No unrestricted fallback is allowed.
- Added an authenticated, loopback-only CONNECT tunnel. Only three official
  OpenAI hosts on port 443 are allowed. Resolved private/special IPs, DNS rebinding
  to LAN addresses, other destinations, plaintext forwarding, alternate ports,
  and inherited proxy chaining are rejected.
- Removed inherited credentials, user environment values, SSH agent, custom CA,
  and key-logging environment settings from Codex. Shell, browser, computer use,
  image reading, apps, Code Mode, web search, host skills, and memories are off.
  Startup verifies there are no exposed MCP servers.
- Disabled analytics, telemetry exporters, prompt telemetry, feedback and saved
  command history. New runtime logs/state use a private temporary directory,
  deleted on clean shutdown. Credentials persist only in the separate profile.
- Added a conservative outbound prompt guard for common credentials, private
  paths, local hostnames, internal IPs and the actual device token. It is not a
  complete detector of arbitrary sensitive information or deliberate obfuscation.
- Kept certificate pinning before any HTTP token or prompt is sent. Restricted
  the Kobo's TLS 1.2 ciphers to forward-secret AES-GCM suites.
- Restricted private-profile permissions without following executable symlinks.
  Pairing secrets, machine-specific settings, and private backups are excluded
  from the source.
- Pinned the launcher to the verified Node 22 runtime recorded privately. A newer
  PATH-selected runtime stalled in a real handshake test; no security check was
  disabled to accommodate it.

## Verification results

**16 automated Node tests passed.** They cover authentication, duplicate requests,
API field/endpoint restrictions, approval refusal, reply assembly, request bounds,
browser/forwarded-header rejection, redaction of internal errors, secret/private
prompt blocking before RPC, environment stripping, file/symlink permissions,
listener address validation, proxy authority attacks, and private DNS answers.

**Seven actual macOS sandbox probes passed:** allowed synthetic file readable;
outside synthetic secret unreadable; approved local proxy reachable; unrelated
loopback port blocked; LAN connection blocked; direct Internet connection blocked;
other-process inspection blocked. Tests used synthetic fixtures, not real secrets.

**Real LuaSec 1.3.2 and LuaSocket transport tests passed.** These execute our actual
Lua transport on the Mac against the live bridge, not a mocked TLS implementation:

- Correct certificate and token successfully fetched state.
- Invalid token returned HTTP 401.
- Wrong certificate/pin was refused before sending any HTTP application bytes.
- Captured encrypted TCP bytes contained no plaintext device token, HTTP request
  line, authorization header, or synthetic prompt marker. The final capture was
  7,497 bytes and was checked in memory, not saved as a packet trace.
- A plaintext HTTP probe exposed no conversation state or token.

The proxy also completed a public-CA-verified TLS 1.3 handshake to an allowed
OpenAI host without sending account credentials or a model prompt. The hardened
native Codex device-login flow reached the official authentication service through
the restricted proxy.

Lua transport unit checks and KOReader v2025.04 UI-contract regression checks also
passed. The latter validate the older text-style and scrolling API contracts;
they are not a substitute for exercising the Kobo screen.

## Pending and residual limits

Host-side authentication and model-response checks do not establish on-device
UI behavior. Device acceptance requires safely ejecting the Kobo and running
the plugin with Wi-Fi enabled; see the [testing guide](TESTING.md).

These checks do not conceal your public IP, allowed DNS destinations, connection
metadata, or the account/model data intentionally sent to OpenAI. Account-side
retention follows your provider/workspace settings. HTTP CONNECT and stdio are
local IPC; the upstream application stream remains TLS-encrypted through the
local tunnel. There is no LAN-facing plaintext HTTP API.

The Node bridge and native Codex executable remain trusted components. The
sandbox is not a VM and permits standard system runtime access and filesystem
metadata needed to run the process. Local privileged software, another process
controlling your account, physical access to unencrypted Kobo storage, other
installed plugins, Kobo firmware/cloud services, and router configuration are
outside the verified scope. A force-killed process can leave private temporary
runtime files. Pattern-based secret blocking cannot guarantee all sensitive
content is recognized.

## Reproduction

See README.md for test commands. `test/macos-sandbox.mjs` uses test/probe.c;
`test/live-wire.mjs` runs test/live-lua.lua with locally built LuaSocket/LuaSec
modules. The test-only dependency builds reside outside the shareable source
bundle and were not installed globally or onto Kobo.

## Handwriting update 0.3.0

The handwriting path uses KOReader v2026.07.1's pen API and the plugin's vector pad. Only bounded vector strokes are transmitted over pinned TLS; no screenshot
of a book or conversation is captured. A separate no-network Apple Vision
helper recognizes them locally and returns an editable draft. No Codex call
occurs until Send, and the existing sensitive-text guard applies then.

The 18-test Node suite passed, along with Lua/LuaJIT handwriting/review tests,
actual local OCR, a kernel sandbox test denying all network paths including
the localhost proxy, and real LuaSec encrypted-stroke/recognition tests.
The worker excludes the Codex profile and writes no raster image to disk.
Physical writing accuracy, latency, and visual layout still need a device check.
