part of 'text_box_editor.dart';

/// Moving the caret by character, word, line and paragraph.
extension _Movement on TextBoxEditorState {
  void _moveHorizontally(
    int direction, {
    required bool extend,
    required bool word,
  }) {
    if (!extend && !_selection.isCollapsed) {
      _select(
        RichSelection.collapsed(
          direction > 0 ? _selection.end : _selection.start,
        ),
      );
      return;
    }

    final forward = direction > 0;
    final caret = _selection.extent;
    final formula = _formula;
    if (formula != null) {
      final span = _formulaSpan(formula)!;
      final inward = !forward
          ? caret.offset > span.start
          : caret.offset < span.end;
      if (inward) {
        // In its source the caret moves as it does through any text.
        final source = _blocks[formula.block].runs[formula.run].text;
        final local = caret.offset - span.start;
        final to = TextBoundaries.step(
          source,
          local,
          forward: forward,
          word: word,
        );
        final target = RichPosition(formula.block, span.start + to);
        _select(RichSelection(extend ? _selection.base : target, target));
        return;
      }
      // At either end of its source the caret steps back out into the text,
      // and the formula is typeset again; a selection carries on into it.
      if (!extend) {
        _closeFormula(emit: true, after: forward);
        return;
      }
    }
    final block = _blocks[caret.block];
    RichPosition? target;
    if (caret.offset == (forward ? block.length : 0)) {
      // Past the end of the block, into the next.
      final next = caret.block + direction;
      if (next >= 0 && next < _blocks.length) {
        target = RichPosition(next, forward ? 0 : _blocks[next].length);
      }
    } else if (block.isEmbed) {
      target = RichPosition(caret.block, forward ? 1 : 0);
    } else {
      final view = _viewFor(caret.block);
      final v = view.toView(caret.offset);
      final formula = view.collapsedAt(forward ? v : v - 1);
      if (formula != null && !extend && !word) {
        // Arrowing into a formula opens it, so it can be edited from the
        // keyboard alone.
        _openFormula((block: caret.block, run: formula.index), atEnd: !forward);
        return;
      }
      final to = TextBoundaries.step(
        view.text,
        v,
        forward: forward,
        word: word,
      );
      target = RichPosition(caret.block, view.toModel(to));
    }
    if (target == null) {
      if (!extend) _select(RichSelection.collapsed(caret));
      return;
    }
    _select(RichSelection(extend ? _selection.base : target, target));
  }

  void _moveVertically(int direction, {required bool extend}) {
    if (_formula != null && !extend) _closeFormula(emit: true);
    final caret = _selection.extent;
    final target = _verticalTarget(caret, direction);
    _select(
      RichSelection(extend ? _selection.base : target, target),
      keepGoalX: true,
    );
  }

  RichPosition _verticalTarget(RichPosition caret, int direction) {
    final rect = _caretRectGlobal(caret);
    if (rect == null) return caret;
    final goalX = _goalX ??= rect.center.dx;

    // First try another line of the same block: a whole line up or down
    // from the middle of the caret's, which is drawn shorter than the line.
    final paragraph = _paragraph(caret.block);
    if (paragraph != null) {
      final localRect = _caretRectLocal(caret);
      if (localRect != null) {
        final view = _viewFor(caret.block);
        final line = paragraph.paragraph.getFullHeightForCaret(
          TextPosition(offset: view.toView(caret.offset)),
        );
        final y = localRect.center.dy + direction * line;
        if (y >= 0 && y < paragraph.size.height) {
          final local = paragraph.globalToLocal(Offset(goalX, 0));
          final position = paragraph.paragraph.getPositionForOffset(
            Offset(local.dx, y),
          );
          return RichPosition(caret.block, view.toModel(position.offset));
        }
      }
    }

    // Then the nearest line of the neighbouring block.
    final next = _lineBeside(caret.block, direction, goalX);
    if (next == null) {
      return RichPosition(
        caret.block,
        direction < 0 ? 0 : _blocks[caret.block].length,
      );
    }
    final block = _blocks[next];
    if (block.isEmbed) return RichPosition(next, direction < 0 ? 1 : 0);
    final target = _paragraph(next);
    if (target == null) return RichPosition(next, 0);
    final local = target.globalToLocal(Offset(goalX, 0));
    final y = direction < 0 ? target.size.height - 1 : 1.0;
    final position = target.paragraph.getPositionForOffset(Offset(local.dx, y));
    return RichPosition(next, _viewFor(next).toModel(position.offset));
  }

  /// The line the caret moves to from block [index], going up for a
  /// negative [direction] and down otherwise, past its first or last line:
  /// the next line of its cell, or the cell above or below it, or from
  /// outside a table into the cell of its nearest row under [goalX].
  int? _lineBeside(int index, int direction, double goalX) {
    final table = TextTables.tableAt(_blocks, index);
    if (table == null) {
      final next = index + direction;
      if (next < 0 || next >= _blocks.length) return null;
      final entered = TextTables.tableAt(_blocks, next);
      final box = entered == null ? null : _tableBox(entered);
      if (entered == null || box == null) return next;
      final cell = TextTables.cellIn(
        _blocks,
        entered,
        direction < 0 ? entered.rows - 1 : 0,
        box.columnAt(box.globalToLocal(Offset(goalX, 0)).dx),
      )!;
      return direction < 0 ? cell.end - 1 : cell.start;
    }
    final lines = TextTables.cellAt(_blocks, index);
    final within = index + direction;
    if (within >= lines.start && within < lines.end) return within;
    final cell = _blocks[index].cell!;
    final row = cell.row + direction;
    if (row < 0) return table.start > 0 ? table.start - 1 : null;
    if (row >= table.rows) {
      return table.end < _blocks.length ? table.end : null;
    }
    final target = TextTables.cellIn(_blocks, table, row, cell.column)!;
    return direction < 0 ? target.end - 1 : target.start;
  }

  void _moveToLineEdge({
    required bool start,
    required bool extend,
    required bool wholeBox,
  }) {
    final formula = _formula;
    RichPosition target;
    if (formula != null) {
      final span = _formulaSpan(formula)!;
      target = RichPosition(formula.block, start ? span.start : span.end);
    } else if (wholeBox) {
      target = start ? RichPosition.zero : RichTextEditing.endOf(_blocks);
    } else {
      final caret = _selection.extent;
      final paragraph = _paragraph(caret.block);
      final rect = _caretRectLocal(caret);
      if (_blocks[caret.block].isEmbed || paragraph == null || rect == null) {
        target = RichPosition(
          caret.block,
          start ? 0 : _blocks[caret.block].length,
        );
      } else {
        final position = paragraph.paragraph.getPositionForOffset(
          Offset(start ? 0 : paragraph.size.width, rect.center.dy),
        );
        target = RichPosition(
          caret.block,
          _viewFor(caret.block).toModel(position.offset),
        );
        if (!start) {
          _select(
            RichSelection(extend ? _selection.base : target, target),
            affinity: TextAffinity.upstream,
          );
          return;
        }
      }
    }
    _select(RichSelection(extend ? _selection.base : target, target));
  }
}
