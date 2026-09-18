# Roadmap

What the groundwork deliberately leaves for later, and why it is safe to leave.

## Not yet built

### PDF page rendering
`PdfElement`, the asset store, text extraction and annotation-over-PDF all
exist; what is missing is drawing the page image. The element renders as a
placeholder that keeps its position, so ink annotated over it is already
anchored correctly. Wiring `pdfrx` (pdfium, BSD-3) into `_PdfBox` is a
self-contained change — it needs no format or schema change.

### Rich-text editing in place
Text is *rendered* with full formatting. Editing goes through a plain-text
field that preserves each line's kind, indentation and inline marks
(`applyPlainText`). A proper inline editor — selection-based bold/italic,
per-run marks, lists that respond to Tab — replaces that one widget.

### Handwriting recognition
`InkElement.writeSearchText` is intentionally empty, and the schema already has
somewhere to put recognised text. Recognition belongs with the AI layer; until
it exists, handwriting is not searchable and nothing pretends otherwise.

### Semantic search in the UI
`EmbeddingRepository` and `NoteAssistant.embedPage` are complete and tested.
What is missing is the background job that keeps embeddings in step with edits,
and the UI that blends semantic hits with FTS hits.

### Resize handles and rotation
The selection overlay draws handles; dragging them is not yet wired. The model
(`Frame.rotation`, `NoteElement.withFrame`) already supports both.

## Planned, in rough order

1. **Move the database onto an isolate.** Every repository method is already
   `Future`-returning for exactly this, so it is an internal change. Worth doing
   before workspaces get large, not before.
2. **PDF rendering** via `pdfrx`.
3. **Inline rich-text editing.**
4. **Import and export.** The page format is already stable and documented;
   `.enex`/OneNote import and Markdown/PDF export sit on top of it.
5. **Embedding indexer** running in the background, then hybrid search.
6. **Sync.** Deliberately last. Pages are immutable, revision-numbered
   documents with ULID identifiers, which is the shape CRDT or
   operational-transform sync needs — but choosing a sync model before the
   editing model has settled would constrain the wrong layer first.

## Deliberately out of scope

* A hosted account, a server, or telemetry.
* Real-time collaborative editing (see sync, above).
* A plugin system, until the internal boundaries have stopped moving.
