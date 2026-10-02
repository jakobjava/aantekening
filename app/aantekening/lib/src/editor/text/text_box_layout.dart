part of 'text_box_editor.dart';

/// Where things are laid out: blocks, the caret, and what a point lands on.
extension _Layout on TextBoxEditorState {
  RenderBlockParagraph? _paragraph(int index) {
    if (index >= _contentKeys.length) return null;
    final object = _contentKeys[index].currentContext?.findRenderObject();
    return object is RenderBlockParagraph && object.hasSize ? object : null;
  }

  /// The picture or PDF page drawn on block [index], as it is laid out.
  RenderBox? _object(int index) {
    if (index >= _contentKeys.length || !_blocks[index].isEmbed) return null;
    final object = _contentKeys[index].currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  RenderBox? _row(int index) {
    if (index >= _rowKeys.length) return null;
    final object = _rowKeys[index].currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  Rect? _caretRectLocal(RichPosition position) {
    final paragraph = _paragraph(position.block);
    if (paragraph == null || _blocks[position.block].isEmbed) return null;
    final view = _viewFor(position.block);
    return paragraph.caretRect(
      view.toView(position.offset),
      _affinity,
      _typingStyle(position.block),
    );
  }

  /// The style text typed next into block [index] will have, where it was
  /// chosen with nothing selected: the caret there is drawn at its size.
  TextStyle? _typingStyle(int index) {
    final pending = _pendingMarks;
    if (pending == null || _formula != null) return null;
    final blockStyle = RichTextStyles.blockStyle(
      _blocks[index].kind,
      RichTextStyles.base(context),
    );
    final marks = RichTextStyles.runStyle(
      pending,
      link: context.tones.paperEmphasis,
    );
    return marks == null ? blockStyle : blockStyle.merge(marks);
  }

  Rect? _caretRectGlobal(RichPosition position) {
    if (_blocks[position.block].isEmbed) {
      final row = _row(position.block);
      if (row == null) return null;
      final x = position.offset == 0 ? 0.0 : row.size.width;
      return MatrixUtils.transformRect(
        row.getTransformTo(null),
        Rect.fromLTWH(x, 0, 1, row.size.height),
      );
    }
    final paragraph = _paragraph(position.block);
    final local = _caretRectLocal(position);
    if (paragraph == null || local == null) return null;
    return MatrixUtils.transformRect(paragraph.getTransformTo(null), local);
  }

  /// The laid-out grid of [table].
  RenderTextTable? _tableBox(TextTable table) {
    RenderObject? object = _row(table.start);
    while (object != null && object is! RenderTextTable) {
      object = object.parent;
    }
    return object is RenderTextTable ? object : null;
  }

  /// The lines a point at [global] can land on: those of the table cell it
  /// is in, or every line of the box.
  CellSpan _linesUnder(Offset global) {
    for (final table in TextTables.tablesIn(_blocks)) {
      final box = _tableBox(table);
      final cell = box?.cellAt(box.globalToLocal(global));
      if (cell != null) {
        return TextTables.cellIn(_blocks, table, cell.row, cell.column)!;
      }
    }
    return (start: 0, end: _blocks.length);
  }

  /// Finds the text position under a global point.
  _Hit? _hitTest(Offset global) {
    // The line closest to the point: the nearest above or below it, and of
    // those — the cells of a table's row lie side by side — the nearest
    // across.
    final lines = _linesUnder(global);
    var best = -1;
    var bestDistance = (double.infinity, double.infinity);
    double outside(double at, double length) =>
        at < 0 ? -at : (at > length ? at - length : 0.0);
    for (var i = lines.start; i < lines.end; i++) {
      final row = _row(i);
      if (row == null) continue;
      final local = row.globalToLocal(global);
      final distance = (
        outside(local.dy, row.size.height),
        outside(local.dx, row.size.width),
      );
      if (distance.$1 < bestDistance.$1 ||
          (distance.$1 == bestDistance.$1 && distance.$2 < bestDistance.$2)) {
        best = i;
        bestDistance = distance;
      }
      if (distance == (0.0, 0.0)) break;
    }
    if (best < 0) return null;

    final block = _blocks[best];
    if (block.isEmbed) {
      final row = _row(best)!;
      final object = _object(best);
      if (object != null &&
          (Offset.zero & object.size).contains(object.globalToLocal(global))) {
        return _Hit(RichPosition(best, 1), embed: true);
      }
      final local = row.globalToLocal(global);
      return _Hit(RichPosition(best, local.dx < row.size.width / 2 ? 0 : 1));
    }

    final paragraph = _paragraph(best);
    if (paragraph == null) return _Hit(RichPosition(best, 0));
    final local = paragraph.globalToLocal(global);

    if (block.kind == TextBlockKind.todo &&
        local.dx < 0 &&
        local.dx > -RichTextStyles.markerWidth &&
        local.dy < paragraph.size.height) {
      return _Hit(RichPosition(best, 0), checkbox: true);
    }

    final view = _viewFor(best);
    final clamped = Offset(
      local.dx.clamp(0, paragraph.size.width),
      local.dy.clamp(0, paragraph.size.height - 0.5),
    );
    for (final run in view.runs) {
      if (!run.collapsed || run.open) continue;
      for (final rect in paragraph.rangeRects(run.viewStart, run.viewEnd)) {
        if (rect.inflate(1).contains(local)) {
          return _Hit(
            RichPosition(best, run.modelEnd),
            formula: (block: best, run: run.index),
          );
        }
      }
    }
    final position = paragraph.paragraph.getPositionForOffset(clamped);
    return _Hit(RichPosition(best, view.toModel(position.offset)));
  }
}
