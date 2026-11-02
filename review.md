# Code review: aantekening

Independent review of `jakobjava/aantekening` at commit `d2130c9`. It covers all
first-party code: the seven `packages/*`, `app/aantekening`, the native runners,
`third_party/` and CI. That is about 100k lines of Dart in `lib/`, plus the tests,
which were read only to see whether a suspected bug is covered.

**How it was done.** No Dart or Flutter toolchain is installed in the review
environment, so everything comes from reading the code. Nothing was compiled,
analysed or run, apart from a few SQLite and float checks reproduced in Python
(noted where they apply). The codebase was split into eight areas, each reviewed
on its own; their reports are Parts 1–8 below. Every finding has a severity, a
category, a `path:line`, a failure scenario, a fix and a confidence mark:
**Confirmed** means the code path was traced; **Plausible** means the mechanism
is in the code but whether it triggers depends on runtime conditions. The
findings marked ✔ in the priority list were checked a second time against the
source while this summary was written.

**Totals.** About 250 findings: about 90 bugs (including robustness/security),
about 70 performance, about 35 design and about 45 redundancy/code-size items,
plus 5 build/CI items. Most are Low. The ones that matter are listed next.

---

## 1. Fix first: data loss, hangs and wrong results

| # | Sev | Finding | Where | Part |
|---|-----|---------|-------|------|
| 1 | High ✔ | Reopening a page while its save is still running shows the old version. Pages of 128 KiB or more are compressed on an isolate first, and `loadDocument` does not wait for the queued save (`_saving`). The next autosave then overwrites the newer save. **Fix:** `await _saving` in `loadDocument`. | `packages/aantekening_store/lib/src/page_repository.dart:120`, `app/aantekening/lib/src/editor/page_editor.dart:497` | 6 (B1) |
| 2 | High ✔ | Copying a page and pasting it below one of its own grandchildren recurses forever, freezes the UI and then rolls back. | `page_repository.dart:683-736` (`_copyTree`) | 1 (B1) |
| 3 | High | A parent cycle made by two offline computers (A moved under B, B under A) is accepted by the folder sync. The recursive CTE in `subtree` (`UNION ALL`) and the bin's parent walks then never end, so delete, move, restore and export hang. | `packages/aantekening_store/lib/src/database.dart:103-123`, `files/folder_mirror.dart:597-666` | 1 (B2) |
| 4 | High ✔ | Importing several `.one` or `.onepkg` files at once: they share one work folder and `entries.first` is returned, so files are imported twice, lost or mixed together. | `packages/aantekening_interchange/lib/src/onenote/onenote_import.dart:48-94` | 5 (#1) |
| 5 | High | The LZX decoder starts the next frame at the wrong place after a match that runs past a frame, which corrupts every later frame of a `.onepkg`. | `packages/aantekening_interchange/lib/src/cabinet/lzx.dart:72-105, 212-256` | 5 (#2) |
| 6 | High ✔ | An AI answer is saved into whichever conversation is showing when it finishes, not the one it was asked in. | `app/aantekening/lib/src/ai/ai_session.dart:858` (`_keepTurn`) | 7 (B1) |
| 7 | High | Double clicks start duplicate paid AI generations: the busy flag is set after an `await`. Stop cancels only one of them, and a podcast row tap starts a generation outright. | `ai_session.dart` (`ask`, `rewrite`, `make`, `makePodcast`, `speakPodcast`), `ai/podcast_view.dart:808` | 7 (B2, B3, B10) |
| 8 | High ✔ | A stream that is cut off is saved as a finished answer: no provider checks for `message_stop`/`[DONE]`/`done`, and `serverEvents` sends out a half-received final event. | `packages/aantekening_ai/lib/src/sse.dart:35`, the three `*_provider.dart` | 4 (B1) |
| 9 | High ✔ | TikZ/pgfplots works out `-x^2` as `(-x)^2`, so `\addplot {-x^2}` draws the parabola upside down. | `packages/aantekening_math/lib/src/tikz/tikz_expression.dart:117-126` | 3 (B1) |
| 10 | Med | One asset id with no `assets` row (an empty id from a damaged or imported page, or undo after the bin was emptied) makes the page impossible to save: `INSERT OR IGNORE` does not ignore foreign-key failures. | `page_repository.dart:643-651` (`_syncAssets`) | 1 (B3) |
| 11 | Med | Quitting or backing up does not wait for saves already under way; `AantekeningStore.close()` does not either. | `editor/page_editor_storage.dart:184-191`, store D3 | 6 (B2), 1 (D3) |
| 12 | Med | A page file in a newer format is overwritten without a copy being kept, and ink coordinates beyond float32 range make a page impossible to save. | `files/folder_mirror.dart` (`_write`), core ink | 1 (B5, B6) |
| 13 | Med ✔ | The canvas checks which of two overlapping text boxes shows something at a point using a page-unit position where screen pixels are needed (`toView` instead of `toScreen`). It is wrong as soon as the view scrolls or zooms. | `packages/aantekening_canvas/lib/src/infinite_canvas_layers.dart:138-146` | 2 (B1) |
| 14 | Med ✔ | A unary `±` is written as `\pma` (`UnaryNode` writes no separator), so the formula does not render. | `packages/aantekening_math/lib/src/ast.dart:134-146` | 3 (B2) |
| 15 | Med | Drops, pastes and media imports finish on whatever page is open by the time they complete. "Undo" on the deleted-sheet message undoes whatever was done last. | `editor/page_editor_drop.dart:346-423`, `page_editor_commands.dart:58-64` | 6 (B4, B5) |
| 16 | Med | The key catcher is never released when the search line or picker never mounts (for example after the notes failed to open), so the whole keyboard stops working. | `search/search_line.dart:103`, `shell/home_shell.dart:108-141` | 8 (B1) |
| 17 | Med ✔ | `storeProvider` registers the store's close only after `await open`, so a store opened by a provider that was disposed in the meantime leaks its SQLite handle and its folder lock. | `app/aantekening/lib/src/providers.dart:33-52` | 8 (B2) |

### Untrusted input (imports, paste) can hang or exhaust memory
The OneNote, cabinet, Xournal and archive readers trust offsets, counts and
references in the file. These are all reachable by drag-and-drop:

- cyclic or shared references, re-parsed exponentially or forever (`file_nodes.dart:167-274`, `section_reader.dart`, `revision_store.dart:461`)
- no cap on decompressed size
- the LZX window size checked only by `assert`
- a LaTeX macro-expansion bomb on the UI isolate
- `latex_reader._matched` backtracking exponentially on unmatched brackets

Xournal import also copies any local file a document names (for example `~/.ssh/id_rsa`) into the notes. See Part 5 (#3–#13) and Part 3 (B5).
**Recommendation:** run every importer in an isolate with a time and byte
budget, track visited nodes in every graph walk, and only import external files
that the user picks.

---

## 2. Performance: the main themes

1. **Too much is rebuilt.**
   - The canvas clears its element-widget cache on every `didUpdateWidget`, so every pointer move during a marquee or lasso, and every pen-down, rebuilds every visible element (Part 2 P1, P3).
   - Every streamed AI token rebuilds the whole AI pane and re-parses the Markdown of every past answer (Part 7 P1).
   - Both editor panes watch the whole tab state, which includes the search query (Part 8 P2).
   - A text box rebuilds every paragraph on every keystroke, two to four times (Part 6 P1).
   - `MathView` re-parses its formula on every build (Part 3 P1).
2. **Quadratic algorithms.**
   - The graph's force layout is O(n²) per frame on the UI isolate (Part 8 P1).
   - Ink: joining strokes into one element re-records every stroke and redraws every tile on each pen lift, which is O(N²) over a writing session (Part 2 P2).
   - Moving a selection is O(k·n) per pointer move (Part 2 P4).
   - Streamed answers rebuild the whole string for each token (Part 4 P1, P2).
   - The math lexer copies the text before each number (Part 3 P2).
   - The fuzzy picker recomputes its rows about 20 times per key (Part 8 P3).
3. **Heavy work on the UI isolate.**
   - Podcast WAV encoding (up to about 115 MB) and the write (Part 7 P4).
   - The gunzip and full JSON re-parse on every page write to the folder (Part 1 P3).
   - Decoding every body below a restored page (Part 1 P2).
   - `ErrorLog` writes with a sync flush (Part 8 P5).
   - PDF export scans every pixel (Part 8 P6).
4. **Missing SQLite indexes** on `pages.parent_id`, `sections.parent_id`, `ai_items.turn_id` and `mirror_outbox.seq` (Part 1 P1).
5. **Caches that never shrink.**
   - `WorkspaceReader` page documents (Part 7 P5).
   - PDF text and raster holders (Part 6 P3).
   - Dictionaries and spelling verdicts, cached twice (Part 4 P6, D4).
   - Ink `Picture`s kept alive by the 200-step undo history (Part 2 P7).
   - The prepared-statement cache (Part 1 P8).

## 3. Architecture

- **God objects.**
  - `CanvasController` (1,521 lines: history, viewport, sheets, tools, selection and ink in one class).
  - `FolderMirror` (879 lines).
  - `AiSession` (1,355 lines; its podcast half, about 310 lines, is independent).
  - `_PageEditorState` (about 58 fields spread over 13 `part` files).
  - `picker.dart` (1,013 lines).

  ADR 34's "state split into extension files" makes the files shorter but not the
  coupling: `_editingId` is used in 11 of 13 files. Extract real collaborators
  (a selection/session object, a history object, a podcast controller) instead
  of splitting files (Parts 2 D1, 6 D1, 7 D1).
- **State duplicated and synced by hand**: `_editingId` vs `isActive`, `_blocks` vs `_lastEmitted`, and "what is showing" in the AI session spread over five nullable fields. This is the root cause of findings 6 and 7 above (Parts 6 D2, 7 D2).
- **The widget layer writes into the model**: `showsAt` and `viewSize` are set on the controller during build, and four notification channels overlap (Part 2 D2, D3).
- **Layering**: `aantekening_interchange` depends on all of `aantekening_store`, SQLite FFI included, for one file codec (`EntityFile`). Moving the codec to `_core` cuts the dependency (Part 5 #23).
- **Async discipline**: many `unawaited(...)` calls with no error handling, so failures reach only `errors.log` (exports, library actions), and there is no `mounted` or "same page" check after awaits. Use a single "run user action" helper that reports errors and checks the page or scope is still current (Parts 6, 7, 8).
- **AI providers** share no base: error mapping, the "unreachable" wrapper and stream finalisation are written four times, and `OllamaProvider` overrides almost everything it inherits. One shared HTTP/stream helper would also fix finding 8 in one place (Part 4 D1, D2).

## 4. Reducing code size (estimated)

| Change | Saving |
|---|---|
| Generic `PreferenceNotifier<T>`/`enumPreference` instead of 19 hand-written preference notifiers | ~150–250 lines (Part 8 R1) |
| Share the provider/model/key plumbing between the AI and podcast settings | ~200 lines (Part 7 R1) |
| Delete the unused `ColorSwatchPanel` + `NoteSwatch` ✔ and `MarkKinds.of` | ~140 lines (Part 6 R1) |
| One LaTeX brace/environment scanner in `LatexSource` instead of six or more copies (one of which caused a nested-environment bug) | ~150 lines (Part 3 R1) |
| Move the fork's macro-only patches into `aantekening_math` through `TexParserSettings.macros`; drop `RendererLatex` *or* the `operator_name` patch (they fix the same thing) | smaller fork diff; one of the two copies goes (Part 3 D1, fork notes) |
| Three unit tables (`units.dart`, `siunitx.dart`, …) merged | ~100 lines (Part 3 R2) |
| A shared AI provider error/stream helper | ~100 lines (Part 4 D1) |
| Unused public API in `_spell`, `_store` and `_canvas`, and barrel exports with no consumer | modest (Parts 1 R1, 2 R1, 4 R1, 3 D5) |
| Duplicate upsert SQL per entity, two atomic-write implementations, two MIME tables, two ruled/dotted paper painters, three "is it a picture" rules | modest, and removes inconsistencies (Parts 1 R2–R4, 5 #25, 2 D4, 6 R4) |
| Edit keys (undo, redo, copy, cut, paste) written out in four key layers; select mode lacks Redo | small, and fixes a bug (Part 6 R2) |
| The vendored `desktop_drop` carries platforms the app doesn't build; `lints` is declared in six pubspecs and unused | small (Part 5 #26, #27) |

## 5. Build and CI
- The release workflow gives every job a write token, runs no tests and uses a third-party action pinned only to a tag (Part 5 #28).
- `--coverage` reports nothing for the pure-Dart packages (Part 5 #29).
- SDK constraints disagree between the root (`^3.9.0`) and the app (`^3.13.3`) (Part 5 #31).
- `flutter_math_fork` in the app's `dev_dependencies` was checked and is correct: only tests import it directly.

## 6. Tests to add
Each Medium-or-higher bug above names the missing test. The most valuable ones:
- a page saved and loaded while the save is still compressing
- paste-copy beneath a grandchild
- a sync simulation with crossed moves
- importing two OneNote files at once
- an LZX match crossing a frame
- canvas hit-testing at non-zero scroll and zoom
- IME composing with `composingBase >= 0`
- a provider stream cut off mid-answer
- a TikZ expression with a leading minus and a power

---

# Detailed findings by area

- Part 1: `aantekening_core` + `aantekening_store`
- Part 2: `aantekening_canvas`
- Part 3: `aantekening_math` + `third_party/flutter_math_fork`
- Part 4: `aantekening_ai` + `aantekening_spell`
- Part 5: `aantekening_interchange`, native runners, `desktop_drop`, build/CI
- Part 6: `app/.../editor/`
- Part 7: `app/.../ai/` + `app/.../settings/`
- Part 8: the rest of the app (shell, look, files, commands, modes, search, graph, spelling, links)


---

## Part 1: `aantekening_core/lib` and `aantekening_store/lib`

Reviewer scope: `packages/aantekening_core/lib`, `packages/aantekening_store/lib`.
I worked by reading the code, because no Dart toolchain is installed. I checked three SQLite behaviours (the seq ties, the CTE that never ends on a cycle, and FK vs `INSERT OR IGNORE`) and the fractional-index arithmetic against Python's `sqlite3`/float. Findings are ordered most severe first within each category.

---

### Bugs

#### B1. High: copying a page below one of its own grandchildren recurses forever
- **Where:** `packages/aantekening_store/lib/src/page_repository.dart:683-736` (`_copyTree`), reached from `copyPage` (`:328`).
- **What:** `_copyTree` lists `source`'s children before it inserts the copy. It then recurses into each child and lists *that child's* children at that moment. When the target parent is a grandchild-level page X (a child of S), the copy C is inserted under X. Copying X then lists C as one of X's children, and copying C lists X′ (just inserted under C), and the cycle repeats.
- **Failure:** Copy page S and paste onto its grandchild T. `LibraryActions.canPaste` allows a *copy* anywhere (only a cut is checked, `app/.../library_actions.dart:503`), and paste calls `copyPage(S, parentId: X, after: T)`. The recursion inserts pages, FTS rows and asset links, each level in a single transaction, until the Dart stack overflows. The window freezes, then everything rolls back. The test "copies a page beneath one of its own subpages" (`store_test.dart:724`) actually pastes beneath the page *itself*, a case that works, so this path is untested.
- **Fix:** Compute `_db.subtree('pages', source.id, live: true)` once, up front. Copy only those ids, mapping old parent to new parent. Alternatively, refuse `parentId` inside the subtree, as `copySection` already does.
- **Confidence:** Confirmed (traced).

#### B2. High: a parent cycle from two computers hangs the store (recursive CTE with `UNION ALL`)
- **Where:** `packages/aantekening_store/lib/src/database.dart:103-123` (`subtree`). Cycles come in through `PageRepository.putPage` (`page_repository.dart:501`), `LibraryRepository.putSection` (`library_repository.dart:380`) and `FolderMirror._apply/_canApply` (`files/folder_mirror.dart:597-666`).
- **What:** Applying a file read from the folder only checks that the parent *exists*, not that it does not lie beneath the item. Suppose computer 1 moves page A under B and computer 2, before syncing, moves B under A. After the scan, the index holds A→B→A. `WITH RECURSIVE … UNION ALL … ORDER BY depth` never ends on a cycle: I reproduced it, and it ran until killed. While-loops that walk up the parents also never end: `BinRepository._sectionPlace` (`bin_repository.dart:256`) and `_restoreAbove` (`:289`).
- **Failure:** After such a sync, `deletePage`, `movePage`, `arrangePage`, `restorePage`, bin `list`/`purge` and `ArchiveExport.write` on the affected pages spin forever, with memory growing, on the UI isolate. `sync_simulation_test` never moves or re-parents anything (no `movePage`/`parentId` in it). `Hierarchy.of` in core does break cycles, so the tree *displays* fine while every store operation hangs.
- **Fix:** In `putPage`/`putSection` (or `_apply`), drop a `parentId` that lies in the item's own subtree (set it to null). Also bound the CTE, either with `UNION` on `id` only (no depth column) or with `WHERE depth < 1000`, and add a visited-set to the two while-loops.
- **Confidence:** Confirmed for the mechanism (CTE reproduced). The scenario is plausible: concurrent offline moves.

#### B3. Medium: `INSERT OR IGNORE` does not ignore FK violations, so one unknown asset id makes a page unsavable
- **Where:** `packages/aantekening_store/lib/src/page_repository.dart:643-651` (`_syncAssets`). It is used by `_save`, `putPage`, `keepVersion` and `_copyTree`.
- **What:** `page_assets.asset_id` has a foreign key to `assets(id)`. In SQLite, `ON CONFLICT`/`OR IGNORE` never applies to FOREIGN KEY constraints (verified: "FOREIGN KEY constraint failed"). Any referenced id that is not in `assets` therefore aborts the whole save or put transaction.
- **Failure scenarios:**
  - `ImageElement.assetIds`/`PdfElement.assetIds` (`aantekening_core/lib/src/document/elements.dart:535,639`) return `''` for an element missing `assetId`. `readString` falls back to `''`, which happens with a damaged or imported page. `TextElement` filters out empty ids, but these two do not. Such a page can never be saved again.
  - Undo after the bin is emptied: `collectGarbage` deletes the asset row, then the editor's undo brings back the image and every autosave throws.
  - In `putPage`, an asset whose `sha256` is not a digest is skipped (`:507`), but the document still references it. The whole page file is then reported as damaged and never applied.
  - `DraftStoring` fails a whole import when a draft references an asset key missing from `draft.assets`.
- **Fix:** Use `INSERT OR IGNORE INTO page_assets SELECT ?, id FROM assets WHERE id = ?`, and filter empty ids in `ImageElement`/`PdfElement.assetIds`.
- **Confidence:** Confirmed (FK behaviour verified). The scenarios are plausible.

#### B4. Medium: `enqueueAll` gives every row of a table the same `seq`, so `flush` pagination skips everything after the first 64
- **Where:** `packages/aantekening_store/lib/src/files/folder_mirror.dart:129-146` (enqueue) and `:273-283` (`flush` pages with `seq > after … LIMIT 64`).
- **What:** In `INSERT … SELECT id, (SELECT COALESCE(MAX(seq),0)+1 FROM mirror_outbox) FROM pages`, the uncorrelated subquery is evaluated once, so all pages get the same seq (verified: all rows got seq 1). After the first batch `after = seq`, and `seq > seq` skips every remaining row of that kind for this flush.
- **Failure:** On first open (or when adopting a legacy DB) with more than 64 pages, `AantekeningStore.open` writes only 64 pages and then writes the identity marker (`store.dart:126-130`). The rest trickle out at 64 per tick-driven flush, and with `automatic: false` only on explicit flushes. `NotesLocation.moveTo` calls `flush()` once and then copies the folder (`app/.../notes_location.dart:84`), so it can copy an incomplete folder if ties remain.
- **Fix:** Paginate on `(seq, kind, id)`, or loop until `SELECT … ORDER BY seq LIMIT 64` (without `seq > ?`) returns nothing, which is safe because written rows are deleted. Alternatively, give each row its own seq (`ROW_NUMBER() OVER ()` + max).
- **Confidence:** Confirmed.

#### B5. Medium: a page file in a newer format is overwritten without being kept
- **Where:** `packages/aantekening_store/lib/src/files/folder_mirror.dart:393-410` (`_write`) and `:431-443` (`_keepTheirs`).
- **What:** When the file on disk changed since it was last recorded, `_write` decodes it with `EntityFile.decode`. That returns `null` for anything with `format > EntityFile.format`, or for anything unreadable. `_keepTheirs(null, …)` returns without keeping a copy, and the file is then overwritten.
- **Failure:** With two computers on different app versions, the newer build writes a page in format 2. The older build edits the same page and silently replaces the newer file with format 1, losing what only format 2 holds. It does the same to a file that is momentarily partial or undecodable.
- **Fix:** When the file differs from the record and cannot be decoded, do not overwrite it. Leave it stuck (or move it aside as `<id>.<ts>.json.gz`) and report a problem.
- **Confidence:** Confirmed (code path). The scenario is plausible.

#### B6. Medium: ink with a coordinate beyond the float32 range reads fine but can never be saved
- **Where:** `packages/aantekening_core/lib/src/document/ink.dart:259-266` (`fromJson` copies doubles into a `Float32List`) and `:296-301` (`_writeHundredths` → `jsonEncode(inf)`). `toJson` (`:239`) has the same problem.
- **What:** A value above ±3.4e38 (for example `1e308` from a damaged or foreign file) becomes `Infinity` in the `Float32List`. `jsonEncode(double.infinity)` throws `JsonUnsupportedObjectError`.
- **Failure:** The page opens. Every autosave and every folder write of it throws (the mirror marks it stuck), and `withAssetsRenamed`/`copiesOf` also fail. The fuzz test uses `±1e308` but rarely reaches a stroke point in 1,500 rounds; `--deep` runs would hit it.
- **Fix:** In `InkStroke.fromJson`, clamp non-finite or out-of-range values (or drop the sample) when filling the buffer. Optionally make `_writeHundredths` write `0.0` for non-finite values.
- **Confidence:** Confirmed (traced).

#### B7. Medium: `importBytes` returns an existing asset whose file is missing, so the picture stays broken
- **Where:** `packages/aantekening_store/lib/src/asset_store.dart:39-42`.
- **What:** Deduplication is decided by the DB row alone. `putPage` inserts asset rows from synced page files even when their bytes have not arrived, and rows can outlive their file. In that case importing the *same bytes* returns the existing row and never writes the file.
- **Failure:** The user re-imports the picture that shows as missing. The app holds the bytes, yet nothing is written and the image stays broken.
- **Fix:** If the row exists but `fileForHash(digest)` does not exist after the bring-back attempt, write the bytes (the same atomic path) before returning.
- **Confidence:** Confirmed (code). The scenario is plausible.

#### B8. Medium: `FractionalIndex.needsRebalance` uses an absolute epsilon, so inserts collide at large positions
- **Where:** `packages/aantekening_core/lib/src/util/fractional_index.dart:26-43`, used by `AantekeningDatabase.positionAmong` (`aantekening_store/lib/src/database.dart:143-146`).
- **What:** At a magnitude of about 4.2e6 (roughly 4,100 appends × 1024) and above, one ULP is at least 1e-9. `between(a, b)` then returns `a` or `b` before `|a-b| < 1e-9` ever triggers a renumber. At position 1.024e7, the 39th insert into the same gap produced a key equal to a neighbour (verified in Python).
- **Failure:** In a long section, a dragged page lands with exactly a neighbour's position. Its order then falls back to `ORDER BY id`, so it can appear on the wrong side.
- **Fix:** Rebalance when `between(a, b)` equals `a` or `b`, or use a relative test (`(b-a).abs() <= a.abs()*1e-12`).
- **Confidence:** Confirmed.

#### B9. Low/Medium: a conflict copy made during `flush` is never announced
- **Where:** `packages/aantekening_store/lib/src/files/folder_mirror.dart:487` (sets `_found`) and `:503` (`scan` resets `_found`). `flush` never adds anything to `_changes`.
- **What:** `_keepAsCopy` called from `_write` (inside `flush`) records the new "(other version)" page in `_found`. Only `scan` emits `_found`, and `scan` starts by resetting it.
- **Failure:** After a write conflict, the page list does not show the kept copy until some other library change triggers a refresh.
- **Fix:** Emit a `FolderChanges(library: true, pages: {id})` from `_keepAsCopy` (or at the end of `flush`) rather than relying on `scan`'s accumulator.
- **Confidence:** Confirmed.

#### B10. Low: `SearchRepository.count` disagrees with `search`
- **Where:** `packages/aantekening_store/lib/src/search_repository.dart:112-132`.
- **What:** `count` does not exclude pages whose *section* or *notebook* is in the bin (`search` does, `:79-81`). It also ignores `prefixLastTerm`/`matchAny`/`sectionId`.
- **Failure:** A summary count includes pages the results list never shows. `count` has no callers outside a test (`store_test.dart:944`), so the simpler fix is to delete it.
- **Confidence:** Confirmed.

#### B11. Low: `BinRepository.empty()` over-counts pages
- **Where:** `packages/aantekening_store/lib/src/bin_repository.dart:166-173` and the counts in `list()` (`:69-73`, `:87`).
- **What:** A page deleted by itself and later included in its deleted section is counted twice: in the section entry's `_sectionPages`, which counts every page including binned ones, and as its own entry. A notebook entry likewise counts pages of sections that were binned separately.
- **Failure:** The message "N pages deleted for good" is too high.
- **Fix:** Count what `purge` actually removes (`SELECT changes()` / `total_changes` diff), or skip entries already covered.
- **Confidence:** Confirmed.

#### B12. Low: `Hierarchy.of` breaks a parent loop at the wrong item
- **Where:** `packages/aantekening_core/lib/src/tree/hierarchy.dart:31-39`.
- **What:** When an item C's ancestor chain *enters* a loop B→D→B, the walk detects the repeat and sets `parents[C] = null`, detaching C even though C is not part of the loop. The loop itself is broken only when one of its own members is iterated.
- **Failure:** In combination with B2, a page that is not part of the cycle jumps to the top level in the tree, depending on iteration order.
- **Fix:** Null the parent of the node where the repeat was found (`at`'s predecessor in the chain), not `id`.
- **Confidence:** Confirmed.

#### B13. Low: `Rescue.restore` stops at the first page it cannot put back
- **Where:** `packages/aantekening_store/lib/src/rescue.dart:285-305`. Exceptions from `_putBack` propagate, and `AantekeningStore.open` (`store.dart:135-139`) catches everything and sets `rescued = []`.
- **Failure:** If one rescued page fails (for example B3 or B6), every rescued page after it is not restored this session and the user is not told about any of them.
- **Fix:** Try/catch per file inside the loop and continue.
- **Confidence:** Confirmed.

---

### Performance

#### P1. Medium: no index on `pages.parent_id`, `sections.parent_id`, `ai_items.turn_id` or `mirror_outbox.seq`
- **Where:** `packages/aantekening_store/lib/src/schema.dart:87-123` and `:255-262` (v4).
- **What:**
  - `idx_pages_siblings(section_id, parent_id, …)` and `idx_sections_siblings(notebook_id, parent_id, …)` cannot serve lookups by `parent_id` alone. Every step of the recursive `subtree` CTE (`database.dart:113-121`) therefore scans the table, as do `_copyTree`'s `WHERE parent_id = ?`, `purgePage`'s `UPDATE pages SET parent_id = ? WHERE parent_id = ?` (`bin_repository.dart:218`), and the `ON DELETE CASCADE` FK checks on `parent_id`. SQLite recommends indexing FK child keys.
  - `ai_items.turn_id` (`ON DELETE SET NULL`) has no index either.
  - Every mirror trigger runs `SELECT MAX(seq) FROM mirror_outbox`, and `flush` runs `WHERE seq > ? ORDER BY seq`, both without an index.
- **Cost:** Purging a section of M pages in a workspace of N pages is O(M·N). Each `deletePage`/`movePage`/`subtree` is O(depth·N). After `enqueueAll` with thousands of rows, each save's trigger scans the outbox.
- **Fix:** Add migration v6 with `CREATE INDEX` on `pages(parent_id)`, `sections(parent_id)`, `ai_items(turn_id)` and `mirror_outbox(seq)`.
- **Confidence:** Confirmed (schema read). Cost is plausible; not benchmarked.

#### P2. Medium: deleting or restoring a page rewrites FTS and decodes every body on the UI isolate, though search already filters the bin
- **Where:** `packages/aantekening_store/lib/src/page_repository.dart:408-448` (`deletePage` removes FTS rows; `restorePage` runs `_readDocument(id)?.extractSearchText()` for each page in the subtree).
- **What:** `SearchRepository.search` already filters on `p.deleted_at IS NULL`, and section and notebook deletion rely on that filter alone. Only page deletion maintains FTS by hand. Restoring therefore synchronously gunzips, parses and extracts text for every page in the subtree, with no isolate, even for heavy pages.
- **Fix:** Leave FTS rows in place on soft delete (the query filters them). Remove them only on purge. `restorePage` then becomes a single `UPDATE`.
- **Confidence:** Confirmed.

#### P3. Medium: every page write to the folder gunzips on the UI isolate, then re-parses the whole JSON only to check it is an object
- **Where:** `packages/aantekening_store/lib/src/files/folder_mirror.dart:326-339` → `page_repository.dart:466-481` (`pageFile` → `_Body.json` → `gzip.decode`, synchronous, not offloaded) and `folder_mirror.dart:416-425` (`_encode` runs `jsonDecode(utf8.decode(json))` on the full document).
- **Cost:** For a 5 MB handwriting page, every flush decompresses on the window's isolate, copies the decompressed bytes to an isolate, fully parses them (allocating the whole object graph) and throws the result away, then recompresses. The gzip CRC already catches corruption of compressed bodies.
- **Fix:** Pass the stored (compressed) bytes to the isolate and do decompress, recompress and digest there. Replace the full parse with a cheap check (first and last non-whitespace bytes are `{`/`}`), or rely on the CRC.
- **Confidence:** Confirmed (traced).

#### P4. Low/Medium: copying, keeping a version and drafting decode and re-encode whole documents synchronously
- **Where:**
  - `packages/aantekening_store/lib/src/page_repository.dart:712-721` (`_copyTree`) and `:393-401` (`keepVersion`): `_readDocument` + `_writeBody` + `extractSearchText`, all on the UI isolate inside one transaction.
  - `aantekening_core/lib/src/document/page_document.dart:246-256` (`withAssetsRenamed` does `jsonDecode(jsonEncode(...))` on every non-ink element). `DraftStoring` calls it for every page even when the id map is empty (`draft_storing.dart:168`).
  - `draft_storing.dart:189` computes `extractSearchText()` and `putPage` computes it again (`page_repository.dart:568`).
- **Cost:** Copying a section of large handwriting pages blocks the window for the sum of all decode and encode times.
- **Fix:** Copy the body blob with SQL and patch the `"id"`, or decode on an isolate (`away`). Skip `withAssetsRenamed` when no element references a key in the map. Drop the encode/decode round trip: `rename` already returns fresh maps. Compute the text once.
- **Confidence:** Confirmed.

#### P5. Low/Medium: `ArchiveExport.write` holds every exported page in memory at once, decompressed
- **Where:** `packages/aantekening_store/lib/src/archive_export.dart:195-241`.
- **What:** All `PageFile`s (each with its `documentJson` gunzipped) are gathered into `files` before the zip is written, and all of it runs synchronously.
- **Cost:** Exporting a large notebook needs memory roughly equal to the sum of the decompressed page sizes, and freezes the window.
- **Fix:** Stream page by page (read, encode, add, release). Also delete `$target.tmp` on failure; today it is left behind.
- **Confidence:** Confirmed.

#### P6. Low: `RichTextEditing.insertText` is quadratic in the number of pasted lines
- **Where:** `packages/aantekening_core/lib/src/document/rich_text_editing.dart:637-645`.
- **What:** Each line runs `splitBlock` and `_insertInline`, and each of those copies the whole block list through `_replaceRange`.
- **Cost:** Pasting about 10k lines does about 5·10⁷ element copies.
- **Fix:** Build the new blocks for all lines first and splice them in once.
- **Confidence:** Confirmed (algorithmic). The impact is plausible.

#### P7. Low: quadratic and repeated work in text helpers
- `aantekening_core/lib/src/digest/rich_markdown.dart:216`: `_endsSentence` copies the whole remaining text (`text.substring(dot + 1).trimLeft()`) for every full stop, which is O(n²) per paragraph. It also builds `RegExp(r'\d')`/`RegExp(r'^\d+$')` per call (`:226`, `:229`). Scan forward by index instead and hoist the regexes.
- `aantekening_core/lib/src/latex/latex_preamble.dart:190,257`: `RegExp`s are built for each macro use inside `expand`.
- `aantekening_store/lib/src/page_repository.dart:744`: `previewOf` builds `RegExp(r'\s+')` on every save.
- **Confidence:** Confirmed.

#### P8. Low: the prepared-statement cache grows without bound
- **Where:** `packages/aantekening_store/lib/src/database.dart:83-84`, fed by `AiRepository.forgetReviews` (`ai_repository.dart:403-410`, one SQL string per `keep.length`) and `FolderMirror._insertRow` (one per column set).
- **Cost:** Each distinct string is a persistent statement that is never finalized until `close`.
- **Fix:** Do not cache dynamic SQL (add a `cache: false` path), or use `json_each(?)` for `NOT IN`.
- **Confidence:** Confirmed.

#### P9. Low: `_forgetAiAbout` filters on `scope_id` alone and cannot use the `(scope_kind, scope_id)` indexes
- **Where:** `packages/aantekening_store/lib/src/bin_repository.dart:232-235`.
- **Cost:** Full scans of `ai_threads` and `ai_items` for every purged page, which is O(pages × AI rows) when emptying the bin.
- **Fix:** Pass the kind (`scope_kind = ? AND scope_id = ?`).
- **Confidence:** Confirmed.

---

### Design

#### D1. Medium: `FolderMirror` is an 879-line god class
- **Where:** `packages/aantekening_store/lib/src/files/folder_mirror.dart`.
- **What:** One class handles scheduling (tickers, watchers, settle timers), outbox draining, conflict detection, conflict copies, folder scanning and ordering, generic row import (`_insertRow` via `PRAGMA table_info`), and stat records.
- **Cost:** B4, B5 and B9 all come from state shared across these concerns (for example `_found` is reused by both flush and scan).
- **Fix:** Split it into a `MirrorWriter` (outbox → files plus conflict policy), a `MirrorReader` (scan/apply), and a small scheduler.
- **Confidence:** Confirmed.

#### D2. Medium: the store is not cycle-safe and validates moves only partially
- **Where:** `LibraryRepository.moveSection`/`copySection` guard against moving or copying into their own subtree. `PageRepository.copyPage` (B1) and every `put*` (B2) do not.
- **What:** The invariants "no cycles" and "parent is in the same section/notebook" are enforced in some write paths and not in others.
- **Fix:** Centralise `_assertNotWithin(table, id, parentId)` in `AantekeningDatabase` and call it from every write that sets `parent_id`.
- **Confidence:** Confirmed.

#### D3. Low/Medium: `AantekeningStore.close()` does not wait for pending page saves
- **Where:** `packages/aantekening_store/lib/src/store.dart:317-327` and `page_repository.dart:154-172`.
- **What:** A save in flight (awaiting `away` compression) that resumes after `close()` runs its transaction on a closed connection. The app works around this with `keepEverything` before exit, but the provider's `onDispose` (`app/.../providers.dart:46-51`) closes without it when switching notes.
- **Fix:** Expose `PageRepository.idle` (the `_saving` future) and await it in `close()` before `mirror.close()`.
- **Confidence:** Plausible.

#### D4. Low: asset GC can race with an unsaved import
- **Where:** `packages/aantekening_store/lib/src/asset_store.dart:147-176`.
- **What:** GC removes any asset row with no `page_assets` link. An asset imported in the last ~700 ms (before the debounced save) has no link yet.
- **Failure:** If emptying the bin coincides with that window, the row is deleted, the file is set aside, and the next save hits B3.
- **Fix:** Exclude assets whose `created_at` is within a grace period, or have GC skip assets newer than the last completed save.
- **Confidence:** Plausible.

#### D5. Low: tables and columns with no live use
- `embeddings` (`schema.dart:183-194`) is never read or written anywhere in the repo. Only purge comments mention it.
- `tags`/`page_tags` are maintained by `putPage`, `pageFile` and `_copyTree`, but no API creates a tag (grep finds no other writer). It is a feature carried at a cost on every page put.
- Either finish these features or drop them in a migration.
- **Confidence:** Confirmed by grep.

---

### Redundancy / code size

#### R1. Low: unused public API (grep of `app/` and `packages/*/lib`)
- `NotesFolder.entries` (`files/notes_folder.dart:130`) and `NotesFolder.removeLeftovers` (`:246`) have no callers at all. `removeLeftovers` also duplicates the leftover cleanup in `NotesFolder.listing` (`:214-221`).
- `SearchRepository.count` (`search_repository.dart:112`) and `AssetStore.totalBytes` (`asset_store.dart:220`) are used only by tests.
- `Ulid.isValid` (`aantekening_core/lib/src/util/ulid.dart:56`) is used only by its test. Meanwhile `NotesFolder._ulid` (`notes_folder.dart:146`) re-implements the same check as a regex: reuse one.
- The `if (formatVersion > currentFormatVersion) { }` block in `aantekening_core/lib/src/document/page_document.dart:332-335` is dead.
- **Confidence:** Confirmed.

#### R2. Low: duplicate upsert and insert SQL for each entity
- **Where:**
  - pages: `page_repository.dart:535-560` (`putPage`) and `:588-605` (`_insert`)
  - sections: `library_repository.dart:380-418`
  - notebooks: `library_repository.dart:67-80` and `:171-189`
  - assets: `asset_store.dart:67-79` and `page_repository.dart:517-529`
- **Fix:** Keep one upsert per table (the `put*` form) and have the create paths call it.
- **Confidence:** Confirmed.

#### R3. Low: duplicated FTS removal and sibling SQL
- `DELETE FROM page_search WHERE rowid = ?` after `_rowIdOf` appears 4 times in `page_repository.dart` (`:418-421`, `:453-456`, `:563-566`, `:636`) and again in `bin_repository.dart:222`. Extract `_unindex(pageId)`.
- `'notebook_id = ? AND parent_id IS ?'` and `'section_id = ? AND parent_id IS ?'` are copied into `draft_storing.dart:140,184`, although `LibraryRepository._siblings`/`PageRepository._siblings` exist.
- **Confidence:** Confirmed.

#### R4. Low: two hand-rolled atomic-write implementations
- **Where:** `AssetStore.importBytes` (`asset_store.dart:44-55`) and `NotesFolder.writeAtomically` (`files/notes_folder.dart:164-186`).
- **What:** Both write to a temporary name beside the target, flush, then rename.
- **Fix:** Have `importBytes` call `NotesFolder.writeAtomically`.
- **Confidence:** Confirmed.

#### R5. Low: duplicate segment-distance math
- **Where:** `InkStroke._distanceSquaredToSegment` (`aantekening_core/lib/src/document/ink.dart:220`) and `ShapeRecognizer._distanceToSegment` (`shape_recognizer.dart:444`). Also `Frame._num` (`util/geometry.dart:296`) duplicates `readDouble` from `json_read.dart`.
- **Fix:** Put a single `segmentDistanceSquared` in `geometry.dart`.
- **Confidence:** Confirmed.

#### R6. Low: double imports, including importing the package barrel from inside `src/`, just for doc-comment references
- **Where:** `aantekening_store/lib/src/schema.dart:6-8`, `aantekening_core/lib/src/util/json_read.dart:9-10` and `aantekening_core/lib/src/tree/tree.dart:4-5`.
- **What:** Each imports the same symbol twice with `show X`, once through the library barrel. That creates a self-import cycle for a dartdoc link.
- **Fix:** Keep only the direct `src/` import.
- **Confidence:** Confirmed.

#### R7. Low: `Rescue.keep` decodes and re-encodes the whole document
- **Where:** `packages/aantekening_store/lib/src/rescue.dart:236-241`.
- **What:** It runs `jsonDecode(document.encode())` only to nest the document inside another `jsonEncode`.
- **Fix:** Build the string as `PageFile._head` does (`'{"kind":…,"document":' + document.encode() + '}'`).
- **Confidence:** Confirmed.

---

## Part 2: `packages/aantekening_canvas/lib`

Scope: every file under `packages/aantekening_canvas/lib` (about 6.9k lines). Callers in `app/aantekening` were read only to confirm usage. Tests were read only to check whether a suspected bug is covered.
Confidence: **Confirmed** means I traced the code path. **Plausible** means the mechanism is in the code but the impact depends on runtime factors.

---

### Bugs

**B1. Medium · Bug · Confirmed: `showsAt` maps page points to the wrong screen point once the view has scrolled or zoomed**
`packages/aantekening_canvas/lib/src/infinite_canvas_layers.dart:138-146`
`_showsAt` passes `widget.view.value.toView(page)` to `space.localToGlobal(...)`. `space` is the `RenderPageSpace`, whose local coordinates are the canvas's screen pixels. `toView` returns view-space *page units* and applies neither `- origin` nor `* zoom`. The point is only right at origin (0,0) and 100% zoom. The one test that exercises this path (`app/aantekening/test/text_box_test.dart:137`) opens the page at the corner at 100%, so it passes.
*Failure:* scroll down, then click the visible text of a box that lies under another box's empty paper. `RenderPagePlacement.hitTestChildren` correctly routes the press to the lower box. `CanvasController.hitTest` evaluates `showsAt` at an unrelated point and returns the upper box. The canvas then selects or moves the upper box (or offers `claimsPointer(upper)`) while the lower box takes the caret. The hover cursor is wrong too.
*Fix:* `space.localToGlobal(widget.view.value.toScreen(page))`. Add a test with a scrolled or zoomed view.

**B2. Medium · Bug · Confirmed: one eraser drag creates many undo steps**
`lib/src/canvas_controller.dart:1326-1363`, `lib/src/infinite_canvas_pointer.dart:77,160`
`eraseAt` always calls `_apply(next)` with `recordUndo: true`. Every pointer-move sample that removes a stroke pushes its own undo entry. Move and transform drags use `_takeUndoRecord()`, which groups a whole drag into one step. Erase does not. The existing tests (`test/canvas_test.dart:442-462`) only make single calls.
*Failure:* one swipe across a paragraph creates 10 to 50 undo steps. Ctrl+Z brings the strokes back one at a time, and the swipe uses up a large share of the 200-step `undoLimit`.
*Fix:* give `eraseAt` a `{bool recordUndo = true}` parameter and pass `_takeUndoRecord()` from both call sites.

**B3. Low-Medium · Bug · Confirmed: a drag whose first step is blocked by the page edge is merged into the previous undo step**
`lib/src/infinite_canvas_pointer.dart:164-169`, `lib/src/canvas_controller.dart:1094-1098`
`translateSelection(..., recordUndo: _takeUndoRecord())` evaluates its argument first, so the one-per-drag undo token is consumed even when `translateSelection` returns early (`moved == Offset.zero`, for example an element at x=0 dragged left first). Every later step of the drag is then applied with `recordUndo: false` and never gets an undo entry of its own.
*Failure:* paste an element (it lands at the edge), nudge it left (blocked), then drag it right. Undo now removes the move *and* the paste together.
*Fix:* consume the token only when a change is actually applied. For example, `translateSelection` and `replaceElements` could return `bool`, and the token could be cleared after a `true` result.

**B4. Low-Medium · Bug · Confirmed: a line written off its sheet and back on is joined across the gap**
`lib/src/infinite_canvas_pointer.dart:139-158`
While the pointer is off `_strokeSheet`, moves are only skipped (`break`). As soon as it returns, `extendStroke` appends the new point to the same `_wetPoints`, so a straight chord connects the exit point to the re-entry point. The test `test/sheets_test.dart:526` covers only leaving the sheet, never coming back. The hold-to-shape timer (`_restAt`) also keeps running while the pen is off the sheet.
*Fix:* once the stroke leaves its sheet, either end it and start a new stroke on re-entry, or latch a "cut" flag that ignores any further samples.

**B5. Low · Bug (latent) · Confirmed: ink set as background disappears, and new strokes can join a locked element**
`lib/src/canvas_controller.dart:828-846`, `1253-1267`; `lib/src/infinite_canvas_layers.dart:358-370`
`setAsBackground` accepts any element kind. The layer builder draws ink only when it is `!element.locked`, and the locked widget layer excludes every `InkElement`. Locked ink is therefore drawn by nothing, although `CanvasPreview`'s documentation says background ink is drawn. `setAsBackground` also leaves `_activeInkElementId` set, and `endStroke` never checks `existing.locked`. A stroke written within 8 s after that call is appended to the invisible, unselectable element. Today the app passes only embeds (`app/.../page_editor_keys.dart:139-141`), but a page file with `"locked": true` on ink also renders nothing.
*Fix:* restrict the API to embeds, or paint locked ink in the background layer. Also clear `_activeInkElementId` in `setAsBackground` and require `!existing.locked` before joining.

**B6. Low · Bug · Confirmed: a controller swap leaves the gesture in progress pointed at the old controller**
`lib/src/infinite_canvas.dart:354-367`
`didUpdateWidget` re-listens and rebuilds `InkAhead` but resets none of `_action`, `_activePointer`, `_transform` or `_strokeSheet`. `_transform.originals` belong to the old page and would be passed to the new controller's `replaceElements`. The old controller keeps `_drawing == true`.
*Fix:* when the controller changes, call `oldWidget.controller.cancelStroke()` and `_resetPointer()`.

**B7. Low · Bug · Confirmed: `replacePlaceholder` records an undo step and clears redo even when nothing is replaced**
`lib/src/canvas_controller.dart:1045-1048`
`_record(...)` runs before `_apply`. If the id is no longer on the page, `withElementReplaced` returns `this`, `_apply` does nothing, and an empty undo step has still been pushed and the redo stack wiped.
*Fix:* check `_byId.containsKey(element.id)` first.

**B8. Low · Bug · Plausible: a zoom snapshot can go stale when a nested repaint boundary repaints**
`lib/src/zoom_snapshot.dart:191-195`
`_current` is invalidated only by `markNeedsPaint` on the `RenderZoomSnapshot` itself. A descendant inside its own `RepaintBoundary` (for example a caret, a loading image or a nested formula) repaints without touching this box. The next zoom then shows a snapshot of the old content, which contradicts the comment at line 202.
*Fix:* validate against the child layer, or have the hosted widgets invalidate the snapshot explicitly.

**B9. Low · Bug · Plausible: scroll events are not arbitrated**
`lib/src/infinite_canvas_gestures.dart:160-187`
`onPointerSignal` handles every `PointerScrollEvent` without `GestureBinding.instance.pointerSignalResolver`. A wheel turned over `overlay` or `afterSheets`, or over any scrollable inside an element widget, also pans the page. The app already uses the resolver elsewhere (`app/.../graph/graph_panel.dart:250`).

---

### Performance

**P1. High · Performance · Confirmed: every canvas `setState` rebuilds every visible element widget**
`lib/src/infinite_canvas_layers.dart:165-169`, `275-290`
`_PageContentState.didUpdateWidget` always runs `_placed = {}`, so `_place` calls the host `builder` for every element in the region and also for up to 64 kept text boxes. Each gets a new widget instance, so every `TextBoxEditor` rebuilds. `_PageContent` is constructed anew on every `InfiniteCanvas` build. Those builds are triggered by:
- `_update(...)` on **every pointer move** of a marquee or lasso (`infinite_canvas_pointer.dart:175-191`)
- every hover cursor change (`infinite_canvas_hover.dart:11`)
- every pointer up (`_resetPointer`, `infinite_canvas_pointer.dart:319`)
- `_beginPinch`
- every `contents` signal (see P3)

*Cost:* dragging a marquee over a page of formula boxes rebuilds all of them on every event. The cache that keeps formulas cheap (`_placed`) only helps when the view moves.
*Fix:* hold `_marquee`, `_lasso` and `_hoverCursor` in `ValueNotifier`s that the `SelectionPainter` and `MouseRegion` listen to, so the whole canvas is not rebuilt. In `_PageContent`, clear `_placed` only when `widget.builder`, the controller or the document identity actually changed.

**P2. Medium-High · Performance · Confirmed: joining strokes into one ink element discards all identity-keyed ink caches on every stroke**
`lib/src/canvas_controller.dart:1255-1267`; `lib/src/canvas_painters.dart:362-373`, `636-640`
Consecutive strokes are appended to one `InkElement`, which can grow to a page of handwriting. Each `endStroke` then does three things:
1. It copies the whole stroke list (`[...existing.strokes, stroke]`).
2. It creates a new element, so `_recorded` re-records **every** stroke. Nothing caches paths per stroke, so `pressurePath` and `chiselPath` re-tessellate N strokes.
3. It fails `_sameElements` on every ink tile the element covers, so all of them are redrawn with `toImageSync`.

`InkAhead` records the element again as well.
*Cost:* the first frame after each pen lift costs O(N) path work plus a full redraw of the visible ink. That is O(N²) over a writing session.
*Fix:* cache a `Picture` per `InkStroke` (an `Expando<InkStroke>`) and compose element pictures from it. For the append-only case, redraw only the tiles that intersect the new stroke's bounds, or draw the new stroke onto the existing tile images.

**P3. Medium · Performance · Confirmed: `contents` fires for changes that do not affect the page, including at pen-down**
`lib/src/canvas_controller.dart:1112-1123` (`beginStroke`), `1126-1135` (`beginShape`), `231-235` (`markSaved`), `683-712` (tools, pen, shape kind)
`beginStroke` calls `_changed()` unconditionally, even when the selection was already empty. `markSaved` signals `contents` on every save (about 700 ms after each edit) only because `isDirty` flipped. Pen colour, tool and shape-kind changes also go through `contents`.
Each signal rebuilds the whole canvas (`infinite_canvas.dart:389-391`), which via P1 rebuilds every element widget. A single stroke therefore causes three full rebuilds (pen-down, `endStroke`, `_resetPointer`), and the first one adds latency at the moment the pen touches the page.
*Fix:* notify only when the selection actually changed. Move the dirty flag, tool and pen state to their own listenable (or to the plain `notifyListeners`), so the page widgets do not rebuild for them.

**P4. Medium · Performance · Confirmed: moving a selection costs O(k·n) per pointer move**
`lib/src/canvas_controller.dart:1099-1105`
`translateSelection` calls `withElementReplaced` once per selected element. Each call does an `indexWhere` and a full `List.of(elements)` copy (`aantekening_core/.../page_document.dart:299-306`). Each `_apply` then adds `_reindex` (O(n), plus `_byId.keys.toSet()`) and `_withSheetsHolding`, which computes an uncached `document.contentBounds` (O(n)).
*Cost:* dragging a select-all of 1,000 elements makes about 10⁶ element copies per move event, plus a full canvas rebuild (P1/P3).
*Fix:* build the moved list in one pass, as `replaceElements` already does (a single loop over a map).

**P5. Medium · Performance · Confirmed: the dotted background draws one `drawCircle` per dot on every scroll frame**
`lib/src/canvas_painters.dart:119-135`, with `repaint: view` at `:35`
`BackgroundPainter` repaints on every view change and issues one draw call per dot. With the default spacing of 24 units it starts drawing at 6 px on screen (25% zoom). On a 2560×1440 view that is about 100k `drawCircle` calls per frame, and about 6k at 100%. `sheet_painter.dart:188-198` already draws the same pattern with a single `drawRawPoints`.
*Fix:* use `drawRawPoints(PointMode.points, …)` with a round cap, or a tiled `ImageShader`.

**P6. Medium · Performance · Confirmed: wet ink costs O(n²) per stroke**
`lib/src/canvas_controller.dart:173-192`; `lib/src/canvas_painters.dart:771-809`; `lib/src/stroke_geometry.dart:286-311`, `315-343`
Every sample copies all samples so far into a new `Float32List` (`wetStrokes`), and the painter rebuilds the whole `smoothPath` or `pressurePath`. For the highlighter, `chiselPath` also allocates and sorts an 8-point hull for every segment. Long strokes from a 240 Hz stylus get slower the longer they run.
*Fix:* keep a growing `Path` (or a Picture of the settled prefix) and append only the tail. The chisel hull of two translated axis-aligned rectangles can be built directly from the step direction, without sorting.

**P7. Medium · Performance · Plausible: ink pictures are never disposed and are kept alive by undo history**
`lib/src/canvas_painters.dart:236-240`, `372`; `lib/src/canvas_controller.dart:84-85`, `1458-1463`
Recorded `ui.Picture`s live in a static `Expando` keyed by element and are never `dispose()`d. Their native memory goes only when the Dart GC collects the element. The 200-entry undo stack holds every earlier version of a growing ink element, so the pictures for N, N+1, N+2, … strokes all stay alive. The GC also does not know how much native memory a Picture holds.
*Fix:* keep a cache owned by the controller or canvas that disposes a picture when its element leaves `_byId`, and re-record lazily if undo brings the element back.

**P8. Low-Medium · Performance · Confirmed: the selection overlay recomputes all geometry on every scroll frame**
`lib/src/canvas_painters.dart:942`, `974-996`, `1020-1025`; `lib/src/selection_handles.dart:254-302`
`SelectionPainter` sits outside `PageSpace` with `repaint: view`, so it repaints on every frame of a scroll. Each repaint runs `SelectionFrame.around`, `outlineOf` and `roundedOutline` for **each** selected element. For the group, `around` and `outlineOf` run three times (directly, in `positionsFor`, and again in `_drawHandles`).
*Fix:* compute the frames once per selection change. Either draw the per-element outlines in page space inside `PageSpace`, or cache them as a Picture.

**P9. Low-Medium · Performance/Design · Confirmed: the base `ChangeNotifier` fires on every ink sample and every scroll step**
`lib/src/canvas_controller.dart:1225`, `1187`, `1169`, `285`
`_addSample`, `extendStroke` (when shaping), `snapToShape` and `stretchTo` all call `notifyListeners()`, even though dedicated `wetInk` and `view` channels exist. App listeners on the controller itself then run per sample: `CanvasSelect` (`app/.../canvas_select.dart:32`, used 6 times) and the minimap's `_follow` (`page_minimap.dart:187`).
*Fix:* make the base notifier fire only for state that has no channel of its own, or remove it and require the specific listenables.

**P10. Low · Performance · Confirmed: every hit test and hover move recomputes the selection geometry**
`lib/src/infinite_canvas.dart:521-527`; `lib/src/infinite_canvas_hover.dart:32-68`; `lib/src/selection_handles.dart:322-332`
`_HandleTargets.hitTestSelf` runs on every pointer hit test, mouse hover included. It calls `selectedElements` (which allocates and sorts) and `SelectionHandles.hitTest`, which builds the frame twice (once in `positionsFor`, once in `sidesFor`). `_cursorAt` then repeats all of that and adds `controller.hitTest` (another spatial query) for every hover event.
*Fix:* cache the selection frame, handle positions and sides per selection or view version.

**P11. Low · Performance · Confirmed: avoidable O(n) work on every edit**
`lib/src/canvas_controller.dart:1468-1487`, `1399-1405`, `726-729`
`_reindex` rebuilds a `SheetFold` (`_foldOf`, O(sheets)) and allocates `_byId.keys.toSet()` on every edit. `_withSheetsHolding` uses `PageDocument.contentBounds`, which is not cached. `contentBounds` on the controller computes the same union again, through `withElementsRemoved` (a list copy whenever placeholders exist).
*Fix:* memoise the fold on `identical(sheets)`, and derive both bounds from one cached value.

**P12. Low · Performance · Confirmed: the lasso copies its whole point list on every extension**
`lib/src/lasso.dart:26-34`
`extendedTo` copies all points (O(n²) over a loop), and each extension triggers a full canvas `setState` (P1).
*Fix:* make the lasso mutable while it is being drawn, or keep it in a `ValueNotifier<List<Offset>>` that the painter reads.

**P13. Low · Performance · Confirmed: a "no strokes on this layer" answer is never cached**
`lib/src/canvas_painters.dart:362-366`
When an element has no strokes for a layer (most elements, on the inverting layer), `_recorded` returns `null` without caching it. Every paint therefore rescans `element.strokes.any(layer.accepts)`.
*Fix:* cache a sentinel value.

**P14. Low · Performance · Confirmed: every snapshot box adds the same static listener to the view**
`lib/src/zoom_snapshot.dart:262-265`
Each `RenderZoomSnapshot` adds the same static `_moved` to the view, so a scroll frame calls it N times, once per visible or kept box.
*Fix:* register it once per view, with a reference count.

---

### Design

**D1. Medium · Design: `CanvasController` is a god class**
`lib/src/canvas_controller.dart` (1,521 lines)
One class holds:
- the document and undo/redo, including history rewritten for placeholders and layout
- the viewport, page edges (`originRange`, `_within`, `obscured`), `reveal`, `zoomToFit` and `resetZoom`
- sheet editing and remapping (`insertSheets`, `moveSheet`, `_remapSheets`, `setLayout`)
- tools and pen settings
- selection, including the ink splitting in `_selectWhere`
- ink capture: smoothing string, shape drafts, `_ShapeDraft`, join policy and timing
- hit testing with host callbacks
- the spatial index

Other view logic lives in extensions in other files (`Stretching` in `canvas_motion.dart`, `ScrollTo` in `canvas_scroll.dart`), so the viewport rules are spread across three files.
*Suggest:* extract `CanvasView` (viewport, edges, reveal, fit, stretch, scrollTo), `InkCapture` (wet points, smoothing, drafts, join), `SheetEditing` (remapping) and `History`. Keep `CanvasController` as a thin façade so callers are unaffected.

**D2. Medium · Design: the widget layer writes back into the model**
`lib/src/infinite_canvas_layers.dart:132`, `160-164`, `177-179`; `lib/src/infinite_canvas.dart:413`; `lib/src/canvas_controller.dart:53`, `64`, `71`, `78`
`_PageContentState` stores its own `_showsAt` closure into `controller.showsAt`, so the model's `hitTest` queries live render objects. `InfiniteCanvas.build` assigns `controller.viewSize` as a side effect of build. `placeholders` and `passesOver` are public mutable function fields that the host sets.
*Consequences:* the last writer wins if two canvases share a controller. `hitTest` is wrong whenever the render tree is not laid out. B1 went unnoticed because this path is invisible from the controller's tests.
*Suggest:* a `CanvasHost` delegate interface given to the controller once, and an explicit `onResize` path for the view size.

**D3. Low-Medium · Design: four notification channels with overlapping meanings**
`lib/src/canvas_controller.dart:140-151`, `259-263`
The channels are `contents` (document, selection, tools and dirty flag), `view`, `wetInk`, and the base notifier, which fires for all of them. Listeners cannot subscribe to "the selection changed" or "the document changed" alone, which is the root cause of P1, P3 and P9.
*Suggest:* separate `document`, `selection` and `tools` listenables, and no catch-all.

**D4. Low · Design: two implementations of ruled and dotted paper**
`lib/src/canvas_painters.dart:28-166` (one paper) and `lib/src/sheet_painter.dart:92-285` (sheets)
They differ in technique (per-line and per-dot calls vs. raw points worked out once), in fading (dropped under 6 px vs. faded down to 35%) and in colours. Sharing the `_Printed`-style generator would fix P5 and remove about 80 lines.

---

### Redundancy / code size

**R1. Low · Redundancy: unused public API and barrel exports with no consumer outside the package**
- `SpatialIndex.boundsOf` (`spatial_index.dart:102`) has no caller anywhere in the repo. `SpatialIndex.length` and `cellCount` are used only by tests.
- `SheetFold({width, height, count})` (`canvas_viewport.dart:201-208`) is used only by `test/sheets_test.dart`.
- The barrel (`aantekening_canvas.dart:13-28`) exports whole libraries, but no file under `app/` uses `SpatialIndex`, `StrokeGeometry`, `WetInkPainter`, `SelectionPainter`, `NibPainter`, `InkTiles`, `Lasso`, `eraserRadiusIn`, `Stretching` or `ScrollTo`. Narrow the exports with `show` lists, as `sheet_painter.dart` and `zoom_snapshot.dart` already do.

**R2. Low · Redundancy: duplicate imports kept only for doc comments**
`lib/src/canvas_controller.dart:10` and `12`, `lib/src/tools.dart:8` and `10`, `lib/aantekening_canvas.dart:10-11`
Each file imports the same symbol twice (once from the barrel, once from `src/`), and the barrel imports itself. A single `src` import is enough for dartdoc to resolve the reference.

**R3. Low · Redundancy: `zoomToFit(Size)` and `resetZoom(Size)` take a size the controller already has**
`lib/src/canvas_controller.dart:432`, `443`
The app's only callers pass `_controller.viewSize` (`app/.../page_editor.dart:320-321`). Use `viewSize` and drop the parameter, as `zoomAtCenter` already does.

**R4. Low · Redundancy: overlapping selection and background API**
`lib/src/canvas_controller.dart:809-824`, `828`, `937`, `1051`
`setBackground(id, background: true)` only forwards to `setAsBackground([id])`. `selectAll(ids)` (replace the selection with these ids) and `selectEverything()` have confusingly swapped names. `translateSelection` re-implements what `replaceElements` already does (see P4).
*Suggest:* `setBackground` → `takeOutOfBackground(id)`, `selectAll` → `selectOnly(ids)`, and implement `translateSelection` with `replaceElements`.

**R5. Low · Redundancy: repeated helpers in the painters**
`lib/src/canvas_painters.dart:338-356` vs `793-809`, and `311-316` vs `629-634`, `348`, `800`
- The inverting-layer `saveLayer`, transform and draw sequence is written twice (`InkPainter._drawStrokes` and `WetInkPainter._paint`).
- The Aabb-to-`Rect` conversion is open-coded several times next to the existing `InkPainter._rectIn`.

Extract `_withInkLayer(canvas, layer, visible, draw)` and `Aabb.toRect`.

**R6. Low · Redundancy: hit-test ordering goes through a temporary map**
`lib/src/canvas_controller.dart:757-764`
`hitTest` builds a map from element to index only to simulate a stable sort. The "later" element on a z tie is decided by the spatial index's iteration order, not by document order, so the comment overstates what the code guarantees. A single loop that keeps the best `(z, documentIndex)` would be both shorter and deterministic.

---

## Part 3: `packages/aantekening_math` (+ `third_party/flutter_math_fork`)

Scope: linear syntax lexer/parser/AST/writer, LaTeX reader, renderer adapters (`MathView`, `RendererLatex`, `HighlightSource`), TikZ (`lib/src/tikz/*`), packages (mhchem/siunitx/physics), and the vendored typesetter fork. Every finding below comes from reading the code. "Confirmed" means I followed the code path by hand. "Plausible" means the reasoning holds but I could not run it, because no toolchain is installed.

---

### Bugs

**B1. High · Bug · `packages/aantekening_math/lib/src/tikz/tikz_expression.dart:117-126` (Confirmed)**
Unary minus binds tighter than `^`. `_power()` takes its base from `_unary()`, so `-2^2` is parsed as `(-2)^2 = 4`. In pgfmath, `^` binds tighter, so TikZ gets `-4`. pgfplots expressions go through the same reader: `_withVariable` (`tikz_axis.dart:478`) turns `x` into `\x`. The textbook `\addplot {-x^2};` (or `plot (\x,{-\x^2})`) is therefore drawn as an upward parabola, the mirror image of what LaTeX draws. Not covered: `tikz_test.dart` only tests `2^3^2` and `-(1+2)/3`.
*Fix:* parse `^` above unary minus. `_unary` handles the sign and then calls `_power`, and `_power` reads `_postfix(_primary())` as its base and recurses through `_unary` only for the exponent.

**B2. Medium · Bug · `packages/aantekening_math/lib/src/ast.dart:134-146` (`UnaryNode.writeLatex`) (Confirmed)**
The operator and the operand are joined with no separator. A prefix `±`/`∓` before a Latin letter therefore makes an undefined control word. `x = +-a` produces `x = \pma`, `-+t` produces `\mpt`, and the typesetter then shows an error box. This also breaks round trips: `LatexReader` reads `x = \pm a`, `LinearWriter` writes `x = +-a`, and re-translating produces `\pma`. Any edit to such a stored formula in Simple mode corrupts it. Only the binary form `a +- b` is tested (`linear_math_test.dart:190`).
*Fix:* when `operatorLatex` ends in a letter and the operand's LaTeX starts with a letter, write a space (or `{}`) between them.

**B3. Medium · Bug · `packages/aantekening_math/lib/src/parser.dart:48, 674-695, 880` (Confirmed)**
`LinearMath.translate` says it never throws, but it can throw a `RangeError`. In `_parseInterval`, the `to` side can consume past the interval's closing token: `_parseCommand` takes an adjacent `[` as an optional argument even when that `[` is the interval end. `skipTo` is then a no-op and `final close = _advance()` consumes the `end` token. The next `_current` reads `_tokens[length]`. Trace for `[a;\foo[x]`: the tokens are `[ a ; \foo [ x ] end`, `_intervalEnd()` returns 4, `\foo` eats `[x]`, `close = end`, `_index = 8`, and `_parseScripts` then evaluates `_current` and throws `RangeError`. Any `\cmd[` that is not in the symbol table hits this, including while it is being typed. Nothing catches it in `FormulaSource._translate` (`app/.../formula_source.dart:84`), and `MathStorage` translates legacy formulas the same way on page open.
*Fix:* make `_advance()` stay on the `end` token. In `_parseInterval`, only take `close` if `_index == end`, otherwise add a diagnostic. In `_parseCommand`, stop at `_atIntervalEnd(_current)`.

**B4. Medium · Bug · `packages/aantekening_math/lib/src/ast.dart:85-98` (`TextNode`) and `lexer.dart:231-249` (Confirmed)**
Quoted text is pasted into `\text{…}` without escaping. `"50% off"` comments out the closing brace. `"cost in $"` switches to maths mode, `"R&D"` is a stray alignment tab, `"a_b"` is a script in text mode, and `"{"` is an unbalanced brace. Each of these makes the whole formula fail to render. The reverse path keeps LaTeX-escaped text: `LatexReader` reads `\text{50\%}` into `TextNode('50\%')`, `LinearWriter` writes `"50\%"`, and that survives the round trip. So `TextNode.text` means plain text on one path and LaTeX on the other. It also cannot hold a `"`, because `LinearWriter` writes `"$text"` without escaping. Only `"if"` is tested.
*Fix:* give `TextNode.text` one meaning, plain text. Escape `\ { } $ & # % _ ^ ~` on write, unescape in `LatexReader._bracedText` for `\text`, and decide how a quote is written in Simple syntax.

**B5. Medium · Bug · `packages/aantekening_math/lib/src/latex_reader.dart:237-256` (`_matched`) (Confirmed by trace, not run)**
Unmatched brackets cause exponential backtracking and unbounded recursion. A failed fence read runs to the end of the group: `inside()` replaces the outer closer, so an inner `(`/`[`/`|` does not stop at the outer `)`. Each nested failure is then read again from `start+1`. Cost grows as about 2^k for k unmatched openers in one brace group, and recursion depth equals k. Triggers include LaTeX with half-open intervals (`[0,1) \cup [1,2) \cup …`), conditional bars (`P(A|B) … P(C|D)`), or a run of `(`. About 25 of these freeze the UI when a LaTeX formula is opened in Simple syntax (`FormulaSource.sourceIn` → `LinearMath.fromLatex`, `text_box_formulas.dart:158`). A few thousand overflow the stack.
*Fix:* make the inner sequence also stop at every enclosing closer (keep a stack of closers in `_Stops`), or record that a closer is absent after position *p* so the scan is not repeated. Read without recursion where possible.

**B6. Medium · Bug · `packages/aantekening_math/lib/src/latex_reader.dart:372-373` (Confirmed)**
`\operatorname*` is misread. `_commandName()` stops at `*`, and `_bracedText()` then sees `*`, not `{`, so it returns `''`. `\operatorname*{argmax}_x f` is read as `\operatorname{}`, a `*` symbol, `{argmax}_x`, and `f`. `LinearWriter` writes ``\operatorname{} `*` {a r g m a x}_x f``. After any edit in Simple mode, the formula renders as an empty operator, an asterisk and italic "argmax" with a side subscript. The `amsmath_test.dart:102` cases cover only `translate`, not `fromLatex`.
*Fix:* call `_Arguments.star()`-style handling (consume `*`) before reading the braced name, and keep it in the `SymbolNode`.

**B7. Medium · Bug · `packages/aantekening_math/lib/src/latex_reader.dart:482-489` (Confirmed)**
A non-grid environment is cut at the *first* `\end{name}`, without counting nesting. The lexer's `_environment` (`lexer.dart:422`) does count it. For nested `array`/`aligned`/`split`, the `RawNode` holds an unbalanced `\begin…\begin…\end`, the rest is read as loose items, and the outer `\end{…}` is silently dropped by the `case 'end'` branch. After a Simple-mode edit the formula no longer parses.
*Fix:* count `\begin{name}`/`\end{name}` depth, or share one environment scanner with the lexer (see R1).

**B8. Medium · Bug · `packages/aantekening_math/lib/src/tikz/tikz_picture.dart:316-325` (Confirmed)**
`\clip` and `\useasboundingbox` are accepted and then ignored. `_path` sets `draws`/`fills` from the command name, so neither is set, and no clip state or bounding box exists anywhere. A picture that crops with `\clip (0,0) rectangle (4,3);` draws everything unclipped, and its bounds grow to cover all of it. A figure that sets its box with `\useasboundingbox` is sized wrongly. There is no error or diagnostic, and it is neither documented (ADR 39) nor tested.
*Fix:* either implement them (clip: keep a clip `Path` in `_Style`, intersect each mark with `Path.combine(PathOperation.intersect, …)` or record a clip on `TikzMark`; bounding box: override `bounds`), or throw `FormatException` the way unsupported environments do, so the user sees why.

**B9. Low · Bug · `packages/aantekening_math/lib/src/math_view.dart:111-117`, `tikz/tikz_picture.dart:166-173` (Confirmed)**
Only `FormatException` is caught around TikZ reading. Arithmetic that gives Infinity/NaN reaches `int` conversions that throw `UnsupportedError`. Examples: `\foreach \x in {0,...,1/0}` hits `.floor()` at `tikz_source.dart:347`, and `samples=0/0` or `regular polygon sides=1/0` hit `number().round()` at `tikz_style.dart:542,571`. Deeply nested `{…}` in paths overflows the stack through `_items` recursion. In `build` the error fails the widget. In `_reportFormula` (`text_box_formulas.dart:237`) and `editTikzSource` it is thrown out of a keystroke handler.
*Fix:* check `isFinite` before `round`/`floor`, and catch `Object` (mapped to a message) in `TikzPicture.problemIn` and around `TikzPicture.read` in `MathView.build`, the way `_parse` already does for TeX.

**B10. Low · Bug · `packages/aantekening_math/lib/src/tikz/tikz_shapes.dart:437`, `tikz_decorations.dart:298-335`, `tikz_ink.dart:179-196` (Confirmed)**
Work is bounded in some places and not others. Grids (2000 lines), loops (400k chars), samples (1000) and marks (400) are capped. But `arc (0:1e9:1)` builds about 11M cubic pieces, `pattern=dots` over a large area (`(0,0) rectangle (300,200)` is about 5M ovals) runs unbounded, and so does a tiny `dash pattern` on a long path. All of it runs synchronously in `build` on the UI thread.
*Fix:* add one per-picture budget (segments/ovals/dashes emitted) to `_Painter` and throw `FormatException('The picture draws too much')` when it is exceeded.

**B11. Low · Bug · `packages/aantekening_math/lib/src/tikz/tikz_node_shapes.dart:20-26` (Plausible)**
`diamond` uses half-diagonals `(2w, 2h)`. TikZ's default `aspect=1` gives a square diamond with half-diagonals `w+h`. Wide flowchart decision nodes therefore come out much flatter than in LaTeX.
*Fix:* use `w + h·aspect` and `h + w/aspect`, with `aspect` defaulting to 1.

---

### Performance

**P1. Medium · Performance · `packages/aantekening_math/lib/src/math_view.dart:66-78, 101-143`; caller `app/aantekening/lib/src/editor/text/text_box_formulas.dart:227-246` (Confirmed)**
Nothing caches typeset results. Every `MathView.build` repeats `LinearMath.latexFor`, `LatexPreamble().takeFrom/apply`, `LatexPackages.expand`, `RendererLatex.of`, a full `TexParser.parse()` and a `typesetHighlights` walk that allocates a `children.toList()` per AST node. While a formula is open, every keystroke runs this twice: `_reportFormula` → `MathView.problemIn` parses, then the rebuilt `MathView` (cache miss in `block_view.dart` `_cache`) parses the same string again. TikZ node labels, AI answers, the cheat sheet (`SyntaxExample.latex` re-translates on each access) and `HighlightSource._Reading` all re-parse as well. The app's widget cache in `block_view.dart` only hides this for unchanged text blocks.
*Fix:* add a small static LRU in `MathView`, keyed by the prepared LaTeX, that stores `(SyntaxTree?, ParseException?)`. Have `problemIn` and `build` share it (the same pattern as `TikzPicture._readBefore`).

**P2. Low · Performance · `packages/aantekening_math/lib/src/lexer.dart:180-184, 220-224` (Confirmed)**
For every number and every `)`, the lexer copies the whole prefix (`source.substring(0, start)`) and runs `$`-anchored, unanchored-start regexes over it (`10\^\(-?\d+\)$` is scanned from each start position). The lexer is therefore O(n²) and runs on every keystroke. A pasted matrix or table of about 1000 numbers (10k chars) copies tens of MB per keystroke.
*Fix:* look back from `start` for the last non-space character (and for `10^`/`10^(`) without allocating, or keep that state as the lexer advances.

**P3. Low · Performance · `packages/aantekening_math/lib/src/ast.dart` (`FractionNode`, `RootNode`, `AccentNode`, `BinaryConstructNode`, `FencedNode`, `GroupNode`, `CommandNode`, `BraketNode`, `HighlightNode`; `writeGrouped` at :30) (Confirmed)**
`writeLatex(StringBuffer)` exists so output can stream, but each container calls `child.toLatex()`, which builds a fresh buffer and string at every level. Total work is O(depth × size). `writeGrouped` also renders a whole subtree to a string only to test whether it is a single token. `LinearWriter` behaves the same way (`write(child)` → `_join(_pieces(...))` per level).
*Fix:* call `child.writeLatex(out)`. In `writeGrouped`, decide "single token" from the node type (`NumberNode` of length 1, `VariableNode`, `SymbolNode` matching `^\\[a-zA-Z]+$`) before rendering anything.

**P4. Low · Performance · `packages/aantekening_math/lib/src/lexer.dart:567-585` (Confirmed)**
`_word()` calls `startsWith` against every entry of `knownWordsByLength` (several hundred) for each letter it lexes.
*Fix:* index by first character, or try `mathSymbols[source.substring(start, start+len)]` for the few distinct lengths, longest first.

**P5. Low · Performance · `packages/aantekening_math/lib/src/tikz/tikz_source.dart:227-256` (Confirmed)**
`expandLoops` calls `text.replaceRange` once per `\foreach`, including the inner loops it has just expanded, and each call copies the whole text (up to 400k chars). Nested loops therefore cost about (number of loops) × 400k.
*Fix:* expand recursively into one `StringBuffer`, expanding a body's inner loops before writing it out.

---

### Design

**D1. Medium · Design · `packages/aantekening_math/lib/src/renderer_latex.dart` (whole file) vs `third_party/flutter_math_fork/lib/src/parser/tex/functions/katex_base/operator_name.dart:34-44` (Plausible)**
Two fixes exist for the same `\operatorname` problem. The fork patch already declines to take a following function (greediness ≤ 1, which includes `\left`, `\frac`, `\sqrt`) as the operator's argument. `amsmath_test.dart:61-62` shows `\operatorname{f}\frac12` parsing with the bare `TexParser` and no `RendererLatex`. `RendererLatex.of` still rewrites every formula containing `\operatorname` on every build, in both `MathView._parse` and `HighlightSource._problems`.
*Fix:* keep one of them. The patch is the better place because it also serves code that bypasses `RendererLatex`. Delete `RendererLatex` and its tests once `latex_render_test.dart:91-95` passes without it.

**D2. Low · Design · `packages/aantekening_math/lib/src/highlight_source.dart:386-401` (Confirmed)**
`_Reading._problems` decides whether a highlighted part "reads" with a bare `TexParser`, without `MathView.prepared` (preamble macros, `\ce`/`\pu`, packages). In a formula that uses a preamble macro (`\R`) or `\ce{…}`, every candidate counts as a problem, so `fit` falls back to the whole formula or to null.
*Fix:* call `MathView.problemIn(..., preamble:, packages:)`, or pass the prepared text in.

**D3. Low · Design · `packages/aantekening_math/lib/src/parser.dart:914-946` (Confirmed)**
`_startsPrimary(Token token)` takes a token, but its `symbol` and `bar` branches test `_current` (through `_isOperatorIn` and `identical(token, _current)`). It is correct today only because every caller passes `_current`, and it breaks silently as soon as someone looks ahead.
*Fix:* drop the parameter, or make `_isOperatorIn` take the token.

**D4. Low · Design · `packages/aantekening_math/lib/src/ast.dart:486-492` (`HighlightNode.latexOf`) (Plausible)**
Highlights are stored as `\colorbox{#FFEF9D}{$…$}`. KaTeX and flutter_math read it, but LaTeX/xcolor does not (`#` is a parameter character; xcolor wants `\colorbox[HTML]{FFEF9D}`). That contradicts `MathStorage`'s rationale that "LaTeX is what every other tool reads". Exports carry it unchanged (nothing in `_store`/`_interchange` rewrites `\colorbox`).
*Fix:* store `\colorbox[HTML]{FFEF9D}{$…$}`, teach the fork/`RendererLatex` to read the `[HTML]` form, and keep reading the old form.

**D5. Low · Design · `packages/aantekening_math/lib/aantekening_math.dart:11-25` (Confirmed by grep across `app/` and `packages/`)**
The barrel exports internals that nothing outside the package uses: `MathParser`, `MathLexer`, `Token`/`TokenType`, `LatexReader`, `LinearWriter`, `RendererLatex`, the whole `ast.dart`, `LatexPackages`, and every symbol table except `greekLetters` (`math_templates.dart:464`). `MathTranslation.tree` (`linear_math.dart:17`) is never read anywhere, tests included, yet the `FormulaSource` cache keeps it alive.
*Fix:* narrow the exports with `show` to `LinearMath`, `MathTranslation`, `MathDiagnostic`, `MathView`, `MathPreamble`, `MathStorage`, `HighlightSource`, `HighlightNode` (only the `defaultColor`/`hex` helpers), `SimpleSyntaxGuide`, `greekLetters`, `TikzPicture` and `TikzView`. Drop `tree`.

---

### Redundancy / code size

**R1. Medium · Redundancy · LaTeX scanning is written at least six times (Confirmed)**
- `aantekening_core` `LatexSource.closingBrace/closingBracket/skipSpaces/isLetter` (used only by `packages/` and `tikz_picture`)
- `renderer_latex.dart:50-80` (`_afterArgument`, `_skipSpace`, `_isLetter`)
- `lexer.dart:483-497` (`_closing`), `lexer.dart:422-455` (`_environment`)
- `latex_reader.dart:276-292` (`_bracedText`), `:482` (`_environment`, which disagrees with the lexer's, see B7)
- `highlight_source.dart:247-361` (`_pairs`, `_closingBrace`, `_closingParen`)
- `tikz/tikz_source.dart:110-135` (`TikzScanner.matching`)

On top of that, `_isLetter` appears seven times (`renderer_latex.dart:85`, `highlight_source.dart:292`, `latex_reader.dart:522`, `linear_writer.dart:508`, `lexer.dart:637`, `tikz_expression.dart:155`, `tikz_source.dart:105`). They differ subtly in escape handling, unclosed-group results (-1, `length`, or null) and nesting, and that is how B7 arose.
*Fix:* move brace/bracket matching, environment extent and `isLetter` into `LatexSource` and use them everywhere. This saves about 150 lines and removes one class of bug.

**R2. Low · Redundancy · three unit systems: `lib/src/units.dart` (`_named`, `_prefixed`, `_prefixes`, `latexOf`, `fromLatex`), `packages/siunitx.dart:8-125` (`_prefixes`, `_unitNames`, `_abbreviation`, `_units`), `packages/mhchem.dart:239-298` (`_physicalUnits`/`_physicalUnit`) (Confirmed)**
Each has its own prefix and unit tables and its own rule for writing `°C`, `%`, `µ` and powers. For example, `Units.latexOf` writes `\mathrm{{}^{\circ}C}`, while siunitx and mhchem write `{}^{\circ}\mathrm{C}`.
*Fix:* one table of SI prefixes and unit symbols plus one `unitLatex(symbol, power)` writer. siunitx keeps only its name→symbol map, and mhchem `\pu` and linear units reuse the writer.

**R3. Low · Redundancy · `packages/aantekening_math/lib/src/parser.dart:37-44` (Confirmed)**
`_prefixes` lists `\neg` and `\nabla`, but both are lexed as `TokenType.symbol` (`neg`/`nabla` are word symbols) or `TokenType.command`, never as `TokenType.operator`. The prefix check `_check(TokenType.operator) && _prefixes.contains(...)` can never match them, so they are dead entries. Other small dead pieces:
- `Token.latex` for unit tokens (`lexer.dart:150-155`): the parser rebuilds the LaTeX from the lexeme in `UnitNode`.
- `LinearWriter._reaches`: the `PostfixNode() => false` arm duplicates the default.
- A stray doc line "Renders the formula held by [element]." on `MathView.source` (`math_view.dart:31`).

**R4. Low · Redundancy · `packages/aantekening_math/lib/src/symbols.dart:53-…` (Confirmed)**
`greekLetters` maps each name to `'\\' + name` except `omicron`. A `List<String>` plus one override would cut about 40 lines, and so would the same pattern elsewhere in `wordSymbols`. Overlap with the fork's own symbol tables (`flutter_math_fork/lib/src/parser/tex/symbols.dart`) is *not* worth removing: the fork maps commands to glyphs for rendering, and this table maps typed words to commands.

---

### `third_party/flutter_math_fork`: is vendoring justified?

- **Size:** 29,482 Dart lines plus 664 KB of KaTeX fonts, vendored through `dependency_overrides` in the root `pubspec.yaml:23`.
- **The README is stale.** It describes 4 patches (gathered, matrix row clearance, equilibrium arrows, delimiter sizing). The code has `aantekening:` changes in 9 files. The 5 undocumented ones are:
  - `macros.dart`: starred `\newcommand*`, `\newcommand` redefining an existing command, `\tag` set after the equation
  - a new 126-line `ams_macros.dart`: `\def`, `\DeclareMathOperator`, labels, and so on
  - `array.dart`: `pmatrix*` and the other starred matrices
  - `operator_name.dart`: overlaps with `RendererLatex` (D1)
  - `eqn_array.dart`: `aligned` and other amsmath display environments
- **What must stay forked:** the layout fixes (`ast/nodes/matrix.dart`, `ast/nodes/left_right.dart`, `render/layout/layout_builder_baseline.dart`) and the equilibrium arrows (`arrow.dart`, `render/svg/stretchy.dart`). They change render objects and SVG data that the public API cannot reach. That alone justifies a fork. They are also KaTeX-parity bug fixes and good candidates for upstream PRs to flutter_math_fork.
- **What could move out of the fork:** the macro additions (`ams_macros.dart`, `\tag`, `\newcommand*`, `\DeclareMathOperator`). `TexParserSettings.macros` exists and `MacroDefinition`/`MacroExpansion` are exported from `package:flutter_math_fork/tex.dart`, so `MathView._parse` and `HighlightSource` could supply them from `aantekening_math`. The `\newcommand` re-definition change is a one-line behaviour flag. That would shrink the fork's diff to the 5 layout/arrow files.
- **What could be trimmed:** about 2.8k lines of `widgets/selectable.dart`, `widgets/selection/*` and `encoder/*` (TeX encoding, used only by selection copy) are never used by the app, which only uses `Math` + `TexParser`. But `math.dart`, `syntax_tree.dart` and `render/layout/line_editable.dart` reference selection, so deleting them would *enlarge* the patch set. I don't recommend deleting them. Pruning the `provider`/`tuple` dependencies along with them is likewise not worth the divergence.
- **Recommendation:** keep the fork, but update its README to list all 9 patched areas, move the macro-only patches into `aantekening_math` through `TexParserSettings.macros`, delete `RendererLatex` or the operator-name patch (D1), and upstream the layout and arrow fixes so the fork can eventually shrink to a pinned upstream release plus a short patch list.

---

## Part 4: `packages/aantekening_ai/lib` and `packages/aantekening_spell/lib`

Scope: LLM providers (Anthropic, OpenAI-compatible, Ollama), SSE, agent loop,
podcast/speech, study sets; the Hunspell port and its isolate checker. Callers in
`app/aantekening` were checked where the impact depends on them. Reviewed by
reading the code only: no toolchain was available, so nothing was run.

Findings are ordered most-severe first within each category.

---

### Bugs

**B1. A stream that is cut off is accepted as a complete answer — High · Bug · Confirmed**
- `packages/aantekening_ai/lib/src/anthropic_provider.dart:319` (`var stop = StopReason.done`) and `:397-405`. The same pattern is in `openai_compatible_provider.dart:467,517-543` and `ollama_provider.dart:303-362`/`_Reply.stop` (`ollama_provider.dart:370`).
- What is wrong: every provider emits `MessageDone(stop: done)` after the `await for` loop ends, whatever caused it to end. Anthropic never checks that a `message_stop` arrived. OpenAI-compatible never checks for `[DONE]` or a `finish_reason`. Ollama never checks for `done: true`. On top of that, `sse.dart:35` sends out the last, unfinished event when the stream ends (the SSE spec says to drop it). That event's half-written JSON then fails `jsonDecode` and surfaces as a raw `FormatException`.
- Failure scenario: a proxy, NAT or load balancer drops a long stream, which is common during minutes of thinking or a slow local model. Depending on where the cut falls:
  - (a) The partial answer is saved as the finished answer, with no "cut off" note, because `_Answering.run`'s "The answer broke off" check (`note_agent.dart:730`) never fires.
  - (b) A `tool_use` block without `content_block_stop` loses its `input`, so `_neutral` hands the tool `{}`.
  - (c) The user sees `it broke off: FormatException: Unexpected end of input`.
- Fix:
  - Track whether the terminal event arrived (`message_stop`, `[DONE]` or a `finish_reason`, `done:true`). If it did not, throw `AiException('…broke off', retryable: true)`.
  - Drop the unfinished trailing event in `serverEvents`.

**B2. Errors raised while streaming the body escape as non-`AiException`s, so they are never retried and show raw text — Medium · Bug · Confirmed**
- `anthropic_provider.dart:320-395`, `openai_compatible_provider.dart:469-516`, `ollama_provider.dart:303-308`.
- What is wrong: only `client.send` is wrapped. The following are not:
  - `http.ClientException` ("Connection closed while receiving data") during `response.stream`
  - `FormatException` from `utf8.decoder` or `jsonDecode`
  - `TypeError` from the `as` casts on event fields

  `PodcastMaker._retrying`/`_again` (`podcast.dart:854,874`) retry only on `AiException.retryable`, so a dropped connection halfway through a podcast segment kills the whole podcast. `ai_session.dart:698` shows such errors as `'it broke off: $error'`, which includes the request URI.
- Fix: wrap the streaming loop in each provider, or better once in a shared helper (see D1), and turn failures into `AiException(retryable: true, cause: e)`.

**B3. When the tool-round limit is reached, the turn ends with no answer and no explanation — Medium · Bug · Confirmed**
- `packages/aantekening_ai/lib/src/note_agent.dart:196-257`.
- What is wrong: the doc comment (`:120`) says the agent stops after 10 rounds "before answering with what it has". In fact, when round 10 also ends in `StopReason.toolUse`, the tool results are added and the `for` loop just runs out. The model is never asked to answer without tools, and nothing is added to the answer.
- Failure scenario: a small local model keeps calling `search_notes`. The user gets an empty (or `"\n\n"`) answer after 10 paid or slow round trips. The saved history also ends on a user tool-result message.
- Fix: after the loop, if the last stop was `toolUse`, send one last request with `tools: const []`, or a nudge saying "answer now with what you have". Failing that, add a note to the answer.
- Not covered by tests: `agent_test.dart` has no round-limit test.

**B4. `finish_reason: tool_calls` with no calls that could be parsed sends the agent round in circles — Medium · Bug · Confirmed**
- `openai_compatible_provider.dart:510-530` together with `note_agent.dart:228-238`.
- What is wrong: `stop` becomes `toolUse` from `finish_reason` alone. `:530` only ever upgrades to `toolUse` and never resets it when `toolCalls` is empty. Some llama.cpp/vLLM tool parsers report `tool_calls` but give no calls they could parse. The agent then:
  - runs zero tools
  - adds an empty `ChatMessage.user([])`, which `body()` drops because `content.isEmpty`
  - sends the same conversation again

  This repeats up to `maxRounds` times, and each round's text is added to the answer.
- Fix: in the provider, `stop = toolCalls.isEmpty && stop == toolUse ? done : stop`. In the agent, treat `toolUse` with no calls as `done`.

**B5. Malformed tool arguments from a model crash the whole turn — Medium · Bug · Confirmed**
- `packages/aantekening_ai/lib/src/note_tools.dart:116-117` (`describe`) and `:234` (`_look`); `NoteTools.run` catches only `AiException` (`:145`); `web_search.dart:132` throws `FormatException`/`TypeError`.
- What is wrong: `(input['visuals'] as List?)` throws `TypeError` when a model sends `"visuals": "v2"`, which small models often do. `describe` runs before `run` (`note_agent.dart:232`) and catches nothing. A SearXNG instance that answers 200 with HTML, or a reader/store exception, also escapes `run`.
- Failure scenario: one bad tool call ends the whole answer with "The answer broke off: type 'String' is not a subtype of type 'List?'". It should instead go back to the model as an `isError` tool result, which is exactly what the `invalidInputKey` path is there to do.
- Fix: use `switch (input['visuals']) { List l => …, String s => [s], _ => [] }`. In `run`, catch `Object` and return `_error(call, …)`.

**B6. A failed model listing is cached for the provider's whole lifetime — Medium · Bug · Confirmed**
- `packages/aantekening_ai/lib/src/openai_compatible_provider.dart:114-125`.
- What is wrong: `_listed ??= listModels().then(…, onError: (_) => {})` stores the empty map from the failure for good. The provider lives as long as the active settings (`app/.../ai/ai_state.dart:134-143`).
- Failure scenario: LM Studio or vLLM is started after the first question, or OpenRouter has a brief network blip. For the rest of the session every model then gets `defaults`: wrong `contextTokens`, so the wrong notes budget; no `structuredOutput`, so study sets lose schema enforcement; no `price`, so no cost shown.
- Fix: on error, clear `_listed` (`_listed = null`) so the next call tries again, perhaps with a back-off. Cache only on success.

**B7. Ollama reuses tool-call ids (`call_0`, `call_1`, …) in every turn — Medium · Bug · Plausible**
- `packages/aantekening_ai/lib/src/ollama_provider.dart:340`.
- What is wrong: ids restart at `call_0` in every assistant turn. Within Ollama's own path this works only because `body()` builds `names[call.id]` in order. Conversations are saved provider-neutrally (`ChatMessage.toJson`), though, and replayed to whichever provider is active.
- Failure scenario: a conversation started on Ollama and continued after switching to Anthropic contains several `tool_use` blocks with the same id. Anthropic rejects duplicate `tool_use` ids, so the conversation can no longer be continued. Some strict OpenAI-compatible routers do the same.
- Fix: create unique ids, for example `call_${DateTime.now().microsecondsSinceEpoch}_$n` or a random suffix.

**B8. Anthropic's context size is guessed as 1M for every non-Haiku-3/4 model and the listing is ignored — Low · Bug · Plausible**
- `packages/aantekening_ai/lib/src/anthropic_provider.dart:74-90`.
- What is wrong: `capabilitiesOf` always passes `context: null`. `claude-sonnet-4*` and `claude-opus-4-0/4-1` therefore count as 1,000,000 tokens even though no 1M beta header is sent.
- Failure scenario: with `notesTokens` set to 200k or 400k, `ContextBudget.forModel` allows about 333k tokens of notes. The request then fails with "prompt is too long" instead of fitting within 200k.
- Fix: reuse the `max_input_tokens` value cached from `listModels`, as the OpenAI-compatible provider does, and default to 200k for the older families.

**B9. An isolate that fails to start raises a second, unhandled error — Low · Bug · Confirmed**
- `packages/aantekening_spell/lib/src/background_checker.dart:31-42` and `:79-81`.
- What is wrong: if `Isolate.spawn` throws, `close()` calls `_started.completeError(...)` on a future that nothing has listened to yet, because `await checker._started.future` was never reached. Dart reports that as an unhandled async error, in addition to the error that is rethrown.
- Fix: in `close()`, call `_started.future.ignore()` before `completeError`, or only complete it when someone is awaiting it.

**B10. A timed-out spelling check is cached as "misspelled" for the session — Low · Bug · Confirmed (code path) / Plausible (frequency)**
- `packages/aantekening_spell/lib/src/checker.dart:131` (`if (_globalClock.elapsed > _timeLimit) return false;`) together with `spell_checker.dart:243-245` (`_verdicts[word] ??= …`) and the app's `Proofreader._verdicts` (`app/.../spelling/proofreader.dart:116`).
- What is wrong: the 250 ms budget, and the 50 ms compound budget, are wall-clock time. A GC pause, a busy isolate or a hard German compound can push a correct word over the limit. The `false` that results is then cached twice and never checked again.
- Failure scenario: a correct long compound word stays underlined until the app restarts.
- Fix: return a separate "timed out" result from `Checker.spell` and do not cache it, or check again once later.

**B11. Unsupported dictionary encodings silently fall back to Latin-1 — Low · Bug · Confirmed**
- `packages/aantekening_spell/lib/src/text_encoding.dart:19-34`.
- What is wrong: only UTF-8, ISO8859-1/-15/-2 are decoded. KOI8-R, microsoft-cp1251, ISO8859-5/-7/-13 and TIS-620 are all `SET` values used by real Hunspell dictionaries (Russian, Bulgarian, Ukrainian, Greek, Baltic, Thai). They decode as Latin-1 with no error.
- Failure scenario: the app allows "dictionaries … added from files" (`app/.../spelling/dictionaries.dart:1-2`). Adding such a dictionary flags every word as misspelled, and nothing says why.
- Fix: refuse unknown encodings with a clear `DictionaryException` when the dictionary is added, or add the few single-byte tables.

---

### Performance

**P1. Every streamed token rebuilds the whole answer, the reasoning and, for study sets, re-parses all the JSON — Medium · Performance · Confirmed**
- `packages/aantekening_ai/lib/src/note_agent.dart:681-689`, `:709-727`, `:632-647`; `answer.dart:274-277`; `study.dart:231-260`; `loose_json.dart:25-41`.
- What is wrong: on each `TextDelta` or `Reasoning` event, `_Answering.run` yields `progress(...)`. Each call does the following:
  - `builder.answer` copies the whole markdown (`_markdown.toString()`) and the citations list
  - `'$reasoning'` copies the whole reasoning buffer
  - for study sets, `_redraft()` calls `StudySet.read`, which runs `LooseJson.valuesIn` over the entire text so far and then `_within`/`_read`, at depth ≤ 2, for every nested map

  `_Fields._name` (`study.dart:733`), `_cited` (`:706`) and `FlashcardSet._key` (`:554`) also compile a new Unicode `RegExp` on every call. The app then rebuilds Riverpod state for each event (`ai_session.dart:691-696`).
- Cost: this is O(n²) in the length of the answer, on the UI isolate. A thinking model that writes 50k characters in deltas of about 4 characters copies roughly 300M characters for the reasoning string alone. A 20 KB flashcard set re-parses about 5k times.
- Fix:
  - Throttle progress to roughly once per frame (16–50 ms), or send only the deltas.
  - Run `_redraft` only on `CitedSpan` or on a timer.
  - Make the RegExps `static final`.

**P2. The Anthropic provider builds text and thinking by repeated string concatenation — Medium · Performance · Confirmed**
- `packages/aantekening_ai/lib/src/anthropic_provider.dart:344` (`block['text'] = '${block['text'] ?? ''}$text'`), `:357` (`thinking`), `:351-354` (the citations list is copied on every `citations_delta`).
- Cost: each block costs O(n²). A 64k-token answer, or a long thinking block, sent in many small deltas copies hundreds of MB.
- Fix: keep a `StringBuffer` per block index, as `partialJson` already does, and write it into `block['text']`/`['thinking']` at `content_block_stop`. Add citations to a `List` in place.

**P3. The whole conversation is serialised 3–5 times per agent round — Low · Performance · Confirmed**
- `note_agent.dart:210-215` (`PromptSize.of`), `:701-705` (again in `_Answering.run`), `provider.dart:223-248` (`jsonEncode(part.toJson())` per part, which includes every `SourcesPart` holding all the notes), `ollama_provider.dart:240-244` (a third `PromptSize`), `openai_compatible_provider.dart:360-369` (`conversationKey` does `jsonEncode` + `utf8.encode` of the first message, that is all the notes, then FNV-hashes it byte by byte on every request), plus the real `jsonEncode(body)`.
- Cost: with `notesTokens` set to 200k–400k (0.8–1.6 MB of notes) and up to 10 rounds, that is tens of MB of JSON work on the UI isolate per question.
- Fix: work out the prompt size once per round and pass it on. Count characters without `jsonEncode`. Cache `conversationKey` per conversation, for example by the identity of the first message.

**P4. N-gram suggestions do work that does not depend on the dictionary entry once per entry — Low/Medium · Performance · Confirmed**
- `packages/aantekening_spell/lib/src/suggester.dart:823-835` and `_ngram` `:1035-1055`.
- What is wrong:
  - For every dictionary entry within ±4 characters of the word, `Casing.lower(entry.word)` allocates a new string.
  - `_ngram` calls `a.substring(i, i + j)` for every n-gram of the misspelled word, which is the same for every entry.
  - The loop over all entries does not check `_suggestionTimeLimit`.
- Cost: for a 10-letter word against a German dictionary, millions of short-lived strings per right-click "suggest". This is the slowest part of suggesting.
- Fix: compute the word's 1-, 2- and 3-grams once, store the lower-case form with each `WordEntry` at load, and check the clock every few thousand entries.

**P5. The affix-file parser compiles a RegExp for every line, three times over — Low · Performance · Confirmed**
- `packages/aantekening_spell/lib/src/affix_rules.dart:510-514` (`trimmed.split(RegExp(r'[ \t]+'))`), called from three full passes (`:258`, `:278`, `:293`) and again from `_table`.
- Cost: dictionaries with large affix files, such as Hungarian or Turkish, take noticeably longer to load (the class comment says "a second or so").
- Fix: use a `static final RegExp _blank`, and do the FLAG/SET/AF read in one pass.

**P6. Each loaded dictionary is kept for the life of the isolate, including versions superseded by an mtime change — Low · Performance/memory · Confirmed**
- `packages/aantekening_spell/lib/src/background_checker.dart:175-209`.
- What is wrong: `_read` is keyed by `(files, mtime, mtime)` and is never pruned. Updating a dictionary file leaves the old `HunspellDictionary` in memory, which is tens of MB for German. Every language ever selected also stays loaded.
- Fix: key by `files`, replace the entry when the mtime changes, and drop dictionaries that the latest `_Use` no longer uses (perhaps keeping one LRU entry).

**P7. Every word in the `.dic` file gets its own `FlagSet` — Low · Performance/memory · Confirmed**
- `word_table.dart:136-139` → `affix_rules.dart:487-496` → `flags.dart:209-212` (`Uint32List` per call). Words share a small set of flag strings, but only AF-aliased dictionaries share `FlagSet`s.
- Fix: in `flagSet`, intern by the flag text (`Map<String, FlagSet>`). This saves an allocation and a sort per word at load, and a few MB of resident memory.

**P8. Smaller items — Low · Performance · Confirmed**
- `streamed_answer.dart:45-46`: `withoutThinkTags` builds a new `RegExp` for every reasoning delta (`openai_compatible_provider.dart:489`, `ollama_provider.dart:317`). It also misses tags split across deltas.
- `loose_json.dart:229`: `text.substring(from + 1)` copies the rest of the whole text for every `\u` that is not followed by 4 hex digits (LaTeX `\underline`, `\uparrow`). Use `text.length - from - 1 < 4` instead.
- `affix_index.dart:312-314`: `insert(0, …)` per affix is O(n²) for large flag classes. Append, then reverse.

---

### Design

**D1. The three providers share no base: error mapping, the "unreachable" wrapper and stream finalisation are written four times — Medium · Design · Confirmed**
- Status→message mapping: `anthropic_provider.dart:538-561` (`_check`), `openai_compatible_provider.dart:625-655` (`refuse`), `speech.dart:491-513` (`_failed`), `web_search.dart:115-133` (`_fetchJson`).
- Network wrappers: `anthropic_provider.dart:303-311`, `openai_compatible_provider.dart:604-608`, `speech.dart:515-528`. Anthropic's `listModels` (`:54-58`) does not wrap at all, unlike the other two.
- Finalisation copied between `openai_compatible_provider.dart:517-543` and `ollama_provider.dart:277-286`: `answer.close()`, then `CitedSpan([])`, then `MessageDone`.
- Effect: the four variants behave differently: `status` is set in some branches only, Anthropic's 401 omits `status`, and only OpenAI maps 404. B1 and B2 also have to be fixed in three places.
- Fix: a small `HttpChatTransport` (or mixin) providing `send(uri, body, stop)` that wraps errors, `streamEvents(response, decode)` that wraps mid-stream errors and checks for termination, and a single `aiError(name, status, body)`.

**D2. `OllamaProvider` extends `OpenAiCompatibleProvider` but overrides almost all of its API surface — Low · Design · Confirmed**
- `ollama_provider.dart:20-38,160-211,229-363`.
- What is wrong: it overrides `listModels`, `capabilitiesOf`, `requestBody`, `answerFormat`, `userMessage`, `toolCall`, `toolMessage` and `chat`. What it inherits and uses is only `body()` (message flattening) and `send`/`refuse`. It still inherits the unused `_listed`, `promptCache`, `room`, `apiKey` and `_reasoningFor`, and its `chat` calls `capabilitiesOf` in a different order from the parent.
- The constructor runs the same `RegExp(r'(/v1)?/*$')` replace twice (`:30,32`).
- Fix: move the message flattening into a shared helper, or make the shared part an abstract base with `@protected` hooks, so that Ollama is not an "is-a OpenAI provider".

**D3. Speech providers close an `http.Client` passed in by the caller — Low · Design · Confirmed**
- `speech.dart:625,717,783` (`void close() => _client.close();`). The chat providers and web search track `_ownsClient` (`anthropic_provider.dart:565`, `web_search.dart:45`).
- Effect: any shared client passed to `VoiceConfig.create(client: …)` is closed under its other users.
- Fix: track ownership the same way everywhere.

**D4. Spelling verdicts are cached twice, without limit, in two isolates — Low · Design/Redundancy · Confirmed**
- `packages/aantekening_spell/lib/src/spell_checker.dart:227,243` caches inside the isolate. `app/.../spelling/proofreader.dart:32,116` caches the same verdicts on the UI side. Neither cache is ever trimmed, apart from a full clear on `addWord`.
- Fix: keep one cache, the app's, which already batches requests, or limit the isolate's (LRU). It also makes B10 worse.

**D5. Duplicated "is this local?" host check — Low · Design · Confirmed**
- `ai_settings.dart:160-166` and `speech.dart:185-191` are the same code. Neither treats `0.0.0.0`, `*.localhost` or `[::1]` written differently as local.
- Fix: one `isLocalHost(Uri)` helper.

---

### Redundancy / code size

**R1. Unused public API in `aantekening_spell` (used only in tests or not at all) — Low · Redundancy · Confirmed (grepped `app/`, `packages/`)**
- `SpellChecker.removeWord` (`spell_checker.dart:28`): the app instead invalidates the proofreader (`app/.../spelling/spelling.dart:89-98`).
- `SpellChecker.personalWords` getter (`:21`).
- `SpellChecker.misspellingsIn` instance method (`:50`): the app uses `Proofreader.misspellingsIn`, which calls the static `misspellingsWith`.
- `HunspellDictionary.wordCharacters` (`dictionary.dart:52`): nothing reads it.
- `HunspellDictionary.rules` is public only to be read internally.
- Fix: delete these or make them private. That leaves `SpellChecker` at roughly `isCorrect`, `addWord`, `suggest` and `misspellingsWith`.

**R2. A trivial wrapper in the Anthropic provider — Low · Redundancy · Confirmed**
- `anthropic_provider.dart:228-244`: `_toolResult` only adds an `assert` and forwards to `_toolResultBlock`. Merge them.

**R3. The library barrel imports itself — Low · Redundancy · Confirmed**
- `packages/aantekening_ai/lib/aantekening_ai.dart:9-10` imports `'aantekening_ai.dart' show ChatProvider` and `'src/provider.dart' show ChatProvider`, both only for a doc reference. One import, or none, since `[ChatProvider]` resolves through the exports, is enough.

**R4. The AF table is read twice — Low · Redundancy · Confirmed**
- `affix_rules.dart:276-290` reads the first AF table into `flagAliases`, and the main loop `case 'AF': table('AF')` (`:443-444`) walks it again only to skip it. Fold this into the single-pass rewrite in P5.

---

### Checked and found fine (to avoid duplicate reports)
- SSE across chunk boundaries and UTF-8 split across chunks: handled correctly by `utf8.decoder` + `LineSplitter` (`sse.dart:14-15`, `ollama_provider.dart:304-306`). The only SSE flaw is the trailing partial event (B1).
- Cancellation: `stoppable` (`provider.dart:422-441`) completes `stop` and cancels the subscription. `ChatRequest.stop` reaches `AbortableRequest` in all three providers. Podcast TTS requests are stopped by the app closing the speech client (`ai_session.dart:1184`).
- `http.Client` lifetimes: chat providers and web search are closed through `ref.onDispose` (`ai_state.dart:142,162`). Podcast writers that own their provider close it (`ai_session.dart:1034-1041`).
- API keys: sent only in headers (`x-api-key`, `Bearer`, `x-goog-api-key`, `xi-api-key`, `x-subscription-token`). None were found in URLs, error messages or logs, and there is no `print`/`log` in either package.
- Hunspell `AffixCondition` start/end matching and lengths, and the long/num/UTF-8 flag modes, match Hunspell's semantics, except that conditions with astral-plane characters are matched per UTF-16 code unit (theoretical only).

---

## Part 5: interchange parsers, native runners, desktop_drop, build/CI

Scope: `packages/aantekening_interchange/lib`, `app/aantekening/{linux,windows}/runner`,
Android `MainActivity.kt`, `third_party/desktop_drop`, `.github/workflows`, `tool/`,
`packaging/`, pubspecs. Reviewed by reading only (no toolchain). Imports run in a
separate isolate (`app/aantekening/lib/src/files/import_flow.dart:166-180`) that the user
can stop, so a hang means "the import never finishes", not a frozen window. Running out of
memory in that isolate can still bring down the whole process. LaTeX dropped or pasted
onto a page is parsed **on the UI isolate**.

---

### Bugs & security

#### 1. [High · Bug · Confirmed] Importing several OneNote files at once mixes or duplicates them
`packages/aantekening_interchange/lib/src/onenote/onenote_import.dart:48-56, 58-60, 87-94`
- `_readLoneSection` copies every `.one` into the same `work/section/` folder, reads the
  whole folder each time, and returns `entries.first`. Drop `a.one` and `b.one` together:
  the second call finds `[a, b]` and returns `a` again. `b` is lost and `a` appears twice,
  with no warning. The whole folder is also re-parsed for every file, which is quadratic.
- `_readPackage` unpacks every `.onepkg` into the same `work/notebook/`. The second
  package lands next to the first, `contents.length == 1` is no longer true, and the second
  notebook gets the first one's sections as well. Files with the same name overwrite each
  other.
- `read` builds a map keyed by `basenameWithoutExtension`, so `Work.one` and
  `Work.onepkg`, or two `Notes.one` files from different folders, quietly collapse into one.
- This is reachable in ordinary use: `drop_import.dart:106-107` passes every dropped file
  of one importer as one `paths` list. No test reads more than one path (the fuzz test
  uses a single file).
- **Fix:** use a fresh subfolder per path, e.g. `work/<index>/`, and key the result by
  index rather than by name. For a lone section, read only the copied file
  (`_readSectionFile`) instead of the whole folder.

#### 2. [High · Bug · Confirmed in code / Plausible in the wild] An LZX match that runs past a frame shifts every later frame
`packages/aantekening_interchange/lib/src/cabinet/lzx.dart:72-105, 212-256`
- `_decodeTokens` may produce more than `wanted`: a match can run past the end of the
  frame, as long as it stays inside the block (line 250 checks only the block).
- `decodeFrame` then copies `outputLength` bytes starting at `frameStart`, which is right
  for this frame. But the next call starts its frame at the current `_windowPosition`,
  which is already *k* bytes into the next frame. So every later frame is shifted by *k*
  bytes, and every file after that point in the folder is corrupted. Nothing detects it,
  because the CAB checksum covers only the compressed bytes.
- libmspack handles this case explicitly (it tracks `frame_posn` separately from
  `window_posn`, and checks that an overrun stays within `block_remaining`).
- The test encoder (`test/support/lzx_encoder.dart:122`) never matches across a frame, and
  there is no real `.onepkg` fixture, so this path is never tested.
- **Fix:** keep `_frameStart` as a field and advance it by exactly `outputLength` per
  frame. Start each frame's `decoded` at `_windowPosition - _frameStart`, taken modulo
  the window, so it counts the overrun already written.

#### 3. [Medium · Security (DoS) · Confirmed] File node lists: exponential re-parsing through self or shared references
`packages/aantekening_interchange/lib/src/onestore/file_nodes.dart:205-250, 254-274`
- Every node of base type 2 calls `read(chunk)` again. The child list is not cached.
- The `visited` set is local to each `read` call, so it does not catch a list that points
  back to itself from one level down. A single fragment holding two nodes that both point
  at its own chunk recurses to the depth limit of 64 with a branching factor of 2, about
  2^64 reads.
- The same applies to the `.onetoc2` file, which `_tableOfContents` reads first.
- **Fix:** cache the parsed `List<FileNode>` by chunk offset, or keep one visited/budget
  set for the whole file. Put a cap on the total number of nodes.

#### 4. [Medium · Security (DoS) · Confirmed] Object graphs are walked as trees: exponential time on shared or cyclic references
- `packages/aantekening_interchange/lib/src/onenote/section_reader.dart:148-175`
  (`_elements`), `451-479` (`_ink`), and `notebook_reader.dart:216-231` (`visit`).
- The depth limits (64 / 64 / 16) bound depth but not total work. An outline element
  whose `elementChildNodes` lists itself, or a child, twice makes about 2^64 calls. A ToC
  node with 1,000 references repeated 16 levels deep makes about 1000^16.
- The output also grows without bound: each visit appends `OneElement`s, so memory blows
  up before time does.
- **Fix:** keep an "on the current path" set of `ExGuid`s (to break cycles) plus a global
  node budget per page, for example 1,000,000. Throw `FormatDamage` once the budget is
  spent.

#### 5. [Medium · Security (DoS) · Confirmed] Transaction log loop never ends on a cyclic chain
`packages/aantekening_interchange/lib/src/onestore/file_nodes.dart:167-191`
- `while (!chunk.isEmpty && seen < transactions)` follows `nextFragment` without a
  visited set. If a fragment points back to itself and holds no entry with `list == 1`,
  `seen` never grows and the loop runs forever.
- With `transactions = 0xFFFFFFFF` and one sentinel per fragment, it runs about 4×10^9
  times.
- `_ListReader.read` already has the right guard (`visited`). This loop needs the same.
- **Fix:** add a `visited` set of offsets and throw `FormatDamage` when an offset repeats.

#### 6. [Medium · Security (DoS) · Confirmed] Revision dependency cycle hangs `_readObjectRevision`
`packages/aantekening_interchange/lib/src/onestore/revision_store.dart:461-475` (and `242`)
- `_revisions[revision.id] = revision` overwrites an existing entry when a later manifest
  reuses an id.
- Example: B, then A (depends on B), then B′ with id B (depends on A). This makes the
  cycle A → B′ → A.
- `_readObjectRevision` walks `dependsOn` until it finds the object or reaches nil, with
  no `seen` set. `read()` at line 264 does have one. An object revision whose base object
  is missing then loops forever.
- **Fix:** reject a duplicate revision id with `FormatDamage`, or add a `seen` set or step
  limit to the loop.

#### 7. [Medium · Security (resource exhaustion) · Confirmed] No limit on decompressed size
- **Cabinet:** `cabinet.dart:416-446, 449-477` and `lzx.dart:348-357`.
  - `extractTo` writes whatever the folders decode, with no cap on total output and no
    check against the declared file sizes.
  - Past the end of its input, `_BitReader._fill` supplies zeros, and a data block
    checksum of 0 skips the check (line 467). So an 8-byte block header with
    `compressedSize = 0` that continues an open block decodes to a full frame (about
    32 KiB). That is a ratio of roughly 4000:1: a 1 MB `.onepkg` can write gigabytes to
    the temp disk. Every `.one` file is then read into memory whole.
  - A side effect: a truncated frame silently decodes as zeros instead of failing.
- **Archive (`.aantekening`/zip):** `archive_import.dart:84, 101`.
  - `file.readBytes()` inflates every entry fully, and `EntityFile.decode` then runs
    `gzip.decode` on page files (double compression). No limit is applied to either.
- **Xournal:** `xournal_import.dart:127-131`.
  - `gzip.decode(bytes)` with no limit, followed by a full DOM parse.
- **Fix:**
  - Pass a byte budget, for example a multiple of the input size plus a hard cap, through
    `Cabinet.read`, the zip and the gzip readers, and throw `FormatDamage` once it is
    exceeded.
  - In LZX, fail when a frame needs bits past the end of its input. Allow only the few
    padding bits the format needs.

#### 8. [Medium · Security (DoS, UI isolate) · Confirmed; code in `_core`] LaTeX macro expansion bomb freezes or kills the app
`packages/aantekening_core/lib/src/latex/latex_preamble.dart:194-266`, reached from
`latex_text.dart:51` and on the UI isolate from `app/.../editor/drop_import.dart:140` and
`page_editor_text.dart:229`.
- `expand` runs 16 rounds with no limit on output size. With
  `\newcommand{\a}{\a\a\a\a\a\a\a\a}` the text grows 8× per round (8^16), so it runs out
  of memory.
- Dropping or pasting such a `.tex` file runs `LatexText.read` synchronously on the UI
  isolate, so the window hangs and then the process dies.
- **Fix:** stop expanding (and keep the text as it is) once the output passes, say,
  10× the input or 1 MB. Run the LaTeX import of dropped files off the UI isolate.

#### 9. [Medium · Security · Confirmed] Xournal import reads and imports any local file a document names
`packages/aantekening_interchange/lib/src/xournal/xournal_import.dart:240-252, 268-281, 293-311`
- `_findBeside` accepts `filename` as given: absolute, or with `..`. `_keepFile` copies
  the file's bytes into the notebook as an asset, without checking that it is a PDF
  (for `type="pdf"`) or an image (for `pixmap`).
- A crafted `.xopp` with `<background type="pdf" filename="/home/u/.ssh/id_ed25519"/>`
  quietly copies that key into the user's notes. From there it travels with any export,
  backup or synced notes folder.
- Absolute PDF paths are legitimate in Xournal++, so the feature cannot simply be removed.
- **Fix:** keep the file only if its bytes sniff as the expected type (`mimeTypeOf` ==
  `application/pdf` or `image/*`). Otherwise warn and skip it.

#### 10. [Medium · Bug · Plausible; vendored upstream code] desktop_drop on Windows passes a byte count as a character count to `DragQueryFile`
`third_party/desktop_drop/windows/desktop_drop_plugin.cpp:224-226`
- `TCHAR filename[MAX_PATH]; DragQueryFile(..., filename, sizeof(TCHAR) * MAX_PATH)`
  tells Windows the buffer holds 520 characters when it holds 260.
- A dropped path longer than 259 characters (possible with long-path support enabled)
  overflows the stack buffer. Shorter long paths are cut off silently.
- **Fix:** query the length first (`DragQueryFileW(drop, i, nullptr, 0)`) and use a
  `std::wstring` of that size, as `windows/runner/clipboard_reader.cpp:48-52` already
  does.

#### 11. [Low-Medium · Bug · Confirmed] Any error other than `FormatDamage` from one damaged section aborts the whole notebook
`packages/aantekening_interchange/lib/src/onenote/notebook_reader.dart:190-194, 241-243`
- Only `FormatDamage` and `FileSystemException` are turned into an `OneUnreadableSection`.
  Several other errors are reachable from file bytes and escape instead:
  - `RangeError` in `file_nodes.dart:160`: `_embedsPackage` with a negative `at`
    (u64 offset ≥ 2^63).
  - `RangeError` in `file_nodes.dart:177/187`: a transaction fragment with
    `chunk.length < 12` gives a negative `position`, and ByteData throws.
  - The same in `file_nodes.dart:230/238`: a list fragment with `length < 20`.
  - `FormatException` from `Guid.parse` in `revision_store.dart:450` on a bad `<ifndf>`
    reference.
  - Null-check `TypeError` from `reference.chunk!` and `node.chunk!`
    (`revision_store.dart:188, 413, 425, 479`) when a node of the wrong base type carries
    a matching id.
- Each of these fails the entire import with a raw error message. The optional `.onetoc2`
  file (`_tableOfContents`) has the same problem.
- **Fix:** make the readers throw only `FormatDamage`: validate `length >= 12/20`,
  `offset >= 0` and `chunk != null`, and use `tryParse`. Also catch `Object` (except
  `OutOfMemoryError`) per section.

#### 12. [Low-Medium · Robustness · Confirmed] The LZX window size from the file header is never validated in release builds
`packages/aantekening_interchange/lib/src/cabinet/lzx.dart:21-23` with `cabinet.dart:453`
- `windowBits = (compression >> 8) & 0x1F`, so 0 to 31. The only check is an `assert`,
  which release builds remove.
- A header value of 31 allocates a 2 GiB `Uint8List`. Values from 22 to 30 allocate
  4 MiB to 1 GiB.
- **Fix:** `if (windowBits < 15 || windowBits > 21) throw FormatDamage(...)`.

#### 13. [Low · Bug · Confirmed] Cyclic `parentId` in an archive overflows the stack
`packages/aantekening_interchange/lib/src/aantekening/archive_import.dart:112-135, 177-186`
- A section or page whose `parentId` is its own id, or an A→B→A loop, makes
  `sectionDraft`, `pagesIn` and `_page` recurse without end.
- The isolate catches the `StackOverflowError`, so the result is "The import failed" with
  no explanation.
- **Fix:** keep a visited set while building the tree. Treat a node already seen as having
  no parent.

#### 14. [Low · Bug · Confirmed] Cabinet extraction: duplicate or empty names, and a 1 MiB directory limit
`packages/aantekening_interchange/lib/src/cabinet/cabinet.dart:318-320, 356-359, 422-427`
- Two entries that normalise to the same name: the first is closed in `onFile`, but
  `putIfAbsent` hands the closed handle back for the second. `writeFromSync` then throws
  `FileSystemException` and the whole import fails.
- A name made only of `..` or `/` normalises to `''`, so the code opens the extraction
  directory itself as a file.
- The file directory is read only up to `min(len - filesOffset, 1 << 20)` bytes. A valid
  cabinet with many long names (more than about 10k files) fails with "Needed 4 bytes".
- There is no `p.isWithin(directory, path)` check after joining. On Windows, components
  such as `.. ` or `...` are normalised by Win32 (Plausible).
- **Fix:** track names already written and give duplicates a suffix or skip them. Skip
  empty names. Check that each resolved path is within the target directory. Read the
  directory until `fileCount` entries are parsed, not up to a fixed size.

#### 15. [Low · Bug (leak) · Confirmed] desktop_drop on Linux leaks two `FlValue`s per drop, and a string at start-up
`third_party/desktop_drop/linux/desktop_drop_plugin.cc:51-53, 96`
- `fl_value_append` takes a new reference to its child, but here the child was just
  created with a +1 reference. The fresh string and float list are therefore never freed.
  Use `fl_value_append_take`, as `linux/runner/clipboard_reader.cc` does.
- The result of `g_ascii_strdown` is never freed.
- `on_drag_motion` (line 58) is connected to `drag-motion`, a signal that returns
  `gboolean`, but the handler returns `void`. This is undefined behaviour. It is harmless
  only because `GTK_DEST_DEFAULT_ALL` makes GTK ignore the return value.

#### 16. [Low · Bug · Confirmed; upstream code] desktop_drop on Windows never sets `*pdwEffect` and logs every path
`third_party/desktop_drop/windows/desktop_drop_plugin.cpp:179-201, 228`
- `DragEnter`, `DragOver` and `Drop` return `S_OK` without setting `*pdwEffect`. The
  effect therefore stays whatever the source allowed (for example MOVE when dragging
  within one drive in Explorer), so the cursor shows "Move", and the effect reported back
  to the source is undefined.
- `std::cout << "done: " << path` prints every dropped file path in release builds, and
  `<iostream>` is not included explicitly.
- **Fix:** set `*pdwEffect = DROPEFFECT_COPY` and remove the logging.

---

### Performance

#### 17. [Medium · Performance · Confirmed] Each external file reference lists the whole notebook folder again
`packages/aantekening_interchange/lib/src/onenote/notebook_reader.dart:199-207`
- `_externalFile` calls `notebook.listSync(recursive: true)` for every `<file>` reference
  (OneNote keeps large attachments and printouts in `onefiles/`). The cost is
  O(references × files on disk), with a disk walk each time.
- Matching by basename anywhere in the folder can also pick the wrong file when two share
  a name.
- **Fix:** build a `Map<basename, path>` once per notebook folder, preferably limited to
  the `onefiles`-style folder next to the section.

#### 18. [Medium · Performance · Confirmed] `ImportWork.keep` calls fsync on every temporary asset
`packages/aantekening_interchange/lib/src/importer.dart:69`
- `writeAsBytesSync(bytes, flush: true)` forces an fsync for every picture and attachment
  written to a temp folder that is deleted after the import. On Windows and HDDs that is
  several milliseconds or more per file, so a notebook with thousands of pictures spends
  tens of seconds just syncing.
- **Fix:** drop `flush: true`. The store makes the asset durable when it copies it in.

#### 19. [Medium · Performance/Design · Confirmed] A whole OneNote notebook is kept in memory before conversion starts
`notebook_reader.dart:140-180`, `onenote_import.dart:48-56`, `bytes.dart:79-84`
- `readNotebookFolder` parses every section (`readAsBytesSync`) into `OneEntry` models
  before `convertOneNote` writes a single asset.
- Picture and attachment bytes are `sublistView`s (`ByteReader.take`), so every
  section's entire `.one` buffer, together with its revision and object maps, stays
  reachable until the end.
- Peak memory is roughly the size of the uncompressed notebook plus its models, which
  for a multi-GB notebook means running out of memory in the import isolate.
- **Fix:** convert one section at a time, writing assets and dropping the
  `RevisionStore` before reading the next. Alternatively, copy only the bytes that are
  kept.

#### 20. [Low-Medium · Performance · Confirmed] Archive import rebuilds the tree in quadratic time
`packages/aantekening_interchange/lib/src/aantekening/archive_import.dart:112-135, 150-156`
- `pagesIn` scans every page file for each page, and `sectionDraft` scans every section
  for each section: O(P² + S²). With 20k pages that is 4×10^8 comparisons.
- **Fix:** group once into `Map<(sectionId, parentId), List<PageFile>>` and
  `Map<parentId, List<Section>>`.

#### 21. [Low · Performance · Confirmed] Revision store copies the id table for every revision, and merges objects repeatedly
`packages/aantekening_interchange/lib/src/onestore/revision_store.dart:302, 277-280`
- `revision.ids = {...?parent?.ids}` copies the parent's whole global id table for every
  revision, which is O(revisions × ids) in both memory and time.
- `objects.addAll` runs once per revision in the chain.
- `Guid.hashCode` is `Object.hashAll(_bytes)`, recomputed on every map lookup
  (`bytes.dart:149`), and `ExGuid`s are the keys of every object map.
- **Fix:** resolve ids through a parent-chained lookup instead of copying. Cache the hash
  in `Guid`, for example by computing it once in the constructor.

#### 22. [Low · Performance · Confirmed] Allocations and regex compilation inside hot loops
- `xournal_import.dart:320-332`: two `RegExp(r'\s+')` compiled per stroke; `:512` one per
  image. Documents hold 10^4 to 10^5 strokes. Hoist them to `static final`.
- `lzx.dart:313`: a `ByteData.sublistView` allocated for every 0xE8 byte (common in
  binary data). Create one `ByteData` per frame instead.
- `section_reader.dart:250`: `ByteData.sublistView(indicesBytes)` created per element
  inside the list comprehension.
- `latex_text.dart:344`: two `substring`s and a new RegExp at every newline. The
  `contains('\n\n')` test is also redundant, because the regex covers it.
- `cabinet.dart:376-378`: `files.where(folder == index)` per folder, which is
  O(folders × files). Group once.

---

### Design

#### 23. [Medium · Design · Confirmed] Interchange depends on the whole store (and SQLite FFI) for one file codec
`packages/aantekening_interchange/pubspec.yaml:12`, `lib/src/aantekening/archive_import.dart:7`
- The only things used from `aantekening_store` are `EntityFile` (with `NotebookFile`,
  `SectionFile`, `PageFile`) and `ArchiveExport.manifestName`.
- `store/lib/src/files/entity_files.dart` imports only `dart:*` and `aantekening_core`.
- Even so, the "pure Dart" importer package, and every import isolate, link `sqlite3`'s
  FFI bindings and the whole store. The export format is also split: the writer lives in
  store, the reader in interchange.
- **Fix:** move `EntityFile` and its codec, plus the manifest name and format constant,
  into `aantekening_core`, which already owns the page format. Then remove `_store` from
  interchange's dependencies and from the architecture diagram.

#### 24. [Low · Design · Confirmed] `FileNode.fields` is a shared, mutable read cursor
`packages/aantekening_interchange/lib/src/onestore/file_nodes.dart:36-37`; used at
`revision_store.dart:156-158, 247-251, 288-296, 322-326`
- Each consumer advances `node.fields.position`, so reading a node twice, or in a
  different order, silently returns the wrong values.
- This is why node lists cannot simply be cached (which finding 3 needs).
- **Fix:** store the body as a `Uint8List` and hand out a fresh `ByteReader` on each
  access (`ByteReader get fields => ByteReader(_body)`).

---

### Redundancy / code size

#### 25. [Low · Redundancy · Confirmed] Two separate MIME-type tables
- `interchange/lib/src/importer.dart:83-115` (`mimeTypeOf`: sniffing plus an extension
  fallback that knows `.txt` but not `.gif`, `.webp` or `.bmp`) and
  `store/lib/src/asset_store.dart:251-262` (`mimeTypeForPath`: knows `.bmp`, `.gif` and
  `.webp` but not `.txt`).
- The app uses both (`media_import.dart:77` and `:96`; `drop_import.dart:146` and `:186`),
  so the same file can get different types depending on the path it came in by.
- **Fix:** keep one function in `_core`: sniff first, then a single extension table.
- The gzip-magic check is also duplicated (`xournal_import.dart:128`,
  `entity_files.dart:65`).

#### 26. [Low · Redundancy · Confirmed] Vendored desktop_drop carries platforms the app does not build
`third_party/desktop_drop/macos/**`, `lib/desktop_drop_web.dart`, `lib/src/web_drop_item.dart`,
and pubspec `web` and `flutter_web_plugins`.
- `app/aantekening` has only `android`, `linux` and `windows` folders, so the macOS and
  web code is dead weight in the fork that has to be maintained.
- **Fix:** remove it (and its pubspec `platforms:` entries), and note the removal in the
  README's list of changes.

#### 27. [Low · Redundancy · Confirmed] The `lints` dev-dependency is never used; root `test` is unused
- `pubspec.yaml:28-29` and `packages/{ai,core,interchange,spell,store}/pubspec.yaml`
  declare `lints: ^6.0.0`. No file references `package:lints`: every
  `analysis_options.yaml` includes the root one, which uses `package:flutter_lints`.
- As a result the pure-Dart packages are analysed with the Flutter lint set, and only
  resolve it through the workspace.
- The root has no tests, so `test` there is unused.
- **Fix:** remove them, or have the pure-Dart packages include `package:lints/recommended.yaml`.
- Checked and *not* an issue: `flutter_math_fork` under the app's `dev_dependencies` is
  correct. Only `app/aantekening/test/*` import it; `lib/` reaches it through
  `aantekening_math`.

---

### Build & CI

#### 28. [Medium · Build · Confirmed] Release workflow: write token for every job, no tests, unpinned third-party action
`.github/workflows/release.yml:10-11, 29-41, 58-73, 34/63`
- `permissions: contents: write` is set at the top level, so the Windows, Linux and Arch
  build jobs all get a write token. Those jobs run `flutter pub get`, third-party build
  scripts, and `subosito/flutter-action@v2`, which is pinned only to a movable tag.
- A tag pushed on a commit that failed CI is still released: neither `tool/check.dart`
  nor `flutter test` runs in this workflow.
- `container: archlinux:base-devel` is a rolling image that is not pinned.
- **Fix:**
  - Set `permissions: contents: read` at the top, and grant `contents: write` only on the
    `release` job.
  - Pin actions to a commit SHA.
  - Add `needs: check`, either a job running `dart tool/check.dart` or a reusable CI
    workflow.

#### 29. [Low-Medium · Build · Confirmed] `--coverage` silently reports nothing for the pure-Dart packages
`tool/check.dart:184-199` with `.github/workflows/deep.yml:87`
- `dart run coverage:format_coverage` needs `coverage` as a direct (dev) dependency.
  `pubspec.lock:156-157` shows it is only `transitive`.
- So the command fails, `_coverageOf` returns `null` without a word, and the nightly
  report leaves out core, store, interchange, ai and spell.
- **Fix:** add `coverage` to the dev-dependencies of the pure-Dart packages (or the root),
  and print a failure when `made.exitCode != 0` instead of returning `null`.

#### 30. [Low · Build · Confirmed] CI hygiene
`.github/workflows/ci.yml`
- There is no `permissions:` block, so the token gets the repository's default
  permissions.
- There is no `concurrency:` group, so superseded PR runs are not cancelled.
- There is no `timeout-minutes`, so the default of 6 h applies; a hang in the fuzz tests
  would burn the whole of it.
- Android is never built, although the app ships an `android/` target and the vendored
  desktop_drop has Android code.
- The apt package list is copied three times (`ci.yml:30`, `deep.yml:82`,
  `release.yml:70`). A composite action, or one script, would remove the drift risk.

#### 31. [Low · Build · Confirmed] SDK constraints do not agree
- `app/aantekening/pubspec.yaml:9` requires `sdk: ^3.13.3`, while the root and every
  package declare `^3.9.0`.
- In a pub workspace the solve uses their intersection, so the `^3.9.0` lower bounds are
  never tested and are likely wrong. CI pins Flutter 3.47.4.
- **Fix:** raise all of them to the same floor.

#### 32. [Low · Packaging · Confirmed] PKGBUILD metadata
`packaging/arch/PKGBUILD`
- `license=('unknown')`, while the repository's own licence and the bundled OFL fonts and
  Apache-2.0 code should be declared.
- `depends` leaves out `wayland`, which the runner links directly (`linux/runner/CMakeLists.txt:31-32`).
  Today `gtk3` pulls it in transitively.

---

#### Reviewed, nothing substantive found
- `app/aantekening/linux/runner/clipboard_reader.cc`: ownership is right
  (`g_autofree`/`g_autoptr`, `*_take`, the call is ref'd and unref'd once on every path).
- `touchpad_hold.cc`: the private queue is moved back to the default queue and then
  destroyed, correctly.
- `opaque_underlay.cc`.
- `windows/runner/clipboard_reader.cpp`: bounds of the DIB header and masks are checked;
  the lock and unlock are paired.
- `pdf_writer.dart`: xref offsets, Paeth filter and outline counts are all correct.
- `MainActivity.kt` is the default template.

---

## Part 6: `app/aantekening/lib/src/editor/`

Scope: the page editor (`page_editor*.dart` parts), the text box editor (`text/`), media views, PDF text, clipboard, and drop/import. I reviewed by reading the code only; no toolchain was run. All paths below are relative to the repo root. The editor prefix is `app/aantekening/lib/src/editor/` (written `editor/` below).

---

### Bugs

#### B1. High · Bug · Confirmed trace (race depends on timing): reopening a page while its save is still running shows the old version, and the next edit writes over the newer one
- **Where:**
  - `editor/page_editor.dart:492-498`: leaving a page fires `unawaited(_persist(leaving, …))`.
  - `editor/page_editor_storage.dart:22`: `_load` calls `store.pages.loadDocument(pageId)`.
  - `packages/aantekening_store/lib/src/page_repository.dart:120-123`: `loadDocument` reads the body immediately and does not wait for `_saving`.
  - `page_repository.dart:150-170`: `saveDocument` compresses a page of 128 KiB or more on an isolate before it writes.
- **What goes wrong:** A large page A is edited, then the user goes A → B → A quickly (back/forward with `H`/`L`, `Ctrl+Tab` twice, or a picker preview). A's save is still being compressed on the isolate, or is queued behind another save. `_load` reads the body that is still on disk, which lacks the last edits. The controller then shows that stale document with a clean undo stack. The save lands afterwards, but `markSaved` only works on the identical document, so nothing on screen corrects. The user's last words have vanished from view. If they type anything, autosave writes stale content plus the new edit over the newer save, and the lost edits are gone for good.
- **Tests:** No test covers this (`test/saving_test.dart` tests only "another page opens at once").
- **Fix:** Keep the in-flight save future for each page id in the editor and await it at the start of `_load`. The alternative is to make `PageRepository.loadDocument` await `_saving`, which is the stronger fix because it also covers the twin pane and other readers.

#### B2. Medium · Bug · Confirmed trace: quitting or backing up does not wait for saves already under way
- **Where:**
  - `editor/page_editor_storage.dart:184-191`: `_saveOpenPage` returns at once when the current page is clean or not ready.
  - `editor/page_editor.dart:497`: the page-switch save is fire-and-forget.
  - `editor/page_editor.dart:537-538`: the save in `dispose` is fire-and-forget, and `dispose` also unregisters from `openSaves` at line 529.
- **What goes wrong:** Edit a large page, switch to another page (or close the tab with `Ctrl+W`), then quit at once. `OpenSaves.saveAll()` (`files/notes_keeper.dart:32`) only calls `_saveOpenPage`. The new page is clean, so it returns immediately. `_beforeExit` then flushes the mirror and exits while the previous page's compress is still on its isolate. Those edits were never written and never rescued.
- **Fix:** Track in-flight `_persist` futures in a set. Have `_saveOpenPage` await them, and keep the disposed editor's last save registered with `OpenSaves` until it completes. A store-level "await pending saves" would also work.

#### B3. Medium · Bug · Plausible (the double send is confirmed; how much it breaks depends on the platform's input method): mid-batch `setEditingState` with a stale composing range
- **Where:**
  - `editor/text/text_box_input.dart:118-139`.
  - `editor/text/text_box_typing.dart:57-61`: `_afterChange` calls `_input.sync()`.
- **What goes wrong:**
  - For each delta, `onReplace` leads to `_insertText`/`_commit`, then `_afterChange`, then `sync()`. That sync calls `valueOf(_composing)` while `_composing` still holds the previous delta's range, because line 135 updates it only after `onReplace`.
  - `_value` already carries the new composing range (`delta.apply`), so the two values differ. The engine is sent `setEditingState` with the old composing range, which is usually empty.
  - The final `sync()` at line 138 then sends a second state with the correct range.
  - So every keystroke of a CJK, dead-key or compose sequence sends two states back to the engine, and the first one clears the composing region. Flutter's own `EditableText` deliberately avoids echoing engine-originated state.
  - On GTK and Android this can end or restart the preedit, which shows up as duplicated or committed-too-early characters.
- **Tests:** The harness only ever sends `composingBase: -1` (`test/editor_harness.dart:248,276,300`), so composition is untested.
- **Fix:** Set `_composing = delta.composing` before calling `onReplace`. Suppress `sync()` while a delta batch is being applied (keep a `_applyingDeltas` flag) and sync once at the end.

#### B4. Medium · Bug · Confirmed trace: async bring-in, paste and insert continue on whatever page is open when they finish
- **Where:**
  - `editor/page_editor_drop.dart:346-423` (`_bringIn`): it awaits `readDropped`, which includes an HTTP download with a 30 s timeout, an asset import, and PDF opening plus text extraction. It also awaits `endOfFrame` once per item. It only re-checks `mounted`.
  - `editor/page_editor_clipboard.dart:26-31` (`_paste`): it checks `_ready` before two clipboard round-trips and not after.
  - `editor/page_editor_media.dart:10-22` and `:193-205`: `_printAsNewPage` uses `ref.read` after `await store.assets.find` with no `mounted` check, and `ref` throws once the widget is disposed.
- **What goes wrong:** A user drops a URL or a large PDF, then switches page while it downloads or imports. The media is placed on the newly opened page. If that page is still loading (`_ready == false`), it is added to the old document and then wiped by `loadDocument`, so it is silently lost.
- **Fix:** Capture `widget.pageId` before the first await. After every await, bail out (or tell the user) unless `mounted && _ready && widget.pageId == captured`.

#### B5. Medium · Bug · Confirmed trace: "Undo" on the deleted-sheet message undoes whatever happened last
- **Where:** `editor/page_editor_commands.dart:58-64`. The callback is `showUndoable('Sheet … is deleted.', _controller.undo)`.
- **What goes wrong:**
  - If the user draws a stroke and then presses Undo in the message, the stroke is undone, not the sheet deletion.
  - After a page switch, it undoes an edit on the other page.
  - If the tab was closed while the message was still visible, it calls `undo` on a disposed `CanvasController`.
- **Fix:** Undo only if the top of the undo stack is still this deletion (compare the document or revision recorded at deletion time) and `!_disposed && widget.pageId == deletedOn`. Alternatively, re-insert the removed sheet explicitly.

#### B6. Low/Medium · Bug · Plausible (confirmed by absence): the caret is never kept in view
- **Where:** `editor/text/text_box_typing.dart:7-21`, `editor/text/text_box_movement.dart:83-90`, `editor/page_editor_text.dart:302-330`.
- **What goes wrong:** Nothing in `editor/` or the canvas reveals the caret rect after a commit or caret move. The canvas is not a `Scrollable`, so `showOnScreen` does nothing. Typing past the bottom of the view, pressing Enter repeatedly, or arrowing down or up moves the caret off-screen, and the page does not follow.
- **Fix:** After `_afterChange`, report the caret rect in page units to the host (for example an `onCaretMoved` callback) and call `_controller.reveal(...)` with a margin when it is outside `_inView`.

#### B7. Low · Bug · Confirmed trace: Cut deletes the selection as it is after the clipboard await, not what was copied
- **Where:**
  - `editor/page_editor_clipboard.dart:15-18`: `deleteSelection()` runs after `await NoteClipboard.copy`.
  - `editor/text/text_box_clipboard.dart:15-33`: `_deleteSelection()` and `_replaceInFormula('')` run after the await.
- **What goes wrong:** A selection change that lands in the gap is cut without having been copied. The gap is a platform-channel round-trip; key repeat or an input method can land in it.
- **Fix:** Delete the ids or range captured before the await, or delete synchronously and then write the clipboard.

#### B8. Low · Bug · Confirmed trace: the text box's paste does not re-check that it is still being edited
- **Where:** `editor/text/text_box_clipboard.dart:41-45`. Only `mounted` is checked after `NoteClipboard.read()`, which makes two platform calls.
- **What goes wrong:** If the user clicks elsewhere in the meantime, `_commit` writes into a box that is no longer being edited. It emits `onChanged` with an undo step, and the selection and state of that box no longer match the page's.
- **Fix:** Use `if (!mounted || !widget.isEditing) return;`.

#### B9. Low · Bug · Confirmed trace: `ref` is used before the `mounted` check in a post-frame callback
- **Where:** `editor/page_editor_storage.dart:58-60`. `_meetRevealRequest` runs `ref.read(revealRequestProvider)` before `!mounted`. It is scheduled from `_load` (line 46).
- **What goes wrong:** If the editor is disposed before that frame ends, Riverpod throws "ref used after dispose".
- **Fix:** Check `mounted` first.

#### B10. Low · Bug · Confirmed trace: PDF failures are cached for the rest of the session
- **Where:**
  - `editor/pdf_text.dart:537-546`: `_read[key] = words` also stores `null` from a failed read, and `containsKey` then never retries.
  - `editor/media_views.dart:647-649`: `picture.failed = true` means "not tried again".
- **What goes wrong:** A transient failure makes a page's text unselectable, or a raster never drawn, until restart. Examples are the document provider still opening, the asset not yet mirrored, or a render racing the document's `keepAWhile` disposal.
- **Fix:** Do not cache `null` from exceptions, or retry after a delay. Clear `failed` when the document instance changes.

#### B11. Low · Bug (resource) · Confirmed trace: `ValueNotifier`s created per formula window are never disposed
- **Where:** `editor/text/text_box_formulas.dart:300` (`opened`, which `_handBack` and `dispose` only set to null), `editor/text/formula_window.dart:165` (`window` in `editTikzSource`).
- **What goes wrong:** Leak-tracker noise and small leaks.
- **Fix:** Dispose after `showFormulaWindow` completes, deferred past the frame in which `value = null` is set.

---

### Performance

#### P1. Medium · Performance · Confirmed trace: each keystroke rebuilds every block of the text box, twice, and twice more with the minimap on
- **Where:**
  - `editor/text/text_box_editor.dart:780-830`: `build` loops over all blocks.
  - `editor/text/text_box_view.dart:263-382`: `_buildBlock` has no memoisation.
  - `editor/text/text_box_editor.dart:941-955`: `_reportSize` runs post-frame.
  - `editor/page_editor_text.dart:332-352`: `_onTextSizeChanged` calls `replaceElement`.
  - `editor/page_minimap.dart:87-95`.
- **Cost per keystroke**, every block of the box:
  - a new `BlockView`, which rebuilds the block's string;
  - `_matchesIn`, which runs the search over the block's text;
  - `_misspellingsIn`, through `TextBoxEditor.textOf`;
  - a new `TextSpan` tree, which `RenderParagraph` must deep-compare;
  - `ListNumbering.ordinals`.

  An auto-width box changes width on almost every character. `_reportSize` then calls `onSizeChanged`, which makes a new element, misses the cache in `_buildElement`, and rebuilds the whole box a second time a frame later. The minimap draws its own full `TextBoxEditor` per box, which doubles this again.

  Old OneNote pages read as one large text box (ADR 35), so this cost grows linearly with page length. Rows are keyed by index (`_rowKeys`), so Enter near the top re-lays-out every paragraph below.
- **Fix:**
  - Cache each block's row widget keyed by `(block identity, decoration, focused, ordinal, open formula)`, the same pattern as `_elementWidgets` and `TypesetFormulas`.
  - Fold the size into the same `replaceElement` as the text where it is known, or make the size report not rebuild the box (pass the frame separately from `element`).

#### P2. Medium · Performance · Confirmed trace: hit-testing a text box on every mouse move measures all of its text
- **Where:** `editor/text/text_box_layout.dart:82-127` (`_showsAt`). It is called from `CanvasController.hitTest`, which `infinite_canvas_hover.dart:57` calls once per hover event, and `page_space.dart:392` also scans linearly.
- **Cost:** For every paragraph it runs `text.text.toPlainText()` (an allocation) and `getBoxesForSelection(0..length)` over the whole paragraph, with no bounds pre-check. Moving the mouse over a long box costs time proportional to all of its glyphs on every event.
- **Fix:** Check `(Offset.zero & paragraph.size).inflate(_reach).contains(at)` before asking for boxes, use `paragraph.text` length via the cached view text, and stop once rows pass the point's y.

#### P3. Medium · Performance (memory) · Confirmed trace: the PDF text cache is unbounded, and per-page raster holders are never pruned
- **Where:**
  - `editor/pdf_text.dart:514-547`: `PdfWordsCache.shared._read` is a process-wide map with no eviction. Each page holds a `Rect` per character twice (`boxes`, `_across`) plus lines.
  - `editor/media_views.dart:534,545`: `PdfRasters._pages` keeps a `PageRasters` for every page ever shown.
- **Cost:** Scrolling through a 500-page PDF keeps every page's character geometry in memory for the session (on the order of 100 MB). `_PdfPageView` also reads words in `_elementWidget` (`editor/page_editor_elements.dart:132`) for every PDF page that is merely built. The raster cache, by contrast, is carefully bounded by pixels.
- **Fix:** Use an LRU with a cap, or keep words alongside `PageRasters` and evict them together. Drop empty `PageRasters` when they have no pictures.

#### P4. Low/Medium · Performance · Confirmed trace: whole-box formatting is computed on every keystroke and thrown away
- **Where:** `editor/page_editor_text.dart:211-227` (`_syncBoxFormatting`, called from `_onCanvasChanged` on every document change) and `editor/text/box_formatting.dart:384-410`.
- **Cost:** While a box is being typed in, it is selected, so `hasBoxes` is true. `_boxFormatting.state` runs `everyMark` over the whole box for each of the 6 marks. `setFallback` then ignores the result because `_editor != null`. This happens twice per keystroke, once for the text and once for the size report.
- **Fix:** Skip it while `_editingId != null`, or compute the fallback state lazily in `TextBoxEditorController.state`.

#### P5. Low · Performance · Confirmed trace: the minimap renders a full interactive `TextBoxEditor` per box
- **Where:** `editor/page_minimap.dart:87-95`.
- **Cost:** Each thumbnail gets a `FocusNode`, a `CaretBlink`, GlobalKeys, `MouseRegion`/`Listener`/`Focus`, and a full build and layout. The whole minimap subtree also rebuilds on every `contents` change.
- **Fix:** Use a read-only paint path (a `RichText` per block, or the `ZoomSnapshot` picture) for the minimap.

#### P6. Low · Performance · Confirmed trace: search highlighting redoes page-wide work on every document change
- **Where:** `editor/page_editor_elements.dart:8-30`. Its cache is keyed by document identity, so it misses on every keystroke.
- **Cost:** `_firstMatchIn` sorts every text box and runs `matchesIn` over their blocks after each edit while a search is highlighted. Each box's build then runs `_matchesIn` per block again (P1).
- **Fix:** Re-run only when the terms change, or only for the element that changed.

#### P7. Low · Performance · Confirmed trace: a right-click reads the whole system clipboard just to enable "Paste"
- **Where:** `editor/text/text_box_menu.dart:59`. `NoteClipboard.read()` goes through `SystemClipboard.read()`, which brings picture bytes (for example a screenshot) across the method channel.
- **Cost:** Latency and memory on every context menu. The menu also waits for spelling suggestions first (line 58).
- **Fix:** Use a cheap `hasStrings` or "has files or picture" probe, or enable Paste unconditionally and handle "nothing to paste" when it runs.

#### P8. Low · Performance · Confirmed trace: regexes are built per call in hot paths
- **Where:**
  - `editor/pdf_text.dart:420-421`: `_inWord` builds a unicode `RegExp` for every character visited in `wordAt`.
  - The newline-collapsing regex is built per call in `text/text_box_typing.dart:90`, `text/text_box_input_method.dart:109` and `text/text_box_clipboard.dart:53`.
- **Fix:** Use `static final` regexes.

#### P9. Low · Performance · Confirmed trace: each mode keypress builds the whole key layer
- **Where:** `editor/page_editor_keys.dart:40` (`_modeKeys().actionFor`) and `:414-430` (`_drawKeys` calls `layers.draw()` twice).
- **Cost:** About 40 `KeyAction`s plus `PageLayers` lookups of the command registry on every key.
- **Fix:** Look the key up first and build only on a miss, or cache the layer per mode and invalidate it on tool or selection change.

---

### Design

#### D1. Medium · Design: ADR 34's parts are "a division of reading, not of access", and the page editor's core state machine is spread over all of them
- **Where:** `editor/page_editor.dart:126-405` has about 58 state fields.
  - `_editingId` is used in 11 of the 13 page-editor files, and `_stopEditing` is called from 10.
  - The caret-placeholder machine (`_placed`, `_caretBefore`, `_editingId`, `_formulaOpen`, `_editingStartsInFormula`) is mutated in `page_editor.dart`, `_storage`, `_text`, `_twin` and `_keys`.
  - Its hardest logic lives in the storage part's canvas listener (`editor/page_editor_storage.dart:92-140`: undo turns a box back into a caret, redo turns it back into a box, a drag ends typing). That file is nominally about loading and saving.
- **Why it matters:** The text box state (`text/text_box_editor.dart`, about 63 fields across 10 parts) shows the same pattern.
- **Suggestion:** Do what ADR 34 already did for `CaretBlink`, `UndoSteps` and `TextBoxInput`. Extract a plain `TypingSession` or `CaretPlacement` class that owns `_placed`, `_caretBefore` and `_editingId` and has `start`, `stop`, `onDocumentChanged` and `documentForSave`. It can then be unit-tested without widgets, and `_onCanvasChanged` shrinks back to saving.

#### D2. Medium · Design: the same state is kept in two or three places and synced by hand
- **Where:**
  - "Editing" exists as both `_editingId` and `_textController.isActive`. These knowingly diverge until a rebuild (comment at `editor/page_editor_media.dart:42-44`, and the same check again in `page_editor_drop.dart:368-372`).
  - `_formulaOpen` (`editor/page_editor_text.dart:358-369`) mirrors `formulaField.value != null`, delivered post-frame.
  - The box's `_blocks` against `widget.element.blocks` is reconciled by `_lastEmitted` identity (`editor/text/text_box_editor.dart:430-445`). The open formula also lives as Simple-syntax source in `_blocks` but as LaTeX in the page (`_stored`, `_showOpenFormulaAsSource`).
- **Why it matters:** Each pair is a source of the async-ordering bugs above and of the many "until it is built again" comments.
- **Suggestion:** Make one side authoritative, for example by deriving `_formulaOpen` and "editing" from the controller. Give the open formula's source a separate field instead of rewriting the run in `_blocks`.

#### D3. Medium · Design: twin panes reach into each other's private state through a global mutable set
- **Where:** `editor/page_editor_twin.dart:3-63`. `_pageEditorsProvider` is a `Provider<Set<_PageEditorState>>` that is mutated in `initState` and `dispose`. `_twin` reads another State's `_disposed`, `_ready`, `_controller` and `_placed`.
- **Why it matters:** Two widget states of one page are kept in sync by copying documents and undo stacks (`CanvasController.follow`). That is fragile, and it is the reason for `_following`, `_shared` and the `_twin?._controller.isDirty` special cases in `_onChangedElsewhere`.
- **Suggestion:** Use one page session per open page id, holding the document, undo history and dirty/save state, shared by both panes. Each pane then keeps only its own viewport and caret.

#### D4. Low · Design: process-wide singletons and app-level code live in the editor folder
- **Where:**
  - Singletons outside Riverpod: `PdfWordsCache.shared` (`editor/pdf_text.dart:518`), `PdfRasters.shared` (`editor/media_views.dart:530`), `TypesetFormulas._cache` (`editor/text/block_view.dart:270`), `NotePalette.recent` (`editor/palette.dart:45`), `touchpadFingers` (`editor/trackpad.dart:40`). They are hard to reset in tests (hence `@visibleForTesting keep`) and are never released.
  - `AantekeningBinding` and `TrackpadAim` are app-wide (the root binding) but live in `editor/trackpad.dart`.
- **Suggestion:** Move these into providers or `look/`/`shell/` as appropriate.

#### D5. Low · Design: build methods have side effects
- **Where:**
  - `_PdfPageState.build` starts and cancels renders (`editor/media_views.dart:349-357` calls `_ask`).
  - `_elementWidget` triggers PDF text extraction (`editor/page_editor_elements.dart:132`).
  - `_canvas()` mutates `_controller.inkSmoothing` (`editor/page_editor.dart:715`).
- **Why it matters:** These work today but make build order matter.
- **Suggestion:** Move them to `didChangeDependencies`, `didUpdateWidget` or listeners.

---

### Redundancy / code size

#### R1. Medium (code size) · Redundancy · Confirmed: dead widgets
- **Where:**
  - `ColorSwatchPanel` (`editor/palette.dart:101-212`) and `NoteSwatch` (`:72-99`, used only by `ColorSwatchPanel`) are referenced nowhere in `app/` or `packages/`, tests included. Removing them is about 140 lines, plus the `colour_picker.dart`/`controls.dart` imports.
  - `MarkKinds.of` (`editor/text/text_box_controller.dart:19-22`) is unused.

#### R2. Low · Redundancy (and an inconsistency) · Confirmed: edit-key actions are duplicated across four key layers
- **Where:** Undo, Redo, Copy, Cut and Paste are written out separately in `_menu` (`editor/page_editor_keys.dart:188-212`), `_normalKeys` (`:332-366`), `_drawKeys` (`:436-448`) and `_selectKeys` (`:478-496`), with different keys in each.
- **Inconsistency:** Select mode has `u` Undo but no Redo.
- **Fix:** Add one helper, `_editActions({copyKey, …})`.

#### R3. Low · Redundancy · Confirmed: the "box being edited, and is it a bare caret?" lookup is open-coded five times
- **Where:** `editor/page_editor_media.dart:36-41`, `page_editor_drop.dart:304-314` and `:364-372`, `page_editor_clipboard.dart:76-78` and `:93-99`, while `_holdsNothing` (`page_editor_text.dart:231-234`) already exists.
- **Fix:** Add a single `TextElement? get _editingBox` and reuse `_holdsNothing`.

#### R4. Low · Redundancy and inconsistency · Confirmed: "what is a picture" is defined three times with different rules
- **Where:** `editor/media_import.dart:230-241` (`_images`), `:315-321` (`isPicture`), `:279` (`importFile`: any `image/*` except SVG), and `editor/system_clipboard.dart:236-242`.
- **Inconsistency:** A dropped `.tiff` or `.heic` is attached as a file (`drop_import.dart:147` uses `isPicture`), while `importFile` would accept it as a picture.
- **Fix:** Use one table of MIME type to extension.

#### R5. Low · Redundancy · Confirmed: small duplicated helpers
- Plain text to `TextBlock.plain` lines appears twice: `editor/drop_import.dart:197-200` and `editor/page_editor_clipboard.dart:42-46`.
- The blank-template and orientation lists for printouts are built twice: `editor/page_editor_media.dart:128-133` and `:198-203`.
- The "new box centred in view" offset is computed three times: `editor/page_editor_text.dart:390`, `:404` and `:424`.
- The newline-collapse regex appears three times (P8).

#### R6. Low · Redundancy · Confirmed: test-only API in production classes
- **Where:**
  - `PdfPageWords.lines` and `isEmpty` (`editor/pdf_text.dart:289-294`) are used only by `test/pdf_text_test.dart`. `lines` allocates a second turned list of all lines.
  - `PdfRasters.pixels` (`editor/media_views.dart:541`) is used only by `test/media_test.dart`.
- **Fix:** Mark them `@visibleForTesting`, or move the logic to test helpers.

---

## Part 7: `app/aantekening/lib/src/ai/` and `app/aantekening/lib/src/settings/` (AI and podcast settings)

Scope: the AI session, AI views (answers, flashcards, quiz, glossary, summary, podcasts, study pages), `ai_state.dart`, `money.dart`, and `settings/ai_settings.dart` and `settings/podcast_settings.dart`. I reviewed by reading the code only, because no toolchain is installed. `app/aantekening/test/ai_test.dart` has no test for any of the races below.

What works well: API keys are kept only in `flutter_secure_storage` (`KeychainSecrets`). They are never written to prefs, logged, or put into URLs. The session keeps generating while other tabs show, as the design intends. Disposal is mostly correct: `AudioPlayer`, its subscriptions, the timers and the controllers are released.

---

### Bugs

**B1. High · Bug · Confirmed: an answer is saved into whichever conversation is showing when it finishes, not the one it was asked in.**
- Where: `app/aantekening/lib/src/ai/ai_session.dart:858-860`, together with `openThread` at 373, `newThread` at 386, `openProfile` at 410-415, `make` at 632-638 and `showPodcast` at 932.
- What is wrong: `_keepTurn` uses `state.threadId ?? createThread(...)` at completion time. Several actions change `threadId` while `pending` is still set, and none of them checks `pending`:
  - the "Overview" pill (`ai_view.dart:467-478`)
  - the `o`, `n` and digit keys (`ai_view.dart:244,255,277`)
  - the `c` chooser (`ai_view.dart:326`)
  - starting a study set or a podcast
- Failure: you ask a follow-up in thread A, then press `1` to look at flashcards while it streams. `openProfile` sets `threadId = null`, so the answer is saved into a brand-new thread. Its follow-ups then lose A's context, even though the answer was generated from A's history. If you open thread B with `c`, the answer is appended to B, with A's history baked into its messages.
- Fix: capture the thread id in `ask()` and keep it in `PendingTurn`, then have `_keepTurn` use that id. Create the thread up front if there is none.

**B2. High · Bug · Confirmed: double-clicks start duplicate, paid generations that cannot all be stopped.**
- Where: `ai_session.dart:439` (`ask`), `491` (`rewrite`), `612` (`make`), `1017` (`makePodcast`), `1192` (`speakPodcast`).
- What is wrong: each method checks `state.pending`, `state.making[id]` or `state.podcasts[id]` and then awaits before it marks itself as running. `ask` awaits `aiModelProvider.future`, `reader.scope` (database) and `webSearchProvider`. `makePodcast` awaits two keychain reads in `_writerOf`. A second click inside that window passes the guard.
- Failure:
  - Two LLM streams, or for podcasts two LLM plus text-to-speech pipelines, run and are billed twice.
  - `_answering`, `_makers[id]` and `_podcasters[id]` are overwritten, so Stop cancels only the second stream. The first keeps running and still saves.
  - For `ask`, both streams write their progress into the same `state.pending`, so the shown answer interleaves two answers.
- Fix: set a synchronous "starting" marker before the first `await` (a placeholder `PendingTurn` or podcast progress), or keep an in-flight `Set<String>`.

**B3. High · Bug · Confirmed: a podcast still being spoken shows on its own page as "not spoken yet", and "Speak it" starts a second run.**
- Where: `ai_session.dart:1101-1124` together with `podcast_view.dart:191,274-293` and `ai_session.dart:1192`.
- What is wrong: `makePodcast` keeps the transcript item and calls `_load()` before speaking. That item appears in the overview and can be opened. Its progress, however, is tracked under the episode *profile* id (`_followPodcast(id, …)`), not the item id. `PodcastPage` looks up `s.podcasts[item.id]`, finds nothing, and shows the "Speak it" button. `speakPodcast(itemId)` then passes its `containsKey(itemId)` guard.
- Failure: the episode is spoken twice in parallel, so text-to-speech is paid twice. Two WAV files are written, the last `updateItem` wins, and the other WAV (tens of MB) is orphaned in the podcast folder. In the same state, `deleteItem` (`ai_session.dart:1244-1250`) skips `stopPodcast` and the audio cleanup because `episode.spoken` is false and the key does not match. The run keeps going, writes a WAV for a deleted item and calls `updateItem` on a missing row.
- Fix: once the item exists, track speaking under the item id: move the `_podcasters` and `podcasts` entry from the profile id to `item.id`. Alternatively, keep a `profileId → itemId` map and consult it in `PodcastPage`, `speakPodcast` and `deleteItem`.

**B4. Medium · Bug · Confirmed (Dart semantics): `state.copyWith(..., x: await ...)` overwrites updates that land during the await.**
- Where: `ai_session.dart:363-369` (`_load`) and `375-382` (`openThread`).
- What is wrong: in `state = state.copyWith(turns: await store.ai.turnsOf(open), …)`, Dart evaluates the receiver `state` *before* the awaited argument. Anything that changes state during `turnsOf` is overwritten by the stale snapshot. That includes stream progress and, worse, terminal clears: `_setMaking(id, null)`, `_setPodcast(key, null)` and `pending: () => null`.
- Failure: a thread is open and a set is being made alongside (the design explicitly supports this). If the set's completion lands during another `_load` (for example the one in `_shown` or `_spoken`), the `making[id]` entry comes back to life. The overview then shows "Being made…" until you press Stop, and `make()` refuses to start again: `containsKey` sends you to `openProfile`. Ordinary progress events are also dropped for a frame.
- Fix: `final turns = await …;` first, then `state = state.copyWith(turns: turns, …)`.

**B5. Medium · Bug · Confirmed: an error while saving leaves the session stuck "answering" forever.**
- Where: `ai_session.dart:714-719` (`_follow` `onDone`).
- What is wrong: `onDone: () async { … await onDone(progress); if (read() != null) write(null); done.complete(); }`. If `_keepTurn`, `_keepSet` or `_keepRewrite` throws, for example a store error or a write to a thread deleted while it streamed (`deleteThread`), the exception escapes as an unhandled zone error. `write(null)` and `done.complete()` never run.
- Failure: `state.pending` stays non-null. Ask is disabled and only "Stop" shows. Stop then calls `_keepTurn` again (`ai_session.dart:833`), which may throw again, so the session is wedged until restart. For sets, `making[id]` stays and the set shows "Being made…" forever.
- Fix: wrap the `onDone` body in `try/finally`: `write(null)` and `done.complete()` in the `finally`, and the error turned into `state.error` in a `catch`.

**B6. Medium · Bug · Confirmed: double-grading a flashcard corrupts the review schedule and skips a card.**
- Where: `app/aantekening/lib/src/ai/flashcards_view.dart:230-252`.
- What is wrong: `_grade` checks `_turned` and then awaits `CardReviews.grade` (a database write) before `setState` clears `_turned` and dequeues. A second press of `3`, or a double-click on a grade button, inside that window grades the *same* card again. Because `grade()` updates `state` optimistically, the second grade is applied on top of the first, compounding the interval. Then both `setState`s call `queue.removeAt(0)`, so the *next* card is removed without being shown or graded.
- Failure: wrong due dates (a card pushed out roughly twice as far), a card silently skipped, and wrong counts (`_done` holds the first card twice). Practice mode has no `await` and is not affected.
- Fix: before awaiting, take the card off the queue and set `_turned = false` synchronously (or set a `_grading` flag), then persist.

**B7. Medium · Bug · Confirmed: changing settings or saving any key mid-answer aborts the in-flight answer, set or podcast.**
- Where: `app/aantekening/lib/src/ai/ai_state.dart:135-145` together with `app/aantekening/lib/src/settings/ai_settings.dart:280`.
- What is wrong: `aiModelProvider` does `ref.onDispose(provider.close)`. It rebuilds whenever the active `ProviderConfig` instance changes (notes per question, think, room, model) and whenever *any* provider key is saved (`ref.invalidate(aiModelProvider)`). `AiSession` keeps using the old `model.provider` for its whole stream, as do `NoteAgent` tool rounds and podcast writers with `own: false`. `close()` force-closes the `http.Client`.
- Failure: you open the settings from the ask line's model button while an answer streams and change "Notes per question". The answer breaks off with "The answer broke off: ClientException…". Saving the key of a *different* provider has the same effect.
- Fix: have the session create and close its own `ChatProvider` per request, or reference-count the provider; dispose it only when no stream holds it.

**B8. Medium · Bug · Plausible: AI sessions survive a change of notes folder and write into the new workspace.**
- Where: `ai_session.dart:341,344-356`.
- What is wrong: `aiSessionProvider` is a non-autoDispose family whose `build` never watches `storeProvider`. `_store` uses `ref.read`. When the notes folder changes, `storeProvider` (`providers.dart:18-20`) is rebuilt, but every session keeps the old threads and items. In-flight streams then call `_keepTurn` / `_keepSet` against the *new* store with a scope and thread ids that belong to the old workspace. The `NoteAgent` also still holds a reader over the closed store.
- Fix: `ref.watch(storeProvider)` in `build`, so the session resets and cancels its subscriptions through `onDispose` on a store change, or invalidate the family when the store changes.

**B9. Medium · Bug · Confirmed: keychain failures are unhandled and there is no fallback, although the docs promise one.**
- Where: `ai_state.dart:59`, `ai_settings.dart:248-251,272-283`, `podcast_settings.dart:245-263`.
- What is wrong: `MemorySecrets` is documented "for … where the system keeps none", but `aiSecretsProvider` always returns `KeychainSecrets`. Only tests and the benchmark override it. No call site catches errors: `_readKey` is `unawaited`, and `_saveKey` is called from `onPressed`.
- Failure: on a Linux desktop without the Secret Service or libsecret, saving a key throws an uncaught exception with no message to the user. `aiModelProvider` fails, so `_Main` shows the "Choose a model" page as if nothing were configured.
- Fix: catch errors from `read`/`write`, show them in the provider block, and fall back to `MemorySecrets` (with a warning) when the keychain is unavailable.

**B10. Medium · Bug · Confirmed: tapping a podcast row on the overview immediately starts a paid generation.**
- Where: `app/aantekening/lib/src/ai/podcast_view.dart:808`.
- What is wrong: `onTap: making == null ? onMake : onShow`. Tapping the row itself, not only the "Make" pill, starts `makePodcast`: an outline model, a transcript model per part, then text-to-speech. This contradicts the study rows' rule, "looking at it never sets a model to work by itself" (`study_pages.dart:194-195`), where a row tap only opens the page.
- Fix: make the row tap `onShow`, or open the episode profile page, and leave making to the pill.

**B11. Low · Bug · Confirmed: ready questions ignore the "Web" toggle in the ask line.**
- Where: `app/aantekening/lib/src/ai/study_pages.dart:646`.
- What is wrong: `askReady` passes `searchWeb: ref.read(aiSettingsProvider).searchWeb`. It ignores the per-session `_web` toggle the user flipped off in `_AskLineState` (`ai_view.dart:1023,1154`), and unlike `_send` and `_rewrite` it does not apply `_webAvailable`.
- Failure: the user turns Web off, clicks "Explain the hardest part", and the web is searched anyway (Anthropic's own search, or Brave).
- Fix: lift the toggle into session or provider state and compute the web decision in one shared helper.

**B12. Low · Bug · Confirmed: an early return in `makePodcast` leaks the podcast's own providers.**
- Where: `ai_session.dart:1055-1057`.
- What is wrong: `if (info == null) return;` comes after `_writerOf` created `own` providers but skips `close()`, unlike the `missing` path at 1048-1051.
- Fix: call `close()` before returning, or put the body in `try/finally`.

**B13. Low · Bug · Confirmed: Stop racing completion saves the turn twice.**
- Where: `ai_session.dart:822-845` against `714-716`.
- What is wrong: while `_follow`'s `onDone` is awaiting `_keepTurn` (store writes), `pending` is still set. Pressing Stop then finds `cancel()` does nothing and `pending.answer` non-empty, and calls `_keepTurn` a second time.
- Failure: the turn is saved twice, the second copy with "*Stopped.*".
- Fix: clear `_answering` and `pending` (or set a "saving" flag) before calling `onDone`; have `stop()` return if the stream has already finished.

**B14. Low · Bug · Plausible: `setState` after an await without a `mounted` check, plus controllers disposed while dialogs close.**
- `podcast_view.dart:157`: `_seek` calls `setState` after `await _ready(path)` (that is, `setSource`) without checking `mounted`, so leaving the page during the first seek throws.
- `study_pages.dart:675` (`askName`) and `flashcards_view.dart:884-887` (`_editCard`) dispose their `TextEditingController`s in `whenComplete`. That runs as soon as `pop()` completes the future, while the route's exit transition and focus loss still touch the autofocused `TextField`. This is the known "TextEditingController was used after being disposed" pattern.
- `podcast_settings.dart:970-971` disposes a speaker's controllers inside the same `setState` that removes the row. Because the rows have no keys, the remaining fields shift onto other rows' elements.
- Fix: guard the `setState` with `mounted`; move the dialog contents into a `StatefulWidget` that owns its controllers; give each speaker row a key.

---

### Performance

**P1. High · Performance · Confirmed: every streamed token rebuilds the whole pane and re-parses every past answer's Markdown.**
- Where: `app/aantekening/lib/src/ai/ai_view.dart:543,548-558,689-708` and `app/aantekening/lib/src/ai/answer_view.dart:47-58`.
- What is wrong: `_Main` watches the *entire* `aiSessionProvider(scope)`, and each token produces a new `PendingTurn`. On every token, `_Conversation` rebuilds every completed turn, and each of those:
  - re-decodes its JSON (`AiAnswer.fromJson(turn.answer)`), which creates a new object, so nothing short-circuits
  - builds a new `AnswerView`, whose `build` reparses the full answer with `md.Document(...).parse`
  - rebuilds its spans, `MathView`s and tables
  - calls `isKept` (a linear scan of the items)

  Background generation of a set or podcast (`making` / `podcasts` progress) triggers the same full rebuild even when only a conversation is showing.
- Cost: with 10 long turns and roughly 50 tokens a second, about 500 Markdown parses and LaTeX layouts a second on the UI isolate, which visibly janks the stream.
- Fix:
  - Watch with `select` per section (turns, pending, and so on).
  - Turn the completed `_Exchange`s into stable `const`-able widgets keyed by `turn.id`, decoding once in the state (`List<AiAnswer>`).
  - Make `AnswerView` stateful and parse in `didUpdateWidget` only when the Markdown changes.
  - Use `ListView.builder`.

**P2. Medium · Performance · Confirmed: the session state's getters re-decode every kept item on every build.**
- Where: `ai_session.dart:246-291` (`setOf`, `profilesWith`, `savedAnswers`, `episodes`), used by `study_pages.dart:412-419,516`, `podcast_view.dart:736-772` and `ai_view.dart:241,548-553`.
- What is wrong: each getter calls `StudySet.fromJson` or `PodcastEpisode.fromJson` on every item, every time it is called. `StudyOverview` calls `setOf` once per profile, giving O(profiles × items) full decodes. A 300-card flashcard set or a podcast transcript is decoded in full each time. The overview watches the whole state, so this runs on every progress event of any background generation, and `_layer()` also runs it on every keypress.
- Fix: classify and decode the items once in `_load` into typed fields (`Map<String, (AiItem, StudySet)>`, `List<(AiItem, PodcastEpisode)>`, `savedAnswers`), so the getters become lookups.

**P3. Medium · Performance · Confirmed: the podcast page re-decodes the episode, stats the file and rebuilds the whole transcript on every position tick.**
- Where: `podcast_view.dart:72,112-113,186-197,546-627`.
- What is wrong: `onPositionChanged` calls `setState` many times a second while playing. Each rebuild:
  - re-decodes the episode JSON (`_episode` getter)
  - runs synchronous I/O, `File(path).existsSync()`, in `build`
  - rebuilds `_Transcript`, a non-lazy `Column` of every line, each with a `GlobalKey`, plus `lines.every` for each segment, which is O(segments × lines)
- Fix: cache the episode and the file's existence in the state, updated in `didUpdateWidget` or `initState`. Put the position in a `ValueNotifier` that only the player bar and the current-line highlight listen to. Use a lazy list.

**P4. Medium · Performance · Confirmed: the podcast WAV is encoded and written synchronously on the UI isolate.**
- Where: `ai_state.dart:96-102`.
- What is wrong: `sound.toWav()` (a per-sample Dart loop) and `writeAsBytesSync(…, flush: true)` run on the UI isolate. At 24 kHz, 16-bit, mono, a 12-part episode of about 40 minutes is roughly 115 MB, so the app freezes for hundreds of milliseconds to seconds. The comment calls it "a few megabytes"; the defaults (up to 12 parts of 1–4 minutes each) say otherwise.
- Fix: do the encoding and writing in `Isolate.run` with async I/O. Consider a compressed format.

**P5. Medium · Performance · Confirmed: `WorkspaceReader` caches every page it has ever read, forever.**
- Where: `app/aantekening/lib/src/ai/workspace_reader.dart:21-23,124-143`.
- What is wrong: `_read` holds the full `PageDocument` (ink included) and the `PageDigest` of every page ever read, for as long as the workspace stays open. Nothing is ever evicted; a page is only replaced when its revision changes, and deleted pages stay. Asking about a large notebook pins all of its documents in memory. By contrast, `VisualRenderer` caps its cache at 64 entries.
- Fix: use an LRU limited by count or bytes, or cache only the digests and reload documents on demand for rendering.

**P6. Low · Performance · Confirmed: listing a notebook's pages repeats the same section queries for every section.**
- Where: `workspace_reader.dart:92-112`.
- What is wrong: `_pagesOfSections` calls `_sectionPath(entry.id)` for each section. Each call repeats `findSection`, `findNotebook` and `listAllSections`, even though `sections` is already loaded, so a notebook with 50 sections costs about 150 extra queries per `pagesIn`. `searchPages` with `within` calls `pagesIn` on every tool call.
- Fix: build the paths from the hierarchy already in hand.

**P7. Low · Performance · Confirmed: the "About you" field rebuilds every page watching the AI settings on each keystroke.**
- Where: `ai_settings.dart:131-136`.
- What is wrong: each keystroke calls `AiSettingsController.update`, so every widget watching `aiSettingsProvider` rebuilds, including `_Main` in every open AI pane (`ai_view.dart:554-555`) and all provider blocks. The writes to prefs are coalesced, but the rebuilds are not.
- Fix: save on focus loss or after a debounce; watch narrower `select`s.

---

### Design

**D1. Medium · Design · Confirmed: `ai_session.dart` (1355 lines) is a god class.**
- `AiSession` owns conversations, rewrites, study-set generation and merging, flashcard additions, podcasts (choosing and closing writers, reading keys, speech, saving audio files), and item and thread CRUD.
- The same file also holds `AiAction`, `PendingTurn`, `CardReviews` with its provider, `deckStatus`, `cardsToStudy` and `workspaceReaderProvider`.
- The podcast half (`ai_session.dart:928-1237`, about 310 lines) is independent of conversations and has its own subscription map.
- Fix:
  - Split it into `ConversationController`, `StudySetMaker` and `PodcastMaker` notifiers, each keyed by scope and sharing a small store and agent factory.
  - Move `CardReviews`, `deckStatus` and `cardsToStudy` next to `flashcards_view.dart`.

**D2. Medium · Design · Confirmed: "what is showing" is spread over five nullable fields with ad-hoc precedence.**
- Where: `AiSessionState` fields `threadId`, `itemId`, `shownProfile` and `shownPodcast`, plus `pending`, together with `ai_view.dart:560-608`.
- What is wrong: every navigation method has to remember to null the others, and `make`/`openProfile` resetting `threadId` is what causes B1. `_Main` resolves which page wins through a nine-branch if-chain.
- Fix: one sealed `AiPage` type (`Overview | Thread(id) | Item(id) | Profile(id) | PodcastDraft(id)`), kept separate from "what is in flight".

**D3. Low · Design · Confirmed: subscriptions are fire-and-forget, so stopped work leaves futures that never complete.**
- Where: `ai_session.dart:681-724,985-1009`.
- What is wrong: `_follow` and `_followPodcast` return a `Completer` future that never completes when the subscription is cancelled (`stop`, `stopMaking`, `stopPodcast`). The code after `await _follow(...)` in `make` (658) and `makePodcast` (1132-1135) never runs after a Stop.
- Fix: use `await for` with an explicit cancellation token, or complete the future in the stop paths.

**D4. Low · Design · Confirmed: circular imports and helpers living in the wrong files.**
- What is wrong:
  - `study_pages.dart` ↔ `podcast_view.dart` import each other.
  - `ai/study_pages.dart` imports `settings/podcast_settings.dart`, which imports `ai/podcast_view.dart`: a cycle between the `ai` and `settings` folders.
  - Generic helpers (`whenOf`, `confirmStep`, `askName`, `threadTitle`, `sizeOf`) live in `study_pages.dart` but are used by `ai_view` and `podcast_view`.
  - `playbackTrouble` lives in a view but is used by settings.
- Fix: move the helpers to `ai/ai_common.dart` and pass `openPodcastSettings` as a callback.

**D5. Low · Design · Confirmed: model lists are fetched with the API key on every settings open, as a side effect of `build`.**
- Where: `ai_settings.dart:235,253-265`, `podcast_settings.dart:672-693,851-868,899`.
- What is wrong: opening the AI settings calls `listModels()` for *every* configured provider, sending each one its key, on every open. `_ModelChoiceField._list` and `_CastEditor._list` start network requests from `build`.
- Fix: put model lists in a cached `FutureProvider.family<List<ModelInfo>, String providerId>`, refreshed on demand.

---

### Redundancy / code size

**R1. Medium · Redundancy · Confirmed: the AI and podcast settings pages duplicate their provider plumbing (about 200 lines saved).**
- The "Add a … provider" `MenuAnchor` with groups for this computer and online: `ai_settings.dart:60-84` vs `podcast_settings.dart:54-78`.
- `_MenuHeading`, identical in both: `ai_settings.dart:188-198` vs `podcast_settings.dart:192-202`.
- The key handling in `_ProviderBlock` and `_VoiceBlock` (`_readKey`, `_saveKey`, `_remove`, the API key field with identical helper texts, "Remove this … provider", the local/online note): `ai_settings.dart:246-292,367-401` vs `podcast_settings.dart:243-271,403-436`.
- Model listing (read key → `create` → `listModels` → `close` → `FutureBuilder` that switches between a `TextField` and a `DropdownMenu`): `ai_settings.dart:253-265,523-607` vs `podcast_settings.dart:672-686,728-771`.
- Fix: a shared `_ProviderShell` (header, address, key row, remove) and a `ModelPicker` widget backed by one model-list provider.

**R2. Low · Redundancy · Confirmed: the same `_settle` helper is copied three times.**
- `_settle(change)` (update the settings, then pop) appears in `study_profile_editor.dart:84-88`, `podcast_settings.dart:507-512` and `podcast_settings.dart:886-891`.
- Fix: extract one helper.

**R3. Low · Redundancy · Confirmed: `ask` and `rewrite` share a copy-pasted preamble.**
- The preamble checks the model, gets the reader and the scope info, gets web search, and rebuilds `history`: `ai_session.dart:440-453` vs `492-505`. `make` repeats the first half (616-623).
- `_follow` and `_followPodcast` (681-724 vs 985-1009) are the same follow-subscription pattern.
- The usage map is built twice (`_usageOf` at 898-909 and inline at 1111-1115); the podcast copy drops `cacheRead`, `cacheWrite` and `webSearches`.
- Fix: a `_prepare()` returning `(model, reader, info, web, history)`, one generic `_follow<T>`, and reuse of `_usageOf`.

**R4. Low · Redundancy · Confirmed: the web-search decision is computed in three places, inconsistently.**
- Where: `ai_view.dart:738-740`, `ai_view.dart:1048-1050` and `study_pages.dart:646`. The last differs, which is B11.
- Fix: one function or provider.

**R5. Low · Redundancy · Confirmed: an `invalidate` that the provider's own `watch` already covers.**
- Where: `ai_settings.dart:700`.
- What is wrong: `ref.invalidate(webSearchProvider)` after changing `searxngUrl` is redundant, because `webSearchProvider` already watches `select((s) => (s.webBackend, s.searxngUrl))`; records compare by value.
- Note: the `invalidate` at line 728 after saving the Brave key *is* needed.

**R6. Low · Redundancy · Confirmed: the study views share scaffolding that could be extracted.**
- The `scrolls ? SingleChildScrollView(child: x) : x` wrapper appears three times: `quiz_view.dart:122-127`, `glossary_view.dart:127`, `flashcards_view.dart:737`.
- The `Footnotes()..numberAll(...)` plus `SourceList` footer appears in `glossary_view.dart:46-47,123` and `summary_sheet.dart:35-40,152`.
- `StudyHeader` and `StudyPaper` are already shared, so the remaining duplication is small. A `StudyBody(scrolls:, citations:, child:)` would remove about 30 lines. Low priority.

**R7. Low · Redundancy · Confirmed: `FlipCard` adds nothing.**
- Where: `flashcards_view.dart:394-410`.
- What is wrong: `FlipCard` is public but used only in its own file, and it is just `turned ? back : front` wrapped in a `KeyedSubtree`. It does not animate.
- Fix: inline it, or make it private.

---

## Part 8: app shell (app/aantekening/lib minus editor/, ai/, settings/)

Scope: `lib/main.dart` and `lib/src/` `app.dart`, `providers.dart`, `preferences.dart`, `error_log.dart`, `input_trace.dart`, `command_menu.dart`, `shell/`, `look/`, `files/`, `commands/`, `modes/`, `search/`, `graph/`, `spelling/`, `links/`.
I reviewed by reading the code; nothing was run. All paths are relative to `app/aantekening/lib/` unless stated otherwise.

**Confidence labels:**
- **Confirmed:** I traced the code path.
- **Plausible:** the code is as described, but the failure depends on runtime or library behaviour I could not run.

---

### Bugs

#### B1. [Medium] [Bug] A key catcher is never released when its widget never mounts, so the keyboard stops working (Confirmed)
- **Where:**
  - `src/search/search_line.dart:103-107` (`SearchLineOpen.open`)
  - `src/shell/home_shell.dart:108-141` (the search line is mounted only in the `data:` branch)
  - `src/shell/picker.dart:48-81` (`PickerKeys`) and `:543-550` (`attach` runs only once `notebooksProvider.hasValue`)
  - `src/commands/command_keys.dart:49`
- **What is wrong (search line):**
  - `SearchLineOpen.open()` creates a `TypeAhead`, which is an early-key-handler `KeyCatch`. It is released only by `SearchLine.initState` (`_typedAhead`) or `close()`.
  - `CommandKeys` stays live while the store is in the error state, because it wraps the `Scaffold`. Ctrl+F still runs `AppCommand.search`, but the `SearchLine` widget is never built.
  - The `TypeAhead` then swallows every printable key, Space, Enter and Backspace for good.
  - Because `KeyCatch.active` is now true, `CommandKeys._onKey` returns early (line 49). Every shortcut stops working.
- **What is wrong (picker):**
  - Ctrl+Shift+E (`notebooks`) opens the picker. Its `PickerKeys._press` returns `true` for every key, Esc included, until `attach()`.
  - `attach()` runs only once `notebooksProvider` has a value, which never happens while the store is in error.
  - So Esc cannot close the picker.
- **Failure scenario:**
  1. The notes cannot be opened ("aantekening is open already").
  2. The user presses Ctrl+F, or Ctrl+Shift+E then Esc.
  3. The keyboard is dead until the store opens.
- **Fix:**
  - Gate the window commands, or at least `search`, `notebooks` and `graph`, on `storeProvider.hasValue`.
  - Make `PickerKeys` pass Esc through when there is no taker.
  - Release the `TypeAhead` on close of a line that never showed (for example, in `HomeShell`, `ref.listen(storeProvider)` and close it).

#### B2. [Medium] [Bug] `storeProvider` registers the store's close only after awaiting the open, so a store opened by a disposed build leaks (Confirmed in code; trigger Plausible)
- **Where:** `src/providers.dart:33-52`
- **What is wrong:**
  - `ref.onDispose(() => _storeClosing = store.close()...)` is registered after `await AantekeningStore.open(...)`.
  - If the provider is disposed or rebuilt while `open` is in flight, `ref.onDispose` lands on a dead ref:
    - In Riverpod 3 it throws.
    - Otherwise it never fires.
  - Either way, the opened `AantekeningStore` (SQLite handle plus folder lock) is never closed.
  - `_storeClosing` was already awaited, so the next build's `open` races it.
- **Triggers:** the notes folder changing while the store is being opened:
  - `NotesLocation._keepAt` invalidates `notesFolderProvider` (`files/notes_location.dart:117-118`).
  - Restore, or "Start new notes there", during a slow open.
- **Failure scenario:** the next open reports `NotesInUse` against its own leaked handle, or two stores mirror the same folder.
- **Fix:**
  - Right after `open`, check `if (!ref.mounted) { await store.close(); throw StateError(...) }`.
  - Or register a disposer before awaiting and close the store when the open completes after disposal.

#### B3. [Medium] [Bug] Export and library actions run unawaited with no error handler, so failures are only written to `errors.log` (Confirmed)
- **Where:**
  - `src/files/export_flow.dart:19-44`, called as `unawaited(exportNotes(...))` from `src/shell/library_menu.dart:349`
  - `src/shell/library_menu.dart:254`, `:257`, `:263-293`, `:307`
  - `src/shell/picker.dart:275-322`, `:348-364`
  - `src/shell/window_commands.dart` (every `unawaited(...)`)
  - `src/files/attached_files.dart:96` (`saveAttachedFile`'s `copy`)
- **What is wrong:**
  - `exportNotes` has no `try`. If `store.exports.write` throws (disk full, permission denied, path on a read-only share), the future errors into `PlatformDispatcher.onError`.
  - `ErrorLog.install` (`src/error_log.dart:36-40`) only logs it.
  - The user gets no "Saved to ..." message and no failure message.
  - The same applies to rename, create, paste, arrange and delete from menus and the picker, and to `saveAttachedFile`.
  - By contrast, PDF export (`pdf_export.dart:362-385`) and import (`import_flow.dart:98-101`) do report failures.
- **Fix:** wrap these in one `runReported(context, future, failMessage)` helper that shows `ScaffoldMessenger.showMessage` on error. At minimum, do this for export and save-copy.

#### B4. [Medium] [Bug] `assetRefProvider` and `assetFileProvider` cache "missing" forever (Plausible)
- **Where:** `src/providers.dart:261-281`
- **What is wrong:**
  - Both are non-`autoDispose` families with no dependency on any revision. A `null` (asset row not there yet, or file not there yet: `existsSync()` false) is kept for the whole session.
  - With the notes folder synced between computers (ADR 19), a page can arrive before its asset file. The picture then shows as missing until restart.
  - `existsSync` is also synchronous I/O inside a provider on the UI isolate.
- **Fix:**
  - Make them `autoDispose` with `keepAWhile()`, as `assetBytesProvider` already is.
  - Watch `libraryRevisionProvider` or a folder-changes signal.
  - Use `await file.exists()`.

#### B5. [Low-Medium] [Bug] Search-as-you-type fills the Back history with intermediate matches (Confirmed)
- **Where:** `src/search/search_session.dart:28-34`, which leads to `library_actions.dart:80-87`, then to `TabsController.updateCurrent`, then `_step` (`src/shell/tabs.dart:298-311`, `:388-394`)
- **What is wrong:**
  - Every typing pause (250 ms) runs `SearchSession.search`, which opens the best hit.
  - Each open goes through `updateCurrent` and `_step`, which pushes the previous page onto `_back` and clears `_forward`.
- **Failure scenario:** typing "thermodynamics" slowly leaves 3-6 unrelated pages on the Back stack. Alt+Left then walks through them instead of returning to where the search started.
- **Fix:** mark search-driven opens as travel (do not record them), or record a single step when the search line closes.

#### B6. [Low-Medium] [Bug] The fuzzy matcher is greedy, so word-start matches later in the text are missed (Confirmed by hand calculation)
- **Where:** `src/commands/fuzzy.dart:16-31`
- **What is wrong:**
  - `indexOf(letter, from)` always takes the leftmost occurrence. Word-start and consecutive bonuses are only earned if the leftmost path happens to hit them.
- **Worked example, query "cal":**
  - "Local calculus" matches inside "Lo**cal**": −1 + 6 + 6, giving 1086.
  - "Notes on calculus" matches at the word start: 3 + 6 + 6, giving 1483.
  - The page whose title contains the same word "calculus" ranks lower only because of an incidental earlier "cal".
  - The same thing hurts Go to, Commands, the keyboard-settings filter and the font filter.
- **Also:**
  - `_isLetterOrDigit` builds a Unicode `RegExp` per character on every call (line 34-35). That runs once per letter × node × rebuild in Go to.
  - Tests (`test/look_test.dart:19-38`) cover only first-word cases.
- **Fix:**
  - Try each word-start occurrence of the first letter (or use a small DP, as fzf and VS Code do) and keep the best score.
  - Hoist the `RegExp` to a `static final`.

#### B7. [Low] [Bug] The startup-only work in the shell never re-runs after "Try again" or a folder change (Confirmed)
- **Where:**
  - `src/shell/home_shell.dart:56`, `:82-93` (`_forgetMissing`)
  - `src/files/notes_keeper.dart:69`, `:76-87` (`_backUpWhenOpen`, `_sayRescued`)
- **What is wrong:**
  - Both run once from `initState`. If the first open fails and the user presses "Try again" (`home_shell.dart:121`), they have already returned.
  - Pages rescued from a failed save are restored silently ("A page could not be saved last time..." never shows).
  - The startup backup is skipped until the hourly timer fires.
  - Stale tabs are not pruned.
- **Fix:** drive them from `ref.listen(storeProvider, ...)` on each new `AsyncData`, not from `initState`.

#### B8. [Low] [Bug] Tab bookkeeping is inconsistent: Close-others tabs cannot be reopened, and history maps leak (Confirmed)
- **Where:** `src/shell/tabs.dart:171-172`, `:230-245`, `:253-258`, `:321-322`
- **What is wrong:**
  - `closeOthers` drops the tabs without adding them to `_closed`, so "Reopen closed tab" cannot bring them back (`close()` does add them).
  - `_back[id]` and `_forward[id]` are never removed when a tab closes, so per-tab history leaks for the session.
  - `reopenedAs` gives a new id, so a reopened tab loses its history anyway.
  - Neither path is tested (`test/app_test.dart:1160-1176` checks counts only).
- **Fix:**
  - Add the others to `_closed` in `closeOthers`.
  - Remove `_back` and `_forward` entries in `close` and `closeOthers`.
  - Carry the history across in `reopen` (move the entries to the new id).

#### B9. [Low] [Bug] Exports flush the folder mirror, which does not matter, but do not save the open page, which does (Confirmed)
- **Where:**
  - `src/files/export_flow.dart:35`
  - `src/files/pdf_export.dart:359`
  - Compare `src/files/backup_settings.dart:148-150` and `src/files/notes_keeper.dart:40-44`
- **What is wrong:**
  - `store.exports.write` (`packages/aantekening_store/lib/src/archive_export.dart:41+`) and `writePdf` (`store.pages.loadDocument`) read the SQLite index, not the folder. So `mirror.flush()` is wasted I/O.
  - Edits still inside the editor's 700 ms debounce are not saved first: `openSaves.saveAll()` is not called. Backup does call it.
  - The impact is small because a dialog usually comes first, but nothing guarantees it.
- **Fix:** call `ref.read(openSavesProvider).saveAll()` (or `keepEverything`) instead of `mirror.flush()`.

#### B10. [Low] [Bug] `FloatingIn` and `FadingPageTransitions` create a `CurvedAnimation` on every build and never dispose it (Confirmed)
- **Where:** `src/look/motion.dart:102`, `:108`, `:213`
- **What is wrong:**
  - The `CurvedAnimation` constructor calls `parent.addStatusListener`, and nothing removes it.
  - `SearchLine` rebuilds `FloatingIn` on every result, step and query change (`search/search_line.dart:259`). The key guide and dialogs rebuild it per change.
  - So status listeners pile up on the parent controller for its lifetime. Flutter's leak tracker flags this.
- **Fix:** make `FloatingIn` stateful, holding its two curves and disposing them; do the same for the page transition. Alternatively, use `animation.drive(CurveTween(...))`, which adds no listener.

#### B11. [Low] [Bug] An attached file opened again reuses whatever copy is in temp (Confirmed)
- **Where:** `src/files/attached_files.dart:51-52`
- **What is wrong:**
  - The check `if (!copy.existsSync()) await source.copy(copy.path)` reuses an existing copy.
  - The doc comment says changing the opened copy "changes nothing on the page". But after the user edits and saves the temp copy in an external program, opening the attachment again opens the edited copy, not the stored original.
  - A copy left partial by a crash mid-copy is also reused forever.
- **Fix:** copy every time (or compare length or hash) and copy to a temp name, then rename.

#### B12. [Low] [Bug] Saving a PDF over an existing file on Windows is not atomic (Confirmed)
- **Where:** `src/files/pdf_export.dart:269-271`
- **What is wrong:** `target.deleteSync()` runs before `part.rename(path)`. If the rename fails (file open in a PDF viewer, AV lock), the old PDF is already gone.
- **Fix:** rename the old file to a backup name first and restore it on failure, or use `File.rename` with a retry and keep the old file until the rename succeeds.

#### B13. [Low] [Bug] Enter typed ahead in Go to uses `ref.watch` outside build, and is lost if the graph is not loaded (Plausible)
- **Where:** `src/look/chooser.dart:118-126`, which calls `command_palette.dart:52-53` and `:79-81` (`ref.watch(...)`)
- **What is wrong:**
  - The post-frame callback calls `widget.choicesFor(ref, ...)`, and `_placeChoices` and `_commandChoices` call `ref.watch` there.
  - That is outside `build`, which Riverpod discourages or asserts on.
  - If `noteGraphProvider` is still loading, `choices` is empty and the typed-ahead Enter is silently dropped.
- **Fix:** compute the choices with `ref.read` in that path, or run the typed-ahead Enter from the first `build` in which choices are non-empty.

---

### Performance

#### P1. [Medium] [Performance] The graph layout is O(n²) per frame on the UI isolate, with allocations in the inner loop (Confirmed)
- **Where:**
  - `src/graph/force_layout.dart:140-160`, called from `graph_panel.dart:139-147` on every ticker frame
  - `graph_panel.dart:470-485`
- **What is wrong:**
  - Every node is compared with every other node, and each pair is visited twice.
  - Each pair allocates 3 `Offset`s (`Offset(dx, dy)`, `* k`, and the `-=` result).
  - The graph holds every page in the workspace (`note_graph.dart:131-143`). A OneNote import of 5,000 pages means 25 M pair updates and 75 M allocations per frame, for up to 300 frames, so the picker freezes.
  - The doc comment's "a few milliseconds for a thousand" does not hold at that size.
  - The painter adds more per-frame work:
    - From zoom 1.4 up, it calls `state._label(...)` (creating a `TextPainter`) for every node before culling off-screen ones.
    - It sorts all names.
    - It does a quadratic `taken.any(box.overlaps)`.
- **Fix:**
  - Use Barnes-Hut (quadtree) or a grid cutoff for repulsion.
  - Use `Float64List` for x, y, vx and vy instead of `Offset`.
  - Visit each pair once, applying the force to both nodes.
  - Cap steps per frame by time.
  - Cull names off-screen before `_label`, and use a spatial grid for overlap.

#### P2. [Medium] [Performance] The editor panes rebuild on every tab-state change, and opening a page makes 3 separate tab updates (Confirmed)
- **Where:**
  - `src/shell/home_shell.dart:208` and `:412` (`ref.watch(tabsProvider)`)
  - `src/shell/library_actions.dart:80-87`
  - `src/providers.dart:100-112` and `:208-216`
- **What is wrong:**
  - `_Panes` and each `_Pane` watch the whole `TabsState`. The search query lives in the tab (`SearchQuery.set` leads to `updateCurrent`).
  - So every search pause, selection, AI toggle or tab reorder rebuilds both `PageEditor`s, the `LayoutBuilder` and the `_Tabs` row.
  - `_select` calls `selectedNotebook.select`, `selectedSection.select` and `selectedPage.select` separately. That makes 3 `TabsState`s, 3 `jsonEncode`s in `_set`, 3 rebuild passes and 2 inconsistent intermediate states.
  - Examples of inconsistent intermediate states: the new notebook paired with the old section, or the new section paired with the old page. Listeners such as the picker's `selectedPageProvider` listener and `recentPages` can observe them.
  - `NoteLinks.openNote` adds a fourth update (`links/note_links.dart:89`).
- **Fix:**
  - Have `_Pane` watch `tabsProvider.select((t) => (t.tabs[index].pageId, t.tabs[index].ai, t.active == index))`, and have `_Panes` select `(active, beside, stacked)`.
  - Add `TabsController.choose({notebookId, sectionId, pageId})` and call it once from `_select`.

#### P3. [Low-Medium] [Performance] The picker recomputes its rows many times per build and per key (Confirmed)
- **Where:** `src/shell/picker.dart:159-208` (`_rowsOf`, `_cursorOf`, `_nodeAt`), `:556-559`, `:619-680`
- **What is wrong:**
  - The calls nest: `_rowsOf(pages)` calls `_cursorOf(sections)`, which calls `_rowsOf(sections)`, which calls `_cursorOf(notebooks)`, which calls `_rowsOf(notebooks)`.
  - `build` calls these through `longest`, then per column through `rows:`, `cursor:` and `empty:`.
  - So a single j/k press builds the page tree about 3×, the section tree about 6× and the notebook list about 12×. Each `treeRows` allocates a `TreePlace` and an unmodifiable ancestor list per row.
  - `_move` and `_shift` repeat this on every key.
  - With a 1,000-page section this is tens of thousands of allocations per keystroke.
- **Fix:** compute the three `(rows, cursor)` pairs once per build (or memoise them per `(tree, collapsed, wanted)`) and pass them down.

#### P4. [Low-Medium] [Performance] Go to rescores every node on every rebuild, including arrow-key moves (Confirmed)
- **Where:** `src/look/chooser.dart:178`, which calls `src/commands/command_palette.dart:119-127`
- **What is wrong:**
  - `Chooser.build` calls `choicesFor(ref, typed)`, which runs `fuzzyScore` against every notebook, section and page, sorts them and builds `Choice` closures.
  - Each Up/Down (`setState(_highlight)`) repeats all of it, though the text did not change.
  - Combined with the per-character `RegExp` in `fuzzy.dart:34`, this becomes noticeable at a few thousand pages.
- **Fix:** cache the choices per `typed` (and graph identity) in the state, and recompute only when either changes.

#### P5. [Low] [Performance] `ErrorLog` writes synchronously, with flush, for every error on the UI isolate (Confirmed)
- **Where:** `src/error_log.dart:71-86`
- **What is wrong:**
  - For every error the code runs `createSync`, `existsSync`, `lengthSync`, possibly `readAsStringSync` of 1 MB and `writeAsStringSync`, then `writeAsStringSync(..., flush: true)`.
  - An error repeated every frame (a paint or layout exception) becomes 60 fsyncs a second on the UI thread, which makes the jank worse.
  - The trim (`substring(kept.length - _most ~/ 2)`) can also split a UTF-16 surrogate pair. That is cosmetic.
- **Fix:**
  - Buffer entries and write them asynchronously in the background, debounced.
  - Rate-limit identical messages.
  - Keep `flush` only for uncaught or fatal errors.

#### P6. [Low] [Performance] PDF export scans every pixel on the UI isolate (Confirmed)
- **Where:** `src/files/page_printer.dart:69-127` (loop at `:104-118`)
- **What is wrong:** `profile` scans every pixel of up to 4096 × `width` strips in Dart on the UI isolate, between raster awaits. That is about 16 M pixel checks per strip of a long canvas page, so the progress dialog stutters.
- **Fix:** send the RGBA strip to `Isolate.run` for the scan, as `_encodeAway` already does for encoding.

#### P7. [Low] [Performance] Sorting by name rebuilds both normalised keys on every comparison (Confirmed)
- **Where:** `src/shell/list_order.dart:63-102`
- **What is wrong:**
  - `compareNames` rebuilds `_nameKey` (rune loop, map lookups, `StringBuffer`) for both sides on every comparison, and parses `BigInt` for digit runs.
  - It runs in `pageTreeProvider`, which recomputes on every autosave (`pageContentsRevisionProvider`) while the picker is open.
- **Fix:** decorate-sort-undecorate (precompute the keys once per item).

#### P8. [Low] [Performance] Moving the notes lists the whole folder synchronously on the UI isolate (Confirmed)
- **Where:** `src/files/notes_location.dart:90`
- **What is wrong:** `Directory(source).listSync(recursive: true)` walks the whole notes folder (thousands of files) synchronously on the UI isolate. It also follows links by default.
- **Fix:** use `list(recursive: true, followLinks: false)` as a stream.

---

### Design

#### D1. [Medium] [Design] Caching is coarse: a few revision counters invalidate almost everything, and family providers are never disposed (Confirmed)
- **Where:**
  - `src/providers.dart:79-96`, `:125-205`
  - `src/graph/note_graph.dart:120-132`
  - `src/files/bin_view.dart:19-23`
- **What is wrong:**
  - `libraryRevisionProvider` is bumped by every rename (the page title is debounced but saves while typing), every arrange or create, and every `FolderChanges` (`notes_keeper.dart:142-144`).
  - Each bump refetches every listened `notebooksProvider`, `sectionTreeProvider`, `pageTreeProvider`, `pageProvider` and `binProvider`, and `noteGraphProvider`, which calls `listAllPages()`.
  - `pageProvider`, `sectionProvider`, `pageTreeProvider`, `sectionTreeProvider`, `assetRefProvider` and `assetFileProvider` are non-`autoDispose` families, so every id ever shown keeps an entry for the session.
- **Fix:**
  - Make the families `autoDispose` (with `keepAWhile` where useful).
  - Split the revision by kind (titles versus structure), or have mutations invalidate the specific family entries they touch.

#### D2. [Low-Medium] [Design] Navigation state lives outside the `Notifier` state, so the UI cannot react to it (Confirmed)
- **Where:** `src/shell/tabs.dart:171-183`, `:250`, `:271-273`
- **What is wrong:**
  - `_back`, `_forward`, `_closed` and `_travellingTo` are mutable fields beside `state`, and `canGoBack`, `canGoForward` and `canReopen` read them directly.
  - Nothing rebuilds when they change. Any enabled or disabled UI for these (menu items, a future toolbar) goes stale.
  - The history side-effect is also buried inside `updateCurrent` (which is the root of B5).
- **Fix:** move the history into `TabsState` (or a separate `NotifierProvider`) and record steps explicitly from the open actions.

#### D3. [Low] [Design] Global mutable statics outside Riverpod (Confirmed)
- **Where:**
  - `_storeClosing` (`src/providers.dart:73`)
  - `KeyCatch._stack` and `_manager` (`src/modes/key_catch.dart:31-34`)
  - The open guide `_open` (`src/modes/key_guide.dart:41`)
  - `_warmed` (`src/look/control_warmup.dart:35`)
  - `ErrorLog.file` and `_waiting`
- **What is wrong:**
  - These outlive `ProviderContainer`s and widget trees.
  - In tests, or after `ProviderScope` re-creation, a stale `_storeClosing` or `KeyCatch` stack carries across.
  - One leaked `KeyCatch` (B1) disables shortcuts globally.
- **Fix:**
  - Hold the store-closing future in a provider (`storeClosingProvider`).
  - Expose `KeyCatch` through an `InheritedWidget` or provider, with a debug assertion that the stack is empty on dispose.

#### D4. [Low] [Design] `picker.dart` is a 1,013-line widget mixing row computation, key mapping and actions (Confirmed)
- **Where:** `src/shell/picker.dart`
- **What is wrong:**
  - Tree and row computation, cursor logic, the key map and library actions all live in one `State`.
  - `_PickerRow` (`:851-958`) re-implements `RowTile`'s selected tint, hover and accent `Drop` by hand.
- **Fix:** move the column model (rows and cursor per column) into a small pure class, which can be unit-tested and also fixes P3. Build `_PickerRow` on `RowTile` with a `leading` indent and chevron.

---

### Redundancy / code size

#### R1. [Medium] [Redundancy] The same preference-backed `Notifier` is written out by hand many times (Confirmed)
- **Where:**
  - 26 `ref.preference(...)` sites in 19 files, among them `shell/recent_pages.dart`, `shell/list_order.dart:240-258`, `shell/new_page_choice.dart:325-354`, `shell/status_line.dart:39-51`, `shell/tabs.dart:469-490`, `shell/tree_rows.dart:12-40`, `files/backup_settings.dart:114-123`, `files/pdf_export.dart:68-89`, `commands/shortcuts.dart:102-119`, `look/floating_pane.dart:38-79`, `spelling/spelling.dart:48-104`.
  - The identical local helper `T named<T extends Enum>(String key, List<T> values, T fallback)` is in both `new_page_choice.dart:333-334` and `pdf_export.dart:74-75`.
- **What is wrong:** each copy repeats the same pattern:
  - `build() => decode(ref.preference(key))`
  - `set(v) { state = v; ref.savePreference(key, v == default ? null : encode(v)); }`
- **Fix:** add a generic `PreferenceNotifier<T>(key, decode, encode, defaultValue)` and an `enumPreference(key, values, fallback)` helper to `preferences.dart`. That removes roughly 150-250 lines.

#### R2. [Low] [Redundancy] Duplicate small helpers (Confirmed)
- **Where and what:**
  - Two filename sanitisers with different rules:
    - `files/export_flow.dart:47-50` `fileName`
    - `files/attached_files.dart:63-69` `safeFileName`
  - Two identical `_say` helpers: `files/import_flow.dart:125-126` and `files/pdf_export.dart:388-389`.
  - Inconsistent untitled placeholders: `files/notes_keeper.dart:94` and `files/bin_view.dart:171` use "Untitled", while `pageTitleOrPlaceholder` (`shell/library_menu.dart:26-27`) uses "Untitled page".
  - `getApplicationSupportDirectory()` is called directly in `main.dart:16`, `preferences.dart:102` and `spelling/spelling.dart:113`, although `supportFolderProvider` (`files/notes_location.dart:21-23`) exists for it.
- **Fix:** keep one sanitiser, one `_say` (or use `ScaffoldMessenger.maybeOf(...)?.showMessage` inline), one placeholder function, and use `supportFolderProvider`.

#### R3. [Low] [Redundancy] Near-duplicate list and footer scaffolding (Confirmed)
- **Where and what:**
  - Two key-hint footers: `shell/picker.dart:961-1013` `_Footer` and `look/chooser.dart:297-315` `_Footer` (a top-bordered strip of key hints).
  - `_PickerRow` versus `RowTile` (see D4).
  - `tooltip == null ? x : Tooltip(message: tooltip, child: x)` is repeated in `look/controls.dart:82`, `:411`, `:1035`.
- **Fix:** share one `KeyHintStrip` widget, and add a `maybeTooltip(...)` helper.

#### R4. [Low] [Redundancy] `look/controls.dart` has no dead code (verified)
- **What I checked:** I grepped the repo for each of the 19 public widgets in the file (`MarkButton`, `SmallButton`, `PaneHeader`, `SmallCaps`, `KeyHint`, `RowTile`, `ChoiceRow`, `LevelSlider`, `CheckRow`, `Swatch`, `PickRing`, `InverseHalves`, `Busy`, `EmptyMessage`, `Loading`, `Callout`, `PillButton`, `Drop`, `DropTab`). Each is used at least once outside its definition.
- **Result:**
  - `PaneHeader` and `DropTab` each have a single caller.
  - The 1,126 lines are mostly genuine, distinct controls.
  - The gains are in callers re-implementing them (R3 and D4), not in the file itself.
  - The other `look/` helpers I checked (`SteadySize`, `FadingPageTransitions`, `GrainNoise`, `resetPanes`, `warmControls`) are all used.
