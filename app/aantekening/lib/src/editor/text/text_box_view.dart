part of 'text_box_editor.dart';

/// What each block is drawn with, and the blocks and tables themselves.
extension _View on TextBoxEditorState {
  /// Where the search's words are in block [index], laid out as [view].
  List<TextRange> _matchesIn(int index, BlockView view) {
    final terms = widget.highlight;
    final mark = widget.mark;
    final length = _blocks[index].length;
    return <TextRange>[
      if (terms != null)
        for (final match in TextBoxEditor.matchesIn(_blocks[index], terms))
          TextRange(
            start: view.toView(match.start),
            end: view.toView(match.end),
          ),
      if (mark != null && mark.block == index && mark.from < length)
        TextRange(
          start: view.toView(mark.from),
          end: view.toView(mark.to.clamp(mark.from, length)),
        ),
    ];
  }

  /// Tells [TextBoxEditor.onMatchPlaced] where the first match is, once for
  /// each search.
  void _placeFirstMatch() {
    if (!mounted) return;
    final terms = widget.highlight;
    final report = widget.onMatchPlaced;
    final box = context.findRenderObject();
    if (terms == null ||
        report == null ||
        identical(terms, _placedMatchesOf) ||
        box is! RenderBox) {
      return;
    }
    for (var i = 0; i < _blocks.length; i++) {
      final matches = _matchesIn(i, _viewFor(i));
      if (matches.isEmpty) continue;
      final paragraph = _paragraph(i);
      final rects = paragraph?.rangeRects(
        matches.first.start,
        matches.first.end,
      );
      if (paragraph == null || rects == null || rects.isEmpty) return;
      _placedMatchesOf = terms;
      report(
        MatrixUtils.transformRect(paragraph.getTransformTo(box), rects.first),
      );
      return;
    }
  }

  /// Where the words spelled wrongly are in block [index], laid out as
  /// [view]: none in code, and not the word being typed.
  List<TextRange> _misspellingsIn(int index, BlockView view) {
    final proofreader = widget.proofreader;
    final block = _blocks[index];
    if (proofreader == null || block.kind == TextBlockKind.code) {
      return const <TextRange>[];
    }
    final caret = _selection.extent;
    return <TextRange>[
      for (final word in proofreader.misspellingsIn(
        TextBoxEditor.textOf(block, code: false),
        caret: widget.isEditing && caret.block == index ? caret.offset : null,
      ))
        TextRange(start: view.toView(word.start), end: view.toView(word.end)),
    ];
  }

  /// Whether the object on block [index] is shown picked, with the handles
  /// that resize it: selected in the text, or in a box picked whole.
  bool _embedSelected(int index) {
    if (!_blocks[index].isEmbed) return false;
    if (!widget.isEditing) return widget.selected;
    final part = _covering[index];
    return part != null && part.from == 0 && part.to == 1;
  }

  /// Whether the table cell block [index] is a line of is selected whole,
  /// and drawn selected as a cell: in a selection from cell to cell, or in
  /// a box picked whole.
  bool _cellSelected(int index) =>
      _blocks[index].inTable &&
      (widget.isEditing ? _covering[index]?.cell ?? false : widget.selected);

  /// What the selection takes in of each block it touches (see
  /// [RichTextEditing.coveredBy]), worked out again only once the text or the
  /// selection has changed.
  Map<int, Covered> get _covering {
    if (!identical(_coveredBlocks, _blocks) || _coveredFor != _selection) {
      _coveredBlocks = _blocks;
      _coveredFor = _selection;
      _covered = <int, Covered>{
        for (final part in RichTextEditing.coveredBy(_blocks, _selection))
          part.block: part,
      };
    }
    return _covered;
  }

