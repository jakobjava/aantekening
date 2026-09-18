/// The text box: rich text, formulas, pictures and PDF pages, edited in place.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../media_views.dart';
import 'block_paragraph.dart';
import 'block_view.dart';
import 'math_templates.dart';
import 'text_box_controller.dart';
import 'text_styles.dart';

/// Called with a text box's new contents. [recordUndo] is true when the change
/// starts a new undo step rather than extending the one being typed.
typedef TextBoxChanged = void Function(
  List<TextBlock> blocks, {
  required bool recordUndo,
});

/// A text box on the canvas, as OneNote's text containers work: click to place
/// the caret, type, format, and press a shortcut to write a formula in place.
///
/// The same widget renders the box when it is not being edited, so nothing
/// shifts when editing starts or stops.
///
/// Formulas are part of the text, stored as LaTeX and shown typeset. The one
/// being edited is shown as its source instead — in Simple or LaTeX syntax,
/// in a code face on a tinted box — and typed in place, with the page editor
/// showing it typeset beneath ([TextBoxEditorController.formula]). Alt+= (as
/// in OneNote) or Ctrl+M starts and finishes a formula; the arrow keys move
/// into one and back out of it.
class TextBoxEditor extends StatefulWidget {
  const TextBoxEditor({
    required this.element,
    required this.isEditing,
    super.key,
    this.controller,
    this.interactive = true,
    this.startInFormula = false,
    this.onStartEditing,
    this.onChanged,
    this.onSizeChanged,
    this.onExit,
    this.highlight,
    this.onMatchPlaced,
  });

  final TextElement element;

  /// Whether this box has the caret.
  final bool isEditing;

  /// Receives this box's formatting state and forwards toolbar commands to it
  /// while it is being edited.
  final TextBoxEditorController? controller;

  /// Whether pointer presses edit the text. Off while a drawing tool is in
  /// use, so the pen can write over a text box.
  final bool interactive;

  /// Whether a new box should open straight into a formula.
  final bool startInFormula;

  /// Asks the host to make this the box being edited.
  final VoidCallback? onStartEditing;

  final TextBoxChanged? onChanged;

  /// Reports the size the content needs, in page units, so the box can grow
  /// and shrink with its text: always in height, and in width too while the
  /// box sizes itself to its text ([TextElement.autoWidth]).
  final ValueChanged<Size>? onSizeChanged;

  /// Asks the host to stop editing, as Escape does.
  final VoidCallback? onExit;

  /// Words to mark wherever they occur in the box, as a search found them.
  final SearchTerms? highlight;

  /// Told where the first word [highlight] marks lies, in the box's own page
  /// units, once it has been laid out: for the page to bring it into view.
  final ValueChanged<Rect>? onMatchPlaced;

  /// Height of the band along the top edge that moves the box when dragged.
  static const double grabBand = 12;

  /// Space between the box's edges and its text.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(6, 0, 6, 8);

  /// The size of a new, empty text box.
  static const Size newBoxSize = Size(minAutoWidth, 44);

  /// The narrowest and widest a box that sizes itself to its text becomes,
  /// padding included. Past the widest it wraps, as a OneNote container does
  /// once it reaches the edge of the page.
  static const double minAutoWidth = 80;
  static const double maxAutoWidth = 600;

  /// Whether a page-space point on [element] falls in its grab band, which
  /// runs along its top edge however the box is turned.
  static bool isInGrabBand(TextElement element, Offset page) =>
      element.frame.pageToLocal(page.dx, page.dy).y < grabBand;

  /// Where [terms] occur in [block]'s text, in the model's offsets.
  ///
  /// Only the text is searched, not formulas: they are shown typeset, where
  /// a word of their source cannot be pointed to.
  static List<TextMatch> matchesIn(TextBlock block, SearchTerms terms) =>
      terms.matchesIn(
        <String>[
          // As many spaces as the formula is long, so offsets stay the model's
          // and words either side of it stay apart.
          for (final run in block.runs)
            run.isMath ? ' ' * run.text.length : run.text,
        ].join(),
      );

  /// Whether [blocks] hold nothing worth keeping: no text, no formula and no
  /// embed. An empty box is removed when editing ends.
  static bool isEmpty(List<TextBlock> blocks) => blocks.every(
    (block) =>
        !block.isEmbed &&
        block.runs.every((run) => !run.isMath && run.text.trim().isEmpty),
  );

  @override
  State<TextBoxEditor> createState() => TextBoxEditorState();
}

/// Which kind of change an edit was, so consecutive edits of the same kind can
/// share one undo step.
enum _EditKind { typing, deleting, other }

/// The formula being edited: a run in a block.
typedef _OpenFormula = ({int block, int run});

/// What a pointer press landed on.
class _Hit {
  const _Hit(this.position, {this.formula, this.checkbox = false});

  final RichPosition position;

  /// A typeset formula under the pointer.
  final _OpenFormula? formula;

  /// Whether the press was on a to-do's checkbox.
  final bool checkbox;
}

/// Rich text copied from a text box, kept so that pasting it back keeps its
/// formatting, formulas and embeds. The system clipboard carries only the
/// plain text, which is what other applications receive.
abstract final class _RichClipboard {
  static String? _plain;
  static List<TextBlock>? _fragment;

  static void store(String plain, List<TextBlock> fragment) {
    _plain = plain;
    _fragment = fragment;
  }

  /// The rich fragment matching [plain], if it was copied from here.
  static List<TextBlock>? match(String plain) =>
      plain == _plain ? _fragment : null;
}

