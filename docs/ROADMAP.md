# Roadmap and acceptance checks

## 1. Stabilize the existing client

Confirm the 0.3.5 right-edge outcome on-device. If it persists, inspect bounded before/after controls-only captures plus geometry before adding further redraw workarounds. Test Pen entry, extended writing, Clear/Undo, keys/pen switches, rotation, reply updates, popups, OCR cancellation and reopening. Restore stylus hooks when the panel closes. Never weaken transport or sandbox controls to address UI faults.

## 2. Selection-first PDF assistant

Add an Ask Codex entry to KOReader's text-selection/highlight flow using the installed version's actual APIs. Explicitly attach selected text/page provenance to an editable question. Offer Explain, follow-up conversation and return-to-page. Preserve reader location and unsent drafts. No entire PDF copy/index is needed for this milestone. Verify exactly what text crosses the bridge, including Unicode and selection from multi-column PDFs.

## 3. Registered local document store

Explicit import over USB or a narrowly scoped authenticated transfer. Bounded, sandboxed per-page text extraction; content-hash identity; local private storage and deletion. Test encrypted/malformed/huge PDFs and document replacement. Never accept arbitrary filesystem paths or external fetch URLs from the client.

## 4. Document-grounded retrieval and conversations

Local per-document lexical retrieval first; add a local embedding model only if measured quality justifies it. Do not introduce a cloud embedding service silently. Evaluate known-answer questions on multiple PDFs, physical/printed page labels, absent answers and cross-document isolation. Validate citations against supplied chunk IDs and provide accurate page jumps. Keep app-server filesystem/shell restrictions.

## 5. Whole-document workflows

Explicit section-by-section summaries, argument maps and cross-section questions with coverage tracking. Add scanned-page OCR separately and only locally by default. Be clear that retrieval can miss context.

## 6. Optional PDF ink

Separate user decision: local per-page freehand ink, eraser/undo, autosave and annotated-copy export. Not required for the selection assistant. No automatic document/annotation submission to Codex.

No PDF milestones above are implemented in version 0.3.5. Do not treat this roadmap as a request to implement every milestone immediately.