  BlockDecoration _decorationFor(int index, BlockView view, bool focused) {
    final matches = _matchesIn(index, view);
    final misspellings = _misspellingsIn(index, view);
    if (!widget.isEditing) {
      // A box picked on the page — by its band, say — shows everything in it
      // selected, as OneNote does with a container.
      final whole =
          widget.selected && view.text.isNotEmpty && !_cellSelected(index)
          ? TextSelection(baseOffset: 0, extentOffset: view.text.length)
          : null;
      return whole == null && matches.isEmpty && misspellings.isEmpty
          ? BlockDecoration.none
          : BlockDecoration(
              selection: whole,
              matches: matches,
              misspellings: misspellings,
            );
    }
    // The caret and selection in the formula being edited are drawn with
    // its source, over the text.
    final inFormula = _formula?.block == index;
    // A cell taken in whole is drawn selected as a cell, not as its text.
    TextSelection? selection;
    final part = inFormula ? null : _covering[index];
    if (part != null && !part.cell) {
      final from = view.toView(part.from);
      final to = view.toView(part.to);
      if (to > from) {
        selection = TextSelection(baseOffset: from, extentOffset: to);
      }
    }

    final caret = _selection.extent;
    final here = caret.block == index && !inFormula;
    return BlockDecoration(
      selection: selection,
      caret: focused && _selection.isCollapsed && here
          ? view.toView(caret.offset)
          : null,
      caretAffinity: _affinity,
      typingStyle: _typingStyle(index),
      composing: here ? _input.composing : null,
      matches: matches,
      misspellings: misspellings,
    );
  }

