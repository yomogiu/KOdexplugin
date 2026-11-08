# Obsidian setup security review

Reviewed 2026-11-08. Scope: `obsidian.mjs`, `obsidian-setup.mjs`, and their tests.
This is a targeted source review and regression check, not a complete bridge,
operating-system, or Obsidian plugin audit. Conversation export is not implemented.

Scope update: the companion preview now implements archived-conversation delivery;
its protocol and ownership are in [the current design](OBSIDIAN.md). This earlier
review describes the folder-setup code. For the agreed local power-user scope,
publisher signature verification and hostile directory-swap defenses are deferred
and are not release blockers. The companion creates notes using Obsidian's Vault
API, retains normal path/symlink checks, and does not grant the model vault access.
The stricter recommendations below remain possible future hardening, not mandatory
prerequisites for the companion preview.

## Hardening applied

| Finding | Impact in current setup | Change |
| --- | --- | --- |
| Opening metadata/config FIFOs could block before file-type validation | Local denial of service requiring filesystem modification | Use nonblocking opens, then reject nonregular files; test in a child process with a timeout. |
| Discovered names and OS errors reached terminal output directly | Terminal escape sequences could manipulate display or terminal features; behavior depends on terminal settings | Escape control and bidi formatting characters in output, reject them in configured paths, and avoid echoing malformed JSON contents. |
| Saved canonical root replaced with a symlink was resolved to a different destination | A later sample could be written outside the selected location | Require the saved root to remain canonical when checking status or writing a sample. Explicit reconnection is required for a changed link. |
| Library configuration reads relied on the CLI to validate the private directory | Future callers could omit the privacy check | Validate private directory ownership/modes and reject directory symlinks at both load and save boundaries. Reject multiply linked private config files. |
| Settings schema accepted unknown fields and unbounded paths on writes | Unexpected data could be persisted; a large config could become unreadable on the next load | Require exact record keys, bound path and serialized sizes, and enforce consistent setup states. |

New notes and directories retain owner-only creation modes. Setup performs no
network requests, does not read book/vault note contents, and does not send vault
paths or discovery results to the model. The external Obsidian app, if explicitly
opened, has its own behavior. Private paths are displayed locally for destination
selection and remain in private configuration; terminal recordings can capture them.

## Remaining boundaries and release requirements

**Concurrent filesystem replacement remains a limitation.** Path checks followed
by path-based writes are subject to directory swaps between operations. The new
canonical-root check blocks an already substituted symlink; it is not a complete
TOCTOU defense. Current writes contain static starter/sample text. Before writing
sensitive conversations, use a reviewed writer that anchors traversal and creation
to open directory descriptors, or an equivalently enforced filesystem sandbox.
Test root and intermediate-directory swaps during writes. Also bind destination
identity to the selected directory so a different directory at the same path
requires reconnection. Do not describe current sample checks as race-proof.

**Bundle ID validation does not authenticate Obsidian's publisher.** The current
app check reads `CFBundleIdentifier`, which another app can imitate. App opening
requires an explicit user action and uses a fixed URI with no note content. Add
signature validation with a publisher requirement grounded in the official release
before treating discovery as publisher authentication. A valid signature without
the expected publisher requirement is insufficient. Never bypass macOS launch
checks or execute an app automatically just because its bundle ID matches.

**A vault is a separate privacy boundary.** Obsidian plugins, cloud sync, sharing,
and backups may access exported notes. File mode 0600 does not protect content from
software running as the same user or ensure cloud confidentiality. Destination
selection now states this before connection. Future export must preview the scope
of content being saved, including quotations and assistant output, and must not
imply that a local destination cannot sync elsewhere. Do not automatically export
prior chats or grant the model access to the vault.

**Future Markdown rendering needs an explicit policy.** Treat model output and
book text as untrusted data: escape metadata values and prevent unintended remote
image loads, HTML, and vault transclusions in generated notes. Do not introduce a
shell, executable template engine, or arbitrary URI actions to render or open notes.

**Setup persistence is atomic but has no concurrent-editor conflict protocol.**
Before a runtime writer consumes these settings, serialize setup mutations or add
revision checks, retain per-destination queue identities, and ensure disconnection
pauses pending work. A same-user attacker who can change the application code or
private configuration is outside the protection offered by Unix file modes.

## Verification and references

Regression tests cover FIFOs, root and subfolder symlinks, hardlinked private
configuration, unsafe modes, extra schema fields, path bounds, terminal controls,
and preservation of existing pairing and notes. They do not establish protection
against hostile concurrent directory replacement or verify Obsidian's publisher.

- [Node filesystem flags](https://nodejs.org/api/fs.html#file-open-constants)
  documents the nonblocking and no-follow flags used for configuration reads.
- [Apple code signing requirements](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
  distinguishes code identity requirements from an app's declared bundle identifier.
