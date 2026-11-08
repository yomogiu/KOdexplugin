# Selection-first reading assistant

The integration uses KOReader v2026.07.1's supported selection-menu hooks.

The reading UI uses a compact note by default, retains the full chat through Expand, and adds separate document chats. See NOTE-UI.md for UI details and CHATS.md for conversation scope.

## Reading flow

**Tools → Kobo Codex** resumes without reselecting a passage; **Resume Codex chat** is available as an optional gesture action. Ask/Explain preserve KOReader's temporary selection when closing the selection menu. This does not automatically save an annotation; native Highlight still controls permanent marking.

1. Select a passage and open KOReader's normal selection menu. **Explain** submits a short preset explanation request; **Ask Codex** opens chat with an attachment and an editable question. Ask itself makes no bridge request.
2. Tap the **Passage** button above the conversation to preview the exact quotation, physical PDF page reference when available, and whether it has been sent. **Detach** removes the attachment from future submission; it does not erase content already in chat history.
3. In Ask, type or handwrite the question and tap **Send**. Existing draft text is retained when entering from selection. Explain submits its preset separately and preserves existing draft text and ink without running OCR on that ink.
4. The complete answer appears when the turn ends. Follow-up questions use the same conversation without repeatedly attaching the quotation. New chat retains the attachment as unsent so the next question includes it again.
5. Tap **Read** to close chat immediately. An already submitted request continues; late replies do not reopen the dialog. Reopening within the same client instance recovers the unsent question/ink/attachment. Closing while Wi-Fi connects cancels that delayed submission.

Chat is an overlay, not a second document view. It does not change the book's page. The reader's view location is captured when the panel opens; an unchanged location causes no navigation on dismissal. If the view changed beneath the overlay, PDF paging restores its native view context (including zoom/pan/scroll), and rolling text restores its xpointer. The origin document must still be open. Document closure cancels queued selection opening, removes the plugin's selection-menu hooks, and skips navigation into the closing book.

## Submitted context

Only the selected text, an explicit question, and available numeric page provenance enter the text prompt. PDF references are **physical, 1-based pages**, not inferred printed page labels. No filename, document path, xpointer, bounding box, image, adjacent page, or whole book is attached. A selection longer than 12000 UTF-8 bytes is rejected without truncation; question plus context must fit the existing 16000-byte client prompt limit.

The model is told to treat the quotation as source text rather than instructions and not to claim access to unseen pages. The bridge's existing prompt guard and tool/filesystem/network restrictions still apply. Submitted text is processed upstream by Codex, through the paired Mac; attachment preview and Ask composition are local.

The chat shows the reader's question and a short page reference rather than repeating the full quotation/instruction wrapper. The bridge retains this bounded display text separately, so reopening a book shows concise history while the model receives the quotation. Each book has a separate conversation; switching books and returning resumes it while the Mac bridge stays running. Attachment state, drafts, ink and reader-return location remain local to the client instance. Restarting the bridge clears working conversations; explicitly saved archives remain available through Chat history. See [chats and archives](CHATS.md).

## Verification and remaining limits

Pure Lua/LuaJIT checks cover exact Unicode/newline and multi-column fixture text, detached capture before native selection cleanup, byte limits, page references and exclusion of private metadata. UI contracts cover the supported menu factories, local-only Ask/preview, explicit submission, retry preservation, follow-up reuse, new-chat reattachment, draft/ink retention, detach, Wi-Fi/close races, document cleanup, native-style view restoration and both orientations with keyboard/pen layouts. They do not establish real-device selection order or e-ink behavior.

On-device checks must verify actual PDF selection order, portrait/landscape rotation, zoom/pan and scrolling position, keyboard/pen composition, Explain during an existing draft, late responses after Read, document switching/resume, and the unresolved right-edge bar. Scanned pages without extractable selection text are not OCRed by this feature. Import/indexing, whole-document retrieval, content-verified document identity, validated citation jumps and PDF ink remain separate milestones.
