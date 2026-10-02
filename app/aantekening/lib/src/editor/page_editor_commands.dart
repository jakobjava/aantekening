part of 'page_editor.dart';

/// The page's commands and the keys that run them.
extension _Commands on _PageEditorState {
  /// Whether a page is showing, for the page's commands to act on.
  bool get _pageShowing => _ready && widget.aiScope == null;

  /// Shows the page as pages, or as one canvas, whichever it is not.
  void _toggleLayout() {
    _stopEditing();
    _controller.setLayout(
      _controller.fold == null ? NoteLayout.pages : NoteLayout.canvas,
    );
  }

  /// Asks what the sheet to add after the one at [after] is printed with —
  /// as that one is, unless another is chosen — then adds it, and shows it.
  Future<void> _addSheet({required int after}) async {
    final sheets = _controller.document.canvas.sheetsShown;
    if (sheets == null) return;
    final template = await chooseSheetTemplate(
      context,
      title: 'Add a sheet after sheet ${after + 1}',
      selected: sheets.templates[after],
      size: sheets.size,
      action: 'Add',
    );
    if (template == null || !mounted) return;
    _controller
      ..insertSheet(after + 1, template)
      ..reveal(sheets.bandOf(after + 1));
  }

  /// Whether the sheet in view can move [by] one, up or down.
  bool _canMoveSheet(int by) {
    final fold = _controller.fold;
    if (fold == null) return false;
    final to = _controller.currentSheet + by;
    return to >= 0 && to < fold.count;
  }

  /// Moves the sheet in view [by] one, up or down, and follows it.
  void _moveSheet(int by) {
    if (!_canMoveSheet(by)) return;
    final to = _controller.currentSheet + by;
    _controller
      ..moveSheet(to - by, to)
      ..reveal(_controller.document.canvas.sheetsShown!.bandOf(to));
  }

  /// Takes away the sheet in view, saying so, with a way to put it back.
  void _deleteSheet() {
    final sheet = _controller.currentSheet;
    _controller.removeSheet(sheet);
    ScaffoldMessenger.maybeOf(context)
        ?.showUndoable('Sheet ${sheet + 1} is deleted.', _controller.undo);
  }

  /// Page-level shortcuts: those of editing what is on the page, and the
  /// page's commands bound to keys the window does not catch — plain
  /// letters, and those typing takes. A text box being edited has them
  /// first, so typing never switches tools.
  Map<ShortcutActivator, VoidCallback> _shortcuts(
    ShortcutBindings bindings,
  ) => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
        _controller.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        _controller.redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true):
        _controller.redo,
    const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
    const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelection,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      _stopEditing();
      _controller.clearSelection();
    },
    const SingleActivator(LogicalKeyboardKey.keyM): _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.keyM, control: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.equal, alt: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
        unawaited(_copySelection()),
    const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
        unawaited(_copySelection(cut: true)),
    const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
        unawaited(_paste()),
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      shift: true,
    ): () =>
        unawaited(_paste(textOnly: true)),
    const SingleActivator(LogicalKeyboardKey.keyA, control: true):
        _selectEverything,
    for (final (key, direction)
        in _arrows) ...<ShortcutActivator, VoidCallback>{
      SingleActivator(key): () => _nudge(direction),
      SingleActivator(key, shift: true): () => _nudge(direction * 10),
    },
    for (final MapEntry(key: command, value: action) in _pageCommands.entries)
      for (final chord in bindings.of(command))
        if (!chord.worksAnywhere) chord.activator: action.run,
  };

  static const List<(LogicalKeyboardKey, Offset)> _arrows =
      <(LogicalKeyboardKey, Offset)>[
        (LogicalKeyboardKey.arrowLeft, Offset(-1, 0)),
        (LogicalKeyboardKey.arrowRight, Offset(1, 0)),
        (LogicalKeyboardKey.arrowUp, Offset(0, -1)),
        (LogicalKeyboardKey.arrowDown, Offset(0, 1)),
      ];

  /// Moves the selection by [delta] page units, as the arrow keys do.
  void _nudge(Offset delta) {
    if (_editingId != null) return;
    _controller.translateSelection(delta);
  }

  void _deleteSelection() {
    // The box being edited is selected so its handles show, but a key that
    // reaches the page while it has lost focus must not delete it.
    if (_editingId != null) return;
    _controller.deleteSelection();
  }

  /// Selects everything on the page. Reached from a text box only where it
  /// had nothing left to select, whose caret goes as the page takes over.
  void _selectEverything() {
    _stopEditing();
    _controller
      ..setTool(CanvasTool.select)
      ..selectEverything();
  }

  /// Takes up [tool], from the ribbon.
  void _selectTool(CanvasTool tool) {
    if (tool != CanvasTool.select) _stopEditing();
    _controller.setTool(tool);
  }

  /// Takes up [tool] from its shortcut, and shows its tab: Draw for the pens
  /// and the eraser, Home — with the text formatting — for typing.
  void _useTool(CanvasTool tool) {
    _selectTool(tool);
    ref
        .read(ribbonProvider.notifier)
        .show(tool == CanvasTool.select ? RibbonTab.home : RibbonTab.draw);
  }

  void _formulaShortcut() => _insertFormula();
}
