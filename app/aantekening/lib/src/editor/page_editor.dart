/// The page editor: ribbon, canvas and autosave.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../search/search_panel.dart';
import 'element_views.dart';
import 'media_import.dart';
import 'page_title.dart';
import 'ribbon/ribbon.dart';
import 'text/box_formatting.dart';
import 'text/formula_preview.dart';
import 'text/math_syntax.dart';
import 'text/math_templates.dart';
import 'text/text_box_controller.dart';
import 'text/text_box_editor.dart';
import 'trackpad.dart';

/// Edits the page that is open: the ribbon across the top of the window, and
/// beneath it the page, laid out among whatever [around] puts beside it.
///
/// The editor stays as other pages are opened, loading each in turn, so the
/// ribbon, the tool in hand and the pens stay as they were. It owns the
/// [CanvasController] directly rather than holding it in a provider: its
/// lifetime is exactly this widget's, which guarantees a final save.
class PageEditor extends ConsumerStatefulWidget {
  const PageEditor({required this.pageId, this.around, super.key});

  /// The page open, or null for none.
  final String? pageId;

  /// Lays the page out in the window below the ribbon — beside the sidebar,
  /// say. The ribbon spans the whole window, over both.
  final Widget Function(BuildContext context, Widget page)? around;

  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  /// How long to wait after the last edit before writing to disk.
  ///
  /// Long enough that a burst of typing or a drawn stroke is one write, short
  /// enough that no meaningful work is at risk if the app stops.
  static const Duration _autosaveDelay = Duration(milliseconds: 700);

  /// Zoom step for the keyboard shortcuts and toolbar buttons.
  static const double _zoomStep = 1.25;

  /// The widest a free-standing picture or PDF page is placed.
  static const double _defaultMediaWidth = 816;

