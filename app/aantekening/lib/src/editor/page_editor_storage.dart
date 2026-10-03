part of 'page_editor.dart';

/// Reading the page, saving it, and following changes made to it elsewhere.
extension _Storage on _PageEditorState {
  /// How long to wait after the last edit before writing to disk.
  ///
  /// Long enough that a burst of typing or a drawn stroke is one write, short
  /// enough that no meaningful work is at risk if the app stops.
  static const Duration _autosaveDelay = Duration(milliseconds: 700);

  /// Reads the open page into the canvas.
  Future<void> _load() async {
    final pageId = widget.pageId!;
    _update(() {
      _loading = true;
      _error = null;
    });
    try {
      final AantekeningStore store =
          _store ?? await ref.read(storeProvider.future);
      _store = store;
      final stored = await store.pages.loadDocument(pageId);
      // Another page may have been opened while this one was read.
      if (!mounted || pageId != widget.pageId) return;
      final page = _withoutEmptyTextBoxes(
        stored ?? PageDocument.empty(id: pageId),
      );
      // Formulas are stored as LaTeX; older pages held some in Simple
      // syntax, which are translated once and saved that way — as is content
      // from before pages had a top-left corner, moved onto the page.
      final document = MathStorage.withLatexFormulas(page).withContentOnPage();
      _controller.loadDocument(document);
      if (_views[pageId] case final view?) _controller.viewport = view;
      if (!identical(document, page)) unawaited(_persist(pageId, document));
      _update(() {
        _loading = false;
        _ready = true;
      });
      // A link followed to a place on this page shows it once the page is
      // laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _meetRevealRequest());
    } on Object catch (error) {
      if (!mounted || pageId != widget.pageId) return;
      _update(() {
        _error = 'This page could not be opened: $error';
        _loading = false;
      });
    }
  }

  /// Brings the place a followed link points at into view, and picks it,
  /// once its page is showing.
  void _meetRevealRequest() {
    final link = ref.read(revealRequestProvider);
    if (!mounted || link == null || link.id != widget.pageId || !_ready) return;
    ref.read(revealRequestProvider.notifier).done();
    final id = link.elementId;
    final element = id == null ? null : _controller.elementById(id);
    if (element == null) return;
    final words = link.words;
    final block = link.block;
    _update(() {
      _revealed = words == null || block == null
          ? null
          : (
              elementId: element.id,
              words: (block: block, from: words.from, to: words.to),
            );
    });
    _controller
      ..reveal(element.bounds)
      ..select(element.id);
  }

  /// Drops text boxes with nothing in them, which an interrupted session or
  /// an undo can leave behind invisibly.
  static PageDocument _withoutEmptyTextBoxes(PageDocument document) =>
      document.withElementsRemoved(<String>{
        for (final element in document.elements)
          if (element is TextElement && TextBoxEditor.isEmpty(element.blocks))
            element.id,
      });

