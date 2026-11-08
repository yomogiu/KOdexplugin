# Roadmap and acceptance checks

## 1. Stabilize the existing client

Verify the right-edge display defect on-device. If it persists, inspect bounded before/after controls-only captures plus geometry before adding further redraw workarounds. Test Pen entry, extended writing, Clear/Undo, keys/pen switches, rotation, reply updates, popups, OCR cancellation and reopening. Restore stylus hooks when the panel closes. Never weaken transport or sandbox controls to address UI faults.

## 2. Selection-first PDF assistant

Implemented in 0.4.0: Explain/Ask Codex selection-menu actions, bounded text/page attachments and preview, editable Ask, follow-up conversation, Read, draft/ink preservation and native reader-location restoration. Uses v2026.07.1 APIs and the existing text-only bridge. Local Unicode/payload/lifecycle/layout checks pass. Actual PDF selection-order/location/rendering checks remain pending. See SELECTION-FLOW.md. No entire PDF copy/index is needed for this milestone.

## 3. Registered local document store

Explicit import over USB or a narrowly scoped authenticated transfer. Bounded, sandboxed per-page text extraction; content-hash identity; local private storage and deletion. Test encrypted/malformed/huge PDFs and document replacement. Never accept arbitrary filesystem paths or external fetch URLs from the client.

## 4. Document-grounded retrieval and conversations

Conversation separation is implemented in 0.6.0 (hardware acceptance pending): each
book has a separate ephemeral model thread and independent reset/Stop. This
does not implement import, indexing, retrieval or whole-book access. See DOCUMENT-CHATS.md.

Local per-document lexical retrieval first; add a local embedding model only if measured quality justifies it. Do not introduce a cloud embedding service silently. Evaluate known-answer questions on multiple PDFs, physical/printed page labels, absent answers and cross-document isolation. Validate citations against supplied chunk IDs and provide accurate page jumps. Keep app-server filesystem/shell restrictions.

## 5. Whole-document workflows

Explicit section-by-section summaries, argument maps and cross-section questions with coverage tracking. Add scanned-page OCR separately and only locally by default. Be clear that retrieval can miss context.

## 6. Optional PDF ink

Separate user decision: local per-page freehand ink, eraser/undo, autosave and annotated-copy export. Not required for the selection assistant. No automatic document/annotation submission to Codex.

## 7. Optional Obsidian and Markdown export

The preferred path is the macOS Obsidian companion preview: vault pairing,
sample-note delivery, explicit archived-conversation import, a durable bridge
queue, and crash-recovery receipts. Build with `npm run package:obsidian` and
pair with `npm run pair:obsidian`. The Mac bridge remains central and grants the
model no additional permissions. Actual Obsidian desktop acceptance, Kobo active
chat/answer save actions, retention controls, and vault migration remain pending.

The earlier `npm run setup:obsidian` command remains a folder-setup fallback;
direct folder export is not implemented. See [Obsidian integration design](OBSIDIAN.md)
and the [companion guide](../obsidian-kodex/README.md).

Version 0.6.0 implements milestone 2 with compact note UI, a scrolling fix, separate book chats and per-book archives/history. Milestone 3, retrieval/citations in milestone 4, and milestones 5–6 remain proposed. Do not treat this roadmap as authorization to import/index books automatically.
