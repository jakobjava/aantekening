part of 'page_editor.dart';

/// Text boxes on the page: placing a caret, typing, and the formula being
/// typed in one.
extension _TextEditing on _PageEditorState {
  /// Makes [id] the text box with the caret.
  void _startEditing(String id, {bool inFormula = false}) {
    if (_editingId == id) return;
    _stopEditing();
    _update(() {
      _editingId = id;
      _editingStartsInFormula = inFormula;
    });
    // An empty box is only a caret on the paper: it gets its outline and
    // handles once something is written in it.
    if (_placed.contains(id)) {
      _controller.clearSelection();
    } else {
      _controller.select(id);
    }
  }

  /// Lets the ribbon's formatting apply to whole text boxes while they are
  /// selected and none is being edited.
  void _syncBoxFormatting() {
    final document = _controller.document;
    final selection = _controller.selection;
    if (identical(document, _formattedDocument) &&
        setEquals(selection, _formattedSelection)) {
      return;
    }
    _formattedDocument = document;
    _formattedSelection = selection;
    final hasBoxes = selection.any(
      (id) => _controller.elementById(id) is TextElement,
    );
    _textController.setFallback(
      hasBoxes ? _boxFormatting : null,
      hasBoxes ? _boxFormatting.state : TextFormatState.none,
    );
  }

  /// Whether the box [id] holds nothing: a caret placed, or a box whose
  /// text has all been deleted.
  bool _holdsNothing(String id) {
    final element = _controller.elementById(id);
    return element is TextElement && TextBoxEditor.isEmpty(element.blocks);
  }

  /// Ends text editing, removing the box if it holds nothing; the box is
  /// let go of too, unless [keepSelection] — it was picked with others.
  ///
  /// All of it happens now, not as the page rebuilds: the box finishes what
  /// it has open first, so what it holds is known.
  void _stopEditing({bool refocusCanvas = true, bool keepSelection = false}) {
    final id = _editingId;
    if (id == null) return;
    _textController.finishEditing();
    _update(() => _editingId = null);
    _caretBefore = null;
    final placed = _placed.remove(id);
    if (_holdsNothing(id)) {
      // Undone, a box emptied comes back with what it last held; a caret
      // placed was never anything, and nothing of it is saved.
      _controller.removeElements(
        <String>{id},
        recordUndo: false,
        markDirty: !placed,
      );
    } else if (!keepSelection && _controller.selection.contains(id)) {
      _controller.clearSelection();
    }
    if (refocusCanvas) _canvasFocus.requestFocus();
  }

  /// Places a caret at [page]: an empty text box, invisible until something
  /// is typed, whose first line starts there. It widens with its text, as a
  /// new OneNote container does.
  String _createTextBox(Offset page) {
    final box = _newTextBox(page);
    _placed.add(box.id);
    _controller.addElement(box, recordUndo: false, markDirty: false);
    return box.id;
  }

  void _onEmptyTap(Offset page) {
    _stopEditing(refocusCanvas: false);
    _startEditing(_createTextBox(page));
  }

  void _onCanvasPress(NoteElement? hit) {
    // Paper pressed with the select tool is not yet known to leave the box: a
    // click there places a caret, and a drag picks what it passes over, each
    // ending the typing as it happens. Ending it on the press left the ribbon
    // with nothing to format, greyed, for as long as the button was down.
    if (hit == null && _controller.tool == CanvasTool.select) return;
    if (hit?.id != _editingId) _stopEditing();
    _canvasFocus.requestFocus();
  }

  bool _claimsPointer(NoteElement element, Offset page) =>
      element is TextElement && !TextBoxEditor.isInGrabBand(element, page);

  /// A selected text box is picked up by its band even under another box.
  bool _grips(NoteElement element, Offset page) =>
      element is TextElement &&
      element.frame.containsPoint(
        page.dx,
        page.dy,
        slop: CanvasController.hitSlop,
      ) &&
      TextBoxEditor.isInGrabBand(element, page);