  /// Called on every change to the page and the view — every frame of
  /// scrolling among them — so it rebuilds nothing itself: the canvas and
  /// the ribbon's buttons each listen for what they show.
  void _onCanvasChanged() {
    if (_revealed case final revealed?
        when !_controller.selection.contains(revealed.elementId)) {
      _update(() => _revealed = null);
    }
    final tool = _controller.tool;
    if (tool.draws) _lastInkTool = tool;
    _syncBoxFormatting();

    final editingId = _editingId;
    final editing = editingId == null
        ? null
        : _controller.elementById(editingId);
    if (editingId != null && editing == null) {
      final caret = _caretBefore;
      if (caret != null && caret.id == editingId) {
        // Undo took back the first words written at the caret: it is a
        // caret again.
        _placed.add(editingId);
        _controller.addElement(caret, recordUndo: false, markDirty: false);
        return;
      }
      // The box was removed from under the caret — by undo, say.
      _editingId = null;
      _placed.remove(editingId);
      if (mounted) _update(() {});
    } else if (editingId != null &&
        _placed.contains(editingId) &&
        !_holdsNothing(editingId)) {
      // Redo wrote the words back: a box again.
      _placed.remove(editingId);
      _controller.select(editingId);
      return;
    }
    final selection = _controller.selection;
    // Anything else picked on the page — by a drag across the paper, say —
    // ends typing in the box, and stays picked.
    if (editingId != null &&
        selection.isNotEmpty &&
        !(selection.length == 1 && selection.contains(editingId))) {
      _stopEditing(keepSelection: true);
    }

    // Until the page has been read, the canvas still holds the one before.
    // The save waits for a pause in the editing, not in the scrolling.
    final pageId = widget.pageId;
    final document = _controller.document;
    if (pageId == null ||
        !_ready ||
        !_controller.isDirty ||
        identical(document, _autosaveFor)) {
      return;
    }
    _autosaveFor = document;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      unawaited(_persist(pageId, _controller.document));
    });
  }

  Future<void> _openFile(BlockEmbed file) async {
    final store = _store;
    if (store == null) return;
    if (!await openAttachedFile(store, file) && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showPlainSnackBar(
        const SnackBar(content: Text('The file could not be opened.')),
      );
    }
  }

  Future<void> _saveFile(BlockEmbed file) async {
    final store = _store;
    if (store != null) await saveAttachedFile(store, file);
  }

  /// Saves the open page now, if it has changes, finishing when it has: as
  /// the app does before it stops.
  Future<void> _saveOpenPage() async {
    final pageId = widget.pageId;
    if (pageId == null || !_ready || !_controller.isDirty) return;
    _autosave?.cancel();
    await _persist(pageId, _controller.document);
  }

  /// Takes in a change another computer made to the open page: shows it,
  /// if nothing has been changed here; otherwise keeps it as a page of its
  /// own before this one's changes are saved over it, and says so.
  Future<void> _onChangedElsewhere(FolderChanges? changes) async {
    final pageId = widget.pageId;
    if (changes == null || pageId == null || !changes.pages.contains(pageId)) {
      return;
    }
    if (!_ready || !_controller.isDirty) {
      _views[pageId] = _controller.viewport;
      await _load();
      return;
    }
    final store = _store;
    if (store == null) return;
    final kept = await store.pages.keepVersion(
      pageId,
      note: 'changed elsewhere',
    );
    _libraryRevision.bump();
    if (!mounted || kept == null) return;
    ScaffoldMessenger.maybeOf(context)?.showPlainSnackBar(
      SnackBar(
        content: Text(
          'This page was changed on another computer while you were '
          'editing it. Their version is kept as “${kept.title}”.',
        ),
      ),
    );
  }

  /// Saves the open page now, as Ctrl+S does.
  void _saveNow() {
    final pageId = widget.pageId;
    if (pageId == null || !_ready) return;
    _autosave?.cancel();
    unawaited(_persist(pageId, _controller.document));
  }

  /// Writes [document] to disk.
  ///
  /// Also called from [dispose] for the final save, so it touches neither
  /// `ref` nor the widget once the widget is gone.
  Future<void> _persist(String pageId, PageDocument document) async {
    final store = _store;
    // Nothing can have been edited on a page that never loaded.
    if (store == null) return;
    if (!_disposed) _saving.value = true;
    try {
      // A caret placed is not saved: it is nothing yet.
      await store.pages.saveDocument(
        pageId,
        _placed.isEmpty ? document : document.withElementsRemoved(_placed),
      );
      if (!_disposed && pageId == widget.pageId) {
        _controller.markSaved(document);
        // A save that failed before has now been made good.
        if (_error != null) _update(() => _error = null);
      }
      // The page list shows previews derived from the body, so it has to be
      // refreshed once the save lands.
      _contentsRevision.bump();
    } on Object catch (error) {
      if (!_disposed) {
        _update(() => _error = 'This page could not be saved: $error');
      }
    } finally {
      if (!_disposed) _saving.value = false;
    }
  }
}