  /// The formula being edited as it is drawn over the text, if one is.
  FormulaOverlay? _formulaOverlay(bool focused) {
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula);
    if (formula == null || span == null || !widget.isEditing) return null;
    final block = _blocks[formula.block];
    final run = block.runs[formula.run];
    final source = run.text;
    final base = (_selection.base.offset - span.start).clamp(0, source.length);
    final extent = (_selection.extent.offset - span.start).clamp(
      0,
      source.length,
    );
    final style = RichTextStyles.formulaSource(
      RichTextStyles.blockStyleOf(block, RichTextStyles.base(context)),
      run.marks,
      accent: context.tones.paperEmphasis,
    );
    final problem = _problem;
    return FormulaOverlay(
      paragraph: _contentKeys[formula.block],
      place: _viewFor(formula.block).runAt(formula.run).viewStart,
      source: TextSpan(text: source, style: style),
      problem: problem == null
          ? null
          : TextSpan(
              text: problem,
              style: style.copyWith(
                fontSize: (style.fontSize ?? RichTextStyles.bodySize) * 0.8,
                color: context.tones.paperEmphasis,
                fontStyle: FontStyle.italic,
              ),
            ),
      inWindow: _window != null,
      caret: focused && base == extent ? extent : null,
      selection: base == extent
          ? null
          : TextSelection(baseOffset: base, extentOffset: extent),
      composing: _input.composing.isValid ? _input.composing : null,
      marks: _sourceMarks(source),
    );
  }

  /// What the highlights in [source], the formula being edited, mark, each
  /// with its colour.
  List<({TextRange range, Color color})> _sourceMarks(String source) =>
      <({TextRange range, Color color})>[
        for (final mark in HighlightSource.all(source, _source.syntax))
          (
            range: TextRange(start: mark.bodyStart, end: mark.bodyEnd),
            color: Color(0xFF000000 | mark.color),
          ),
      ];

  /// [table], each of its cells a column of its lines.
  Widget _buildTable(
    TextTable table,
    TextStyle base,
    BlockPaint paint,
    List<int> ordinals,
    bool focused,
  ) {
    final cells = <Widget>[];
    final shading = <int, Color>{};
    var i = table.start;
    while (i < table.end) {
      final cell = TextTables.cellAt(_blocks, i);
      final place = _blocks[i].cell!;
      if (place.shading case final color?) {
        shading[place.row * table.columns + place.column] = Color(color);
      }
      cells.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var line = cell.start; line < cell.end; line++)
              _buildBlock(line, base, paint, ordinals[line], focused, false),
          ],
        ),
      );
      i = cell.end;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      // Only as wide as its columns, in a box of any width.
      child: Align(
        alignment: AlignmentDirectional.topStart,
        widthFactor: 1,
        child: TextTableView(
          columns: table.columns,
          widths: TextTables.widthsOf(_blocks, table),
          // A table laid out without lines shows them faintly only while it
          // is being typed in, to show where its cells are.
          lineColor: _blocks[table.start].cell!.borders
              ? RichTextStyles.tableRule
              : widget.isEditing
              ? RichTextStyles.tableRule.withValues(alpha: 0.35)
              : const Color(0x00000000),
          shading: shading,
          selected: <int>{
            for (var i = table.start; i < table.end; i++)
              if (_cellSelected(i))
                _blocks[i].cell!.row * table.columns + _blocks[i].cell!.column,
          },
          selectionColor: paint.selectionColor,
          children: cells,
        ),
      ),
    );
  }

  Widget _buildBlock(
    int index,
    TextStyle base,
    BlockPaint paint,
    int ordinal,
    bool focused,
    bool autoWidth,
  ) {
    final block = _blocks[index];
    final indent = block.indent * RichTextStyles.indentStep;

    if (block.isEmbed) {
      final caret = _selection.extent;
      return KeyedSubtree(
        key: _rowKeys[index],
        child: Padding(
          padding: EdgeInsets.only(left: indent, top: 2, bottom: 4),
          child: EmbedBlock(
            embed: block.embed!,
            style: base,
            align: block.align,
            objectKey: _contentKeys[index],
            selected: _embedSelected(index),
            caretSide:
                widget.isEditing &&
                    focused &&
                    _selection.isCollapsed &&
                    caret.block == index
                ? caret.offset
                : null,
            caretVisible: _blink.visible,
            caretColor: paint.caretColor,
            caretWidth: paint.caretWidth,
            caretHeight:
                (base.fontSize ?? RichTextStyles.bodySize) * (base.height ?? 1),
          ),
        ),
      );
    }

    final view = _viewFor(index);
    final spacing = block.spacing;
    final blockStyle = RichTextStyles.blockStyleOf(block, base);
    final paragraph = BlockParagraph(
      key: _contentKeys[index],
      decoration: _decorationFor(index, view, focused),
      paint: paint,
      caretVisible: _blink.visible,
      child: RichText(
        text: view.span(
          base: base,
          mark: context.tones.paperEmphasis,
          open: _shown,
        ),
        textAlign: RichTextStyles.alignOf(block),
        // A box sizing itself to its text measures its longest line, and
        // places the paragraph across the box as it is aligned; a box of
        // fixed width gives every paragraph the full width to align in.
        textWidthBasis: autoWidth
            ? TextWidthBasis.longestLine
            : TextWidthBasis.parent,
      ),
    );

    final marker = blockMarker(
      block,
      blockStyle,
      context.tones.paperEmphasis,
      ordinal,
    );
    Widget row = Row(
      mainAxisSize: autoWidth ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (indent > 0) SizedBox(width: indent),
        if (marker != null)
          SizedBox(width: RichTextStyles.markerWidth, child: marker),
        if (autoWidth)
          Flexible(child: paragraph)
        else
          Expanded(child: paragraph),
      ],
    );

    if (block.kind == TextBlockKind.quote) {
      row = Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: RichTextStyles.titleRule, width: 3),
          ),
        ),
        child: row,
      );
    } else if (block.kind == TextBlockKind.code) {
      row = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: const BoxDecoration(color: RichTextStyles.codeFill),
        child: row,
      );
    }

    return KeyedSubtree(
      key: _rowKeys[index],
      child: Padding(
        // A block laid out as it was elsewhere keeps the space it had there,
        // in place of the page's own.
        padding: spacing == null
            ? const EdgeInsets.only(bottom: 2)
            : EdgeInsets.only(
                top: spacing.before * RichTextStyles.unitsPerPoint,
                bottom: spacing.after * RichTextStyles.unitsPerPoint,
              ),
        child: row,
      ),
    );
  }
}
