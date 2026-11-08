# Contributor handoff

## Project scope

KOdexplugin is a KOReader reading companion with a Mac bridge, a dedicated
restricted Codex profile, and local handwriting recognition. Questions and
selected passages are submitted explicitly. Whole-book import, indexing,
retrieval, and PDF ink remain separate work; this document does not authorize
automatic uploads or broader model permissions.

## Implementation guide

- [Architecture](ARCHITECTURE.md): bridge, sandbox, transport, background workers,
  rendering, and proposed document retrieval.
- [Selection flow](SELECTION-FLOW.md): Explain/Ask, passage attachments, payload
  limits, and reader-location restoration.
- [Reading note](NOTE-UI.md): compact/expanded layouts, scrolling, and highlights.
- [Document chats](DOCUMENT-CHATS.md): opaque book identity, isolated threads,
  and bridge/client compatibility.
- [Chat archives](CHAT-ARCHIVES.md): source-level archive behavior, persistence,
  resource limits, and deployment requirements.
- [Handwriting](../HANDWRITING.md): stylus input, local recognition, and privacy.
- [Obsidian integration](OBSIDIAN.md): companion pairing, durable bridge queue,
  explicit archive imports, delivery receipts, and the folder-setup fallback.
- [Roadmap](ROADMAP.md): proposed work and acceptance checks.

## Verification priorities

Local Node and Lua/LuaJIT checks exercise transport/security contracts,
conversation isolation, asynchronous requests, draft/ink preservation,
selection capture, and rendering bounds. Current test commands are in the
[README](../README.md); security controls and additional verification procedures
are described in the [technical README](PROTOTYPE_README.md).

These checks do not reproduce the physical e-ink controller. Verify selection
order, reading-position restoration, keyboard-visible scrolling, rotation,
handwriting accuracy/latency, and conversation switching on hardware. The
[right-edge display defect](DISPLAY-ISSUE.md) remains unresolved; controls-only
diagnostics are available. Do not claim that source checks establish a hardware
fix.

## Deployment and private state

Deploy compatible bridge and plugin versions together. Follow each feature's
deployment notes, preserve pairing and native book settings, and account for
in-memory conversations before restarting the bridge. Restart KOReader after
replacing plugin files.

Private profiles, certificates, pairing tokens, transcripts, diagnostic images,
and local operational notes must stay out of Git. A source checkout does not
include a configured runtime. Follow the current installation instructions in
the [README](../README.md) and the feature-specific guides above.
