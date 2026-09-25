/// The text box: rich text, formulas, pictures and PDF pages, edited in place.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_spell/aantekening_spell.dart' show WordSpan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../command_menu.dart';
import '../../commands/editor_keys.dart';
import '../../look/tones.dart';
import '../../spelling/proofreader.dart';
import '../note_clipboard.dart';
import 'block_paragraph.dart';
import 'block_view.dart';
import 'block_widgets.dart';
import 'formula_source.dart';
import 'list_numbering.dart';
import 'math_templates.dart';
import 'text_box_controller.dart';
import 'text_boundaries.dart';
import 'table_view.dart';
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
    this.selected = false,
    this.controller,
    this.interactive = true,
    this.startInFormula = false,
    this.onStartEditing,
    this.onChanged,
    this.onSizeChanged,
    this.onExit,
    this.highlight,
    this.mark,
    this.proofreader,
    this.onMatchPlaced,
    this.onPasteElements,
    this.onEmbedToBackground,
    this.pageId,
    this.onOpenLink,
  });

  final TextElement element;

  /// Whether this box has the caret.
  final bool isEditing;

  /// Whether the box is picked on the page. Its band shows while it is, so
  /// it stays in view as the box is dragged about, whatever the pointer
  /// passes over.
  final bool selected;

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

  /// Words to mark in one paragraph: those a followed link points at.
  final WordsMark? mark;

  /// What marks the words spelled wrongly, if spelling is checked.
  final Proofreader? proofreader;

  /// Told where the first word [highlight] marks lies, in the box's own page
  /// units, once it has been laid out: for the page to bring it into view.
  final ValueChanged<Rect>? onMatchPlaced;

  /// Asks the host to put things copied from the page onto the page
  /// instead of into the text: a drawing, which cannot go into text, or
  /// anything pasted at a bare caret, which is where it goes.
  final ValueChanged<List<NoteElement>>? onPasteElements;

  /// Asks the host to make the picture or PDF page on block [block] part of
  /// the page's background, where it is: [local], in the box's own units.
  final void Function(int block, Rect local)? onEmbedToBackground;

  /// The page the box is on, for links to a paragraph of it.
  final String? pageId;

  /// Opens a link in the text, clicked with Ctrl held or opened from the
  /// menu: to a note, or on the web.
  final ValueChanged<String>? onOpenLink;

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
      terms.matchesIn(textOf(block));

  /// [block]'s text with each formula — and, unless [code] is set, each
  /// stretch of code — written as as many spaces as it is long, so offsets
  /// stay the model's and the words either side of it stay apart.
  static String textOf(TextBlock block, {bool code = true}) => <String>[
    for (final run in block.runs)
      run.isMath || (!code && run.marks.code)
          ? ' ' * run.text.length
          : run.text,
  ].join();

  /// Whether [blocks] hold nothing worth keeping: no text, no formula, no
  /// embed and no table. An empty box is removed when editing ends.
  static bool isEmpty(List<TextBlock> blocks) => blocks.every(
    (block) =>
        !block.isEmbed &&
        !block.inTable &&
        block.runs.every((run) => !run.isMath && run.text.trim().isEmpty),
  );

  @override
  State<TextBoxEditor> createState() => TextBoxEditorState();
}

/// Words of a paragraph of a text box: offsets [from] to [to] of its
/// [block]th paragraph's text.
typedef WordsMark = ({int block, int from, int to});

/// Which kind of change an edit was, so consecutive edits of the same kind can
/// share one undo step.
enum _EditKind { typing, deleting, resizing, other }

/// The formula being edited: a run in a block.
typedef _OpenFormula = ({int block, int run});

/// What a pointer press landed on.
class _Hit {
  const _Hit(
    this.position, {
    this.formula,
    this.checkbox = false,
    this.embed = false,
  });

  final RichPosition position;

  /// A typeset formula under the pointer.
  final _OpenFormula? formula;

  /// Whether the press was on a to-do's checkbox.
  final bool checkbox;

  /// Whether the press was on a picture or PDF page itself, rather than
  /// beside it on its line.
  final bool embed;
}

