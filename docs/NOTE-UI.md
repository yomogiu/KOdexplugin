# Reading note and expanded chat

Reading interactions use a compact note by default. Expand opens the full-screen view for handwriting and longer conversations.

## Interaction

**Tools → Kobo Codex** reopens the same conversation without a new selection. The **Resume Codex chat** Dispatcher action can be assigned in KOReader's gesture settings; the plugin does not replace existing bindings. Ask/Explain close the native selection menu with its keep-highlight option, leaving the temporary source mark visible behind the note and on return. KOReader retains control of the temporary selection's ordinary lifetime. Permanent annotations still require the native Highlight action.

While a document is open, Ask Codex opens a small note-like dialog with the native composer focused and the keyboard ready. Its empty state contains a title, optional one-line passage-preview button, question input and Read / Keys / Expand / Send controls. It does not allocate or display an empty transcript. The book remains visible around the dialog, and background gestures are consumed so they cannot turn pages through the note.

Send submits the current question through the existing non-blocking, pinned transport. Until acknowledgment, the draft stays editable; newer edits are preserved. The same Send button becomes Stop during submission/generation. The first acknowledged question grows the same dialog to include read-only history. Completed answers appear beneath their questions, above the separate editable follow-up input. Questions and answers never become part of the editable input widget. Long answers open at their beginning; manually scrolled history retains its reading anchor. Responses remain hidden until the turn ends.

Codex answer bodies receive a light gray highlight (16% darkening). Labels and user questions remain plain. Character ranges come from message roles, not matching the word “Codex” in user content. UTF-8 character offsets and KOReader's own shaped glyph rectangles support wrapped Unicode/RTL text. Highlight rectangles are clipped to the text viewport and painted after the normal read-only text, preserving black text and avoiding modifications to stored response content.

The input uses KOReader's native focus/cursor behavior. No periodic cursor animation was added: the note does not schedule continuous e-ink refreshes. Both input and transcript use font size 18 in note mode.

Expand keeps the same panel and exposes the full keyboard/pen/Stop/More controls. Handwriting uses the expanded writing surface. Compact returns to the smaller dialog and retains draft, cursor and unsent ink. A pending OCR job must finish or be cancelled before switching modes. Generic chat from the file manager keeps the full-size layout.

## Rendering and sizing

Compact width is 86% of the shorter screen dimension. The history view's total target height is the smaller of 55% of screen height or 78% of the space above the keyboard. The empty note sizes to its controls and input. Portrait/landscape, keyboard visibility and the optional passage line are included in sizing. Touch controls retain the native dimensions.

Compact mode clears only its opaque frame and advertises that it does not cover the screen. Its frame paint requests a matching frame refresh, while stable subwidget changes still use the existing coalesced regional painter. Layout/mode changes redraw the uncovered reader through KOReader's normal reinitialization path. Expanded mode retains the original whole-screen paint/refresh safeguard. Closing uses the established reader-location restoration and preserves the draft/ink within the client instance.

## Local verification and device acceptance

The direct-paint guard allows a verified stack containing only the chat's own keyboard above the chat, with painted keyboard bounds and non-overlapping update regions. Other popups/key popups still defer paints; overlapping regions fall back to UIManager's ordinary stacked repaint. Regression checks invoke pinned native pan, swipe and scrollbar handlers with the keyboard topmost and verify both viewport movement and an actual queued regional repaint. Physical display behavior still requires device acceptance.

The Lua/LuaJIT UI suite covers the reading default, focused native composer, empty/history sizing, complete-only output, shared Send/Stop, read-only history, Unicode role-based highlight ranges and clipped shading writes, answer-start positioning, idle polling, draft/cursor/ink preservation, expansion/collapse, frame-only painting and both orientations with keyboard and attachment combinations. Existing selection, background worker, transport and display diagnostic checks remain applicable.

These are geometry/lifecycle/paint contracts, not native font rendering or e-ink-controller simulation. On-device checks must confirm legibility of size-18 text, highlight contrast/ghosting, cursor/input readiness, wrapping and RTL text, keyboard clearance, first-question growth, long-answer scrolling, expansion/pen/compact round trips, reader background restoration, and the previously reported right-edge artifact.