class TextBoxEditorState extends State<TextBoxEditor>
    implements DeltaTextInputClient, TextEditorCommands {
  static const Duration _blinkInterval = Duration(milliseconds: 530);
  static const Duration _undoGroupPause = Duration(milliseconds: 1500);
  static const Duration _multiClickWindow = Duration(milliseconds: 450);

  late List<TextBlock> _blocks;
  List<TextBlock>? _lastEmitted;
  RichSelection _selection = const RichSelection.collapsed(RichPosition.zero);
  TextAffinity _affinity = TextAffinity.downstream;

  /// The formula being edited. Its run in [_blocks] holds the source in
  /// [_syntax]; what is reported to the page holds LaTeX ([_stored]).
  _OpenFormula? _formula;

  /// The syntax the open formula's source is in.
  MathMode _syntax = MathMode.linear;

  /// The formula as stored when it was opened, and the source it was shown
  /// as. While the source is as it was, the stored LaTeX is kept exactly
  /// rather than rewritten the way the translation would spell it.
  String? _openedLatex;
  String _openedSource = '';

  /// The Simple source translated last, with the translation: it is needed
  /// both to store the formula and to preview it.
  (String, MathTranslation)? _translation;

  /// What the preview was last told about the formula being edited.
  FormulaSession? _session;
  Rect? _reportedAnchor;

  /// The search whose first match was last reported to [onMatchPlaced].
  SearchTerms? _placedMatchesOf;

  /// The syntax setting this box follows while it is being edited.
  ValueNotifier<MathMode>? _syntaxSetting;

  /// Formatting to use for the next typed text, set by toggling a mark with
  /// nothing selected.
  TextMarks? _pendingMarks;

  /// The horizontal position, in global coordinates, that vertical caret
  /// movement tries to keep.
  double? _goalX;

  final FocusNode _focusNode = FocusNode(debugLabel: 'TextBoxEditor');
  final ValueNotifier<bool> _caretVisible = ValueNotifier<bool>(true);
  Timer? _blinkTimer;

  TextInputConnection? _connection;
  TextEditingValue _imeValue = TextEditingValue.empty;
  TextRange _composing = TextRange.empty;

  final List<GlobalKey> _rowKeys = <GlobalKey>[];
  final List<GlobalKey> _paragraphKeys = <GlobalKey>[];

  _EditKind? _lastEditKind;
  DateTime _lastEditTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _undoBreak = true;

  int? _dragPointer;
  int _touchCount = 0;
  DateTime _lastPress = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastPressPosition = Offset.zero;
  int _clickCount = 0;

  bool _hovering = false;
  Size? _reportedSize;

  /// Whether anything has been written in this box. A new box is only a
  /// caret until then; one whose text has all been deleted keeps its band,
  /// so it can still be moved.
  bool _hadContent = false;

  // ------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    _blocks = _nonEmpty(widget.element.blocks);
    _lastEmitted = widget.element.blocks;
    _selection = RichSelection.collapsed(RichTextEditing.endOf(_blocks));
    _focusNode.addListener(_onFocusChanged);
    if (widget.isEditing) _beginEditing();
  }

  @override
  void didUpdateWidget(TextBoxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(widget.element.blocks, _lastEmitted)) {
      // Changed from outside — undo, redo, or another view of the page. The
      // caret stays as close to where it was as the new text allows.
      _blocks = _nonEmpty(widget.element.blocks);
      _lastEmitted = widget.element.blocks;
      _showOpenFormulaAsSource();
      _selection = RichSelection(
        RichTextEditing.clamp(_blocks, _selection.base),
        RichTextEditing.clamp(_blocks, _selection.extent),
      );
      _undoBreak = true;
      _syncIme();
      // The preview shows what undo left, or closes if the formula is gone.
      _reportFormula();
    }
    if (old.controller != widget.controller && widget.isEditing) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
      _followSyntax(widget.controller);
      _publishState();
    }
    if (widget.isEditing && !old.isEditing) {
      _beginEditing();
    } else if (!widget.isEditing && old.isEditing) {
      _endEditing();
    }
  }

  @override
  void dispose() {
    _followSyntax(null);
    widget.controller?.detach(this);
    _closeConnection();
    _blinkTimer?.cancel();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _caretVisible.dispose();
    super.dispose();
  }

  static List<TextBlock> _nonEmpty(List<TextBlock> blocks) =>
      blocks.isEmpty ? const <TextBlock>[TextBlock()] : blocks;

  void _beginEditing() {
    widget.controller?.attach(this);
    _followSyntax(widget.controller);
    // A click on a formula opens it before the box is attached; tell the
    // preview now.
    if (_formula != null) {
      _session = null;
      _reportFormula();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isEditing) return;
      _focusNode.requestFocus();
      // A click that starts editing asks for focus before this box knows it
      // is being edited, so the focus listener may already have run and
      // passed over the connection; open it here too.
      if (_focusNode.hasFocus) _openConnection();
      if (widget.startInFormula && _formula == null) {
        toggleFormula();
        // A structure chosen on the ribbon before there was a box for it.
        final queued = widget.controller?.takeQueuedMath();
        if (queued != null) insertMath(queued);
      }
    });
    _restartBlink();
    _publishState();
  }

  void _endEditing() {
    _closeFormula(emit: true);
    _followSyntax(null);
    widget.controller?.detach(this);
    _closeConnection();
    _blinkTimer?.cancel();
    if (_focusNode.hasFocus) _focusNode.unfocus();
    setState(() {
      _selection = RichSelection.collapsed(_selection.extent);
      _pendingMarks = null;
    });
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus && widget.isEditing) {
      _openConnection();
      _restartBlink();
    } else {
      _closeConnection();
      _blinkTimer?.cancel();
    }
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------- editing

  /// Commits an edit: shows it, reports it, and keeps the IME in step.
  void _commit(RichEdit edit, _EditKind kind) {
    final now = DateTime.now();
    final record =
        _undoBreak ||
        kind == _EditKind.other ||
        kind != _lastEditKind ||
        now.difference(_lastEditTime) > _undoGroupPause;
    _lastEditKind = kind;
    _lastEditTime = now;
    _undoBreak = false;

    setState(() {
      _blocks = _nonEmpty(edit.blocks);
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
    setState(() {
      _selection = clamped;
      _affinity = affinity;
      _pendingMarks = null;
      if (!keepGoalX) _goalX = null;
    });
    _undoBreak = true;
    _afterChange();
  }

  void _afterChange() {
    _restartBlink();
    _syncIme();
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

  static bool _isMathRun(List<TextBlock> blocks, _OpenFormula formula) =>
      formula.block < blocks.length &&
      formula.run < blocks[formula.block].runs.length &&
      blocks[formula.block].runs[formula.run].isMath;

  BlockView _viewFor(int index) => BlockView(
    _blocks[index],
    openRun: _formula?.block == index ? _formula!.run : null,
  );

  // ---------------------------------------------------------------- typing

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
      _commit(removed, _EditKind.typing);
      _chooseSyntax(MathMode.latex);
      _startFormula();
      return;
    }

    final lines = text.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) _paragraphBreak();
      final line = lines[i];
      if (line.isEmpty) continue;
      final start = _selection.start;
      final marks =
          _pendingMarks ??
          RichTextEditing.marksAt(_blocks[start.block], start.offset);
      final pending = _pendingMarks;
      _commit(
        RichTextEditing.insertText(_blocks, _selection, line, marks: marks),
        _EditKind.typing,
      );
      _pendingMarks = pending;
      if (line == ' ') {
        final shortcut = RichTextEditing.applyMarkdownShortcut(
          _blocks,
          _selection.extent,
        );
        if (shortcut != null) _commit(shortcut, _EditKind.other);
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
      RichTextEditing.insertParagraphBreak(_blocks, _selection),
      _EditKind.other,
    );
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
        _EditKind.deleting,
      );
      return;
    }
    _commit(
      RichTextEditing.deleteRange(_blocks, _selection),
      _EditKind.deleting,
    );
  }

  void _deleteBackward({bool word = false}) {
    if (_formula != null) {
      _deleteInFormula(forward: false, word: word);
      return;
    }
    if (!_selection.isCollapsed) {
      _deleteSelection();
      return;
    }
    final caret = _selection.extent;
    final block = _blocks[caret.block];
    if (caret.offset == 0) {
      _commit(
        RichTextEditing.deleteBackwardAtBlockStart(_blocks, caret.block),
        _EditKind.deleting,
      );
      return;
    }
    if (block.isEmbed) {
      _commit(
        RichTextEditing.deleteEmbed(_blocks, caret.block),
        _EditKind.deleting,
      );
      return;
    }
    final view = _viewFor(caret.block);
    final v = view.toView(caret.offset);
    // The first Backspace after a formula selects it, the second deletes it,
    // so a formula is never lost to a stray keypress — as in OneNote.
    final formula = view.collapsedAt(v - 1);
    if (formula != null) {
      _select(
        RichSelection(
          RichPosition(caret.block, formula.modelEnd),
          RichPosition(caret.block, formula.modelStart),
        ),
      );
      return;
    }
    final target = word ? _wordLeft(view.text, v) : _graphemeLeft(view.text, v);
    _commit(
      RichTextEditing.deleteRange(
        _blocks,
        RichSelection(RichPosition(caret.block, view.toModel(target)), caret),
      ),
      _EditKind.deleting,
    );
  }

  void _deleteForward({bool word = false}) {
    if (_formula != null) {
      _deleteInFormula(forward: true, word: word);
      return;
    }
    if (!_selection.isCollapsed) {
      _deleteSelection();
      return;
    }
    final caret = _selection.extent;
    final block = _blocks[caret.block];
    if (caret.offset == block.length) {
      _commit(
        RichTextEditing.deleteForwardAtBlockEnd(_blocks, caret.block),
        _EditKind.deleting,
      );
      return;
    }
    if (block.isEmbed) {
      _commit(
        RichTextEditing.deleteEmbed(_blocks, caret.block),
        _EditKind.deleting,
      );
      return;
    }
    final view = _viewFor(caret.block);
    final v = view.toView(caret.offset);
    final formula = view.collapsedAt(v);
    if (formula != null) {
      _select(
        RichSelection(
          RichPosition(caret.block, formula.modelStart),
          RichPosition(caret.block, formula.modelEnd),
        ),
      );
      return;
    }
    final target = word
        ? _wordRight(view.text, v)
        : _graphemeRight(view.text, v);
    _commit(
      RichTextEditing.deleteRange(
        _blocks,
        RichSelection(caret, RichPosition(caret.block, view.toModel(target))),
      ),
      _EditKind.deleting,
    );
  }

  // -------------------------------------------------------------- formulas

  /// The syntax formulas are typed in, as the person has chosen it.
  MathMode get _preferredSyntax =>
      widget.controller?.formulaSyntax.value ?? _syntax;

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
    if (syntax == _syntax) return;
    final formula = _formula;
    if (formula == null || !_isMathRun(_blocks, formula)) {
      _syntax = syntax;
      return;
    }
    final run = _blocks[formula.block].runs[formula.run];
    final latex = _latexFor(run.text);
    _syntax = syntax;
    final source = _sourceIn(syntax, latex);
    _openedLatex = latex;
    _openedSource = source;
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, syntax, run.marks),
    );
    final span = _formulaSpan(formula)!;
    setState(() {
      _selection = RichSelection.collapsed(
        RichPosition(formula.block, span.end),
      );
      _goalX = null;
    });
    _undoBreak = true;
    _connection?.updateConfig(_inputConfiguration());
    _afterChange();
    _reportFormula();
  }

  /// [latex] as it is typed in [syntax].
  static String _sourceIn(MathMode syntax, String latex) =>
      syntax == MathMode.latex ? latex : LinearMath.fromLatex(latex);

  MathTranslation _translate(String source) {
    final last = _translation;
    if (last != null && last.$1 == source) return last.$2;
    final translation = LinearMath.translate(source);
    _translation = (source, translation);
    return translation;
  }

  /// The LaTeX the open formula is stored as while its source is [source].
  String _latexFor(String source) {
    final opened = _openedLatex;
    if (opened != null && source == _openedSource) return opened;
    if (_syntax == MathMode.latex || source.trim().isEmpty) return source;
    return _translate(source).latex;
  }

  /// [blocks] as they are stored, with the open formula's source as LaTeX.
  List<TextBlock> _stored(List<TextBlock> blocks) {
    final formula = _formula;
    if (formula == null || !_isMathRun(blocks, formula)) return blocks;
    final run = blocks[formula.block].runs[formula.run];
    if (run.math == MathMode.latex && _syntax == MathMode.latex) {
      return blocks;
    }
    return RichTextEditing.replaceRun(
      blocks,
      formula.block,
      formula.run,
      TextRun.math(_latexFor(run.text), MathMode.latex, run.marks),
    );
  }

  /// After undo or another change from outside, shows the open formula as
  /// source again, or lets it go if it is gone.
  void _showOpenFormulaAsSource() {
    final formula = _formula;
    if (formula == null) return;
    if (!_isMathRun(_blocks, formula)) {
      _formula = null;
      _openedLatex = null;
      return;
    }
    final run = _blocks[formula.block].runs[formula.run];
    final latex = run.math == MathMode.linear
        ? LinearMath.toLatex(run.text)
        : run.text;
    final source = latex == _openedLatex
        ? _openedSource
        : _sourceIn(_syntax, latex);
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, _syntax, run.marks),
    );
  }

  /// Starts a new, empty formula at the caret.
  void _startFormula() {
    _syntax = _preferredSyntax;
    final (edit, :block, :run) = RichTextEditing.insertMath(
      _blocks,
      _selection,
      _syntax,
    );
    final start = RichTextEditing.runSpans(edit.blocks[block])[run].start;
    _formula = (block: block, run: run);
    _openedLatex = null;
    _openedSource = '';
    _commit((
      blocks: edit.blocks,
      selection: RichSelection.collapsed(RichPosition(block, start)),
    ), _EditKind.other);
    _connection?.updateConfig(_inputConfiguration());
    _reportFormula();
  }

  /// Opens an existing formula for editing: shows it as its source, with the
  /// caret at its end or start.
  void _openFormula(_OpenFormula formula, {bool atEnd = true}) {
    if (!_isMathRun(_blocks, formula)) return;
    _syntax = _preferredSyntax;
    final run = _blocks[formula.block].runs[formula.run];
    // Formulas are stored as LaTeX; one from an older page may still be in
    // Simple syntax.
    final legacy = run.math == MathMode.linear;
    final latex = legacy ? LinearMath.toLatex(run.text) : run.text;
    final source = _sourceIn(_syntax, latex);
    _openedLatex = latex;
    _openedSource = source;
    _formula = formula;
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, _syntax, run.marks),
    );
    if (legacy) _emitStored(record: false);
    final span = _formulaSpan(formula)!;
    setState(() {
      _selection = RichSelection.collapsed(
        RichPosition(formula.block, atEnd ? span.end : span.start),
      );
      _pendingMarks = null;
      _goalX = null;
    });
    _undoBreak = true;
    _connection?.updateConfig(_inputConfiguration());
    _afterChange();
    _reportFormula();
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
    final diagnostics = _syntax == MathMode.linear && source.trim().isNotEmpty
        ? _translate(source).diagnostics
        : const <MathDiagnostic>[];
    final session = FormulaSession(
      latex: _latexFor(source),
      error: diagnostics.isEmpty ? null : diagnostics.first.message,
    );
    if (session == _session) return;
    _session = session;
    controller?.reportFormula(this, session, _reportedAnchor);
  }

  /// Reports where the source of the formula being edited has been laid
  /// out, in this box's own page units, so its preview can sit beneath it.
  void _reportFormulaAnchor() {
    final formula = _formula;
    final session = _session;
    if (formula == null || session == null || !mounted) return;
    final paragraph = _paragraph(formula.block);
    final box = context.findRenderObject();
    if (paragraph == null || box is! RenderBox || !paragraph.hasSize) return;
    final layout = _viewFor(formula.block).runAt(formula.run);
    final rects = paragraph.formulaRects(layout.outerStart, layout.outerEnd);
    if (rects.isEmpty) return;
    var rect = rects.first;
    for (final other in rects.skip(1)) {
      rect = rect.expandToInclude(other);
    }
    final anchor = MatrixUtils.transformRect(
      paragraph.getTransformTo(box),
      rect,
    );
    if (anchor == _reportedAnchor) return;
    _reportedAnchor = anchor;
    widget.controller?.reportFormula(this, session, anchor);
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
    final latex = _latexFor(source);
    _formula = null;
    _openedLatex = null;
    _openedSource = '';
    _connection?.updateConfig(_inputConfiguration());
    _reportFormula();
    if (span == null || run == null) return;

    if (source.trim().isEmpty) {
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
        _commit((blocks: blocks, selection: selection), _EditKind.other);
      } else {
        _blocks = _nonEmpty(blocks);
        _selection = selection;
      }
      return;
    }

    // The stored text already has this LaTeX: every edit reported it.
    final blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(latex, MathMode.latex, run.marks),
    );
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
      _blocks = _nonEmpty(blocks);
      _selection = selection;
      return;
    }
    setState(() {
      _blocks = _nonEmpty(blocks);
      _selection = RichSelection(
        RichTextEditing.clamp(_blocks, selection.base),
        RichTextEditing.clamp(_blocks, selection.extent),
      );
      _goalX = null;
    });
    _undoBreak = true;
    _afterChange();
  }

  /// Replaces the selected part of the formula's source with [text], leaving
  /// the caret [caretAt] characters into it, or after it.
  void _replaceInFormula(String text, {int? caretAt}) {
    final formula = _formula!;
    final span = _formulaSpan(formula)!;
    final source = _blocks[formula.block].runs[formula.run].text;
    final from = (_selection.start.offset - span.start).clamp(0, source.length);
    final to = (_selection.end.offset - span.start).clamp(from, source.length);
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
    ), text.isEmpty ? _EditKind.deleting : _EditKind.typing);
  }

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
    final target = forward
        ? (word ? _wordRight(source, local) : _graphemeRight(source, local))
        : (word ? _wordLeft(source, local) : _graphemeLeft(source, local));
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
    ), _EditKind.deleting);
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

  // ------------------------------------------------------------- commands

  @override
  void toggleMark(MarkKind kind) {
    _focusNode.requestFocus();
    if (_formula != null) return;
    final has = kind.isSetIn;

    if (_selection.isCollapsed) {
      final caret = _selection.extent;
      final current =
          _pendingMarks ??
          RichTextEditing.marksAt(_blocks[caret.block], caret.offset);
      setState(() => _pendingMarks = kind.setIn(current, on: !has(current)));
      _publishState();
      return;
    }
    final on = !RichTextEditing.everyMark(_blocks, _selection, has);
    _commit((
      blocks: RichTextEditing.applyMarks(
        _blocks,
        _selection,
        (marks) => kind.setIn(marks, on: on),
      ),
      selection: _selection,
    ), _EditKind.other);
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
      ), _EditKind.other);
      return;
    }
    if (_selection.isCollapsed) {
      final caret = _selection.extent;
      final current =
          _pendingMarks ??
          RichTextEditing.marksAt(_blocks[caret.block], caret.offset);
      setState(() => _pendingMarks = change(current));
      _publishState();
      return;
    }
    _commit((
      blocks: RichTextEditing.applyMarks(_blocks, _selection, change),
      selection: _selection,
    ), _EditKind.other);
  }

  @override
  void setFontSize(double points) =>
      _changeMarks((marks) => marks.withSize(points));

  @override
  void setTextColor(int? color) =>
      _changeMarks((marks) => marks.withColor(color));

  @override
  void setHighlight(int? color) =>
      _changeMarks((marks) => marks.withHighlight(color));

  @override
  void toggleBlockKind(TextBlockKind kind) {
    _focusNode.requestFocus();
    _commit((
      blocks: RichTextEditing.toggleBlockKind(_blocks, _selection, kind),
      selection: _selection,
    ), _EditKind.other);
  }

  @override
  void indent(int delta) {
    _focusNode.requestFocus();
    _commit((
      blocks: RichTextEditing.indentBlocks(_blocks, _selection, delta),
      selection: _selection,
    ), _EditKind.other);
  }

  @override
  void toggleFormula() {
    _focusNode.requestFocus();
    if (_formula != null) {
      _closeFormula(emit: true);
      return;
    }
    // With a formula selected, the shortcut opens it rather than adding
    // another beside it.
    final selected = _selectedFormula();
    if (selected != null) {
      _openFormula(selected);
      return;
    }
    _startFormula();
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

  @override
  void insertMath(MathTemplate template) {
    _focusNode.requestFocus();
    if (_formula == null) {
      final selected = _selectedFormula();
      if (selected != null) {
        _openFormula(selected);
      } else {
        _startFormula();
      }
    }
    final formula = _formula;
    if (formula == null) return;
    final span = _formulaSpan(formula)!;
    final source = _blocks[formula.block].runs[formula.run].text;
    final from = (_selection.start.offset - span.start).clamp(0, source.length);
    final to = (_selection.end.offset - span.start).clamp(from, source.length);

    // Symbols come with a space either side to keep them apart from their
    // neighbours; none is needed against a bracket or another space.
    var text = template.inSyntax(_syntax);
    if (text.startsWith(' ') &&
        (from == 0 || ' ([{'.contains(source[from - 1]))) {
      text = text.substring(1);
    }
    if (text.endsWith(' ') &&
        to < source.length &&
        ' )]},;'.contains(source[to])) {
      text = text.substring(0, text.length - 1);
    }
    final caret = text.indexOf(MathTemplate.caret);
    final clean = text.replaceAll(MathTemplate.caret, '');
    _undoBreak = true;
    _replaceInFormula(clean, caretAt: caret < 0 ? clean.length : caret);
    _undoBreak = true;
  }

  @override
  void finishFormula({bool after = true}) {
    if (_formula == null) return;
    _closeFormula(emit: true, after: after);
    _focusNode.requestFocus();
  }

  @override
  void insertEmbeds(List<BlockEmbed> embeds) {
    if (embeds.isEmpty) return;
    _closeFormula(emit: true);
    _focusNode.requestFocus();
    _commit(
      RichTextEditing.insertFragment(_blocks, _selection, <TextBlock>[
        for (final embed in embeds) TextBlock.embedded(embed),
      ]),
      _EditKind.other,
    );
  }

  void _toggleChecked(int block) {
    if (_blocks[block].kind != TextBlockKind.todo) return;
    _undoBreak = true;
    _commit((
      blocks: RichTextEditing.toggleChecked(_blocks, block),
      selection: _selection,
    ), _EditKind.other);
  }

  void _publishState() {
    final controller = widget.controller;
    if (controller == null || !widget.isEditing) return;
    final formula = _formula;
    final caret = _selection.extent;
    final block = _blocks[caret.block];

    final Set<MarkKind> marks;
    final TextMarks sample;
    if (formula != null) {
      sample = _blocks[formula.block].runs[formula.run].marks;
    } else if (_selection.isCollapsed) {
      sample = _pendingMarks ?? RichTextEditing.marksAt(block, caret.offset);
    } else {
      // A mixed selection shows the formatting where it starts.
      final start = _selection.start;
      final first = _blocks[start.block];
      sample = RichTextEditing.marksAt(
        first,
        math.min(start.offset + 1, first.length),
      );
    }
    if (_selection.isCollapsed) {
      marks = MarkKinds.of(sample);
    } else {
      marks = <MarkKind>{
        for (final kind in MarkKind.values)
          if (RichTextEditing.everyMark(_blocks, _selection, kind.isSetIn))
            kind,
      };
    }

    controller.report(
      this,
      TextFormatState(
        marks: marks,
        blockKind: block.isEmbed ? TextBlockKind.paragraph : block.kind,
        inFormula: formula != null,
        fontSize: sample.size ?? RichTextStyles.defaultPointsFor(block),
        textColor: sample.color,
        highlight: sample.highlight,
      ),
    );
  }

  // ------------------------------------------------------------ clipboard

  Future<void> _copy({bool cut = false}) async {
    if (_selection.isCollapsed) return;
    final formula = _formula;
    if (formula != null) {
      // Part of a formula's source is copied as the text it is.
      final span = _formulaSpan(formula)!;
      final source = _blocks[formula.block].runs[formula.run].text;
      final from = (_selection.start.offset - span.start).clamp(
        0,
        source.length,
      );
      final to = (_selection.end.offset - span.start).clamp(
        from,
        source.length,
      );
      await Clipboard.setData(ClipboardData(text: source.substring(from, to)));
      if (cut && mounted && _formula != null) _replaceInFormula('');
      return;
    }
    final fragment = RichTextEditing.slice(_blocks, _selection);
    final plain = RichTextEditing.plainTextOf(fragment);
    _RichClipboard.store(plain, fragment);
    await Clipboard.setData(ClipboardData(text: plain));
    if (cut && mounted) _deleteSelection();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    if (_formula != null) {
      _undoBreak = true;
      _replaceInFormula(text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
      return;
    }
    final fragment = _RichClipboard.match(text);
    if (fragment != null) {
      _commit(
        RichTextEditing.insertFragment(_blocks, _selection, fragment),
        _EditKind.other,
      );
    } else {
      _undoBreak = true;
      _insertText(text);
    }
  }

  // -------------------------------------------------------------- keyboard

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.isEditing) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return _isTextKey(event)
          ? KeyEventResult.skipRemainingHandlers
          : KeyEventResult.ignored;
    }
    // While the input method is composing — a dead key, an accent, an East
    // Asian candidate — every key belongs to it.
    if (_composing.isValid && !_composing.isCollapsed) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    // AltGr arrives as Ctrl+Alt on Windows. On layouts where it types
    // characters — {, }, [, ], \ and @ on German keyboards, all of which LaTeX
    // needs — the character must win over any shortcut.
    if (control && alt && _producesCharacter(event)) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final handled = _handleKey(
      key,
      event,
      shift: shift,
      alt: alt,
      control: control,
    );
    if (handled != null) return handled;

    if (control || (alt && !_producesCharacter(event))) {
      // Unclaimed shortcuts — Ctrl+S, Ctrl+Z — belong to the page.
      _undoBreak = true;
      return KeyEventResult.ignored;
    }
    // Anything else is text, delivered through the input method. Stopping it
    // here keeps the canvas's single-letter tool shortcuts from seeing it.
    return KeyEventResult.skipRemainingHandlers;
  }

  static bool _producesCharacter(KeyEvent event) {
    final character = event.character;
    return character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 0x20 &&
        character.codeUnitAt(0) != 0x7F;
  }

  static bool _isTextKey(KeyEvent event) => _producesCharacter(event);

  static bool _isFormulaToggle(
    LogicalKeyboardKey key,
    KeyEvent event,
    bool alt,
    bool control,
  ) =>
      (alt &&
          !control &&
          (key == LogicalKeyboardKey.equal || event.character == '=')) ||
      (control && key == LogicalKeyboardKey.keyM);

  KeyEventResult? _handleKey(
    LogicalKeyboardKey key,
    KeyEvent event, {
    required bool shift,
    required bool alt,
    required bool control,
  }) {
    const handled = KeyEventResult.handled;

    // Ctrl+Shift+M switches the syntax formulas are typed in, translating
    // the one being edited.
    if (control && shift && key == LogicalKeyboardKey.keyM) {
      _chooseSyntax(
        _preferredSyntax == MathMode.latex ? MathMode.linear : MathMode.latex,
      );
      return handled;
    }

    // Formula toggles: Alt+= as in OneNote (Alt+Shift+0 on a German
    // keyboard, which is why the character is checked too), or Ctrl+M on any
    // layout.
    if (_isFormulaToggle(key, event, alt, control)) {
      toggleFormula();
      return handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_formula != null) {
        _closeFormula(emit: true);
      } else {
        widget.onExit?.call();
      }
      return handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_formula != null) {
        _closeFormula(emit: true);
      } else if (control) {
        _toggleChecked(_selection.extent.block);
      } else {
        _paragraphBreak();
      }
      return handled;
    }

    if (key == LogicalKeyboardKey.tab) {
      if (_formula != null) {
        _moveToSlot(forward: !shift);
      } else {
        indent(shift ? -1 : 1);
      }
      return handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      _deleteBackward(word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _deleteForward(word: control);
      return handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveHorizontally(-1, extend: shift, word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveHorizontally(1, extend: shift, word: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveVertically(-1, extend: shift);
      return handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveVertically(1, extend: shift);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveToLineEdge(start: true, extend: shift, wholeBox: control);
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveToLineEdge(start: false, extend: shift, wholeBox: control);
      return handled;
    }

    if (!control) return null;

    switch (key) {
      case LogicalKeyboardKey.keyA:
        _selectAll();
        return handled;
      case LogicalKeyboardKey.keyC:
        unawaited(_copy());
        return handled;
      case LogicalKeyboardKey.keyX:
        unawaited(_copy(cut: true));
        return handled;
      case LogicalKeyboardKey.keyV:
        unawaited(_paste());
        return handled;
      case LogicalKeyboardKey.keyB:
        toggleMark(MarkKind.bold);
        return handled;
      case LogicalKeyboardKey.keyI:
        toggleMark(MarkKind.italic);
        return handled;
      case LogicalKeyboardKey.keyU:
        toggleMark(MarkKind.underline);
        return handled;
      case LogicalKeyboardKey.minus when !alt:
        toggleMark(MarkKind.strikethrough);
        return handled;
      case LogicalKeyboardKey.keyE when !shift:
        toggleMark(MarkKind.code);
        return handled;
      case LogicalKeyboardKey.keyH when shift:
        toggleMark(MarkKind.highlight);
        return handled;
      case LogicalKeyboardKey.period:
        toggleBlockKind(TextBlockKind.bulleted);
        return handled;
      case LogicalKeyboardKey.slash:
        toggleBlockKind(TextBlockKind.numbered);
        return handled;
      case LogicalKeyboardKey.digit1 when !alt:
        toggleBlockKind(TextBlockKind.todo);
        return handled;
      case LogicalKeyboardKey.digit1 when alt:
        toggleBlockKind(TextBlockKind.heading1);
        return handled;
      case LogicalKeyboardKey.digit2 when alt:
        toggleBlockKind(TextBlockKind.heading2);
        return handled;
      case LogicalKeyboardKey.digit3 when alt:
        toggleBlockKind(TextBlockKind.heading3);
        return handled;
      case LogicalKeyboardKey.keyN when shift:
        // Normal text, as in OneNote. Toggling to a paragraph always lands on
        // a paragraph.
        toggleBlockKind(TextBlockKind.paragraph);
        return handled;
    }
    return null;
  }

  void _selectAll() {
    final formula = _formula;
    if (formula != null) {
      final span = _formulaSpan(formula)!;
      _select(
        RichSelection(
          RichPosition(formula.block, span.start),
          RichPosition(formula.block, span.end),
        ),
      );
      return;
    }
    _select(RichSelection(RichPosition.zero, RichTextEditing.endOf(_blocks)));
  }

  // ------------------------------------------------------------- movement

  void _moveHorizontally(
    int direction, {
    required bool extend,
    required bool word,
  }) {
    if (!extend && !_selection.isCollapsed) {
      _select(
        RichSelection.collapsed(
          direction < 0 ? _selection.start : _selection.end,
        ),
      );
      return;
    }

    final caret = _selection.extent;
    final formula = _formula;
    if (formula != null && !extend) {
      // At either end of its source the caret steps back out into the text,
      // and the formula is typeset again.
      final span = _formulaSpan(formula)!;
      if (direction < 0 && caret.offset <= span.start) {
        _closeFormula(emit: true, after: false);
        return;
      }
      if (direction > 0 && caret.offset >= span.end) {
        _closeFormula(emit: true);
        return;
      }
    }
    final block = _blocks[caret.block];
    RichPosition? target;
    if (direction < 0) {
      if (caret.offset == 0) {
        if (caret.block > 0) {
          target = RichPosition(
            caret.block - 1,
            _blocks[caret.block - 1].length,
          );
        }
      } else if (block.isEmbed) {
        target = RichPosition(caret.block, 0);
      } else {
        final view = _viewFor(caret.block);
        final v = view.toView(caret.offset);
        final formulaBefore = view.collapsedAt(v - 1);
        if (formulaBefore != null && !extend && !word) {
          // Arrowing into a formula opens it, so it can be edited from the
          // keyboard alone.
          _openFormula((block: caret.block, run: formulaBefore.index));
          return;
        }
        var to = word ? _wordLeft(view.text, v) : _graphemeLeft(view.text, v);
        // The room beside the formula being edited is not text to stop in.
        while (to > 0 && view.toModel(to) == caret.offset) {
          to = word ? _wordLeft(view.text, to) : _graphemeLeft(view.text, to);
        }
        target = RichPosition(caret.block, view.toModel(to));
      }
    } else {
      if (caret.offset == block.length) {
        if (caret.block < _blocks.length - 1) {
          target = RichPosition(caret.block + 1, 0);
        }
      } else if (block.isEmbed) {
        target = RichPosition(caret.block, 1);
      } else {
        final view = _viewFor(caret.block);
        final v = view.toView(caret.offset);
        final formulaAfter = view.collapsedAt(v);
        if (formulaAfter != null && !extend && !word) {
          _openFormula((
            block: caret.block,
            run: formulaAfter.index,
          ), atEnd: false);
          return;
        }
        var to = word ? _wordRight(view.text, v) : _graphemeRight(view.text, v);
        while (to < view.text.length && view.toModel(to) == caret.offset) {
          to = word ? _wordRight(view.text, to) : _graphemeRight(view.text, to);
        }
        target = RichPosition(caret.block, view.toModel(to));
      }
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

    // First try another line of the same block.
    final paragraph = _paragraph(caret.block);
    if (paragraph != null) {
      final localRect = _caretRectLocal(caret);
      if (localRect != null) {
        final y = direction < 0 ? localRect.top - 1 : localRect.bottom + 1;
        if (y >= 0 && y < paragraph.size.height) {
          final local = paragraph.globalToLocal(Offset(goalX, 0));
          final view = _viewFor(caret.block);
          final position = paragraph.paragraph.getPositionForOffset(
            Offset(local.dx, y),
          );
          return RichPosition(caret.block, view.toModel(position.offset));
        }
      }
    }

    // Then the nearest line of the neighbouring block.
    final next = caret.block + direction;
    if (next < 0) return RichPosition(caret.block, 0);
    if (next >= _blocks.length) {
      return RichPosition(caret.block, _blocks[caret.block].length);
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

  static int _graphemeLeft(String text, int offset) {
    if (offset <= 0) return 0;
    final range = CharacterRange.at(text, offset);
    return range.moveBack() ? range.stringBeforeLength : 0;
  }

  static int _graphemeRight(String text, int offset) {
    if (offset >= text.length) return text.length;
    final range = CharacterRange.at(text, offset);
    return range.moveNext()
        ? text.length - range.stringAfterLength
        : text.length;
  }

  static bool _isWordChar(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      (unit >= 0xC0 && unit != 0xD7 && unit != 0xF7 && unit != 0xFFFC);

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x0A;

  static int _wordLeft(String text, int offset) {
    var i = offset;
    while (i > 0 && _isSpace(text.codeUnitAt(i - 1))) {
      i--;
    }
    if (i == 0) return 0;
    if (!_isWordChar(text.codeUnitAt(i - 1))) return i - 1;
    while (i > 0 && _isWordChar(text.codeUnitAt(i - 1))) {
      i--;
    }
    return i;
  }

  static int _wordRight(String text, int offset) {
    var i = offset;
    while (i < text.length && _isSpace(text.codeUnitAt(i))) {
      i++;
    }
    if (i == text.length) return i;
    if (!_isWordChar(text.codeUnitAt(i))) return i + 1;
    while (i < text.length && _isWordChar(text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  // ----------------------------------------------------------------- layout

  RenderBlockParagraph? _paragraph(int index) {
    if (index >= _paragraphKeys.length) return null;
    final object = _paragraphKeys[index].currentContext?.findRenderObject();
    return object is RenderBlockParagraph && object.hasSize ? object : null;
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
    return paragraph.caretRect(view.toView(position.offset), _affinity);
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

  /// Finds the text position under a global point.
  _Hit? _hitTest(Offset global) {
    // The block whose row is vertically closest to the point.
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _blocks.length; i++) {
      final row = _row(i);
      if (row == null) continue;
      final local = row.globalToLocal(global);
      final distance = local.dy < 0
          ? -local.dy
          : (local.dy > row.size.height ? local.dy - row.size.height : 0.0);
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
      if (distance == 0) break;
    }
    if (best < 0) return null;

    final block = _blocks[best];
    if (block.isEmbed) {
      final row = _row(best)!;
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
      if (!run.collapsed) continue;
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

  // --------------------------------------------------------------- pointer

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
        event.buttons & kPrimaryMouseButton == 0) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    if (box.globalToLocal(event.position).dy < TextBoxEditor.grabBand) return;

    final hit = _hitTest(event.position);
    if (hit == null) return;
    if (hit.checkbox) {
      _toggleChecked(hit.position.block);
      return;
    }
    if (!widget.isEditing) widget.onStartEditing?.call();
    _focusNode.requestFocus();

    final now = DateTime.now();
    final isRepeat =
        now.difference(_lastPress) < _multiClickWindow &&
        (event.position - _lastPressPosition).distance < 6;
    _clickCount = isRepeat ? (_clickCount % 3) + 1 : 1;
    _lastPress = now;
    _lastPressPosition = event.position;
    _dragPointer = event.pointer;

    // A click in the source of the formula being edited places the caret in
    // it, the tinted margin around it included.
    final formula = _formula;
    if (formula != null && _clickCount == 1) {
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

    switch (_clickCount) {
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

  RichPosition? _hitInOpenFormula(Offset global, _OpenFormula formula) {
    final paragraph = _paragraph(formula.block);
    final span = _formulaSpan(formula);
    if (paragraph == null || span == null) return null;
    final view = _viewFor(formula.block);
    final layout = view.runAt(formula.run);
    final local = paragraph.globalToLocal(global);
    final rects = paragraph.formulaRects(layout.outerStart, layout.outerEnd);
    if (!rects.any((rect) => rect.inflate(2).contains(local))) return null;
    final position = paragraph.paragraph.getPositionForOffset(local);
    final model = view.toModel(position.offset).clamp(span.start, span.end);
    return RichPosition(formula.block, model);
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
        final from = _wordLeft(source, _wordRight(source, local));
        final to = _wordRight(source, from);
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
    final end = _wordRight(view.text, v);
    final start = _wordLeft(view.text, end);
    _select(
      RichSelection(
        RichPosition(position.block, view.toModel(start)),
        RichPosition(position.block, view.toModel(end)),
      ),
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _dragPointer || _clickCount != 1) return;
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
  }

  // ------------------------------------------------------------------ caret

  void _restartBlink() {
    _blinkTimer?.cancel();
    _caretVisible.value = true;
    // Tests turn blinking off through the framework's own switch, so that
    // waiting for the page to settle does not wait on the caret forever.
    if (!widget.isEditing || EditableText.debugDeterministicCursor) return;
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      _caretVisible.value = !_caretVisible.value;
    });
  }

  // ---------------------------------------------------------- input method

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

  void _openConnection() {
    if (_connection?.attached ?? false) return;
    _imeValue = _currentValue();
    _connection = TextInput.attach(this, _inputConfiguration())
      ..show()
      ..setEditingState(_imeValue);
    _scheduleImeGeometry();
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
    _composing = TextRange.empty;
  }

  /// The current block as the input method sees it.
  TextEditingValue _currentValue() {
    final extent = _selection.extent;
    if (extent.block >= _blocks.length || _blocks[extent.block].isEmbed) {
      return TextEditingValue.empty;
    }
    final view = _viewFor(extent.block);
    final extentView = view.toView(extent.offset);
    final baseView = _selection.base.block == extent.block
        ? view.toView(_selection.base.offset)
        : extentView;
    final composing = _composing.isValid && _composing.end <= view.text.length
        ? _composing
        : TextRange.empty;
    return TextEditingValue(
      text: view.text,
      selection: TextSelection(baseOffset: baseView, extentOffset: extentView),
      composing: composing,
    );
  }

  void _syncIme() {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    final value = _currentValue();
    if (value != _imeValue) {
      _imeValue = value;
      connection.setEditingState(value);
    }
    _scheduleImeGeometry();
  }

  void _scheduleImeGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connection = _connection;
      if (!mounted || connection == null || !connection.attached) return;
      final caret = _selection.extent;
      final paragraph = _paragraph(caret.block);
      if (paragraph == null) return;
      connection.setEditableSizeAndTransform(
        paragraph.size,
        paragraph.getTransformTo(null),
      );
      final rect = _caretRectLocal(caret);
      if (rect != null) connection.setCaretRect(rect);
    });
  }

  @override
  TextEditingValue? get currentTextEditingValue => _imeValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // Only used without the delta model, which this client never requests.
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (!widget.isEditing) return;
    for (final delta in deltas) {
      _imeValue = delta.apply(_imeValue);
      switch (delta) {
        case TextEditingDeltaInsertion():
          _applyImeEdit(
            TextRange.collapsed(delta.insertionOffset),
            delta.textInserted,
          );
        case TextEditingDeltaDeletion():
          _applyImeEdit(delta.deletedRange, '');
        case TextEditingDeltaReplacement():
          _applyImeEdit(delta.replacedRange, delta.replacementText);
        case TextEditingDeltaNonTextUpdate():
          _applyImeSelection(delta.selection);
      }
      _composing = delta.composing;
    }
    if (mounted) setState(() {});
    _syncIme();
  }

  /// Applies a change the input method made to the current block's text.
  void _applyImeEdit(TextRange range, String text) {
    final caret = _selection.extent;
    if (_blocks[caret.block].isEmbed) {
      _insertText(text);
      return;
    }
    final view = _viewFor(caret.block);
    final start = range.start.clamp(0, view.text.length);
    final end = range.end.clamp(start, view.text.length);

    final formula = _formula;
    if (formula != null && formula.block == caret.block) {
      final layout = view.runAt(formula.run);
      if (start >= layout.viewStart && end <= layout.viewEnd) {
        setState(() {
          _selection = RichSelection(
            RichPosition(caret.block, view.toModel(start)),
            RichPosition(caret.block, view.toModel(end)),
          );
        });
        _replaceInFormula(text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
        return;
      }
      // An edit beside the formula: finish it, and type after it.
      _closeFormula(emit: true);
      if (text == '\n') {
        _paragraphBreak();
      } else if (text.isNotEmpty) {
        _insertText(text);
      }
      return;
    }

    // A selection reaching beyond this block is replaced as a whole; the input
    // method only ever sees the block holding the caret.
    if (!_selection.isMultiBlock) {
      setState(() {
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
    if (_blocks[caret.block].isEmbed || !selection.isValid) return;
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

  @override
  void performAction(TextInputAction action) {
    // Enter arrives as a newline inserted through the delta model.
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    _composing = TextRange.empty;
  }

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  bool onFocusReceived() => false;

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {}

  // ------------------------------------------------------------------ build

  void _ensureKeys() {
    while (_rowKeys.length < _blocks.length) {
      _rowKeys.add(GlobalKey());
      _paragraphKeys.add(GlobalKey());
    }
  }

  /// Where the search's words are in block [index], laid out as [view].
  List<TextRange> _matchesIn(int index, BlockView view) {
    final terms = widget.highlight;
    if (terms == null) return const <TextRange>[];
    return <TextRange>[
      for (final match in TextBoxEditor.matchesIn(_blocks[index], terms))
        TextRange(start: view.toView(match.start), end: view.toView(match.end)),
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

  BlockDecoration _decorationFor(int index, BlockView view, bool focused) {
    final matches = _matchesIn(index, view);
    if (!widget.isEditing) {
      return matches.isEmpty
          ? BlockDecoration.none
          : BlockDecoration(matches: matches);
    }
    final start = _selection.start;
    final end = _selection.end;

    TextSelection? selection;
    if (!_selection.isCollapsed && index >= start.block && index <= end.block) {
      final from = index == start.block ? view.toView(start.offset) : 0;
      final to = index == end.block
          ? view.toView(end.offset)
          : view.text.length;
      if (to > from) {
        selection = TextSelection(baseOffset: from, extentOffset: to);
      }
    }

    final caret = _selection.extent;
    final formula = _formula;
    TextRange? formulaRange;
    if (formula != null && formula.block == index) {
      final layout = view.runAt(formula.run);
      formulaRange = TextRange(start: layout.outerStart, end: layout.outerEnd);
    }

    return BlockDecoration(
      selection: selection,
      caret: focused && _selection.isCollapsed && caret.block == index
          ? view.toView(caret.offset)
          : null,
      caretAffinity: _affinity,
      composing: caret.block == index ? _composing : null,
      formula: formulaRange,
      matches: matches,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = RichTextStyles.base(context);
    final focused = _focusNode.hasFocus;
    final autoWidth = widget.element.autoWidth;
    final empty = TextBoxEditor.isEmpty(_blocks);

    final paint = BlockPaint(
      caretColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.22),
      formulaColor: RichTextStyles.formulaFill,
      formulaOutline: RichTextStyles.formulaOutline,
      composingColor: RichTextStyles.ink,
      matchColor: RichTextStyles.searchMatch,
    );

    final ordinals = _ordinals();
    final rows = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      rows.add(
        _buildBlock(i, base, scheme, paint, ordinals[i], focused, autoWidth),
      );
    }
    if (_formula != null && widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportFormulaAnchor(),
      );
    }
    if (widget.onMatchPlaced != null &&
        !identical(widget.highlight, _placedMatchesOf)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _placeFirstMatch());
    }

    // Until something is typed, a new box is only a caret on the paper, as in
    // OneNote: no band to drag it by, no outline.
    if (!empty) _hadContent = true;
    final showChrome = empty
        ? widget.isEditing && _hadContent
        : widget.isEditing || _hovering;
    final content = Stack(
      children: <Widget>[
        Padding(
          padding: TextBoxEditor.padding.copyWith(
            top: TextBoxEditor.padding.top + TextBoxEditor.grabBand,
          ),
          child: Column(
            crossAxisAlignment: autoWidth
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TextBoxEditor.grabBand,
          child: _GrabBand(visible: showChrome, active: widget.isEditing),
        ),
      ],
    );

    return MouseRegion(
      cursor: widget.interactive ? SystemMouseCursors.text : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border:
                  _hovering && !widget.isEditing && widget.interactive && !empty
                  ? Border.all(color: RichTextStyles.boxOutline)
                  : null,
            ),
            // The content is laid out at its natural size and reported, so
            // the box can grow to fit it; until the frame catches up, the
            // overflow still paints.
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: autoWidth ? TextBoxEditor.minAutoWidth : null,
              maxWidth: autoWidth ? TextBoxEditor.maxAutoWidth : null,
              minHeight: 0,
              maxHeight: double.infinity,
              child: _SizeReporter(onSize: _reportSize, child: content),
            ),
          ),
        ),
      ),
    );
  }

  void _reportSize(Size size) {
    final reported = _reportedSize;
    if (reported != null &&
        (size.width - reported.width).abs() < 0.5 &&
        (size.height - reported.height).abs() < 0.5) {
      return;
    }
    _reportedSize = size;
    final frame = widget.element.frame;
    final widthChanged =
        widget.element.autoWidth && (size.width - frame.width).abs() >= 0.5;
    if (widthChanged || (size.height - frame.height).abs() >= 0.5) {
      widget.onSizeChanged?.call(size);
    }
  }

  /// Numbers for numbered lists, restarting per list and per nesting level.
  List<int> _ordinals() {
    final ordinals = List<int>.filled(_blocks.length, 0);
    final counters = <int>[];
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final level = block.indent;
      if (block.kind == TextBlockKind.numbered && !block.isEmbed) {
        while (counters.length <= level) {
          counters.add(0);
        }
        counters.length = level + 1;
        counters[level]++;
        ordinals[i] = counters[level];
      } else if (counters.length > level) {
        counters.length = level;
      }
    }
    return ordinals;
  }

  Widget _buildBlock(
    int index,
    TextStyle base,
    ColorScheme scheme,
    BlockPaint paint,
    int ordinal,
    bool focused,
    bool autoWidth,
  ) {
    final block = _blocks[index];
    final indent = block.indent * RichTextStyles.indentStep;

    if (block.isEmbed) {
      final start = _selection.start;
      final end = _selection.end;
      final selected =
          widget.isEditing &&
          !_selection.isCollapsed &&
          start <= RichPosition(index, 0) &&
          end >= RichPosition(index, 1);
      final caret = _selection.extent;
      return KeyedSubtree(
        key: _rowKeys[index],
        child: Padding(
          padding: EdgeInsets.only(left: indent, top: 2, bottom: 4),
          child: _EmbedBlock(
            embed: block.embed!,
            selected: selected,
            caretSide:
                widget.isEditing &&
                    focused &&
                    _selection.isCollapsed &&
                    caret.block == index
                ? caret.offset
                : null,
            caretVisible: _caretVisible,
            caretColor: paint.caretColor,
            caretWidth: paint.caretWidth,
          ),
        ),
      );
    }

    final view = _viewFor(index);
    final blockStyle = RichTextStyles.blockStyle(block.kind, base);
    final paragraph = BlockParagraph(
      key: _paragraphKeys[index],
      decoration: _decorationFor(index, view, focused),
      paint: paint,
      caretVisible: _caretVisible,
      child: RichText(
        text: view.span(base: base),
        textAlign: view.isDisplayFormula ? TextAlign.center : TextAlign.start,
        textScaler: TextScaler.noScaling,
        // A box sizing itself to its text measures its longest line; a box of
        // fixed width gives every paragraph the full width, so a lone formula
        // can be centred in it.
        textWidthBasis: autoWidth
            ? TextWidthBasis.longestLine
            : TextWidthBasis.parent,
      ),
    );

    final marker = _marker(block, blockStyle, scheme, ordinal);
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
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        child: row,
      );
    } else if (block.kind == TextBlockKind.code) {
      row = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: row,
      );
    }

    return KeyedSubtree(
      key: _rowKeys[index],
      child: Padding(padding: const EdgeInsets.only(bottom: 2), child: row),
    );
  }

  Widget? _marker(
    TextBlock block,
    TextStyle style,
    ColorScheme scheme,
    int ordinal,
  ) {
    final muted = style.copyWith(color: scheme.onSurfaceVariant);
    switch (block.kind) {
      case TextBlockKind.bulleted:
        return _Bullet(
          level: block.indent,
          color: scheme.onSurfaceVariant,
          fontSize: style.fontSize ?? RichTextStyles.bodySize,
          lineHeight:
              (style.fontSize ?? RichTextStyles.bodySize) *
              (style.height ?? 1.4),
        );
      case TextBlockKind.numbered:
        return Text(
          '${_ordinalLabel(ordinal, block.indent)}.',
          style: muted,
          textScaler: TextScaler.noScaling,
        );
      case TextBlockKind.todo:
        final size = (style.fontSize ?? RichTextStyles.bodySize) * 1.1;
        final lineHeight =
            (style.fontSize ?? RichTextStyles.bodySize) * (style.height ?? 1.4);
        return Padding(
          padding: EdgeInsets.only(top: math.max(0, (lineHeight - size) / 2)),
          child: Align(
            alignment: Alignment.topLeft,
            child: Icon(
              block.checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: size,
              color: block.checked ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        );
      case TextBlockKind.paragraph:
      case TextBlockKind.heading1:
      case TextBlockKind.heading2:
      case TextBlockKind.heading3:
      case TextBlockKind.code:
      case TextBlockKind.quote:
        return null;
    }
  }

  /// 1, 2, 3 at the top level; a, b, c beneath; i, ii, iii beneath that.
  static String _ordinalLabel(int n, int level) {
    switch (level % 3) {
      case 1:
        var value = n;
        final letters = StringBuffer();
        while (value > 0) {
          value--;
          letters.write(String.fromCharCode(0x61 + value % 26));
          value ~/= 26;
        }
        return letters.toString().split('').reversed.join();
      case 2:
        const numerals = <(int, String)>[
          (1000, 'm'),
          (900, 'cm'),
          (500, 'd'),
          (400, 'cd'),
          (100, 'c'),
          (90, 'xc'),
          (50, 'l'),
          (40, 'xl'),
          (10, 'x'),
          (9, 'ix'),
          (5, 'v'),
          (4, 'iv'),
          (1, 'i'),
        ];
        var value = n;
        final out = StringBuffer();
        for (final (amount, symbol) in numerals) {
          while (value >= amount) {
            out.write(symbol);
            value -= amount;
          }
        }
        return out.toString();
      default:
        return '$n';
    }
  }
}

/// A list bullet, drawn rather than typed so it looks the same whatever fonts
/// are installed: a disc, then a circle, then a square as lists nest.
class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.level,
    required this.color,
    required this.fontSize,
    required this.lineHeight,
  });

  final int level;
  final Color color;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: lineHeight,
    child: CustomPaint(
      painter: _BulletPainter(
        level: level,
        color: color,
        size: fontSize * 0.34,
      ),
    ),
  );
}

