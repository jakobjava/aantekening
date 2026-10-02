part of 'text_box_editor.dart';

/// What the input method sees of the box, and its edits applied to it.
extension _InputMethod on TextBoxEditorState {
  TextInputConfiguration _inputConfiguration() {
    final inFormula = _formula != null;
    return TextInputConfiguration(
      viewId: View.maybeOf(context)?.viewId,
      inputType: TextInputType.multiline,
      inputAction: TextInputAction.newline,
      enableDeltaModel: true,
      // Autocorrect would "fix" sin, cos and alpha into words.
      autocorrect: !inFormula,
      enableSuggestions: !inFormula,
      smartDashesType: inFormula
          ? SmartDashesType.disabled
          : SmartDashesType.enabled,
      smartQuotesType: inFormula
          ? SmartQuotesType.disabled
          : SmartQuotesType.enabled,
      textCapitalization: inFormula
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      keyboardAppearance: Theme.of(context).brightness,
    );
  }

  /// The source of the formula being edited, and where it starts in its
  /// block, if one is.
  ({String source, int start})? get _openSource {
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula);
    if (formula == null || span == null) return null;
    return (
      source: _blocks[formula.block].runs[formula.run].text,
      start: span.start,
    );
  }

  /// The current block as the input method sees it, with [composing] where
  /// it still fits: in a formula, its source alone.
  TextEditingValue _inputValue(TextRange composing) {
    if (_openSource case (:final source, :final start)) {
      int local(RichPosition position) =>
          (position.offset - start).clamp(0, source.length);
      return TextEditingValue(
        text: source,
        selection: TextSelection(
          baseOffset: local(_selection.base),
          extentOffset: local(_selection.extent),
        ),
        composing: composing.isValid && composing.end <= source.length
            ? composing
            : TextRange.empty,
      );
    }
    final extent = _selection.extent;
    if (extent.block >= _blocks.length || _blocks[extent.block].isEmbed) {
      return TextEditingValue.empty;
    }
    final view = _viewFor(extent.block);
    final extentView = view.toView(extent.offset);
    final baseView = _selection.base.block == extent.block
        ? view.toView(_selection.base.offset)
        : extentView;
    return TextEditingValue(
      text: view.text,
      selection: TextSelection(baseOffset: baseView, extentOffset: extentView),
      composing: composing.isValid && composing.end <= view.text.length
          ? composing
          : TextRange.empty,
    );
  }

  /// Where the text the input method sees is on screen, once laid out.
  InputGeometry? _inputGeometry() {
    if (!mounted) return null;
    final caret = _selection.extent;
    final layer = _formulaLayerBox;
    if (_openSource case (:final start, source: _) when layer != null) {
      return (
        size: layer.size,
        transform: layer.getTransformTo(null),
        caret: layer.sourceCaretRect(caret.offset - start),
      );
    }
    final paragraph = _paragraph(caret.block);
    if (paragraph == null) return null;
    return (
      size: paragraph.size,
      transform: paragraph.getTransformTo(null),
      caret: _caretRectLocal(caret),
    );
  }

  /// Applies a change the input method made to the current block's text,
  /// or to the source of the formula being edited.
  void _applyImeEdit(TextRange range, String text) {
    final caret = _selection.extent;
    if (_openSource case (:final source, :final start)) {
      final from = range.start.clamp(0, source.length);
      final to = range.end.clamp(from, source.length);
      _update(() {
        _selection = RichSelection(
          RichPosition(caret.block, start + from),
          RichPosition(caret.block, start + to),
        );
      });
      _replaceInFormula(text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
      return;
    }
    if (_blocks[caret.block].isEmbed) {
      _insertText(text);
      return;
    }
    final view = _viewFor(caret.block);
    final start = range.start.clamp(0, view.text.length);
    final end = range.end.clamp(start, view.text.length);

    // A selection reaching beyond this block is replaced as a whole; the input
    // method only ever sees the block holding the caret.
    if (!_selection.isMultiBlock) {
      _update(() {
        _selection = RichSelection(
          RichPosition(caret.block, view.toModel(start)),
          RichPosition(caret.block, view.toModel(end)),
        );
      });
    }
    if (text.isEmpty) {
      if (!_selection.isCollapsed) _deleteSelection();
      return;
    }
    if (text == '\n') {
      _paragraphBreak();
      return;
    }
    _insertText(text);
  }

  void _applyImeSelection(TextSelection selection) {
    final caret = _selection.extent;
    if (!selection.isValid) return;
    if (_openSource case (:final source, :final start)) {
      RichPosition at(int offset) =>
          RichPosition(caret.block, start + offset.clamp(0, source.length));
      final base = at(selection.baseOffset);
      final extent = at(selection.extentOffset);
      if (base == _selection.base && extent == _selection.extent) return;
      _select(RichSelection(base, extent));
      return;
    }
    if (_blocks[caret.block].isEmbed) return;
    final view = _viewFor(caret.block);
    final base = RichPosition(
      caret.block,
      view.toModel(selection.baseOffset.clamp(0, view.text.length)),
    );
    final extent = RichPosition(
      caret.block,
      view.toModel(selection.extentOffset.clamp(0, view.text.length)),
    );
    if (_selection.isMultiBlock && selection.isCollapsed) return;
    if (base == _selection.base && extent == _selection.extent) return;
    _select(RichSelection(base, extent));
  }
}
