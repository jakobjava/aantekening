part of 'page_editor.dart';

/// Cutting, copying and pasting what is on the page, and the menu a
/// right-click on it opens.
extension _Clipboard on _PageEditorState {
  /// Copies the things picked on the page, or cuts them. Text being edited
  /// is copied by its box.
  Future<void> _copySelection({bool cut = false}) async {
    if (_editingId != null) return;
    final selected = _controller.selectedElements;
    if (selected.isEmpty) return;
    await NoteClipboard.copy(ElementsClip(selected));
    if (cut && mounted) _controller.deleteSelection();
  }

  /// Pastes what was copied — as it was, or as its text only — onto the
  /// page: things from the page as copies of them, pictures and PDF pages
  /// from a box as themselves, text in a new box. With
  /// [at], a place on the page, that is where it goes; else copies go a step
  /// on from what they copy, and a box into the middle of the view.
  Future<void> _paste({Offset? at, bool textOnly = false}) async {
    if (_editingId != null || !_ready) return;
    final clip = textOnly
        ? await NoteClipboard.readText()
        : await NoteClipboard.read();
    if (clip == null || !mounted) return;
    switch (clip) {
      case ElementsClip(:final elements):
        _pasteElements(elements, at: at);
      // Pictures and PDF pages alone go on the page by themselves.
      case TextClip(:final asElements?):
        _pasteElements(asElements, at: at ?? _controller.viewCenter);
      case TextClip(:final blocks):
        _pasteBox(blocks, at: at);
      case PlainClip(:final plain):
        _pasteBox(<TextBlock>[
          for (final line in plain.replaceAll('\r\n', '\n').split('\n'))
            TextBlock.plain(line),
        ], at: at);
    }
  }

  /// Copies of [elements] on the page, at [at] or a step on from them.
  void _pasteElements(List<NoteElement> elements, {Offset? at}) {
    final Vec2 offset;
    if (at != null) {
      final bounds = NoteElement.boundsOf(elements);
      offset = Vec2(at.dx - bounds.left, at.dy - bounds.top);
    } else {
      _pasteCount = identical(elements, _pasted) ? _pasteCount + 1 : 1;
      _pasted = elements;
      offset = Vec2(24.0 * _pasteCount, 24.0 * _pasteCount);
    }
    final copies = NoteElement.copiesOf(
      elements,
      now: DateTime.now().millisecondsSinceEpoch,
      offset: offset,
    );
    _controller
      ..setTool(CanvasTool.select)
      ..addElements(copies)
      ..selectAll(copies.map((element) => element.id));
  }

  /// Things from the page that the box being edited passed on rather than
  /// take into its text: pasted at its caret, in place of the box, where it
  /// is a bare caret on the paper, else a step on from what they copy.
  void _pasteFromBox(List<NoteElement> elements) {
    final id = _editingId;
    final box = id == null ? null : _controller.elementById(id);
    if (box is! TextElement || !TextBoxEditor.isEmpty(box.blocks)) {
      _pasteElements(elements);
      return;
    }
    // The empty box goes as the typing ends.
    _stopEditing();
    _pasteElements(
      elements,
      at: Offset(box.frame.x, box.frame.y) + _textOrigin,
    );
  }

  /// A new box holding [blocks], at [at] or in the middle of the view.
  void _pasteBox(List<TextBlock> blocks, {Offset? at}) {
    final box = _newTextBox(at ?? _controller.viewCenter, blocks: blocks);
    _controller
      ..setTool(CanvasTool.select)
      ..addElement(box)
      ..select(box.id);
  }

  /// Takes the picture or PDF page on block [block] of the box [boxId] out
  /// of it, to lie where it is, [local] in the box's own units, as part of
  /// the page's background. A box left empty goes with it.
  void _embedToBackground(String boxId, int block, Rect local) {
    final box = _controller.elementById(boxId);
    if (box is! TextElement || block >= box.blocks.length) return;
    final embed = box.blocks[block].embed;
    if (embed == null) return;
    final center = box.frame.localToPage.apply(
      local.center.dx,
      local.center.dy,
    );
    final picture = embed.toElement(
      frame: Frame(
        x: center.x - local.width / 2,
        y: center.y - local.height / 2,
        width: local.width,
        height: local.height,
        rotation: box.frame.rotation,
      ),
      now: DateTime.now().millisecondsSinceEpoch,
    );
    final rest = RichTextEditing.deleteEmbed(box.blocks, block).blocks;
    if (TextBoxEditor.isEmpty(rest)) {
      if (_editingId == boxId) _stopEditing();
      _controller.removeElements(<String>{boxId});
    } else {
      _controller.replaceElement(box.copyWith(blocks: rest));
    }
    // One undo step for all of it.
    _controller
      ..addElement(picture, recordUndo: false)
      ..setBackground(picture.id, background: true, recordUndo: false);
  }

  /// Opens the source of the TikZ picture [id] in a window of its own, the
  /// picture drawn again as it changes, one undo step for it all. Emptied,
  /// the picture goes.
  Future<void> _editTikz(String id) async {
    final picture = _controller.elementById(id);
    if (picture is! TikzElement) return;
    var recorded = false;
    await editTikzSource(
      context,
      source: picture.source,
      onChanged: (source) {
        final current = _controller.elementById(id);
        if (current is! TikzElement) return;
        _changingTikz(current);
        _controller.replaceElement(
          current.copyWith(
            source: source,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          recordUndo: !recorded,
        );
        recorded = true;
      },
    );
    final edited = _controller.elementById(id);
    if (edited is TikzElement && edited.source.trim().isEmpty) {
      _controller.removeElements(<String>{id});
    }
  }

  /// Picks what is right-clicked — or nothing, on the bare paper — and
  /// opens the menu for what is picked or, on the paper, the picture set
  /// as the background there.
  void _onContextMenu(Offset page, Offset global) {
    _menuPoint = page;
    final hit = _controller.hitTest(page);
    if (_controller.pressesGroup(page, hit)) {
      // Nothing being typed in is picked along with other things.
    } else if (hit == null) {
      _stopEditing();
      _controller.clearSelection();
    } else if (hit.id == _editingId ||
        !_controller.selection.contains(hit.id)) {
      _stopEditing();
      _controller.select(hit.id);
    }
    _openMenu(clicked: true);
  }
}