class _BulletPainter extends CustomPainter {
  const _BulletPainter({
    required this.level,
    required this.color,
    required this.size,
  });

  final int level;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final center = Offset(size, area.height / 2);
    final paint = Paint()..color = color;
    switch (level % 3) {
      case 0:
        canvas.drawCircle(center, size / 2, paint);
      case 1:
        canvas.drawCircle(
          center,
          size / 2 - 0.5,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
      default:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: size * 0.85,
            height: size * 0.85,
          ),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_BulletPainter old) =>
      old.level != level || old.color != color || old.size != size;
}

/// The strip along the top of a text box that moves it when dragged.
class _GrabBand extends StatelessWidget {
  const _GrabBand({required this.visible, required this.active});

  final bool visible;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Drawn on the paper, so in the paper's colours rather than the theme's.
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: SizedBox(
        height: TextBoxEditor.grabBand,
        child: visible
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? RichTextStyles.boxBandActive
                      : RichTextStyles.boxBand,
                ),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                      color: RichTextStyles.boxGrip,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// A picture or PDF page on its own line inside a text box.
class _EmbedBlock extends StatelessWidget {
  const _EmbedBlock({
    required this.embed,
    required this.selected,
    required this.caretSide,
    required this.caretVisible,
    required this.caretColor,
    required this.caretWidth,
  });

  final BlockEmbed embed;
  final bool selected;

  /// 0 or 1 when the caret sits before or after the object.
  final int? caretSide;
  final ValueListenable<bool> caretVisible;
  final Color caretColor;
  final double caretWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(embed.width, constraints.maxWidth);
        final height = width / embed.aspectRatio;
        final side = caretSide;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: switch (embed.kind) {
                    EmbedKind.image => AssetImageView(assetId: embed.assetId),
                    EmbedKind.pdfPage => PdfPageView(
                      assetId: embed.assetId,
                      pageIndex: embed.pageIndex,
                    ),
                  },
                ),
                if (selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.18),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                if (side != null)
                  Positioned(
                    left: side == 0 ? -caretWidth - 1 : null,
                    right: side == 1 ? -caretWidth - 1 : null,
                    top: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: caretVisible,
                      builder: (context, visible, _) => Container(
                        width: caretWidth,
                        color: visible ? caretColor : Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reports its child's laid-out size after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  _RenderSizeReporter createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (_last == measured) return;
    _last = measured;
    // Reported after the frame: resizing the box is a state change, which
    // must not happen in the middle of layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