  final CanvasController _controller = CanvasController();
  final TextBoxEditorController _textController = TextBoxEditorController();
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'Canvas');
  final ValueNotifier<bool> _saving = ValueNotifier<bool>(false);
  late final BoxFormatting _boxFormatting = BoxFormatting(_controller);

  /// Where on screen the source of the formula being edited is, for its
  /// preview.
  final ValueNotifier<Rect?> _formulaOnScreen = ValueNotifier<Rect?>(null);

  /// Whether that is known yet. The preview waits for it rather than
  /// appearing somewhere else first and then jumping beneath the formula.
  final ValueNotifier<bool> _formulaPlaced = ValueNotifier<bool>(false);

  /// The tab showing before a formula brought the Math tab forward, to go
  /// back to when it is finished.
  RibbonTab? _tabBeforeMath;
  bool _formulaOpen = false;
  final double _trackpadPanScale = trackpadPanScale();

  /// The pen or highlighter used last, which the ribbon's colours and widths
  /// apply to while neither is in hand.
  CanvasTool _lastInkTool = CanvasTool.pen;

  /// What the formatting of selected boxes was last worked out from.
  PageDocument? _formattedDocument;
  Set<String> _formattedSelection = const <String>{};

  late final RibbonCommands _ribbonCommands = RibbonCommands(
    canvas: _controller,
    text: _textController,
    lastInkTool: () => _lastInkTool,
    onToolSelected: _selectTool,
    onFormula: _insertFormula,
    onInsertTextBox: _insertTextBox,
    onInsertImage: () => unawaited(_insertMedia(MediaKind.image)),
    onInsertPdf: () => unawaited(_insertMedia(MediaKind.pdf)),
    onZoomIn: () => _controller.zoomAtCenter(_zoomStep),
    onZoomOut: () => _controller.zoomAtCenter(1 / _zoomStep),
    onFitPage: () => _controller.zoomToFit(_controller.viewSize),
    onActualSize: () => _controller.resetZoom(_controller.viewSize),
    onMathInsert: _insertMath,
    saving: _saving,
  );

  Timer? _autosave;

  /// The text box with the caret, if any.
  String? _editingId;

  /// Whether the box being edited should open straight into a formula.
  bool _editingStartsInFormula = false;

  /// Whether the open page is being read, and whether it has been: the
  /// canvas shows it, and edits to it are saved, only once it is ready.
  bool _loading = false;
  bool _ready = false;
  bool _disposed = false;
  Object? _error;

  /// Held in fields rather than read through `ref` when saving, because the
  /// final save runs from [dispose], where `ref` may no longer be used.
  AantekeningStore? _store;
  late final LibraryRevision _libraryRevision;

  @override
  void initState() {
    super.initState();
    _libraryRevision = ref.read(libraryRevisionProvider.notifier);
    _controller.addListener(_onCanvasChanged);
    _textController.formula.addListener(_onFormulaChanged);
    _textController.formulaAnchor.addListener(_placeFormulaPanel);
    // The syntax formulas are typed in is the person's preference, which a
    // text box can switch too.
    _textController.formulaSyntax
      ..value = ref.read(mathSyntaxProvider)
      ..addListener(_onSyntaxChosen);
    if (widget.pageId != null) unawaited(_load());
  }

  void _onSyntaxChosen() => ref
      .read(mathSyntaxProvider.notifier)
      .set(_textController.formulaSyntax.value);

  @override
  void didUpdateWidget(PageEditor old) {
    super.didUpdateWidget(old);
    if (old.pageId == widget.pageId) return;
    // Leaving a page must never lose what is on it: its last changes are
    // saved to it before the next page is read.
    _autosave?.cancel();
    final leaving = old.pageId;
    if (leaving != null && _ready && _controller.isDirty) {
      unawaited(_persist(leaving, _controller.document));
    }
    _ready = false;
    _editingId = null;
    _elementWidgets.clear();
    if (widget.pageId != null) unawaited(_load());
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _controller.removeListener(_onCanvasChanged);
    _disposed = true;
    final pageId = widget.pageId;
    if (pageId != null && _ready && _controller.isDirty) {
      unawaited(_persist(pageId, _controller.document));
    }
    _textController.formula.removeListener(_onFormulaChanged);
    _textController.formulaAnchor.removeListener(_placeFormulaPanel);
    _textController.formulaSyntax.removeListener(_onSyntaxChosen);
    _controller.dispose();
    _textController.dispose();
    _canvasFocus.dispose();
    _saving.dispose();
    _formulaOnScreen.dispose();
    _formulaPlaced.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ load / save

  /// Reads the open page into the canvas.
  Future<void> _load() async {
    final pageId = widget.pageId!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AantekeningStore store =
          _store ?? await ref.read(storeProvider.future);
      _store = store;
      final stored = await store.pages.loadDocument(pageId);
      // Another page may have been opened while this one was read.
      if (!mounted || pageId != widget.pageId) return;
      final page = _withoutEmptyTextBoxes(
        stored ?? PageDocument.empty(id: pageId),
      );
      // Formulas are stored as LaTeX; older pages held some in Simple
      // syntax, which are translated once and saved that way — as is content
      // from before pages had a top-left corner, moved onto the page.
      final document = MathStorage.withLatexFormulas(page).withContentOnPage();
      _controller.loadDocument(document);
      if (!identical(document, page)) unawaited(_persist(pageId, document));
      setState(() {
        _loading = false;
        _ready = true;
      });
    } on Object catch (error) {
      if (!mounted || pageId != widget.pageId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Drops text boxes with nothing in them, which an interrupted session or
  /// an undo can leave behind invisibly.
  static PageDocument _withoutEmptyTextBoxes(PageDocument document) =>
      document.withElementsRemoved(<String>{
        for (final element in document.elements)
          if (element is TextElement && TextBoxEditor.isEmpty(element.blocks))
            element.id,
      });

  /// Called on every change to the page and the view — every frame of
  /// scrolling among them — so it rebuilds nothing itself: the canvas and
  /// the ribbon's buttons each listen for what they show.
  void _onCanvasChanged() {
    if (traceInput) _traceView();
    final tool = _controller.tool;
    if (tool.draws) _lastInkTool = tool;
    _syncBoxFormatting();
    _placeFormulaPanel();

    final editingId = _editingId;
    if (editingId != null &&
        _controller.document.elementById(editingId) == null) {
      // The box was removed from under the caret — by undo, say.
      _editingId = null;
      if (mounted) setState(() {});
    }

    // Until the page has been read, the canvas still holds the one before.
    final pageId = widget.pageId;
    if (pageId == null || !_ready || !_controller.isDirty) return;

    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      unawaited(_persist(pageId, _controller.document));
    });
  }

  /// Saves the open page now, as Ctrl+S does.
  void _saveNow() {
    final pageId = widget.pageId;
    if (pageId == null || !_ready) return;
    _autosave?.cancel();
    unawaited(_persist(pageId, _controller.document));
  }

  CanvasViewport? _tracedView;

  /// Prints each change of view, how far it moved and what moved it.
  void _traceView() {
    final view = _controller.viewport;
    final before = _tracedView;
    _tracedView = view;
    if (before == null || before == view) return;
    final moved = view.toScreen(before.origin);
    traceLine(
      'view origin=(${view.origin.dx.toStringAsFixed(1)}, '
      '${view.origin.dy.toStringAsFixed(1)}) '
      'zoom=${view.zoom.toStringAsFixed(4)} '
      'moved=(${moved.dx.toStringAsFixed(1)}, ${moved.dy.toStringAsFixed(1)}) '
      'by ${traceCaller()}',
    );
  }

  /// Writes [document] to disk.
  ///
  /// Also called from [dispose] for the final save, so it touches neither
  /// `ref` nor the widget once the widget is gone.
  Future<void> _persist(String pageId, PageDocument document) async {
    final store = _store;
    // Nothing can have been edited on a page that never loaded.
    if (store == null) return;
    if (!_disposed) _saving.value = true;
    try {
      await store.pages.saveDocument(pageId, document);
      if (!_disposed && pageId == widget.pageId) _controller.markSaved();
      // The page list shows titles and previews derived from the body, so it
      // has to be refreshed once the save lands.
      _libraryRevision.bump();
    } on Object catch (error) {
      if (!_disposed) setState(() => _error = error);
    } finally {
      if (!_disposed) _saving.value = false;
    }
  }

  // ----------------------------------------------------------- text editing

  /// Makes [id] the text box with the caret.
  void _startEditing(String id, {bool inFormula = false}) {
    if (_editingId == id) return;
    _stopEditing();
    setState(() {
      _editingId = id;
      _editingStartsInFormula = inFormula;
    });
    // An empty box is only a caret on the paper: it gets its outline and
    // handles once something is written in it.
    final element = _controller.document.elementById(id);
    if (element is TextElement && !TextBoxEditor.isEmpty(element.blocks)) {
      _controller.select(id);
    } else {
      _controller.clearSelection();
    }
  }

  /// Lets the ribbon's formatting apply to whole text boxes while they are
  /// selected and none is being edited.
  void _syncBoxFormatting() {
    final document = _controller.document;
    final selection = _controller.selection;
    if (identical(document, _formattedDocument) &&
        setEquals(selection, _formattedSelection)) {
      return;
    }
    _formattedDocument = document;
    _formattedSelection = selection;
    final hasBoxes = selection.any(
      (id) => document.elementById(id) is TextElement,
    );
    _textController.setFallback(
      hasBoxes ? _boxFormatting : null,
      hasBoxes ? _boxFormatting.state : TextFormatState.none,
    );
  }

  /// Ends text editing, removing the box if it was left empty.
  void _stopEditing({bool refocusCanvas = true}) {
    final id = _editingId;
    if (id == null) return;
    setState(() => _editingId = null);
    if (_controller.selection.contains(id)) _controller.clearSelection();
    if (refocusCanvas) _canvasFocus.requestFocus();
    // The box finishes any open formula as it leaves editing, which happens
    // in this frame's rebuild; only after that is it known to be empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final element = _controller.document.elementById(id);
      if (element is TextElement && TextBoxEditor.isEmpty(element.blocks)) {
        _controller.removeElements(<String>{id}, recordUndo: false);
      }
    });
  }

  /// Places a caret at [page]: an empty text box, invisible until something
  /// is typed, whose first line starts there. It widens with its text, as a
  /// new OneNote container does.
  String _createTextBox(Offset page) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = Ulid.generate();
    _controller.addElement(
      TextElement(
        id: id,
        frame: Frame(
          x: page.dx - TextBoxEditor.padding.left,
          y: page.dy - TextBoxEditor.grabBand - 10,
          width: TextBoxEditor.newBoxSize.width,
          height: TextBoxEditor.newBoxSize.height,
        ),
        createdAt: now,
        updatedAt: now,
        blocks: const <TextBlock>[TextBlock()],
        autoWidth: true,
      ),
      // The box is recorded in history and saved with its first edit; an
      // empty box that is abandoned leaves no trace.
      recordUndo: false,
      markDirty: false,
    );
    return id;
  }

  void _onEmptyTap(Offset page) {
    _stopEditing(refocusCanvas: false);
    _startEditing(_createTextBox(page));
  }

  void _onCanvasPress(NoteElement? hit) {
    if (hit?.id != _editingId) _stopEditing();
    _canvasFocus.requestFocus();
  }

  bool _claimsPointer(NoteElement element, Offset page) =>
      element is TextElement && !TextBoxEditor.isInGrabBand(element, page);

  void _onElementDoubleTap(NoteElement element) {
    if (element is MathElement) _convertLegacyFormula(element);
  }

  /// Turns a free-standing formula from an earlier build into a text box
  /// holding it, where it can be edited in place.
  void _convertLegacyFormula(MathElement formula) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final box = TextElement(
      id: Ulid.generate(),
      frame: Frame(
        x: formula.frame.x,
        y: formula.frame.y - TextBoxEditor.grabBand,
        width: math.max(formula.frame.width, 240),
        height: formula.frame.height + TextBoxEditor.grabBand,
      ),
      createdAt: now,
      updatedAt: now,
      blocks: <TextBlock>[
        TextBlock(runs: <TextRun>[TextRun.math(formula.source, formula.mode)]),
      ],
    );
    _controller
      ..removeElements(<String>{formula.id})
      ..addElement(box);
    _startEditing(box.id);
  }

  void _onTextChanged(
    String id,
    List<TextBlock> blocks, {
    required bool recordUndo,
  }) {
    final element = _controller.document.elementById(id);
    if (element is! TextElement) return;
    _controller.replaceElement(
      element.copyWith(
        blocks: blocks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      recordUndo: recordUndo,
    );
    // The first thing typed at a bare caret turns it into a box, with its
    // outline and handles.
    if (id == _editingId &&
        !_controller.selection.contains(id) &&
        !TextBoxEditor.isEmpty(blocks)) {
      _controller.select(id);
    }
  }

  void _onTextSizeChanged(String id, Size size) {
    final element = _controller.document.elementById(id);
    if (element is! TextElement) return;
    final frame = element.frame;
    _controller.replaceElement(
      // copyWith rather than withFrame: fitting the text is not the user
      // resizing the box, so a box that widens with its text keeps doing so.
      // It grows from its top-left corner, where its text starts, even when
      // turned.
      element.copyWith(
        frame: frame.resizedFromTopLeft(
          element.autoWidth ? size.width : frame.width,
          size.height,
        ),
      ),
      // Growing with the text belongs to the edit that caused it, and a box
      // measuring itself on first layout is not an edit at all.
      recordUndo: false,
      markDirty: false,
    );
  }

  // --------------------------------------------------------------- formulas

  /// A formula opening brings the Math tab forward, as Office does with its
  /// equation tools; finishing it goes back to where the ribbon was.
  void _onFormulaChanged() {
    final open = _textController.formula.value != null;
    if (open != _formulaOpen) {
      _formulaOpen = open;
      final ribbon = ref.read(ribbonProvider.notifier);
      final tab = ref.read(ribbonProvider).tab;
      if (open) {
        if (tab != RibbonTab.math) {
          _tabBeforeMath = tab;
          ribbon.show(RibbonTab.math);
        }
      } else {
        final before = _tabBeforeMath;
        _tabBeforeMath = null;
        if (before != null && tab == RibbonTab.math) ribbon.show(before);
      }
    }
    _placeFormulaPanel();
  }

  /// Works out where on screen the formula being edited is, from where its
  /// text box reports it and where the box is in view.
  void _placeFormulaPanel() {
    final id = _editingId;
    final element = id == null ? null : _controller.document.elementById(id);
    final local = _textController.formulaAnchor.value;
    if (_textController.formula.value == null ||
        element == null ||
        local == null) {
      _formulaOnScreen.value = null;
      _formulaPlaced.value = false;
      return;
    }
    final toPage = element.frame.localToPage;
    final viewport = _controller.viewport;
    Offset screen(Offset point) {
      final page = toPage.apply(point.dx, point.dy);
      return viewport.toScreen(Offset(page.x, page.y));
    }

    final corners = <Offset>[
      screen(local.topLeft),
      screen(local.topRight),
      screen(local.bottomLeft),
      screen(local.bottomRight),
    ];
    var rect = Rect.fromPoints(corners[0], corners[1]);
    for (final corner in corners.skip(2)) {
      rect = rect.expandToInclude(Rect.fromPoints(corner, corner));
    }
    _formulaOnScreen.value = rect;
    _formulaPlaced.value = true;
  }

  /// Puts a structure or symbol from the ribbon into the formula being
  /// edited, or into a new one.
  void _insertMath(MathTemplate template) {
    if (_textController.isActive) {
      _textController.insertMath(template);
      return;
    }
    _textController.queueMath(template);
    _insertFormula();
  }

  /// Places a caret in the middle of the view, for typing without first
  /// clicking the page.
  void _insertTextBox() {
    _stopEditing(refocusCanvas: false);
    _controller.setTool(CanvasTool.select);
    final center = _controller.viewCenter;
    _startEditing(
      _createTextBox(
        Offset(center.dx - TextBoxEditor.newBoxSize.width / 2, center.dy),
      ),
    );
  }

  /// Writes a formula: in the box being edited, or in a new box in view.
  void _insertFormula() {
    if (_textController.isActive) {
      _textController.toggleFormula();
      return;
    }
    _controller.setTool(CanvasTool.select);
    final center = _controller.viewCenter;
    final id = _createTextBox(
      Offset(center.dx - TextBoxEditor.newBoxSize.width / 2, center.dy),
    );
    _startEditing(id, inFormula: true);
  }

  // ------------------------------------------------------------------ media

  /// Inserts pictures or PDF pages: into the text box being edited, at its
  /// caret, or onto the canvas in view if no box is being edited.
  Future<void> _insertMedia(MediaKind kind) async {
    final store = _store;
    if (store == null) return;
    final List<ImportedMedia> items;
    try {
      items = await MediaImport.pickAndImport(store, kind);
    } on Object catch (error) {
      _showMessage('Could not import: $error');
      return;
    }
    if (items.isEmpty || !mounted) return;

    // At a bare caret the pictures go onto the paper where the caret is, as
    // in OneNote; in a box with text they go into the box.
    final editingId = _editingId;
    final editing = editingId == null
        ? null
        : _controller.document.elementById(editingId);
    final atBareCaret =
        editing is TextElement && TextBoxEditor.isEmpty(editing.blocks);
    if (_textController.isActive && !atBareCaret) {
      _textController.insertEmbeds(<BlockEmbed>[
        for (final item in items) item.toEmbed(),
      ]);
      return;
    }

    final width = _controller.document.canvas.paperWidth ?? _defaultMediaWidth;
    final center = _controller.viewCenter;
    var y = center.dy - 120;
    if (editing != null && atBareCaret) {
      y = editing.frame.y + TextBoxEditor.grabBand;
      _stopEditing();
    }
    final elements = <NoteElement>[];
    for (final item in items) {
      final itemWidth = math.min(item.width, width);
      final element = item.toElement(
        editing != null && atBareCaret
            ? Offset(editing.frame.x + TextBoxEditor.padding.left, y)
            : Offset(center.dx - itemWidth / 2, y),
        maxWidth: width,
      );
      elements.add(element);
      y += element.frame.height + 24;
    }
    _controller
      ..setTool(CanvasTool.select)
      ..addElements(elements)
      ..selectAll(elements.map((element) => element.id));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- shortcuts

  /// Page-level shortcuts. A text box being edited stops the plain-letter
  /// ones from reaching here, so typing never switches tools.
  Map<ShortcutActivator, VoidCallback>
  get _shortcuts => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
        _controller.undo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        _controller.redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true):
        _controller.redo,
    const SingleActivator(LogicalKeyboardKey.delete): _deleteSelection,
    const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelection,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      _stopEditing();
      _controller.clearSelection();
    },
    // A tool's shortcut also brings its tab forward on the ribbon.
    const SingleActivator(LogicalKeyboardKey.keyV): () =>
        _useTool(CanvasTool.select),
    const SingleActivator(LogicalKeyboardKey.keyT): () =>
        _useTool(CanvasTool.select),
    const SingleActivator(LogicalKeyboardKey.keyP): () =>
        _useTool(CanvasTool.pen),
    const SingleActivator(LogicalKeyboardKey.keyH): () =>
        _useTool(CanvasTool.highlighter),
    const SingleActivator(LogicalKeyboardKey.keyE): () =>
        _useTool(CanvasTool.eraser),
    const SingleActivator(LogicalKeyboardKey.keyM): _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.keyM, control: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.equal, alt: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.f1, control: true): () =>
        ref.read(ribbonProvider.notifier).toggleCollapsed(),
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
        _controller.zoomAtCenter(_zoomStep),
    const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
        _controller.zoomAtCenter(_zoomStep),
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () =>
        _controller.zoomAtCenter(_zoomStep),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
        _controller.zoomAtCenter(1 / _zoomStep),
    const SingleActivator(
      LogicalKeyboardKey.numpadSubtract,
      control: true,
    ): () =>
        _controller.zoomAtCenter(1 / _zoomStep),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
        _controller.resetZoom(_controller.viewSize),
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveNow,
    const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
      _controller
        ..setTool(CanvasTool.select)
        ..selectEverything();
    },
    for (final (key, direction)
        in _arrows) ...<ShortcutActivator, VoidCallback>{
      SingleActivator(key): () => _nudge(direction),
      SingleActivator(key, shift: true): () => _nudge(direction * 10),
    },
  };

  static const List<(LogicalKeyboardKey, Offset)> _arrows =
      <(LogicalKeyboardKey, Offset)>[
        (LogicalKeyboardKey.arrowLeft, Offset(-1, 0)),
        (LogicalKeyboardKey.arrowRight, Offset(1, 0)),
        (LogicalKeyboardKey.arrowUp, Offset(0, -1)),
        (LogicalKeyboardKey.arrowDown, Offset(0, 1)),
      ];

  /// Moves the selection by [delta] page units, as the arrow keys do.
  void _nudge(Offset delta) {
    if (_editingId != null) return;
    _controller.translateSelection(delta);
  }

  void _deleteSelection() {
    // The box being edited is selected so its handles show, but a key that
    // reaches the page while it has lost focus must not delete it.
    if (_editingId != null) return;
    _controller.deleteSelection();
  }

  /// Takes up [tool], from the ribbon.
  void _selectTool(CanvasTool tool) {
    if (tool != CanvasTool.select) _stopEditing();
    _controller.setTool(tool);
  }

  /// Takes up [tool] from its shortcut, and shows its tab: Draw for the pens
  /// and the eraser, Home — with the text formatting — for typing.
  void _useTool(CanvasTool tool) {
    _selectTool(tool);
    ref
        .read(ribbonProvider.notifier)
        .show(tool == CanvasTool.select ? RibbonTab.home : RibbonTab.draw);
  }

  void _formulaShortcut() => _insertFormula();

  // ----------------------------------------------------------------- build

  /// The page laid out alone, where no [PageEditor.around] is given.
  static Widget _alone(BuildContext context, Widget page) => page;

  @override
  Widget build(BuildContext context) {
    ref.listen<MathMode>(
      mathSyntaxProvider,
      (_, syntax) => _textController.formulaSyntax.value = syntax,
    );
    final highlight = ref.watch(searchHighlightProvider);

    return Column(
      children: <Widget>[
        Ribbon(commands: _ribbonCommands, enabled: _ready),
        Expanded(child: (widget.around ?? _alone)(context, _page(highlight))),
      ],
    );
  }

  Widget _page(SearchTerms? highlight) {
    final pageId = widget.pageId;
    if (pageId == null) return const _NoPageSelected();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: <Widget>[
        if (_error != null) _ErrorBanner(error: _error!),
        if (_ready)
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _canvas(pageId, highlight)),
                // The formula being edited is typed in its text box and shown
                // typeset beneath, at a size that does not change with zoom.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _formulaPlaced,
                    builder: (context, placed, _) => !placed
                        ? const SizedBox.shrink()
                        : ValueListenableBuilder<FormulaSession?>(
                            valueListenable: _textController.formula,
                            builder: (context, session, _) => session == null
                                ? const SizedBox.shrink()
                                : CustomSingleChildLayout(
                                    delegate: _BelowFormula(_formulaOnScreen),
                                    child: FormulaPreview(
                                      session: session,
                                      onDone: _textController.finishFormula,
                                    ),
                                  ),
                          ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _canvas(String pageId, SearchTerms? highlight) => CallbackShortcuts(
    bindings: _shortcuts,
    child: Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      child: InfiniteCanvas(
        controller: _controller,
        claimsPointer: _claimsPointer,
        onEmptyTap: _onEmptyTap,
        onCanvasPress: _onCanvasPress,
        onElementDoubleTap: _onElementDoubleTap,
        elementBuilder: (context, element) =>
            _buildElement(element, highlight, _firstMatchIn(highlight)),
        header: CanvasHeader(
          frame: PageTitle.frame,
          child: Listener(
            // Going to the title ends typing in a text box.
            onPointerDown: (_) => _stopEditing(refocusCanvas: false),
            child: PageTitle(
              key: ValueKey<String>(pageId),
              pageId: pageId,
              highlight: highlight,
              onFinished: _canvasFocus.requestFocus,
            ),
          ),
        ),
        trackpadPanScale: _trackpadPanScale,
      ),
    ),
  );

  /// The text box holding the first word [highlight] finds, reading down the
  /// page: the one brought into view.
  String? _firstMatchIn(SearchTerms? highlight) {
    if (highlight == null) return null;
    final document = _controller.document;
    if (identical(document, _matchedDocument) &&
        identical(highlight, _matchedTerms)) {
      return _firstMatch;
    }
    _matchedDocument = document;
    _matchedTerms = highlight;
    final boxes = document.elements.whereType<TextElement>().toList()
      ..sort((a, b) {
        final byTop = a.bounds.top.compareTo(b.bounds.top);
        return byTop != 0 ? byTop : a.bounds.left.compareTo(b.bounds.left);
      });
    return _firstMatch = boxes
        .where(
          (box) => box.blocks.any(
            (block) => TextBoxEditor.matchesIn(block, highlight).isNotEmpty,
          ),
        )
        .firstOrNull
        ?.id;
  }

  /// What [_firstMatchIn] last looked through, and what it found.
  PageDocument? _matchedDocument;
  SearchTerms? _matchedTerms;
  String? _firstMatch;

  /// Scrolls to [local], where a match lies in [element], in its own units.
  void _revealMatch(NoteElement element, Rect local) {
    final toPage = element.frame.localToPage;
    var bounds = Aabb.empty;
    for (final corner in <Offset>[
      local.topLeft,
      local.topRight,
      local.bottomLeft,
      local.bottomRight,
    ]) {
      final page = toPage.apply(corner.dx, corner.dy);
      bounds = bounds.union(Aabb(page.x, page.y, page.x, page.y));
    }
    _controller.reveal(bounds);
  }

  /// What each element's widget was last built from, and the widget.
  ///
  /// The canvas asks for every visible element's widget whenever the view
  /// moves. Handing back the same widget for an unchanged element lets the
  /// framework skip rebuilding it, so panning and zooming never re-lay out
  /// text or re-typeset formulas.
  final Map<String, (_ElementBuild, Widget)> _elementWidgets =
      <String, (_ElementBuild, Widget)>{};

  Widget? _buildElement(
    NoteElement element,
    SearchTerms? highlight,
    String? firstMatch,
  ) {
    final id = element.id;
    final isEditing = id == _editingId;
    final built = (
      element: element,
      isEditing: isEditing,
      startsInFormula: isEditing && _editingStartsInFormula,
      interactive: _controller.tool == CanvasTool.select,
      highlight: element is TextElement ? highlight : null,
      placesMatch: id == firstMatch,
    );
    final cached = _elementWidgets[id];
    if (cached != null && cached.$1 == built) return cached.$2;
    if (_elementWidgets.length > _controller.document.elements.length + 64) {
      _elementWidgets.removeWhere(
        (key, _) => _controller.document.elementById(key) == null,
      );
    }
    final widget = _elementWidget(built);
    _elementWidgets[id] = (built, widget);
    return widget;
  }

  Widget _elementWidget(_ElementBuild built) {
    final element = built.element;
    if (element is! TextElement) return CanvasElementView(element: element);
    final id = element.id;
    return TextBoxEditor(
      element: element,
      isEditing: built.isEditing,
      controller: _textController,
      interactive: built.interactive,
      startInFormula: built.startsInFormula,
      highlight: built.highlight,
      onMatchPlaced: built.placesMatch
          ? (local) => _revealMatch(element, local)
          : null,
      onStartEditing: () => _startEditing(id),
      onChanged: (blocks, {required recordUndo}) =>
          _onTextChanged(id, blocks, recordUndo: recordUndo),
      onSizeChanged: (size) => _onTextSizeChanged(id, size),
      onExit: _stopEditing,
    );
  }
}

