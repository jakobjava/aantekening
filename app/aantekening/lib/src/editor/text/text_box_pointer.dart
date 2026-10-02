part of 'text_box_editor.dart';

/// Presses, drags and clicks: placing the caret, selecting, resizing
/// objects and table columns.
extension _Pointer on TextBoxEditorState {
  /// The smallest an object in the text may be resized to, in page units.
  static const double _minEmbedWidth = 24;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.interactive) return;
    if (event.kind == PointerDeviceKind.touch) {
      _touchCount++;
      if (_touchCount > 1) {
        // A second finger is a pinch, which the canvas handles.
        _dragPointer = null;
        return;
      }
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kSecondaryMouseButton != 0) {
      if (!widget.grouped) unawaited(_showMenu(event.position));
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    if (box.globalToLocal(event.position).dy < TextBoxEditor.grabBand) {
      // The band picks the box up whole, as a box rather than the text in
      // it, so typing in it ends: the page shows it picked, everything in it
      // selected, and Delete takes the box away. A box emptied of its text
      // is left as it is, to be moved, since leaving it removes it.
      if (widget.isEditing && !TextBoxEditor.isEmpty(_blocks)) {
        widget.onExit?.call();
      }
      return;
    }

    // A column's right-hand line resizes the column, and a double-click on
    // it fits the column to its text again.
    final edge = _columnEdgeAt(event.position);
    if (edge != null) {
      if (!widget.isEditing) widget.onStartEditing?.call();
      _focusNode.requestFocus();
      if (_clicks.press(event.position) == 2) {
        _commit((
          blocks: TableEditing.setColumnWidth(
            _blocks,
            edge.table,
            edge.column,
            null,
          ),
          selection: _selection,
        ), EditKind.other);
        return;
      }
      _columnResize = (
        table: edge.table.start,
        column: edge.column,
        from: event.position,
        width: edge.box.columnWidth(edge.column),
      );
      return;
    }

    final hit = _hitTest(event.position);
    if (hit == null) return;
    if (hit.checkbox) {
      _toggleChecked(hit.position.block);
      return;
    }
    if (!widget.isEditing) widget.onStartEditing?.call();
    _focusNode.requestFocus();

    // A corner of a picture or PDF page resizes it rather than moving the
    // caret. The object is picked as the drag starts, so its handles stay in
    // view while it is dragged.
    final corner = _cornerAt(hit.position.block, event.position);
    if (corner != null) {
      final index = hit.position.block;
      _select(RichSelection(RichPosition(index, 0), RichPosition(index, 1)));
      _resize = (
        block: index,
        corner: corner,
        from: event.position,
        width: _object(index)!.size.width,
      );
      return;
    }

    _clicks.press(event.position);
    _dragPointer = event.pointer;

    // A click in the source of the formula being edited places the caret in
    // it, the tinted margin around it included.
    final formula = _formula;
    if (formula != null && _clicks.count == 1) {
      final inside = _hitInOpenFormula(event.position, formula);
      if (inside != null) {
        _select(
          RichSelection(
            HardwareKeyboard.instance.isShiftPressed ? _selection.base : inside,
            inside,
          ),
        );
        return;
      }
    }

    switch (_clicks.count) {
      case 2 when hit.embed && _fileAt(hit.position.block) != null:
        widget.onOpenFile?.call(_fileAt(hit.position.block)!);
      case 2:
        _selectWordAt(hit);
      case 3:
        _select(
          RichSelection(
            RichPosition(hit.position.block, 0),
            RichPosition(
              hit.position.block,
              _blocks[hit.position.block].length,
            ),
          ),
        );
      default:
        final hitFormula = hit.formula;
        if (hitFormula != null && !HardwareKeyboard.instance.isShiftPressed) {
          var target = hitFormula;
          final open = _formula;
          if (open != null) {
            final wasEmpty = _blocks[open.block].runs[open.run].text
                .trim()
                .isEmpty;
            _closeFormula(emit: true);
            // Closing an empty formula removes its run, shifting the runs
            // after it in the same block down by one.
            if (wasEmpty &&
                open.block == target.block &&
                open.run < target.run) {
              target = (block: target.block, run: target.run - 1);
            }
          }
          _openFormula(target);
          return;
        }
        // Ctrl+click follows a link, as it does in OneNote and Word.
        final link = _linkAt(hit.position);
        if (link != null && HardwareKeyboard.instance.isControlPressed) {
          widget.onOpenLink?.call(link);
          return;
        }
        // A click on a picture or PDF page picks it, as it does on the page.
        if (hit.embed && !HardwareKeyboard.instance.isShiftPressed) {
          _select(
            RichSelection(
              RichPosition(hit.position.block, 0),
              RichPosition(hit.position.block, 1),
            ),
          );
          return;
        }
        // A click beside the formula being edited finishes it.
        _select(
          RichSelection(
            HardwareKeyboard.instance.isShiftPressed
                ? _selection.base
                : hit.position,
            hit.position,
          ),
        );
    }
  }

  /// The table column whose right-hand line is under [global], if any.
  ({TextTable table, int column, RenderTextTable box})? _columnEdgeAt(
    Offset global,
  ) {
    for (final table in TextTables.tablesIn(_blocks)) {
      final box = _tableBox(table);
      final column = box?.edgeAt(box.globalToLocal(global));
      if (column != null) return (table: table, column: column, box: box!);
    }
    return null;
  }

  /// Resizes the column being dragged so that its line follows the pointer,
  /// no further than the box it is in allows, as a picture is resized.
  void _resizeColumn(Offset to) {
    final resize = _columnResize;
    final table = resize == null
        ? null
        : TextTables.tableAt(_blocks, resize.table);
    final box = table == null ? null : _tableBox(table);
    if (resize == null || table == null || box == null) return;
    final drag = box.globalToLocal(to).dx - box.globalToLocal(resize.from).dx;
    final widest =
        (widget.element.autoWidth ? _widest : widget.element.frame.width) -
        TextBoxEditor.padding.horizontal -
        (box.size.width - box.columnWidth(resize.column));
    final width = math.max(
      TableEditing.minColumnWidth,
      math.min(resize.width + drag, widest),
    );
    if ((width - box.columnWidth(resize.column)).abs() < 0.5) return;
    _commit((
      blocks: TableEditing.setColumnWidth(_blocks, table, resize.column, width),
      selection: _selection,
    ), EditKind.resizing);
  }

  /// Where in the source of the formula being edited a point at [global]
  /// lands, if it is on the source drawn over the text.
  RichPosition? _hitInOpenFormula(Offset global, _OpenFormula formula) {
    final layer = _formulaLayerBox;
    final span = _formulaSpan(formula);
    if (layer == null || span == null) return null;
    final offset = layer.sourceOffsetAt(layer.globalToLocal(global));
    if (offset == null) return null;
    return RichPosition(
      formula.block,
      (span.start + offset).clamp(span.start, span.end),
    );
  }

  void _selectWordAt(_Hit hit) {
    final position = hit.position;
    final block = _blocks[position.block];
    if (block.isEmbed) {
      _select(
        RichSelection(
          RichPosition(position.block, 0),
          RichPosition(position.block, 1),
        ),
      );
      return;
    }
    final formula = _formula;
    if (formula != null && formula.block == position.block) {
      final span = _formulaSpan(formula)!;
      if (position.offset >= span.start && position.offset <= span.end) {
        final source = _blocks[formula.block].runs[formula.run].text;
        final local = position.offset - span.start;
        final from = TextBoundaries.wordBefore(
          source,
          TextBoundaries.wordAfter(source, local),
        );
        final to = TextBoundaries.wordAfter(source, from);
        _select(
          RichSelection(
            RichPosition(formula.block, span.start + from),
            RichPosition(formula.block, span.start + to),
          ),
        );
        return;
      }
    }
    final hitFormula = hit.formula;
    if (hitFormula != null) {
      final span = RichTextEditing.runSpans(block)[hitFormula.run];
      _select(
        RichSelection(
          RichPosition(position.block, span.start),
          RichPosition(position.block, span.end),
        ),
      );
      return;
    }
    final view = _viewFor(position.block);
    final v = view.toView(position.offset);
    final end = TextBoundaries.wordAfter(view.text, v);
    final start = TextBoundaries.wordBefore(view.text, end);
    _select(
      RichSelection(
        RichPosition(position.block, view.toModel(start)),
        RichPosition(position.block, view.toModel(end)),
      ),
    );
  }

  /// The corner of the object on block [index] that a press at [global]
  /// takes hold of, or null where the press takes hold of none: a handle is
  /// only there while the object is picked.
  EmbedCorner? _cornerAt(int index, Offset global) {
    final object = _embedSelected(index) ? _object(index) : null;
    return object == null
        ? null
        : EmbedHandles.at(
            object.size,
            object.globalToLocal(global),
            pixel: screenPixelIn(object),
          );
  }

  /// Resizes the object being dragged so that its corner follows the pointer.
  void _resizeEmbed(Offset to) {
    final resize = _resize;
    final embed = resize == null ? null : _blocks[resize.block].embed;
    final object = resize == null ? null : _object(resize.block);
    if (resize == null || embed == null || object == null) return;
    // Measured in the box's own units, so a resize follows the pointer at any
    // zoom and however the box is turned.
    final drag = object.globalToLocal(to) - object.globalToLocal(resize.from);
    final row = _row(resize.block);
    final indent = _blocks[resize.block].indent * RichTextStyles.indentStep;
    // A picture never grows wider than the box holding it; one that sizes
    // itself to its content can grow until the box is as wide as it goes.
    final widest = widget.element.autoWidth
        ? _widest
        : math.max(_minEmbedWidth, (row?.size.width ?? 0) - indent);
    final width =
        (resize.width + resize.corner.widening(drag, embed.aspectRatio)).clamp(
          _minEmbedWidth,
          widest,
        );
    if ((width - embed.width).abs() < 0.5) return;
    _commit((
      blocks: RichTextEditing.replaceEmbed(
        _blocks,
        resize.block,
        embed.copyWith(width: width, height: width / embed.aspectRatio),
      ),
      selection: _selection,
    ), EditKind.resizing);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_resize != null) {
      _resizeEmbed(event.position);
      return;
    }
    if (_columnResize != null) {
      _resizeColumn(event.position);
      return;
    }
    if (event.pointer != _dragPointer || _clicks.count != 1) return;
    final formula = _formula;
    if (formula != null) {
      // A drag that starts in the formula being edited selects within it.
      final paragraph = _paragraph(formula.block);
      final span = _formulaSpan(formula);
      if (paragraph == null || span == null) return;
      final view = _viewFor(formula.block);
      final position = paragraph.paragraph.getPositionForOffset(
        paragraph.globalToLocal(event.position),
      );
      final model = view.toModel(position.offset).clamp(span.start, span.end);
      final extent = RichPosition(formula.block, model);
      if (extent != _selection.extent) {
        _select(RichSelection(_selection.base, extent));
      }
      return;
    }
    final hit = _hitTest(event.position);
    if (hit == null || hit.position == _selection.extent) return;
    _select(RichSelection(_selection.base, hit.position));
  }

  void _onPointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch && _touchCount > 0) {
      _touchCount--;
    }
    if (event.pointer == _dragPointer) _dragPointer = null;
    _resize = null;
    _columnResize = null;
  }
}
