part of 'text_box_editor.dart';

/// The formula being edited: opening, translating, typing in and
/// finishing it.
extension _Formulas on TextBoxEditorState {
  static bool _isMathRun(List<TextBlock> blocks, _OpenFormula formula) =>
      formula.block < blocks.length &&
      formula.run < blocks[formula.block].runs.length &&
      blocks[formula.block].runs[formula.run].isMath;

  /// The syntax formulas are typed in, as the person has chosen it.
  MathMode get _preferredSyntax =>
      widget.controller?.formulaSyntax.value ?? _source.syntax;

  /// Follows [controller]'s syntax setting, translating the open formula
  /// whenever it changes; null to stop following.
  void _followSyntax(TextBoxEditorController? controller) {
    final setting = controller?.formulaSyntax;
    if (identical(setting, _syntaxSetting)) return;
    _syntaxSetting?.removeListener(_onSyntaxSetting);
    _syntaxSetting = setting?..addListener(_onSyntaxSetting);
  }

  void _onSyntaxSetting() {
    final setting = _syntaxSetting;
    if (setting != null) _switchSyntax(setting.value);
  }

  /// Makes [syntax] the one formulas are typed in: the setting, which this
  /// box then follows, or this box alone if it has no controller.
  void _chooseSyntax(MathMode syntax) {
    final setting = widget.controller?.formulaSyntax;
    if (setting != null) {
      setting.value = syntax;
    } else {
      _switchSyntax(syntax);
    }
  }

