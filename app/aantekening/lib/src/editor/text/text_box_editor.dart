/// The text box: rich text, formulas, pictures and PDF pages, edited in place.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart'
    show SelectionHandle, SelectionHandles;
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_spell/aantekening_spell.dart' show WordSpan;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../command_menu.dart';
import '../../commands/editor_keys.dart';
import '../../look/icons.dart';
import '../../look/tones.dart';
import '../../spelling/proofreader.dart';
import '../note_clipboard.dart';
import 'aligned_column.dart';
import 'block_paragraph.dart';
import 'block_view.dart';
import 'block_widgets.dart';
import 'caret_blink.dart';
import 'click_count.dart';
import 'formula_overlay.dart';
import 'formula_source.dart';
import 'formula_window.dart';
import 'list_numbering.dart';
import 'math_templates.dart';
import 'table_view.dart';
import 'text_boundaries.dart';
import 'text_box_controller.dart';
import 'text_box_input.dart';
import 'text_styles.dart';
import 'undo_steps.dart';

part 'text_box_typing.dart';
part 'text_box_formulas.dart';
part 'text_box_input_method.dart';
part 'text_box_clipboard.dart';
part 'text_box_keyboard.dart';
part 'text_box_movement.dart';
part 'text_box_layout.dart';
part 'text_box_menu.dart';
part 'text_box_pointer.dart';
part 'text_box_view.dart';

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
    this.grouped = false,
    this.caretOnly = false,
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
    this.onOpenFile,
    this.onSaveFile,
  });

  final TextElement element;

  /// Whether this box has the caret.
  final bool isEditing;

  /// Whether the box is picked on the page. Its band shows while it is, so
  /// it stays in view as the box is dragged about, whatever the pointer
  /// passes over.
  final bool selected;

  /// Whether the box is picked along with other things: a right-click on it
  /// is then the page's, for all of them, and opens no menu of its own.
  final bool grouped;

  /// Whether the box is only a caret placed on the paper, nothing written
  /// at it yet, as in OneNote: it shows no band and no outline, and takes
  /// no presses, which go to what lies beneath it. One whose text has all
  /// been deleted is not, and keeps its band while it is typed in, so it
  /// can still be moved.
  final bool caretOnly;

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

  /// Opens an attached file, double-clicked or opened from the menu.
  final ValueChanged<BlockEmbed>? onOpenFile;

  /// Saves a copy of an attached file somewhere, from the menu.
  final ValueChanged<BlockEmbed>? onSaveFile;

  /// Height of the band along the top edge that moves the box when dragged.
  static const double grabBand = TextElement.grabBand;

  /// Space between the box's edges and its text, below the grab band.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    TextElement.sidePadding,
    0,
    TextElement.sidePadding,
    TextElement.bottomPadding,
  );

  /// The size of a new, empty text box.
  static const Size newBoxSize = Size(minAutoWidth, 44);

  /// The narrowest and widest a box that sizes itself to its text becomes,
  /// padding included. Past the widest it wraps, as a OneNote container does
  /// once it reaches the edge of the page.
  static const double minAutoWidth = 80;
  static const double maxAutoWidth = 600;

  /// The narrowest a box sizing itself to its text is while a formula is
  /// typed in it, so the field the source is typed in, as wide as the box,
  /// has room.
  static const double formulaWidth = 240;

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
        // A formula begun and nothing written in it holds nothing either.
        block.runs.every((run) => run.text.trim().isEmpty),
  );

  @override
  State<TextBoxEditor> createState() => TextBoxEditorState();
}

/// Words of a paragraph of a text box: offsets [from] to [to] of its
/// [block]th paragraph's text.
typedef WordsMark = ({int block, int from, int to});

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

/// [blocks] as the box shows them: at least one line, and every table a
/// whole grid.
List<TextBlock> _wellFormed(List<TextBlock> blocks) => blocks.isEmpty
    ? const <TextBlock>[TextBlock()]
    : TextTables.normalize(blocks);

