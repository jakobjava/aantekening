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

  /// Whether the formula [run], [latex] as LaTeX, can only be typed as
  /// LaTeX: one brought in as LaTeX, which may use what Simple syntax has no
  /// words for, and a TikZ picture, which Simple syntax has none for.
  static bool _latexOnly(TextRun run, String latex) =>
      run.imported || TikzPicture.holds(latex);

  /// Whether the formula being edited can only be typed as LaTeX.
  bool get _openIsLatexOnly {
    final formula = _formula;
    if (formula == null || !_isMathRun(_blocks, formula)) return false;
    final run = _blocks[formula.block].runs[formula.run];
    return _latexOnly(run, _source.latexFor(run.text));
  }

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
  /// exactly as it was until something is typed. A formula that can only
  /// be typed as LaTeX stays LaTeX.
  void _switchSyntax(MathMode syntax) {
    if (syntax == _source.syntax || _openIsLatexOnly) return;
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
      run.copyWith(text: source, math: syntax),
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
      run.copyWith(text: _source.latexFor(run.text), math: MathMode.latex),
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
      run.copyWith(text: source, math: _source.syntax),
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
    final run = _blocks[formula.block].runs[formula.run];
    // Formulas are stored as LaTeX; one from an older page may still be in
    // Simple syntax.
    final legacy = run.math == MathMode.linear;
    final latex = LinearMath.latexFor(run.math!, run.text);
    _source.syntax = _latexOnly(run, latex) ? MathMode.latex : _preferredSyntax;
    final source = FormulaSource.withCentring(
      FormulaSource.sourceIn(_source.syntax, latex),
      centred:
          _isAlone(_blocks[formula.block]) &&
          _blocks[formula.block].align == BlockAlign.center,
    );
    _source.opened(latex, source);
    _formula = formula;
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      run.copyWith(text: source, math: _source.syntax),
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

  /// [edit] of line [index] with what it made of that line, if it was a
  /// formula centred alone on it, back where lines start wherever it no
  /// longer is: the centring was the formula's. Text typed beside it, and
  /// a line broken off it, are not centred.
  RichEdit _centringKeptToFormula(int index, RichEdit edit) {
    final before = _blocks[index];
    if (!_isAlone(before) || before.align != BlockAlign.center) return edit;
    final blocks = List<TextBlock>.of(edit.blocks);
    final made = edit.blocks.length > _blocks.length ? 2 : 1;
    for (var i = index; i < index + made && i < blocks.length; i++) {
      if (!_isAlone(blocks[i]) && blocks[i].align == BlockAlign.center) {
        blocks[i] = blocks[i].copyWith(align: BlockAlign.start);
      }
    }
    return (blocks: blocks, selection: edit.selection);
  }

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

  /// Typesets the formula being edited in its place as its source now
  /// stands, if it can be, and tells the page whether one is being edited,
  /// for it to draw the field its source is typed in.
  void _reportFormula() {
    final formula = _formula;
    final open = formula != null && _formulaSpan(formula) != null;
    if (open) {
      final run = _blocks[formula.block].runs[formula.run];
      final source = run.text;
      final diagnostics = _source.diagnostics(source);
      final latex = _source.latexFor(source);
      final problem = diagnostics.isNotEmpty
          ? diagnostics.first.message
          : MathView.problemIn(
              latex,
              preamble: MathPreamble.read(context),
              packages: run.imported,
            );
      if (problem == null ||
          FormulaSource.centring(source).formula.trim().isEmpty) {
        _shown = latex;
      }
      _problem = problem;
    } else {
      _shown = '';
      _problem = null;
    }
    _placeSource();
    if (open == _reportedOpen) return;
    _reportedOpen = open;
    widget.controller?.reportFormula(this, open ? _formulaField : null);
  }

  /// Moves the source of the formula being edited into a window of its own
  /// once it grows long, and back beneath its line once it is short again
  /// ([FormulaWindow]); while it is in one, shows the window what it now
  /// is.
  void _placeSource() {
    // Nothing on the page is to change while it is being built: this waits
    // for the frame to end when the formula is changed from outside.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _placeSource();
      });
      return;
    }
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula);
    final window = _window;
    if (formula == null || span == null || !widget.isEditing) {
      if (window != null) _handBack(window);
      return;
    }
    final source = _blocks[formula.block].runs[formula.run].text;
    final limit = widget.controller?.formulaWindow ?? const FormulaWindow();
    if (!limit.holds(source, already: window != null)) {
      if (window != null) _handBack(window);
      return;
    }
    final (source: _, :from, :to) = _sourceSelection(formula);
    final shown = FormulaWindowSource(
      value: TextEditingValue(
        text: source,
        selection: _selection.extent.offset < _selection.base.offset
            ? TextSelection(baseOffset: to, extentOffset: from)
            : TextSelection(baseOffset: from, extentOffset: to),
      ),
      marks: _sourceMarks(source),
      problem: _problem,
      latexOnly: _openIsLatexOnly,
    );
    if (window != null) {
      window.value = shown;
      return;
    }
    final opened = ValueNotifier<FormulaWindowSource?>(shown);
    _update(() => _window = opened);
    unawaited(
      showFormulaWindow(context, source: opened, onChanged: _editInWindow).then(
        (finished) {
          if (!finished || !identical(_window, opened)) return;
          _update(() => _window = null);
          finishFormula();
        },
      ),
    );
  }

  /// Closes [window], the source of the formula going back beneath its line
  /// if it is still being edited.
  void _handBack(ValueNotifier<FormulaWindowSource?> window) {
    _update(() => _window = null);
    window.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isEditing) _focusNode.requestFocus();
    });
  }

  /// Takes what was typed or selected in the window the formula being
  /// edited is typed in.
  void _editInWindow(TextEditingValue value) {
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula);
    if (formula == null || span == null) return;
    final source = _blocks[formula.block].runs[formula.run].text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    RichPosition at(int offset) =>
        RichPosition(formula.block, span.start + offset);
    final placed = RichSelection(
      at(selection.baseOffset),
      at(selection.extentOffset),
    );
    if (value.text == source) {
      _select(placed);
      return;
    }
    _commit((
      blocks: RichTextEditing.replaceRunText(
        _blocks,
        formula.block,
        formula.run,
        value.text,
      ),
      selection: placed,
    ), value.text.length < source.length ? EditKind.deleting : EditKind.typing);
  }

  /// Opens the source of the TikZ picture on block [index] in the window
  /// formulas are typed in, the picture drawn again as it changes. Emptied,
  /// the picture goes.
  Future<void> _editPicture(int index) async {
    final source = _blocks[index].embed?.source;
    if (source == null) return;
    _undoSteps.breakStep();
    await editTikzSource(
      context,
      source: source,
      onChanged: (changed) {
        final embed = _blocks[index].embed;
        if (embed?.source == null) return;
        _commit((
          blocks: RichTextEditing.replaceEmbed(
            _blocks,
            index,
            embed!.copyWith(source: changed),
          ),
          selection: _selection,
        ), EditKind.typing);
      },
    );
    _undoSteps.breakStep();
    if (!mounted) return;
    if (_blocks[index].embed?.source?.trim().isEmpty ?? false) {
      _commit(RichTextEditing.deleteEmbed(_blocks, index), EditKind.deleting);
    }
    _focusNode.requestFocus();
  }

  /// The layer the source of the formula being edited is drawn in.
  RenderFormulaLayer? get _formulaLayerBox {
    final object = _formulaLayer.currentContext?.findRenderObject();
    return object is RenderFormulaLayer && object.hasSize ? object : null;
  }

  /// Finishes the formula being edited, showing it typeset again, and places
  /// the caret after it (or before it, or at [caretOverride], given in the
  /// offsets of the source). A formula left empty is removed.
  ///
  /// Finished [onwards] — with Enter, Esc or Done — a formula centred alone
  /// on its line leaves the caret at the start of the line after it, a new
  /// one if there is none, as text goes on beneath a displayed formula:
  /// after it on its own line the caret would stand in the middle.
  void _closeFormula({
    bool emit = false,
    bool after = true,
    bool onwards = false,
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
      run.copyWith(text: latex, math: MathMode.latex),
    );
    var blocks = _centredAsMarked(replaced, formula.block, centred: centred);
    final end = span.start + latex.length;
    RichPosition map(RichPosition p) {
      if (p.block != formula.block || p.offset <= span.start) return p;
      if (p.offset >= span.end) {
        return RichPosition(p.block, p.offset - span.end + end);
      }
      return RichPosition(p.block, after ? end : span.start);
    }

    var selection = caretOverride == null
        ? RichSelection.collapsed(
            RichPosition(formula.block, after ? end : span.start),
          )
        : RichSelection(map(caretOverride.base), map(caretOverride.extent));
    final line = blocks[formula.block];
    if (onwards &&
        after &&
        caretOverride == null &&
        line.cell == null &&
        _isAlone(line) &&
        line.align == BlockAlign.center) {
      final next = formula.block + 1;
      if (next == blocks.length) {
        blocks = <TextBlock>[...blocks, TextBlock(indent: line.indent)];
      }
      selection = RichSelection.collapsed(RichPosition(next, 0));
    }
    // A TikZ picture alone on its line is a picture in the text, as one
    // brought in is.
    if (_isAlone(line) && TikzPicture.holds(latex)) {
      blocks = <TextBlock>[...blocks]
        ..[formula.block] = TextBlock.embedded(
          BlockEmbed.tikz(latex),
          indent: line.indent,
          align: line.align,
          spacing: line.spacing,
          cell: line.cell,
        );
      RichPosition onPicture(RichPosition p) => p.block == formula.block
          ? RichPosition(p.block, p.offset > 0 ? 1 : 0)
          : p;
      selection = RichSelection(
        onPicture(selection.base),
        onPicture(selection.extent),
      );
    }
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