  void _onTextChanged(
    String id,
    List<TextBlock> blocks, {
    required bool recordUndo,
  }) {
    final element = _controller.elementById(id);
    if (element is! TextElement) return;
    final changed = element.copyWith(
      blocks: blocks,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final written = !TextBoxEditor.isEmpty(blocks);
    if (!_placed.contains(id)) {
      _controller.replaceElement(changed, recordUndo: recordUndo);
    } else if (!written) {
      // A formula begun at a caret, say: still nothing to keep.
      _controller.replaceElement(changed, recordUndo: false, markDirty: false);
      return;
    } else {
      // The first thing written at a caret makes it a box, with its outline
      // and handles, arriving in history now.
      _placed.remove(id);
      _caretBefore = element;
      _controller.replacePlaceholder(changed);
    }
    if (written && id == _editingId && !_controller.selection.contains(id)) {
      _controller.select(id);
    }
  }

  void _onTextSizeChanged(String id, Size size) {
    final element = _controller.elementById(id);
    if (element is! TextElement) return;
    final frame = element.frame;
    _controller.replaceElement(
      // copyWith rather than withFrame: fitting the text is not the user
      // resizing the box, so a box that widens with its text keeps doing so.
      // It grows from its top-left corner, where its text starts, even when
      // turned.
      element.copyWith(
        frame: frame.resizedFromTopLeft(
          element.autoWidth ? size.width : frame.width,
          size.height,
        ),
      ),
      // Growing with the text belongs to the edit that caused it, and a box
      // measuring itself on first layout is not an edit at all.
      recordUndo: false,
      markDirty: false,
    );
  }

  /// A formula opening brings the Math tab forward, as Office does with its
  /// equation tools; finishing it goes back to where the ribbon was.
  void _onFormulaChanged() {
    final open = _textController.formulaField.value != null;
    if (open != _formulaOpen) {
      _update(() => _formulaOpen = open);
      final ribbon = ref.read(ribbonProvider.notifier);
      final tab = ref.read(ribbonProvider).tab;
      if (open) {
        if (tab != RibbonTab.math) {
          _tabBeforeMath = tab;
          ribbon.show(RibbonTab.math);
        }
      } else {
        final before = _tabBeforeMath;
        _tabBeforeMath = null;
        if (before != null && tab == RibbonTab.math) ribbon.show(before);
      }
    }
  }

  /// Puts a structure or symbol from the ribbon into the formula being
  /// edited, or into a new one.
  void _insertMath(MathTemplate template) {
    if (_textController.isActive) {
      _textController.insertMath(template);
      return;
    }
    _textController.queueMath(template);
    _insertFormula();
  }

  /// Places a caret in the middle of the view, for typing without first
  /// clicking the page.
  void _insertTextBox() {
    _stopEditing(refocusCanvas: false);
    _controller.setTool(CanvasTool.select);
    final center = _controller.viewCenter;
    _startEditing(
      _createTextBox(
        Offset(center.dx - TextBoxEditor.newBoxSize.width / 2, center.dy),
      ),
    );
  }

  /// Writes a formula: in the box being edited, or in a new box in view.
  void _insertFormula() {
    if (_textController.isActive) {
      _textController.toggleFormula();
      return;
    }
    _controller.setTool(CanvasTool.select);
    final center = _controller.viewCenter;
    final id = _createTextBox(
      Offset(center.dx - TextBoxEditor.newBoxSize.width / 2, center.dy),
    );
    _startEditing(id, inFormula: true);
  }

  /// Asks for LaTeX, and puts what it writes — text, formulas, lists,
  /// tables — into the box being edited at its caret, or into a box of its
  /// own in the middle of the view.
  Future<void> _insertLatex() async {
    final source = await askForLatex(context);
    if (source == null || !mounted) return;
    final blocks = LatexText.read(source).blocks;
    if (blocks.isEmpty) return;
    if (_textController.isActive) {
      _textController.insertBlocks(blocks);
      return;
    }
    _controller.setTool(CanvasTool.select);
    final center = _controller.viewCenter;
    final box = _newTextBox(
      Offset(center.dx - TextBoxEditor.maxAutoWidth / 2, center.dy),
      blocks: blocks,
    );
    _controller
      ..addElement(box)
      ..select(box.id);
  }
}

/// Where a new box's text starts from its top-left corner: where the
/// click that placed its caret was.
final Offset _textOrigin = Offset(
  TextBoxEditor.padding.left,
  TextBoxEditor.grabBand + 10,
);

/// A text box whose first line starts at [page], holding [blocks], that
/// widens with its text.
TextElement _newTextBox(
  Offset page, {
  List<TextBlock> blocks = const <TextBlock>[TextBlock()],
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return TextElement(
    id: Ulid.generate(),
    frame: Frame(
      x: page.dx - _textOrigin.dx,
      y: page.dy - _textOrigin.dy,
      width: TextBoxEditor.newBoxSize.width,
      height: TextBoxEditor.newBoxSize.height,
    ),
    createdAt: now,
    updatedAt: now,
    blocks: blocks,
    autoWidth: true,
  );
}