  /// Shows the open formula in [syntax], translated. What is stored stays
  /// exactly as it was until something is typed.
  void _switchSyntax(MathMode syntax) {
    if (syntax == _source.syntax) return;
    final formula = _formula;
    if (formula == null || !_isMathRun(_blocks, formula)) {
      _source.syntax = syntax;
      return;
    }
    final run = _blocks[formula.block].runs[formula.run];
    final latex = _source.latexFor(run.text);
    _source.syntax = syntax;
    final source = FormulaSource.withCentring(
      FormulaSource.sourceIn(syntax, latex),
      centred: FormulaSource.centring(run.text).centred,
    );
    _source.opened(latex, source);
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, syntax, run.marks),
    );
    final span = _formulaSpan(formula)!;
    _update(() {
      _selection = RichSelection.collapsed(
        RichPosition(formula.block, span.end),
      );
      _goalX = null;
    });
    _undoSteps.breakStep();
    _input.reconfigure();
    _afterChange();
    _reportFormula();
  }

  /// [blocks] as they are stored, with the open formula's source as LaTeX.
  List<TextBlock> _stored(List<TextBlock> blocks) {
    final formula = _formula;
    if (formula == null || !_isMathRun(blocks, formula)) return blocks;
    final run = blocks[formula.block].runs[formula.run];
    if (run.math == MathMode.latex && _source.syntax == MathMode.latex) {
      return blocks;
    }
    return RichTextEditing.replaceRun(
      blocks,
      formula.block,
      formula.run,
      TextRun.math(_source.latexFor(run.text), MathMode.latex, run.marks),
    );
  }

  /// After undo or another change from outside, shows the open formula as
  /// source again, or lets it go if it is gone.
  void _showOpenFormulaAsSource() {
    final formula = _formula;
    if (formula == null) return;
    if (!_isMathRun(_blocks, formula)) {
      _formula = null;
      _source.closed();
      return;
    }
    final run = _blocks[formula.block].runs[formula.run];
    final source = _source.sourceOf(LinearMath.latexFor(run.math!, run.text));
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, _source.syntax, run.marks),
    );
  }

  /// Starts a new, empty formula at the caret.
  void _startFormula() {
    _source.syntax = _preferredSyntax;
    final (edit, :block, :run) = RichTextEditing.insertMath(
      _blocks,
      _selection,
      _source.syntax,
      marks: _typingMarks(),
    );
    final start = RichTextEditing.runSpans(edit.blocks[block])[run].start;
    _formula = (block: block, run: run);
    _openedAs = '';
    _source.closed();
    _commit((
      blocks: edit.blocks,
      selection: RichSelection.collapsed(RichPosition(block, start)),
    ), EditKind.other);
    _input.reconfigure();
    _reportFormula();
  }

  /// Opens an existing formula for editing: shows it as its source, with the
  /// caret at its end or start.
  void _openFormula(_OpenFormula formula, {bool atEnd = true}) {
    if (!_isMathRun(_blocks, formula)) return;
    _source.syntax = _preferredSyntax;
    final run = _blocks[formula.block].runs[formula.run];
    // Formulas are stored as LaTeX; one from an older page may still be in
    // Simple syntax.
    final legacy = run.math == MathMode.linear;
    final latex = LinearMath.latexFor(run.math!, run.text);
    final source = FormulaSource.withCentring(
      FormulaSource.sourceIn(_source.syntax, latex),
      centred:
          _isAlone(_blocks[formula.block]) &&
          _blocks[formula.block].align == BlockAlign.center,
    );
    _source.opened(latex, source);
    _formula = formula;
    _openedAs = latex;
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, _source.syntax, run.marks),
    );
    if (legacy) _emitStored(record: false);
    final span = _formulaSpan(formula)!;
    _update(() {
      _selection = RichSelection.collapsed(
        RichPosition(formula.block, atEnd ? span.end : span.start),
      );
      _pendingMarks = null;
      _goalX = null;
    });
    _undoSteps.breakStep();
    _input.reconfigure();
    _afterChange();
    _reportFormula();
  }

  /// Whether [block] is a formula alone on its line.
  static bool _isAlone(TextBlock block) =>
      block.runs.length == 1 && block.runs.single.isMath;

  /// [blocks] with block [index], if it is a formula alone on its line,
  /// centred as its source said: centred if it ended with the centring mark,
  /// back where lines start if it was centred and no longer ends with it.
  static List<TextBlock> _centredAsMarked(
    List<TextBlock> blocks,
    int index, {
    required bool centred,
  }) {
    final block = blocks[index];
    if (!_isAlone(block)) return blocks;
    final align = centred
        ? BlockAlign.center
        : (block.align == BlockAlign.center ? BlockAlign.start : block.align);
    if (align == block.align) return blocks;
    return <TextBlock>[...blocks]..[index] = block.copyWith(align: align);
  }

  /// Tells the preview about the formula being edited, or that there is none.
  void _reportFormula() {
    final controller = widget.controller;
    final formula = _formula;
    if (formula == null || _formulaSpan(formula) == null) {
      if (_session == null) return;
      _session = null;
      _reportedAnchor = null;
      controller?.reportFormula(this, null);
      return;
    }
    final source = _blocks[formula.block].runs[formula.run].text;
    final diagnostics = _source.diagnostics(source);
    final session = FormulaSession(
      latex: _source.latexFor(source),
      error: diagnostics.isEmpty ? null : diagnostics.first.message,
    );
    if (session == _session) return;
    _session = session;
    controller?.reportFormula(
      this,
      session,
      anchor: _reportedAnchor,
      field: _formulaField,
    );
  }

  /// The layer the source of the formula being edited is drawn in.
  RenderFormulaLayer? get _formulaLayerBox {
    final object = _formulaLayer.currentContext?.findRenderObject();
    return object is RenderFormulaLayer && object.hasSize ? object : null;
  }

  /// Reports where the source of the formula being edited is drawn, in this
  /// box's own page units, so its preview can sit beneath it.
  void _reportFormulaAnchor() {
    final session = _session;
    if (_formula == null || session == null || !mounted) return;
    final layer = _formulaLayerBox;
    final rect = layer?.formulaBox;
    final box = context.findRenderObject();
    if (layer == null || rect == null || box is! RenderBox) return;
    final anchor = MatrixUtils.transformRect(layer.getTransformTo(box), rect);
    if (anchor == _reportedAnchor) return;
    _reportedAnchor = anchor;
    widget.controller?.reportFormula(
      this,
      session,
      anchor: anchor,
      field: _formulaField,
    );
  }

  /// Finishes the formula being edited, showing it typeset again, and places
  /// the caret after it (or before it, or at [caretOverride], given in the
  /// offsets of the source). A formula left empty is removed.
  void _closeFormula({
    bool emit = false,
    bool after = true,
    RichSelection? caretOverride,
  }) {
    final formula = _formula;
    if (formula == null) return;
    final span = _formulaSpan(formula);
    final run = span == null ? null : _blocks[formula.block].runs[formula.run];
    final source = run?.text ?? '';
    final latex = _source.latexFor(source);
    final (formula: written, :centred) = FormulaSource.centring(source);
    _formula = null;
    _openedAs = '';
    _source.closed();
    _input.reconfigure();
    _reportFormula();
    if (span == null || run == null) return;

    if (written.trim().isEmpty) {
      final blocks = RichTextEditing.removeRun(
        _blocks,
        formula.block,
        formula.run,
      );
      final removedLength = span.end - span.start;
      RichPosition shift(RichPosition p) =>
          p.block == formula.block && p.offset >= span.end
          ? RichPosition(p.block, p.offset - removedLength)
          : p;
      final selection = caretOverride == null
          ? RichSelection.collapsed(RichPosition(formula.block, span.start))
          : RichSelection(
              shift(caretOverride.base),
              shift(caretOverride.extent),
            );
      if (emit) {
        _commit((blocks: blocks, selection: selection), EditKind.other);
      } else {
        _blocks = _wellFormed(blocks);
        _selection = selection;
      }
      return;
    }

    // The stored text already has this LaTeX: every edit reported it. Where
    // the line lies is decided now, and reported.
    final replaced = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(latex, MathMode.latex, run.marks),
    );
    final blocks = _centredAsMarked(replaced, formula.block, centred: centred);
    final end = span.start + latex.length;
    RichPosition map(RichPosition p) {
      if (p.block != formula.block || p.offset <= span.start) return p;
      if (p.offset >= span.end) {
        return RichPosition(p.block, p.offset - span.end + end);
      }
      return RichPosition(p.block, after ? end : span.start);
    }

    final selection = caretOverride == null
        ? RichSelection.collapsed(
            RichPosition(formula.block, after ? end : span.start),
          )
        : RichSelection(map(caretOverride.base), map(caretOverride.extent));
    if (!mounted) {
      _blocks = _wellFormed(blocks);
      _selection = selection;
      return;
    }
    _update(() {
      _blocks = _wellFormed(blocks);
      _selection = RichSelection(
        RichTextEditing.clamp(_blocks, selection.base),
        RichTextEditing.clamp(_blocks, selection.extent),
      );
      _goalX = null;
    });
    _undoSteps.breakStep();
    if (!identical(blocks, replaced)) _emitStored(record: true);
    _afterChange();
  }

  /// Replaces the selected part of the formula's source with [text], leaving
  /// the caret [caretAt] characters into it, or after it.
  void _replaceInFormula(String text, {int? caretAt}) {
    final formula = _formula!;
    final span = _formulaSpan(formula)!;
    final (:source, :from, :to) = _sourceSelection(formula);
    final updated = source.replaceRange(from, to, text);
    _commit((
      blocks: RichTextEditing.replaceRunText(
        _blocks,
        formula.block,
        formula.run,
        updated,
      ),
      selection: RichSelection.collapsed(
        RichPosition(
          formula.block,
          span.start + from + (caretAt ?? text.length),
        ),
      ),
    ), text.isEmpty ? EditKind.deleting : EditKind.typing);
  }

  /// The source of [formula], and where the selection starts and ends in it.
  ({String source, int from, int to}) _sourceSelection(_OpenFormula formula) {
    final span = _formulaSpan(formula)!;
    final source = _blocks[formula.block].runs[formula.run].text;
    final from = (_selection.start.offset - span.start).clamp(0, source.length);
    final to = (_selection.end.offset - span.start).clamp(from, source.length);
    return (source: source, from: from, to: to);
  }

  /// The highlight in the formula being edited that the selection lies in,
  /// if it lies in one.
  HighlightSpan? _highlightAtSelection(_OpenFormula formula) {
    final (:source, :from, :to) = _sourceSelection(formula);
    return HighlightSource.around(source, from, to, _source.syntax);
  }

  /// Highlights the part of the formula's source that is selected — or,
  /// with nothing selected, the whole formula — in [color] as the
  /// highlighter is chosen, as the syntax's own construct, so the typeset
  /// formula and its preview show it. Where the selection lies in a
  /// highlight already, a colour recolours that one, and [toggle], or
  /// [color] null, takes it off.
  ///
  /// The selection is fitted to a whole part of the formula first
  /// ([HighlightSource.fit]), so marking it never leaves the formula broken,
  /// and any highlight inside it gives way, so it is marked evenly.
  void _highlightInFormula(int? color, {bool toggle = false}) {
    final formula = _formula!;
    final (:source, :from, :to) = _sourceSelection(formula);
    final syntax = _source.syntax;
    final existing = HighlightSource.around(source, from, to, syntax);
    final ({int start, int end}) part;
    final String body;
    if (existing != null) {
      part = (start: existing.start, end: existing.end);
      body = source.substring(existing.bodyStart, existing.bodyEnd);
    } else {
      final fitted = color == null
          ? null
          : HighlightSource.fit(
              source,
              from == to ? 0 : from,
              from == to ? source.length : to,
              syntax,
            );
      if (fitted == null) return;
      part = fitted;
      body = HighlightSource.unwrapAll(
        source.substring(fitted.start, fitted.end),
        syntax,
      );
    }

    final wrapped = color == null || (toggle && existing != null)
        ? (text: body, body: 0)
        : HighlightSource.wrap(body, syntax, RichTextStyles.onPaper(color));
    // What is marked stays selected, so pressing again takes it off.
    final marked = _formulaSpan(formula)!.start + part.start + wrapped.body;
    _commit((
      blocks: RichTextEditing.replaceRunText(
        _blocks,
        formula.block,
        formula.run,
        source.replaceRange(part.start, part.end, wrapped.text),
      ),
      selection: RichSelection(
        RichPosition(formula.block, marked),
        RichPosition(formula.block, marked + body.length),
      ),
    ), EditKind.other);
  }

  /// Highlights what is selected in the text in [color], or with null takes
  /// the highlight off it: the words by their marks, and each formula whole
  /// by the highlight in its LaTeX — the one that shows, and can be taken
  /// off, in the formula's source.
  void _highlightSelection(int? color) {
    final blocks = List<TextBlock>.of(
      RichTextEditing.applyMarks(
        _blocks,
        _selection,
        (marks) => marks.withHighlight(color),
      ),
    );
    var base = _selection.base;
    var extent = _selection.extent;
    for (final (block: i, :from, :to, cell: _) in _covering.values) {
      final block = blocks[i];
      if (block.isEmbed) continue;
      final spans = RichTextEditing.runSpans(block);
      final runs = List<TextRun>.of(block.runs);
      // How much longer the formulas changed so far have grown.
      var grown = 0;
      for (var j = 0; j < runs.length; j++) {
        final run = runs[j];
        if (!run.isMath || spans[j].start < from || spans[j].end > to) {
          continue;
        }
        final plain = HighlightSource.unwrapAll(run.text, MathMode.latex);
        final latex = color == null
            ? plain
            : HighlightSource.wrap(
                plain,
                MathMode.latex,
                RichTextStyles.onPaper(color),
              ).text;
        runs[j] = run.copyWith(text: latex);
        // What follows the formula moves along with its end.
        final after = spans[j].end + grown;
        final by = latex.length - run.text.length;
        RichPosition moved(RichPosition p) => p.block == i && p.offset >= after
            ? RichPosition(i, p.offset + by)
            : p;
        base = moved(base);
        extent = moved(extent);
        grown += by;
      }
      blocks[i] = block.copyWith(runs: runs);
    }
    _commit((
      blocks: blocks,
      selection: RichSelection(base, extent),
    ), EditKind.other);
  }

  /// Whether all that is selected in the text is highlighted: every word,
  /// and every formula whole.
  bool _selectionHighlighted() => RichTextEditing.everyRun(
    _blocks,
    _selection,
    (run) => run.isMath
        ? HighlightSource.whole(run.text, MathMode.latex) != null
        : run.marks.highlight != null,
  );

  void _deleteInFormula({required bool forward, bool word = false}) {
    final formula = _formula!;
    final span = _formulaSpan(formula)!;
    final source = _blocks[formula.block].runs[formula.run].text;
    if (!_selection.isCollapsed) {
      _replaceInFormula('');
      return;
    }
    final local = _selection.extent.offset - span.start;
    if (source.isEmpty) {
      // Deleting in an empty formula removes it.
      _closeFormula(emit: true);
      return;
    }
    // At its edge, a formula is left rather than eaten into from inside.
    if (!forward && local == 0) {
      _closeFormula(emit: true, after: false);
      return;
    }
    if (forward && local == source.length) {
      _closeFormula(emit: true);
      return;
    }
    final target = TextBoundaries.step(
      source,
      local,
      forward: forward,
      word: word,
    );
    final from = math.min(local, target);
    final to = math.max(local, target);
    _commit((
      blocks: RichTextEditing.replaceRunText(
        _blocks,
        formula.block,
        formula.run,
        source.replaceRange(from, to, ''),
      ),
      selection: RichSelection.collapsed(
        RichPosition(formula.block, span.start + from),
      ),
    ), EditKind.deleting);
  }

  /// The places in [source] a template leaves to fill in: inside empty
  /// brackets, and after a comma or semicolon with nothing yet behind it.
  static List<int> _slotsIn(String source) => <int>[
    for (final match in RegExp(
      r'\(\)|\{\}|\[\]|[,;] (?=[,;)\]}])',
    ).allMatches(source))
      match.start +
          (match.group(0)!.length == 2 && match.group(0)![1] == ' ' ? 2 : 1),
  ];

  /// Moves the caret to the next place in the formula left to fill in, or
  /// the previous one, as Tab does in an equation editor. Past the last it
  /// goes to the end.
  void _moveToSlot({required bool forward}) {
    final formula = _formula!;
    final span = _formulaSpan(formula)!;
    final source = _blocks[formula.block].runs[formula.run].text;
    final local = _selection.extent.offset - span.start;
    final slots = _slotsIn(source);
    final int target;
    if (forward) {
      target = slots.firstWhere(
        (slot) => slot > local,
        orElse: () => source.length,
      );
    } else {
      target = slots.lastWhere((slot) => slot < local, orElse: () => 0);
    }
    _select(
      RichSelection.collapsed(RichPosition(formula.block, span.start + target)),
    );
  }

  _OpenFormula? _selectedFormula() {
    final start = _selection.start;
    final end = _selection.end;
    if (start.block != end.block || _blocks[start.block].isEmbed) return null;
    final spans = RichTextEditing.runSpans(_blocks[start.block]);
    for (var i = 0; i < spans.length; i++) {
      if (_blocks[start.block].runs[i].isMath &&
          spans[i].start == start.offset &&
          spans[i].end == end.offset &&
          !_selection.isCollapsed) {
        return (block: start.block, run: i);
      }
    }
    return null;
  }
}
