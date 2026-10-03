part of 'text_box_editor.dart';

/// Editing the text: typing, deleting and breaking lines, each change
/// committed and reported.
extension _Typing on TextBoxEditorState {
  /// Commits an edit: shows it, reports it, and keeps the IME in step.
  void _commit(RichEdit edit, EditKind kind) {
    final record = _undoSteps.startsStep(kind);

    _update(() {
      _blocks = _wellFormed(edit.blocks);
      _selection = RichSelection(
        RichTextEditing.clamp(_blocks, edit.selection.base),
        RichTextEditing.clamp(_blocks, edit.selection.extent),
      );
      _affinity = TextAffinity.downstream;
    });
    _emitStored(record: record);
    _afterChange();
    if (_formula != null) _reportFormula();
  }

  /// Reports the text as it is stored — the open formula as LaTeX — to the
  /// page.
  void _emitStored({required bool record}) {
    final stored = _stored(_blocks);
    _lastEmitted = stored;
    widget.onChanged?.call(stored, recordUndo: record);
  }

  /// Moves the selection without changing the text.
  void _select(
    RichSelection selection, {
    bool keepGoalX = false,
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final clamped = RichSelection(
      RichTextEditing.clamp(_blocks, selection.base),
      RichTextEditing.clamp(_blocks, selection.extent),
    );
    // Leaving a formula finishes it, removing it if nothing was typed.
    final formula = _formula;
    if (formula != null && !_formulaContains(formula, clamped)) {
      _closeFormula(emit: true, caretOverride: clamped);
      return;
    }
    _update(() {
      _selection = clamped;
      _affinity = affinity;
      _pendingMarks = null;
      if (!keepGoalX) _goalX = null;
    });
    _undoSteps.breakStep();
    _afterChange();
  }

  void _afterChange() {
    _restartBlink();
    _input.sync();
    _publishState();
  }

  bool _formulaContains(_OpenFormula formula, RichSelection selection) {
    final span = _formulaSpan(formula);
    if (span == null) return false;
    bool inside(RichPosition p) =>
        p.block == formula.block &&
        p.offset >= span.start &&
        p.offset <= span.end;
    return inside(selection.base) && inside(selection.extent);
  }

  RunSpan? _formulaSpan(_OpenFormula formula) {
    if (formula.block >= _blocks.length) return null;
    final block = _blocks[formula.block];
    if (formula.run >= block.runs.length || !block.runs[formula.run].isMath) {
      return null;
    }
    return RichTextEditing.runSpans(block)[formula.run];
  }

  BlockView _viewFor(int index) => BlockView(
    _blocks[index],
    openRun: _formula?.block == index ? _formula!.run : null,
  );

  void _insertText(String text) {
    if (text.isEmpty) return;
    if (_formula != null) {
      _replaceInFormula(text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
      return;
    }

    // "$$" opens a LaTeX formula, the way Markdown notes write one.
    if (text == r'$' && _selection.isCollapsed && _charBeforeCaret() == r'$') {
      final caret = _selection.extent;
      final removed = RichTextEditing.deleteRange(
        _blocks,
        RichSelection(RichPosition(caret.block, caret.offset - 1), caret),
      );
      _commit(removed, EditKind.typing);
      _chooseSyntax(MathMode.latex);
      _startFormula();
      return;
    }

    final lines = text.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) _paragraphBreak();
      final line = lines[i];
      if (line.isEmpty) continue;
      final marks = _typingMarks();
      final pending = _pendingMarks;
      _commit(
        _centringKeptToFormula(
          _selection.start.block,
          RichTextEditing.insertText(_blocks, _selection, line, marks: marks),
        ),
        EditKind.typing,
      );
      _pendingMarks = pending;
      if (line == ' ') {
        final shortcut = RichTextEditing.applyMarkdownShortcut(
          _blocks,
          _selection.extent,
        );
        if (shortcut != null) _commit(shortcut, EditKind.other);
      }
    }
  }

  String? _charBeforeCaret() {
    final caret = _selection.extent;
    final block = _blocks[caret.block];
    if (block.isEmbed || caret.offset == 0) return null;
    final view = _viewFor(caret.block);
    final v = view.toView(caret.offset);
    return v == 0 ? null : view.text[v - 1];
  }

  void _paragraphBreak() {
    _commit(
      TableEditing.insertBreak(_blocks, _selection) ??
          _centringKeptToFormula(
            _selection.start.block,
            RichTextEditing.insertParagraphBreak(_blocks, _selection),
          ),
      EditKind.other,
    );
  }