class TextBoxEditorState extends State<TextBoxEditor>
    implements TextEditorCommands {
  late List<TextBlock> _blocks;
  List<TextBlock>? _lastEmitted;
  RichSelection _selection = const RichSelection.collapsed(RichPosition.zero);
  TextAffinity _affinity = TextAffinity.downstream;

  /// The formula being edited. Its run in [_blocks] holds its source, in
  /// [FormulaSource.syntax]; what is reported to the page holds LaTeX
  /// ([_stored]).
  _OpenFormula? _formula;
  final FormulaSource _source = FormulaSource();

  /// The formula being edited as it is typeset in its place, as LaTeX: its
  /// source as it last could be, so a slip while typing leaves the formula
  /// as it was rather than blanking it. Empty for a new one.
  String _shown = '';

  /// What keeps the source of the formula being edited from being typeset,
  /// if anything does.
  String? _problem;

  /// Lays out the source of the formula being edited, which is drawn over
  /// everything on the page ([_formulaField]), where that layer is.
  final GlobalKey _formulaLayer = GlobalKey();
  final LayerLink _formulaLink = LayerLink();
  final FormulaChanges _formulaChanges = FormulaChanges();

  /// The source of the formula being edited, drawn over the page where this
  /// box lays it out, and taking the presses that land on it as the box
  /// takes those on its text.
  late final Widget _formulaField = CompositedTransformFollower(
    link: _formulaLink,
    showWhenUnlinked: false,
    child: Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        hitTestBehavior: HitTestBehavior.deferToChild,
        child: CustomPaint(
          size: Size.infinite,
          painter: FormulaFieldPainter(
            layer: _formulaLayer,
            caretVisible: _blink.visible,
            changes: _formulaChanges,
          ),
        ),
      ),
    ),
  );

  /// The source of the formula being edited as the window it is typed in
  /// shows it, while it is long enough to be typed in one
  /// ([FormulaWindow]).
  ValueNotifier<FormulaWindowSource?>? _window;

  /// Whether the page was last told that a formula is being edited here.
  bool _reportedOpen = false;

  /// The search whose first match was last reported to [TextBoxEditor.onMatchPlaced].
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
  final CaretBlink _blink = CaretBlink();

  /// The connection to the input method, open while the box has focus.
  late final TextBoxInput _input = TextBoxInput(
    valueOf: _inputValue,
    configuration: _inputConfiguration,
    geometry: _inputGeometry,
    accepts: () => widget.isEditing,
    onReplace: _applyImeEdit,
    onSelect: _applyImeSelection,
    onComposed: () {
      if (mounted) setState(() {});
    },
  );

  final List<GlobalKey> _rowKeys = <GlobalKey>[];
  final List<GlobalKey> _contentKeys = <GlobalKey>[];

  final UndoSteps _undoSteps = UndoSteps();

  int? _dragPointer;

  /// The object being resized by one of its handles: which block it is on,
  /// which handle is held, where the drag began and how wide it was then.
  ({int block, SelectionHandle handle, Offset from, double width})? _resize;

  /// The cursor over a handle of a picked object, while it is over one.
  MouseCursor? _handleCursor;

  /// The table column being resized by its right-hand line: the block the
  /// table starts on, the column, where the drag began and how wide the
  /// column was then.
  ({int table, int column, Offset from, double width})? _columnResize;

  int _touchCount = 0;
  final ClickCounter _clicks = ClickCounter();

  /// What the selection takes in of each block, as last worked out
  /// ([_covering]), and the text and selection it was worked out for.
  List<TextBlock>? _coveredBlocks;
  RichSelection? _coveredFor;
  Map<int, Covered> _covered = const <int, Covered>{};

  Size? _reportedSize;

  /// Rebuilds the box after [change], for the parts of it kept in other
  /// files of this library, which cannot call [setState] themselves.
  void _update(VoidCallback change) => setState(change);

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
      _undoSteps.breakStep();
      _input.sync();
      // The formula shows what undo left, or closes if it is gone.
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
    // A window left with nothing to type in goes once the frame is done.
    final window = _window;
    if (window != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => window.value = null);
    }
    _input.close();
    _blink.stop();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _blink.dispose();
    _formulaChanges.dispose();
    super.dispose();
  }

  /// Verdicts on the spelling of words in the box have come in.
  void _onProofread() => setState(() {});

  void _beginEditing() {
    widget.controller?.attach(this);
    _followSyntax(widget.controller);
    // A click on a formula opens it before the box is attached; tell the
    // page now.
    if (_formula != null) {
      _reportedOpen = false;
      _reportFormula();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isEditing) return;
      _focusNode.requestFocus();
      // A click that starts editing asks for focus before this box knows it
      // is being edited, so the focus listener may already have run and
      // passed over the connection; open it here too.
      if (_focusNode.hasFocus) _input.open();
      if (widget.startInFormula && _formula == null) {
        toggleFormula();
        // A structure chosen in the guide before there was a box for it.
        final queued = widget.controller?.takeQueuedMath();
        if (queued != null) insertMath(queued);
      }
    });
    _restartBlink();
    _publishState();
  }

  void _endEditing() {
    // The page had the formula finished and reported before it let go of
    // the box ([finishEditing]); nothing is reported from a rebuild.
    _closeFormula();
    _followSyntax(null);
    widget.controller?.detach(this);
    _input.close();
    _blink.stop();
    if (_focusNode.hasFocus) _focusNode.unfocus();
    setState(() {
      _selection = RichSelection.collapsed(_selection.extent);
      _pendingMarks = null;
    });
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus && widget.isEditing) {
      _input.open();
      _restartBlink();
    } else {
      _input.close();
      _blink.stop();
    }
    if (mounted) setState(() {});
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
    ), EditKind.other);
  }

  @override
  void setFontSize(double points) =>
      _changeMarks((marks) => marks.withSize(points));

  @override
  void setFont(String? family) =>
      _changeMarks((marks) => marks.withFont(family));

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
    ), EditKind.other);
  }

  @override
  void indent(int delta) {
    _focusNode.requestFocus();
    _commit((
      blocks: RichTextEditing.indentBlocks(_blocks, _selection, delta),
      selection: _selection,
    ), EditKind.other);
  }

  @override
  void toggleFormula() {
    _focusNode.requestFocus();
    if (_formula != null) {
      _closeFormula(emit: true, onwards: true);
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
    _undoSteps.breakStep();
    _replaceInFormula(clean, caretAt: caret < 0 ? clean.length : caret);
    _undoSteps.breakStep();
  }

  @override
  void finishEditing() => _closeFormula(emit: true);

  @override
  void finishFormula({bool after = true}) {
    if (_formula == null) return;
    _closeFormula(emit: true, after: after, onwards: true);
    _focusNode.requestFocus();
  }

  @override
  void insertEmbeds(List<BlockEmbed> embeds) => insertBlocks(<TextBlock>[
    for (final embed in embeds) TextBlock.embedded(embed),
  ]);

  @override
  void typeText(String text) {
    for (final (index, line) in text.split('\n').indexed) {
      if (index > 0) _paragraphBreak();
      _insertText(line);
    }
  }

  @override
  void insertBlocks(List<TextBlock> blocks) {
    if (blocks.isEmpty) return;
    _closeFormula(emit: true);
    _focusNode.requestFocus();
    _commit(
      RichTextEditing.insertFragment(_blocks, _selection, blocks),
      EditKind.other,
    );
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
        latexOnly: _openIsLatexOnly,
        fontSize: sample.size ?? RichTextStyles.defaultPointsFor(block),
        font: sample.font,
        textColor: sample.color,
        highlight: sample.highlight,
      ),
    );
  }

  // ------------------------------------------------------------------ caret

  /// Lights the caret and blinks it, while the box is being edited.
  void _restartBlink() {
    if (widget.isEditing) {
      _blink.restart();
    } else {
      _blink.stop();
    }
  }

  // ------------------------------------------------------------------ build

  void _ensureKeys() {
    while (_rowKeys.length < _blocks.length) {
      _rowKeys.add(GlobalKey());
      _contentKeys.add(GlobalKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureKeys();
    final tones = context.tones;
    final base = RichTextStyles.base(context);
    final focused = _focusNode.hasFocus;
    final autoWidth = widget.element.autoWidth;

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
    // Each row, and where across the box it sits in a box as wide as its
    // text: a paragraph by its alignment, a table at the start.
    final rows = <(Widget, double)>[];
    var i = 0;
    while (i < _blocks.length) {
      final table = TextTables.tableAt(_blocks, i);
      if (table == null) {
        rows.add((
          _buildBlock(i, base, paint, ordinals[i], focused, autoWidth),
          switch (_blocks[i].align) {
            BlockAlign.start => 0,
            BlockAlign.center => 0.5,
            BlockAlign.end => 1,
          },
        ));
        i++;
      } else {
        rows.add((_buildTable(table, base, paint, ordinals, focused), 0));
        i = table.end;
      }
    }
    if (widget.onMatchPlaced != null &&
        !identical(widget.highlight, _placedMatchesOf)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _placeFirstMatch());
    }

    final content = Stack(
      children: <Widget>[
        Padding(
          padding: TextBoxEditor.padding.copyWith(
            top: TextBoxEditor.padding.top + TextBoxEditor.grabBand,
          ),
          child: FormulaLayer(
            key: _formulaLayer,
            formula: _formulaOverlay(focused),
            paint: paint,
            changes: _formulaChanges,
            outset: TextBoxEditor.padding,
            child: autoWidth
                ? AlignedColumn(
                    // As wide as the narrowest box, between its padding.
                    minWidth:
                        (_formula == null
                            ? TextBoxEditor.minAutoWidth
                            : TextBoxEditor.formulaWidth) -
                        TextBoxEditor.padding.horizontal,
                    children: <Widget>[
                      for (final (row, across) in rows)
                        AlignedRow(across: across, child: row),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[for (final (row, _) in rows) row],
                  ),
          ),
        ),
        // Where the field the formula's source is typed in is placed from,
        // over everything on the page ([_formulaField]). Only while one is
        // open: it gives the box a layer of its own.
        if (_formula != null)
          Positioned(
            left: TextBoxEditor.padding.left,
            top: TextBoxEditor.padding.top + TextBoxEditor.grabBand,
            child: CompositedTransformTarget(
              link: _formulaLink,
              child: const SizedBox.shrink(),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TextBoxEditor.grabBand,
          child: GrabBand(
            height: TextBoxEditor.grabBand,
            movable: widget.interactive,
          ),
        ),
      ],
    );

    return IgnorePointer(
      ignoring: widget.caretOnly,
      child: MouseRegion(
        cursor:
            _handleCursor ??
            (widget.interactive ? SystemMouseCursors.text : MouseCursor.defer),
        onHover: (event) {
          final grabbed = widget.interactive ? _handleAt(event.position) : null;
          final cursor = grabbed == null
              ? null
              : SelectionHandles.cursorFor(
                  grabbed.handle,
                  widget.element.frame.rotation,
                );
          if (cursor != _handleCursor) {
            setState(() => _handleCursor = cursor);
          }
        },
        onExit: (_) {
          if (_handleCursor != null) setState(() => _handleCursor = null);
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
                // Nothing of the box shows until it is clicked, when the page
                // frames it as anything picked. A caret a formula is begun at
                // is not yet picked on the page, which draws no frame round
                // it: it draws the same frame itself.
                border:
                    widget.isEditing && !widget.selected && !widget.caretOnly
                    ? Border.all(color: tones.paperEmphasis, width: 1.5)
                    : null,
                borderRadius: const BorderRadius.all(
                  Radius.circular(RichTextStyles.boxCorner),
                ),
              ),
              // The content is laid out at its natural size and reported, so
              // the box can grow to fit it; until the frame catches up, the
              // overflow still paints.
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: autoWidth ? TextBoxEditor.minAutoWidth : null,
                maxWidth: autoWidth ? _widest : null,
                minHeight: 0,
                maxHeight: double.infinity,
                child: SizeReporter(onSize: _reportSize, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The widest this box grows while it sizes itself to its text.
  double get _widest => widget.element.widthLimit ?? TextBoxEditor.maxAutoWidth;

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
}
