# Roadmap and acceptance checks

## Available now

- Passage Explain/Ask with local preview, explicit submission, follow-ups, and return
  to the reader. See [selection flow](SELECTION-FLOW.md).
- Compact note, expanded handwriting controls, local recognition, and background
  transport. See [reading UI](NOTE-UI.md) and [handwriting](../HANDWRITING.md).
- Separate book chats and durable explicit archives. See [chats and archives](CHATS.md).
- macOS Obsidian companion with vault pairing, queued connection samples, explicit
  archive import, and delivery receipts. Pairing and sample delivery have been verified
  in desktop use; the wider archive and lifecycle acceptance work continues. See
  [Obsidian integration](OBSIDIAN.md).

## Next acceptance and usability work

1. Verify on-device selection order, reading-position restoration, keyboard-visible
   scrolling, rotation, pen/keys switching, Undo/Clear, OCR cancellation, and reopening.
   The [right-edge display artifact](DISPLAY-ISSUE.md) remains unresolved.
2. Complete Obsidian archive-picker, rendering, conflict, unload/reload, and restart
   acceptance in the real desktop app. Keep questions on the central Mac bridge.
3. Add Kobo actions for saving an active chat or selected answer, with stable message
   identity, explicit content scope, source provenance, and truthful delivery status.
4. Add retention/queue-management controls and explicit vault/destination migration.
   Preserve user edits and bind pending work to its selected destination.
5. Decide whether to implement direct Markdown-folder delivery. Existing folder-setup
   tools are experimental and do not deliver exports; they are not part of normal setup.

## Future document workflows

These are proposed features, not permissions to import or index a user's books.

- Explicit local document registration with content-hash identity, private storage,
  deletion, and bounded sandboxed extraction. Reject arbitrary client paths/fetch URLs;
  test encrypted, malformed, replaced, and oversized documents.
- Local per-document lexical retrieval before considering a local embedding model.
  Evaluate known/absent answers, document isolation, and accurate physical/printed page
  references. Validate citation IDs before offering page jumps. Do not silently add
  a cloud embedding service or relax the model sandbox.
- Section summaries, argument maps, and cross-section questions with coverage tracking.
  Retrieval can omit context; it is not whole-book comprehension on every turn.
- Explicit local scanned-page OCR, separate from pen-vector recognition.
- Optional page-coordinate PDF ink with undo, autosave, and annotated-copy export.
  Keep originals intact and do not automatically submit ink or page images to Codex.
