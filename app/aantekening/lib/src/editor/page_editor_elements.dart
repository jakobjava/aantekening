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
    // A picture moved or resized is shown by the widget it had: drawing a
    // TikZ picture again as it is dragged would keep it behind the pointer.
    final cached = _elementWidgets[id];
    if (cached != null &&
        (cached.$1 == built ||
            CanvasElementView.showsAlike(cached.$1.element, element))) {
      return cached.$2;
    }
    if (_elementWidgets.length > _controller.document.elements.length + 64) {
      _elementWidgets.removeWhere(
        (key, _) => _controller.elementById(key) == null,
      );
    }
    final widget = _elementWidget(built);
    _elementWidgets[id] = (built, widget);
    return widget;
  }

  /// Fits the frame of the TikZ picture [id], drawn [drawn] large unscaled,
  /// to its drawing once its source has changed, keeping its width and
  /// keeping it as far out of its drawing's proportions as it was:
  /// stretched, or not. Otherwise the frame stays as it was made or
  /// resized, and the picture fills it, as a stretched picture does.
  void _fitTikz(String id, Size drawn) {
    final before = _tikzDrawn[id];
    _tikzDrawn[id] = drawn;
    final changed = _tikzChanged.remove(id);
    final picture = _controller.elementById(id);
    if (picture is! TikzElement ||
        drawn.isEmpty ||
        changed == null ||
        before == null ||
        before.isEmpty) {
      return;
    }
    final frame = picture.frame;
    // Unless something else has resized it since: undone, say.
    if (changed != Size(frame.width, frame.height)) return;
    final height =
        frame.height *
        (drawn.height / drawn.width) /
        (before.height / before.width);
    if ((height - frame.height).abs() < 0.5) return;
    // What the drawing makes it, not an edit of its own.
    _controller.replaceElement(
      picture.withFrame(frame.copyWith(height: height)),
      recordUndo: false,
      markDirty: false,
    );
  }

  /// Notes that the source of [picture] is about to change, for its frame
  /// to be fitted to what it then draws.
  void _changingTikz(TikzElement picture) => _tikzChanged[picture.id] = Size(
    picture.frame.width,
    picture.frame.height,
  );

  Widget _elementWidget(_ElementBuild built) {
    final element = built.element;
    if (element is! TextElement) {
      return CanvasElementView(
        element: element,
        onDrawn: element is TikzElement
            ? (drawn) => _fitTikz(element.id, drawn)
            : null,
      );
    }
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