/// What an element's widget is built from: built from the same again, it is
/// the same widget.
typedef _ElementBuild = ({
  NoteElement element,
  bool isEditing,
  bool startsInFormula,
  bool interactive,
  SearchTerms? highlight,
  bool placesMatch,
});

/// Where the page goes while none is open.
class _NoPageSelected extends StatelessWidget {
  const _NoPageSelected();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.edit_note_rounded,
              size: 48,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Select a page, or create one',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '$error',
        style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
      ),
    );
  }
}

/// Places the formula panel beneath the formula being edited, or above it
/// when there is no room below, always within the view.
class _BelowFormula extends SingleChildLayoutDelegate {
  _BelowFormula(this.formula) : super(relayout: formula);

  /// Where the formula is on screen.
  final ValueListenable<Rect?> formula;

  static const double _gap = 6;
  static const double _margin = 8;

  /// As wide as the source above it, within the preview's limits.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = math.max(0.0, constraints.maxWidth - 2 * _margin);
    final source = formula.value?.width ?? 0;
    final width = math.min(
      available,
      (source + 24).clamp(FormulaPreview.minWidth, FormulaPreview.maxWidth),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0, constraints.maxHeight - 2 * _margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = formula.value ?? const Rect.fromLTWH(24, 24, 0, 0);
    final x = (anchor.left - 6)
        .clamp(
          _margin,
          math.max(_margin, size.width - childSize.width - _margin),
        )
        .toDouble();
    var y = anchor.bottom + _gap;
    final above = anchor.top - _gap - childSize.height;
    if (y + childSize.height > size.height - _margin && above >= _margin) {
      y = above;
    }
    y = y
        .clamp(
          _margin,
          math.max(_margin, size.height - childSize.height - _margin),
        )
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BelowFormula oldDelegate) =>
      !identical(oldDelegate.formula, formula);
}
