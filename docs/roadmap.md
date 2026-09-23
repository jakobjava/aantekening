# Roadmap

What the groundwork deliberately leaves for later, and why it is safe to leave.

## Not yet built

### Touch editing on phones
Text boxes are edited with the platform keyboard and IME on Android as on the
desktop, but the touch conventions are not all there yet: no selection handles
or long-press menu, and a finger dragged across a text box selects text rather
than scrolling the page. Two fingers pan and zoom anywhere.

### Pasting and dropping files
Pictures and PDFs come in through the insert buttons, and anything on a page —
pictures and PDF pages included — is copied and pasted within the app (ADR
14). Pasting a screenshot copied in another application, and dropping files
onto the page, both need a clipboard or drag-and-drop plugin, since Flutter's
own clipboard carries only text; the importer they would call
(`MediaImport.importFile`) already exists. On a touch screen the right-click
menu is not yet opened by a long press.

### Formulas edited as typeset maths
A formula being edited shows its source, with the typeset result previewed
beneath it; everywhere else it is typeset. Editing directly in the typeset
form, as OneNote's "professional" mode does, is a structured editor of its own
and would build on the same runs.

### Handwriting recognition
`InkElement.writeSearchText` is intentionally empty, and the schema already has
somewhere to put recognised text. Recognition belongs with the AI layer; until
it exists, handwriting is not searchable and nothing pretends otherwise.

### Semantic search in the UI
`EmbeddingRepository` and `NoteAssistant.embedPage` are complete and tested.
What is missing is the background job that keeps embeddings in step with edits,
and the UI that blends semantic hits with FTS hits.

### Smaller gaps
* Pictures inside a text box grow no wider than the box, as a table's
  columns do; a box of fixed width does not widen for them.
* Tables have no merged cells, and rows take the height of their text, not
  one dragged to. Cells pasted into a cell go into it as lines, rather than
  filling the cells beside it. Free-standing tables from earlier builds are
  shown but not edited.
* Tabs keep each page's view, but not its undo history: going to another
  page, in a tab or not, starts that page's history afresh.
* Colours picked with the colour picker are remembered for the session only.
* Deleted notebooks, sections and pages stay in the workspace and the store can
  restore them, but there is no recycle bin in the app to do it from yet.
* Pages and sections move and copy by cut, copy and paste; they cannot yet be
  dragged about the panes.
* The graph shows how notes nest, not how they refer to one another: pages
  have no links between them yet. Its layout compares every dot with every
  other, comfortable for a thousand or so pages; a Barnes–Hut quadtree would
  take it further.
* The ribbon has no keyboard route of its own (Office's Alt key tips); its
  commands have shortcuts, and it deliberately never takes the focus.
* Trackpad scrolling on Linux is scaled back to finger distance from what GTK
  reports (see `trackpadPanScale`); there is no setting to make it faster or
  slower yet.
* The text box editor does not yet describe itself to screen readers; a stock
  text field would have, and it needs adding by hand (see ADR 8).
* Spelling is checked in text boxes but not yet in page titles. Every chosen
  language is checked at once; the language of a paragraph is not detected,
  and there is no grammar checking. A word added to the dictionary cannot yet
  be taken out again from the app.

## Planned, in rough order

1. **Move the database onto an isolate.** Every repository method is already
   `Future`-returning for exactly this, so it is an internal change. Worth doing
   before workspaces get large, not before.
2. **Touch editing and the Android build.**
3. **Paste and drop** for pictures and PDFs.
4. **Import and export.** The page format is stable and documented;
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
