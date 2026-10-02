part of 'page_editor.dart';

/// What each element on the page is shown with, and the word a search
/// brings into view.
extension _Elements on _PageEditorState {
  /// The text box holding the first word [highlight] finds, reading down the
  /// page: the one brought into view.
  String? _firstMatchIn(SearchTerms? highlight) {
    if (highlight == null) return null;
    final document = _controller.document;
    if (identical(document, _matchedDocument) &&
        identical(highlight, _matchedTerms)) {
      return _firstMatch;
    }
    _matchedDocument = document;
    _matchedTerms = highlight;
    final boxes = document.elements.whereType<TextElement>().toList()
      ..sort((a, b) {
        final byTop = a.bounds.top.compareTo(b.bounds.top);
        return byTop != 0 ? byTop : a.bounds.left.compareTo(b.bounds.left);
      });
    return _firstMatch = boxes
        .where(
          (box) => box.blocks.any(
            (block) => TextBoxEditor.matchesIn(block, highlight).isNotEmpty,
          ),
        )
        .firstOrNull
        ?.id;
  }

  /// Scrolls to [local], where a match lies in [element], in its own units.
  void _revealMatch(NoteElement element, Rect local) {
    final toPage = element.frame.localToPage;
    var bounds = Aabb.empty;
    for (final corner in <Offset>[
      local.topLeft,
      local.topRight,
      local.bottomLeft,
      local.bottomRight,
    ]) {
      final page = toPage.apply(corner.dx, corner.dy);
      bounds = bounds.union(Aabb(page.x, page.y, page.x, page.y));
    }
    _controller.reveal(bounds);
  }

  Widget? _buildElement(
    NoteElement element,
    SearchTerms? highlight,
    String? firstMatch,
  ) {
    final id = element.id;
    final isEditing = id == _editingId;
    final built = (
      element: element,
      isEditing: isEditing,
      selected: _controller.selection.contains(id),
      grouped:
          _controller.selection.length > 1 &&
          _controller.selection.contains(id),
      caretOnly: _onlyCaret(id),
      startsInFormula: isEditing && _editingStartsInFormula,
      interactive: _controller.tool == CanvasTool.select,
      highlight: element is TextElement ? highlight : null,
      mark: _revealed?.elementId == id ? _revealed!.words : null,
      proofreader: element is TextElement ? _proofreader : null,
      placesMatch: id == firstMatch,
    );
    final cached = _elementWidgets[id];
    if (cached != null && cached.$1 == built) return cached.$2;
    if (_elementWidgets.length > _controller.document.elements.length + 64) {
      _elementWidgets.removeWhere(
        (key, _) => _controller.elementById(key) == null,
      );
    }
    final widget = _elementWidget(built);
    _elementWidgets[id] = (built, widget);
    return widget;
  }

  Widget _elementWidget(_ElementBuild built) {
    final element = built.element;
    if (element is! TextElement) return CanvasElementView(element: element);
    final id = element.id;
    return TextBoxEditor(
      element: element,
      isEditing: built.isEditing,
      selected: built.selected,
      grouped: built.grouped,
      caretOnly: built.caretOnly,
      controller: _textController,
      interactive: built.interactive,
      startInFormula: built.startsInFormula,
      highlight: built.highlight,
      mark: built.mark,
      proofreader: built.proofreader,
      onMatchPlaced: built.placesMatch
          ? (local) => _revealMatch(element, local)
          : null,
      onStartEditing: () => _startEditing(id),
      onChanged: (blocks, {required recordUndo}) =>
          _onTextChanged(id, blocks, recordUndo: recordUndo),
      onSizeChanged: (size) => _onTextSizeChanged(id, size),
      onExit: _stopEditing,
      onPasteElements: _pasteFromBox,
      onEmbedToBackground: (block, local) =>
          _embedToBackground(id, block, local),
      onOpenFile: (file) => unawaited(_openFile(file)),
      onSaveFile: (file) => unawaited(_saveFile(file)),
      pageId: widget.pageId,
      onOpenLink: (uri) => unawaited(ref.read(noteLinksProvider).open(uri)),
    );
  }
}