class TextBoxEditorState extends State<TextBoxEditor>
    implements DeltaTextInputClient, TextEditorCommands {
  static const Duration _blinkInterval = Duration(milliseconds: 530);
  static const Duration _undoGroupPause = Duration(milliseconds: 1500);
  static const Duration _multiClickWindow = Duration(milliseconds: 450);

  /// The smallest an object in the text may be resized to, in page units.
  static const double _minEmbedWidth = 24;

  late List<TextBlock> _blocks;
  List<TextBlock>? _lastEmitted;
  RichSelection _selection = const RichSelection.collapsed(RichPosition.zero);
  TextAffinity _affinity = TextAffinity.downstream;

  /// The formula being edited. Its run in [_blocks] holds its source, in
  /// [FormulaSource.syntax]; what is reported to the page holds LaTeX
  /// ([_stored]).
  _OpenFormula? _formula;
  final FormulaSource _source = FormulaSource();

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
  final List<GlobalKey> _contentKeys = <GlobalKey>[];

  _EditKind? _lastEditKind;
  DateTime _lastEditTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _undoBreak = true;

  int? _dragPointer;

  /// The object being resized by one of its corners: which block it is on,
  /// which corner is held, where the drag began and how wide it was then.
  ({int block, EmbedCorner corner, Offset from, double width})? _resize;

  /// The table column being resized by its right-hand line: the block the
  /// table starts on, the column, where the drag began and how wide the
  /// column was then.
  ({int table, int column, Offset from, double width})? _columnResize;

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
    _blocks = _wellFormed(widget.element.blocks);
    _lastEmitted = widget.element.blocks;
    _selection = RichSelection.collapsed(RichTextEditing.endOf(_blocks));
    _focusNode.addListener(_onFocusChanged);
    widget.proofreader?.addListener(_onProofread);
    if (widget.isEditing) _beginEditing();
  }

  @override
  void didUpdateWidget(TextBoxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.proofreader != widget.proofreader) {
      old.proofreader?.removeListener(_onProofread);
      widget.proofreader?.addListener(_onProofread);
    }
    if (!identical(widget.element.blocks, _lastEmitted)) {
      // Changed from outside — undo, redo, or another view of the page. The
      // caret stays as close to where it was as the new text allows.
      _blocks = _wellFormed(widget.element.blocks);
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
    widget.proofreader?.removeListener(_onProofread);
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

  /// Verdicts on the spelling of words in the box have come in.
  void _onProofread() => setState(() {});

  /// [blocks] as the box shows them: at least one line, and every table a
  /// whole grid.
  static List<TextBlock> _wellFormed(List<TextBlock> blocks) => blocks.isEmpty
      ? const <TextBlock>[TextBlock()]
      : TextTables.normalize(blocks);

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
      final marks = _typingMarks();
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
      TableEditing.insertBreak(_blocks, _selection) ??
          RichTextEditing.insertParagraphBreak(_blocks, _selection),
      _EditKind.other,
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
      _commit(edit, _EditKind.other);
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
        _EditKind.deleting,
      );
      return;
    }
    // Selected cells go as selected text does: rows and columns taken in
    // whole go with them.
    _commit(
      RichTextEditing.deleteRange(_blocks, _selection, closeUp: true),
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
        TableEditing.deleteBackward(_blocks, caret.block) ??
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
    final target = word
        ? TextBoundaries.wordBefore(view.text, v)
        : TextBoundaries.characterBefore(view.text, v);
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
        ? TextBoundaries.wordAfter(view.text, v)
        : TextBoundaries.characterAfter(view.text, v);
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
    final source = FormulaSource.sourceIn(syntax, latex);
    _source.opened(latex, source);
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
    _source.closed();
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
    _source.syntax = _preferredSyntax;
    final run = _blocks[formula.block].runs[formula.run];
    // Formulas are stored as LaTeX; one from an older page may still be in
    // Simple syntax.
    final legacy = run.math == MathMode.linear;
    final latex = LinearMath.latexFor(run.math!, run.text);
    final source = FormulaSource.sourceIn(_source.syntax, latex);
    _source.opened(latex, source);
    _formula = formula;
    _blocks = RichTextEditing.replaceRun(
      _blocks,
      formula.block,
      formula.run,
      TextRun.math(source, _source.syntax, run.marks),
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
    final diagnostics = _source.diagnostics(source);
    final session = FormulaSession(
      latex: _source.latexFor(source),
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
    final latex = _source.latexFor(source);
    _formula = null;
    _source.closed();
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
        _blocks = _wellFormed(blocks);
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
      _blocks = _wellFormed(blocks);
      _selection = selection;
      return;
    }
    setState(() {
      _blocks = _wellFormed(blocks);
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
    ), text.isEmpty ? _EditKind.deleting : _EditKind.typing);
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
    ), _EditKind.other);
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
    ), _EditKind.other);
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
    final target = forward
        ? (word
              ? TextBoundaries.wordAfter(source, local)
              : TextBoundaries.characterAfter(source, local))
        : (word
              ? TextBoundaries.wordBefore(source, local)
              : TextBoundaries.characterBefore(source, local));
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
    if (_formula != null) {
      // In a formula only a highlight means anything.
      if (kind == MarkKind.highlight) {
        _highlightInFormula(RichTextStyles.highlightYellow, toggle: true);
      }
      return;
    }
    final has = kind.isSetIn;

    if (_selection.isCollapsed) {
      final current = _typingMarks();
      setState(() => _pendingMarks = kind.setIn(current, on: !has(current)));
      _publishState();
      return;
    }
    if (kind == MarkKind.highlight) {
      _highlightSelection(
        _selectionHighlighted() ? null : RichTextStyles.highlightYellow,
      );
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
      ), _EditKind.other);
      return;
    }
    if (_selection.isCollapsed) {
      setState(() => _pendingMarks = change(_typingMarks()));
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

  /// Highlights the selection, or with nothing selected what is typed next.
  /// In the formula being edited it is the part of its source selected, or
  /// the highlight the selection lies in, or the whole formula.
  @override
  void setHighlight(int? color) {
    _focusNode.requestFocus();
    if (_formula != null) {
      _highlightInFormula(color);
    } else if (!_selection.isCollapsed) {
      _highlightSelection(color);
    } else {
      _changeMarks((marks) => marks.withHighlight(color));
    }
  }

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
    var text = template.inSyntax(_source.syntax);
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
      sample = _typingMarks();
    } else {
      // A mixed selection shows the formatting where it starts.
      final start = _selection.start;
      final first = _blocks[start.block];
      sample = RichTextEditing.marksAt(
        first,
        math.min(start.offset + 1, first.length),
      );
    }
    final highlighted = formula != null
        ? _highlightAtSelection(formula) != null
        : _selection.isCollapsed
        ? sample.highlight != null
        : _selectionHighlighted();
    marks = <MarkKind>{
      for (final kind in MarkKind.values)
        if (kind != MarkKind.highlight &&
            (_selection.isCollapsed
                ? kind.isSetIn(sample)
                : RichTextEditing.everyMark(_blocks, _selection, kind.isSetIn)))
          kind,
      if (highlighted) MarkKind.highlight,
    };

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
      final (:source, :from, :to) = _sourceSelection(formula);
      await NoteClipboard.copy(PlainClip(source.substring(from, to)));
      if (cut && mounted && _formula != null) _replaceInFormula('');
      return;
    }
    final fragment = RichTextEditing.slice(_blocks, _selection);
    await NoteClipboard.copy(
      TextClip(RichTextEditing.plainTextOf(fragment), fragment),
    );
    if (cut && mounted) _deleteSelection();
  }

  /// Pastes what was copied — as it was, or as its text only — over the
  /// selection. Things copied from the page go into the text where they can
  /// — text boxes as their text, pictures and PDF pages as objects in it —
  /// and onto the page where they cannot, or where there is no text yet to
  /// put them in: at a bare caret on the paper.
  Future<void> _paste({bool textOnly = false}) async {
    final clip = textOnly
        ? await NoteClipboard.readText()
        : await NoteClipboard.read();
    if (clip == null || !mounted) return;
    if (_formula != null) {
      _undoBreak = true;
      _replaceInFormula(clip.plain.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
      return;
    }
    final blocks = switch (clip) {
      PlainClip() => null,
      TextClip(:final blocks) => blocks,
      // At a bare caret, things from the page are pasted as themselves.
      ElementsClip() when TextBoxEditor.isEmpty(_blocks) => null,
      ElementsClip(:final asBlocks) => asBlocks,
    };
    if (blocks != null) {
      _commit(
        RichTextEditing.insertFragment(_blocks, _selection, blocks),
        _EditKind.other,
      );
    } else if (clip is ElementsClip) {
      widget.onPasteElements?.call(clip.elements);
    } else if (_isLink(clip.plain.trim())) {
      // A link pasted alone is pasted as one, to be followed.
      final link = clip.plain.trim();
      _commit(
        RichTextEditing.insertText(
          _blocks,
          _selection,
          link,
          marks: _typingMarks().withLink(link),
        ),
        _EditKind.other,
      );
    } else {
      _undoBreak = true;
      _insertText(clip.plain);
    }
  }

  /// Whether [text] is a link and nothing else: to a note, or on the web.
  static bool _isLink(String text) {
    if (text.contains(RegExp(r'\s'))) return false;
    if (NoteLink.isNoteLink(text)) return true;
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
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

    // Ctrl+Tab goes on to the window, to change tabs.
    if (key == LogicalKeyboardKey.tab && !control) {
      if (_formula != null) {
        _moveToSlot(forward: !shift);
      } else {
        _tab(backward: shift);
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
        // With nothing left to select in the box, the page takes Ctrl+A and
        // selects everything on it.
        return _selectAll() ? handled : null;
      case LogicalKeyboardKey.keyC:
        unawaited(_copy());
        return handled;
      case LogicalKeyboardKey.keyX:
        unawaited(_copy(cut: true));
        return handled;
      case LogicalKeyboardKey.keyV:
        unawaited(_paste(textOnly: shift));
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

  /// Selects everything in the box, or in the formula being edited.
  ///
  /// Returns false where there was nothing to select — an empty box, or one
  /// already selected whole — so that the caret blinking in a box with
  /// nothing in it does not swallow Ctrl+A.
  bool _selectAll() {
    final formula = _formula;
    final span = formula == null ? null : _formulaSpan(formula)!;
    final whole = span == null
        ? _wholeBox
        : RichSelection(
            RichPosition(formula!.block, span.start),
            RichPosition(formula.block, span.end),
          );
    if (whole.isCollapsed || whole == _selection) return false;
    _select(whole);
    return true;
  }

  /// Everything in the box, from its first block to the end of its last.
  RichSelection get _wholeBox =>
      RichSelection(RichPosition.zero, RichTextEditing.endOf(_blocks));

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
        var to = word
            ? TextBoundaries.wordBefore(view.text, v)
            : TextBoundaries.characterBefore(view.text, v);
        // The room beside the formula being edited is not text to stop in.
        while (to > 0 && view.toModel(to) == caret.offset) {
          to = word
              ? TextBoundaries.wordBefore(view.text, to)
              : TextBoundaries.characterBefore(view.text, to);
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
        var to = word
            ? TextBoundaries.wordAfter(view.text, v)
            : TextBoundaries.characterAfter(view.text, v);
        while (to < view.text.length && view.toModel(to) == caret.offset) {
          to = word
              ? TextBoundaries.wordAfter(view.text, to)
              : TextBoundaries.characterAfter(view.text, to);
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

  // ----------------------------------------------------------------- layout

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

  // -------------------------------------------------------------- spelling

  /// The menu a right-click at [global] opens: what can be done about a
  /// word spelled wrongly there, cutting, copying and pasting, and for a
  /// picture or PDF page, setting it as the page's background.
  ///
  /// A right-click outside the selection first places the caret there, or
  /// picks the object there, as a click would, so the menu acts on what was
  /// clicked.
  Future<void> _showMenu(Offset global) async {
    // A formula being edited is finished first, as a click elsewhere
    // finishes it, and the text laid out again with it typeset, so the
    // words are found, and replaced, in the text as it is kept. A click in
    // its source leaves it open, to copy from.
    final open = _formula;
    final inFormula = open != null && _hitInOpenFormula(global, open) != null;
    if (open != null && !inFormula) {
      finishFormula();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final hit = inFormula ? null : _hitTest(global);
    if (hit != null && !hit.checkbox && !_selects(hit.position)) {
      if (!widget.isEditing) widget.onStartEditing?.call();
      _focusNode.requestFocus();
      final block = hit.position.block;
      _select(
        hit.embed
            ? RichSelection(RichPosition(block, 0), RichPosition(block, 1))
            : RichSelection.collapsed(hit.position),
      );
    }

    final misspelled = hit == null ? null : _misspelledAt(hit.position);
    final suggestions = misspelled == null
        ? const <String>[]
        : await widget.proofreader!.suggest(misspelled.spelled);
    final canPaste = await NoteClipboard.read() != null;
    if (!mounted) return;
    final selected = !_selection.isCollapsed;
    final picture = hit != null && hit.embed ? hit.position.block : null;
    final table = hit == null
        ? null
        : TextTables.tableAt(_blocks, hit.position.block);
    final link = hit == null ? null : _linkAt(hit.position);
    final paragraphLink = hit == null ? null : _linkTo(hit.position.block);
    await showCommandMenu(context, global, <List<MenuCommand>>[
      if (misspelled case (:final index, :final word, :final spelled)) ...[
        if (suggestions.isEmpty)
          const <MenuCommand>[MenuCommand('No suggestions', null)]
        else
          <MenuCommand>[
            for (final suggestion in suggestions)
              MenuCommand(
                suggestion,
                () => _replaceWord(index, word, spelled, suggestion),
              ),
          ],
        <MenuCommand>[
          MenuCommand(
            'Add to dictionary',
            () => unawaited(widget.proofreader!.addWord(spelled)),
          ),
          MenuCommand('Ignore', () => widget.proofreader!.ignore(spelled)),
        ],
      ],
      <MenuCommand>[
        MenuCommand(
          'Cut',
          selected ? () => unawaited(_copy(cut: true)) : null,
          shortcut: EditorKey.cut.keys,
        ),
        MenuCommand(
          'Copy',
          selected ? () => unawaited(_copy()) : null,
          shortcut: EditorKey.copy.keys,
        ),
        MenuCommand(
          'Paste',
          canPaste ? () => unawaited(_paste()) : null,
          shortcut: EditorKey.paste.keys,
        ),
        MenuCommand(
          'Paste text only',
          canPaste ? () => unawaited(_paste(textOnly: true)) : null,
          shortcut: EditorKey.pasteText.keys,
        ),
      ],
      if (link != null || paragraphLink != null)
        <MenuCommand>[
          if (link != null) ...<MenuCommand>[
            MenuCommand('Open link', () => widget.onOpenLink?.call(link)),
            MenuCommand(
              'Copy link',
              () => unawaited(Clipboard.setData(ClipboardData(text: link))),
            ),
          ],
          if (paragraphLink != null)
            MenuCommand(
              'Copy link to paragraph',
              () => unawaited(
                Clipboard.setData(ClipboardData(text: paragraphLink)),
              ),
            ),
        ],
      if (table != null) ..._tableCommands(table, hit!.position.block),
      if (picture != null && widget.onEmbedToBackground != null)
        <MenuCommand>[
          MenuCommand(
            'Set picture as background',
            () => _embedToBackground(picture),
          ),
        ],
    ]);
  }

  /// What can be done to [table] from the cell block [index] is in: adding
  /// rows and columns beside it, removing its row, its column or the whole
  /// table, and fitting dragged columns to their text again.
  List<List<MenuCommand>> _tableCommands(TextTable table, int index) {
    final cell = _blocks[index].cell!;
    void edit(RichEdit Function(List<TextBlock> blocks) change) {
      _focusNode.requestFocus();
      _commit(change(_blocks), _EditKind.other);
    }

    final dragged = TextTables.widthsOf(
      _blocks,
      table,
    ).any((width) => width != null);
    return <List<MenuCommand>>[
      <MenuCommand>[
        MenuCommand(
          'Insert row above',
          () => edit((b) => TableEditing.insertRow(b, table, cell.row)),
        ),
        MenuCommand(
          'Insert row below',
          () => edit((b) => TableEditing.insertRow(b, table, cell.row + 1)),
        ),
        MenuCommand(
          'Insert column left',
          () => edit(
            (b) => TableEditing.insertColumn(
              b,
              table,
              cell.column,
              caretRow: cell.row,
            ),
          ),
        ),
        MenuCommand(
          'Insert column right',
          () => edit(
            (b) => TableEditing.insertColumn(
              b,
              table,
              cell.column + 1,
              caretRow: cell.row,
            ),
          ),
        ),
      ],
      <MenuCommand>[
        MenuCommand(
          'Delete row',
          () => edit((b) => TableEditing.deleteRow(b, table, cell.row)),
        ),
        MenuCommand(
          'Delete column',
          () => edit(
            (b) => TableEditing.deleteColumn(
              b,
              table,
              cell.column,
              caretRow: cell.row,
            ),
          ),
        ),
        MenuCommand(
          'Delete table',
          () => edit((b) => TableEditing.deleteTable(b, table)),
        ),
        if (dragged)
          MenuCommand(
            'Fit columns to text',
            () => edit(
              (b) => (
                blocks: TableEditing.fitColumns(b, table),
                selection: _selection,
              ),
            ),
          ),
      ],
    ];
  }

  /// The link on the text at [position], if there is one.
  String? _linkAt(RichPosition position) {
    final block = _blocks[position.block];
    for (final (i, span) in RichTextEditing.runSpans(block).indexed) {
      if (span.start <= position.offset && position.offset < span.end) {
        return block.runs[i].marks.link;
      }
    }
    return null;
  }

  /// A link to paragraph [block] of this box, or null off a page.
  String? _linkTo(int block) {
    final pageId = widget.pageId;
    return pageId == null
        ? null
        : NoteLink.page(
            pageId,
            elementId: widget.element.id,
            block: block,
          ).toString();
  }

  /// Whether the selection takes in [position].
  bool _selects(RichPosition position) =>
      !_selection.isCollapsed &&
      _selection.start <= position &&
      position <= _selection.end;

  /// The word spelled wrongly at [at], if spelling is checked and one is.
  ({int index, WordSpan word, String spelled})? _misspelledAt(RichPosition at) {
    final proofreader = widget.proofreader;
    if (proofreader == null || _blocks[at.block].isEmbed) return null;
    final text = TextBoxEditor.textOf(_blocks[at.block], code: false);
    final word = proofreader
        .misspellingsIn(text)
        .where((word) => word.start <= at.offset && at.offset <= word.end)
        .firstOrNull;
    return word == null
        ? null
        : (
            index: at.block,
            word: word,
            spelled: text.substring(word.start, word.end),
          );
  }

  /// Asks the host to make the object on block [block] part of the page's
  /// background, where it is drawn now.
  void _embedToBackground(int block) {
    final object = _object(block);
    final box = context.findRenderObject();
    if (object == null || box is! RenderBox) return;
    widget.onEmbedToBackground?.call(
      block,
      MatrixUtils.transformRect(
        object.getTransformTo(box),
        Offset.zero & object.size,
      ),
    );
  }

  /// Puts [replacement] in place of [word] in block [index], unless the
  /// text has changed so that [spelled] is no longer there.
  void _replaceWord(
    int index,
    WordSpan word,
    String spelled,
    String replacement,
  ) {
    if (index >= _blocks.length) return;
    final block = _blocks[index];
    final text = TextBoxEditor.textOf(block, code: false);
    if (word.end > text.length ||
        text.substring(word.start, word.end) != spelled) {
      return;
    }
    if (!widget.isEditing) widget.onStartEditing?.call();
    _commit(
      RichTextEditing.insertText(
        _blocks,
        RichSelection(
          RichPosition(index, word.start),
          RichPosition(index, word.end),
        ),
        replacement,
        marks: RichTextEditing.marksAt(block, word.start + 1),
      ),
      _EditKind.other,
    );
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
        event.buttons & kSecondaryMouseButton != 0) {
      unawaited(_showMenu(event.position));
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
      if (_countClick(event) == 2) {
        _commit((
          blocks: TableEditing.setColumnWidth(
            _blocks,
            edge.table,
            edge.column,
            null,
          ),
          selection: _selection,
        ), _EditKind.other);
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

    _countClick(event);
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

  /// Counts [event] as the first, second or third click in a row, where it
  /// comes soon enough after the one before and near enough to it.
  int _countClick(PointerDownEvent event) {
    final now = DateTime.now();
    final isRepeat =
        now.difference(_lastPress) < _multiClickWindow &&
        (event.position - _lastPressPosition).distance < 6;
    _clickCount = isRepeat ? (_clickCount % 3) + 1 : 1;
    _lastPress = now;
    _lastPressPosition = event.position;
    return _clickCount;
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
        (widget.element.autoWidth
            ? TextBoxEditor.maxAutoWidth
            : widget.element.frame.width) -
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
    ), _EditKind.resizing);
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
        ? TextBoxEditor.maxAutoWidth
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
    ), _EditKind.resizing);
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
    _resize = null;
    _columnResize = null;
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
      _contentKeys.add(GlobalKey());
    }
  }

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

  List<TextBlock>? _coveredBlocks;
  RichSelection? _coveredFor;
  Map<int, Covered> _covered = const <int, Covered>{};

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
    // A cell taken in whole is drawn selected as a cell, not as its text.
    TextSelection? selection;
    final part = _covering[index];
    if (part != null && !part.cell) {
      final from = view.toView(part.from);
      final to = view.toView(part.to);
      if (to > from) {
        selection = TextSelection(baseOffset: from, extentOffset: to);
      }
    }

    final caret = _selection.extent;
    final formula = _formula;
    TextRange? formulaRange;
    var formulaMarks = const <({TextRange range, Color color})>[];
    if (formula != null && formula.block == index) {
      final layout = view.runAt(formula.run);
      formulaRange = TextRange(start: layout.outerStart, end: layout.outerEnd);
      // The source is laid out character for character from its start.
      formulaMarks = <({TextRange range, Color color})>[
        for (final mark in HighlightSource.all(
          _blocks[index].runs[formula.run].text,
          _source.syntax,
        ))
          (
            range: TextRange(
              start: layout.viewStart + mark.bodyStart,
              end: layout.viewStart + mark.bodyEnd,
            ),
            color: Color(0xFF000000 | mark.color),
          ),
      ];
    }

    return BlockDecoration(
      selection: selection,
      caret: focused && _selection.isCollapsed && caret.block == index
          ? view.toView(caret.offset)
          : null,
      caretAffinity: _affinity,
      typingStyle: _typingStyle(index),
      composing: caret.block == index ? _composing : null,
      formula: formulaRange,
      formulaMarks: formulaMarks,
      matches: matches,
      misspellings: misspellings,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    final tones = context.tones;
    final base = RichTextStyles.base(context);
    final focused = _focusNode.hasFocus;
    final autoWidth = widget.element.autoWidth;
    final empty = TextBoxEditor.isEmpty(_blocks);

    // The paper is white in light and dark mode alike, so what is drawn on
    // it takes the interface's mark as made to show on paper.
    final paint = BlockPaint(
      caretColor: tones.paperEmphasis,
      selectionColor: tones.paperSelection,
      formulaColor: tones.paperFill,
      formulaOutline: tones.paperOutline,
      composingColor: RichTextStyles.ink,
      matchColor: tones.paperMatch,
      misspellingColor: tones.paperEmphasis,
    );

    final ordinals = ListNumbering.ordinals(_blocks);
    final rows = <Widget>[];
    var i = 0;
    while (i < _blocks.length) {
      final table = TextTables.tableAt(_blocks, i);
      if (table == null) {
        rows.add(_buildBlock(i, base, paint, ordinals[i], focused, autoWidth));
        i++;
      } else {
        rows.add(_buildTable(table, base, paint, ordinals, focused));
        i = table.end;
      }
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
        : widget.isEditing || widget.selected || _hovering;
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
          child: GrabBand(
            height: TextBoxEditor.grabBand,
            visible: showChrome,
            active: widget.isEditing || widget.selected,
          ),
        ),
      ],
    );

    return MouseRegion(
      cursor: widget.interactive ? SystemMouseCursors.text : MouseCursor.defer,
      // Only a pointer hovering with no button held counts: one dragging
      // another box across this one is not pointing at it.
      onEnter: (event) {
        if (event.buttons == 0) setState(() => _hovering = true);
      },
      onHover: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
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
              child: SizeReporter(onSize: _reportSize, child: content),
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

  /// [table], each of its cells a column of its lines.
  Widget _buildTable(
    TextTable table,
    TextStyle base,
    BlockPaint paint,
    List<int> ordinals,
    bool focused,
  ) {
    final cells = <Widget>[];
    var i = table.start;
    while (i < table.end) {
      final cell = TextTables.cellAt(_blocks, i);
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
          lineColor: RichTextStyles.tableRule,
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
            objectKey: _contentKeys[index],
            selected: _embedSelected(index),
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
      key: _contentKeys[index],
      decoration: _decorationFor(index, view, focused),
      paint: paint,
      caretVisible: _caretVisible,
      child: RichText(
        text: view.span(base: base, mark: context.tones.paperEmphasis),
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
      child: Padding(padding: const EdgeInsets.only(bottom: 2), child: row),
    );
  }
}