  /// Tab: on to another cell of a table, or a table started after a word,
  /// or else the list indented — and Shift+Tab back.
  void _tab({required bool backward}) {
    final edit =
        TableEditing.moveToCell(_blocks, _selection, backward: backward) ??
        (backward ? null : TableEditing.startTable(_blocks, _selection));
    if (edit == null) {
      indent(backward ? -1 : 1);
    } else if (identical(edit.blocks, _blocks)) {
      _select(edit.selection);
    } else {
      _commit(edit, EditKind.other);
    }
  }

  void _deleteSelection() {
    final start = _selection.start;
    final end = _selection.end;
    // Deleting exactly one object removes its line too, rather than leaving an
    // empty paragraph where the picture was.
    if (start.block == end.block &&
        _blocks[start.block].isEmbed &&
        start.offset == 0 &&
        end.offset == 1) {
      _commit(
        RichTextEditing.deleteEmbed(_blocks, start.block),
        EditKind.deleting,
      );
      return;
    }
    // Selected cells go as selected text does: rows and columns taken in
    // whole go with them.
    _commit(
      RichTextEditing.deleteRange(_blocks, _selection, closeUp: true),
      EditKind.deleting,
    );
  }

  /// Deletes what is selected, or else a character, or a [word], [forward]
  /// of the caret or back from it. The first press that would eat into a
  /// formula selects it, and the second deletes it, so a formula is never
  /// lost to a stray keypress — as in OneNote.
  void _delete({required bool forward, bool word = false}) {
    if (_formula != null) {
      _deleteInFormula(forward: forward, word: word);
      return;
    }
    if (!_selection.isCollapsed) {
      _deleteSelection();
      return;
    }
    final caret = _selection.extent;
    final block = _blocks[caret.block];
    if (caret.offset == (forward ? block.length : 0)) {
      _commit(
        forward
            ? RichTextEditing.deleteForwardAtBlockEnd(_blocks, caret.block)
            : TableEditing.deleteBackward(_blocks, caret.block) ??
                  RichTextEditing.deleteBackwardAtBlockStart(
                    _blocks,
                    caret.block,
                  ),
        EditKind.deleting,
      );
      return;
    }
    if (block.isEmbed) {
      _commit(
        RichTextEditing.deleteEmbed(_blocks, caret.block),
        EditKind.deleting,
      );
      return;
    }
    final view = _viewFor(caret.block);
    final v = view.toView(caret.offset);
    final formula = view.collapsedAt(forward ? v : v - 1);
    if (formula != null) {
      final start = RichPosition(caret.block, formula.modelStart);
      final end = RichPosition(caret.block, formula.modelEnd);
      _select(forward ? RichSelection(start, end) : RichSelection(end, start));
      return;
    }
    final target = RichPosition(
      caret.block,
      view.toModel(
        TextBoundaries.step(view.text, v, forward: forward, word: word),
      ),
    );
    _commit(
      RichTextEditing.deleteRange(
        _blocks,
        forward ? RichSelection(caret, target) : RichSelection(target, caret),
      ),
      EditKind.deleting,
    );
  }

  /// The formatting what is typed next takes: what was chosen for it with
  /// nothing selected, or that of the text it is typed into.
  TextMarks _typingMarks() {
    final start = _selection.start;
    return _pendingMarks ??
        RichTextEditing.marksAt(_blocks[start.block], start.offset);
  }

  /// Applies [change] to the selection's formatting, to the formula being
  /// edited, or — with nothing selected — to whatever is typed next.
  void _changeMarks(TextMarks Function(TextMarks marks) change) {
    _focusNode.requestFocus();
    final formula = _formula;
    if (formula != null) {
      final run = _blocks[formula.block].runs[formula.run];
      _commit((
        blocks: RichTextEditing.replaceRun(
          _blocks,
          formula.block,
          formula.run,
          run.copyWith(marks: change(run.marks).forFormula),
        ),
        selection: _selection,
      ), EditKind.other);
      return;
    }
    if (_selection.isCollapsed) {
      _update(() => _pendingMarks = change(_typingMarks()));
      _publishState();
      return;
    }
    _commit((
      blocks: RichTextEditing.applyMarks(_blocks, _selection, change),
      selection: _selection,
    ), EditKind.other);
  }

  void _toggleChecked(int block) {
    if (_blocks[block].kind != TextBlockKind.todo) return;
    _undoSteps.breakStep();
    _commit((
      blocks: RichTextEditing.toggleChecked(_blocks, block),
      selection: _selection,
    ), EditKind.other);
  }
}
