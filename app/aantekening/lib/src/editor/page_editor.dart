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

import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/editor_keys.dart';
import '../commands/shortcuts.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import '../providers.dart';
import '../input_trace.dart';
import '../links/note_links.dart';
import '../search/search_panel.dart';
import '../spelling/proofreader.dart';
import '../spelling/spelling.dart';
import '../ai/ai_view.dart';
import 'element_views.dart';
import 'media_import.dart';
import 'note_clipboard.dart';
import 'page_minimap.dart';
import 'page_title.dart';
import 'ribbon/mini_toolbar.dart';
import 'ribbon/ribbon.dart';
import 'text/box_formatting.dart';
import 'text/cheat_sheet.dart';
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
  const PageEditor({
    required this.pageId,
    this.around,
    this.aiScope,
    super.key,
  });

  /// The page open, or null for none.
  final String? pageId;

  /// Lays the page out in the window below the ribbon — beside the sidebar,
  /// say. The ribbon spans the whole window, over both.
  final Widget Function(BuildContext context, Widget page)? around;

  /// What the AI is being asked about, when it is shown in place of the
  /// page — or null while the page is.
  final NoteLink? aiScope;

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

  /// The Home tab's text formatting, over every right-click menu on the
  /// page.
  late final Widget _menuToolbar = MiniToolbar(commands: _ribbonCommands);

  /// What was pasted from last, and how many times, so each paste of the
  /// same things lands a step further on from the last.
  List<NoteElement>? _pasted;
  int _pasteCount = 0;

  Timer? _autosave;
  late final VoidCallback _stopTracingView;

  /// The text box with the caret, if any.
  String? _editingId;

  /// Where each page opened this session was last seen from, so going back
  /// to it — in another tab, say — finds it as it was left.
  final Map<String, CanvasViewport> _views = <String, CanvasViewport>{};

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
  late final VoidCallback _unregisterCommands;

  @override
  void initState() {
    super.initState();
    _libraryRevision = ref.read(libraryRevisionProvider.notifier);
    _unregisterCommands = ref
        .read(commandHandlersProvider)
        .register(_pageCommands);
    _controller.addListener(_onCanvasChanged);
    _stopTracingView = traceViewOf(_controller);
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
    if (leaving != null && _ready) {
      _views[leaving] = _controller.viewport;
      if (_controller.isDirty) {
        unawaited(_persist(leaving, _controller.document));
      }
    }
    _ready = false;
    _editingId = null;
    _elementWidgets.clear();
    if (widget.pageId != null) unawaited(_load());
  }

  @override
  void dispose() {
    _unregisterCommands();
    _autosave?.cancel();
    _controller.removeListener(_onCanvasChanged);
    _stopTracingView();
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
      if (_views[pageId] case final view?) _controller.viewport = view;
      if (!identical(document, page)) unawaited(_persist(pageId, document));
      setState(() {
        _loading = false;
        _ready = true;
      });
      // A link followed to a place on this page shows it once the page is
      // laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _meetRevealRequest());
    } on Object catch (error) {
      if (!mounted || pageId != widget.pageId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Brings the place a followed link points at into view, and picks it,
  /// once its page is showing.
  void _meetRevealRequest() {
    final link = ref.read(revealRequestProvider);
    if (!mounted || link == null || link.id != widget.pageId || !_ready) return;
    ref.read(revealRequestProvider.notifier).done();
    final id = link.elementId;
    final element = id == null ? null : _controller.document.elementById(id);
    if (element == null) return;
    final words = link.words;
    final block = link.block;
    setState(() {
      _revealed = words == null || block == null
          ? null
          : (
              elementId: element.id,
              words: (block: block, from: words.from, to: words.to),
            );
    });
    _controller
      ..reveal(element.bounds)
      ..select(element.id);
  }

  /// The words a followed link points at, marked in their text box until
  /// something else is picked.
  ({String elementId, WordsMark words})? _revealed;

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
    if (_revealed case final revealed?
        when !_controller.selection.contains(revealed.elementId)) {
      setState(() => _revealed = null);
    }
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
    // Anything else picked on the page — by a drag across the paper, say —
    // ends typing in the box.
    final selection = _controller.selection;
    if (editingId != null &&
        selection.isNotEmpty &&
        !(selection.length == 1 && selection.contains(editingId))) {
      _stopEditing();
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
    final box = _newTextBox(page);
    _controller.addElement(
      box,
      // The box is recorded in history and saved with its first edit; an
      // empty box that is abandoned leaves no trace.
      recordUndo: false,
      markDirty: false,
    );
    return box.id;
  }

  /// Where a new box's text starts from its top-left corner: where the
  /// click that placed its caret was.
  static final Offset _textOrigin = Offset(
    TextBoxEditor.padding.left,
    TextBoxEditor.grabBand + 10,
  );

  /// A text box whose first line starts at [page], holding [blocks], that
  /// widens with its text.
  static TextElement _newTextBox(
    Offset page, {
    List<TextBlock> blocks = const <TextBlock>[TextBlock()],
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return TextElement(
      id: Ulid.generate(),
      frame: Frame(
        x: page.dx - _textOrigin.dx,
        y: page.dy - _textOrigin.dy,
        width: TextBoxEditor.newBoxSize.width,
        height: TextBoxEditor.newBoxSize.height,
      ),
      createdAt: now,
      updatedAt: now,
      blocks: blocks,
      autoWidth: true,
    );
  }

  void _onEmptyTap(Offset page) {
    _stopEditing(refocusCanvas: false);
    _startEditing(_createTextBox(page));
  }

  void _onCanvasPress(NoteElement? hit) {
    // Paper pressed with the select tool is not yet known to leave the box: a
    // click there places a caret, and a drag picks what it passes over, each
    // ending the typing as it happens. Ending it on the press left the ribbon
    // with nothing to format, greyed, for as long as the button was down.
    if (hit == null && _controller.tool == CanvasTool.select) return;
    if (hit?.id != _editingId) _stopEditing();
    _canvasFocus.requestFocus();
  }

  bool _claimsPointer(NoteElement element, Offset page) =>
      element is TextElement && !TextBoxEditor.isInGrabBand(element, page);

  /// A selected text box is picked up by its band even under another box.
  bool _grips(NoteElement element, Offset page) =>
      element is TextElement &&
      element.frame.containsPoint(
        page.dx,
        page.dy,
        slop: CanvasController.hitSlop,
      ) &&
      TextBoxEditor.isInGrabBand(element, page);

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
    final List<BlockEmbed> items;
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
      _textController.insertEmbeds(items);
      return;
    }

    final width = _controller.document.canvas.paperWidth ?? _defaultMediaWidth;
    final center = _controller.viewCenter;
    var y = center.dy - 120;
    if (editing != null && atBareCaret) {
      y = editing.frame.y + TextBoxEditor.grabBand;
      _stopEditing();
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final elements = <NoteElement>[];
    for (final item in items) {
      // No wider than the paper, keeping its proportions.
      final itemWidth = math.min(item.width, width);
      final itemHeight = itemWidth / item.aspectRatio;
      final element = item.toElement(
        frame: Frame(
          x: editing != null && atBareCaret
              ? editing.frame.x + TextBoxEditor.padding.left
              : center.dx - itemWidth / 2,
          y: y,
          width: itemWidth,
          height: itemHeight,
        ),
        now: now,
      );
      elements.add(element);
      y += itemHeight + 24;
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

  // -------------------------------------------------------- copy and paste

  /// Copies the things picked on the page, or cuts them. Text being edited
  /// is copied by its box.
  Future<void> _copySelection({bool cut = false}) async {
    if (_editingId != null) return;
    final selected = _controller.selectedElements;
    if (selected.isEmpty) return;
    await NoteClipboard.copy(ElementsClip(selected));
    if (cut && mounted) _controller.deleteSelection();
  }

  /// Pastes what was copied — as it was, or as its text only — onto the
  /// page: things from the page as copies of them, text in a new box. With
  /// [at], a place on the page, that is where it goes; else copies go a step
  /// on from what they copy, and a box into the middle of the view.
  Future<void> _paste({Offset? at, bool textOnly = false}) async {
    if (_editingId != null || !_ready) return;
    final clip = textOnly
        ? await NoteClipboard.readText()
        : await NoteClipboard.read();
    if (clip == null || !mounted) return;
    switch (clip) {
      case ElementsClip(:final elements):
        _pasteElements(elements, at: at);
      case TextClip(:final blocks):
        _pasteBox(blocks, at: at);
      case PlainClip(:final plain):
        _pasteBox(<TextBlock>[
          for (final line in plain.replaceAll('\r\n', '\n').split('\n'))
            TextBlock.plain(line),
        ], at: at);
    }
  }

  /// Copies of [elements] on the page, at [at] or a step on from them.
  void _pasteElements(List<NoteElement> elements, {Offset? at}) {
    final Vec2 offset;
    if (at != null) {
      final bounds = NoteElement.boundsOf(elements);
      offset = Vec2(at.dx - bounds.left, at.dy - bounds.top);
    } else {
      _pasteCount = identical(elements, _pasted) ? _pasteCount + 1 : 1;
      _pasted = elements;
      offset = Vec2(24.0 * _pasteCount, 24.0 * _pasteCount);
    }
    final copies = NoteElement.copiesOf(
      elements,
      now: DateTime.now().millisecondsSinceEpoch,
      offset: offset,
    );
    _controller
      ..setTool(CanvasTool.select)
      ..addElements(copies)
      ..selectAll(copies.map((element) => element.id));
  }

  /// Things from the page that the box being edited passed on rather than
  /// take into its text: pasted at its caret, in place of the box, where it
  /// is a bare caret on the paper, else a step on from what they copy.
  void _pasteFromBox(List<NoteElement> elements) {
    final id = _editingId;
    final box = id == null ? null : _controller.document.elementById(id);
    if (box is! TextElement || !TextBoxEditor.isEmpty(box.blocks)) {
      _pasteElements(elements);
      return;
    }
    // The empty box goes as the typing ends.
    _stopEditing();
    _pasteElements(
      elements,
      at: Offset(box.frame.x, box.frame.y) + _textOrigin,
    );
  }

  /// A new box holding [blocks], at [at] or in the middle of the view.
  void _pasteBox(List<TextBlock> blocks, {Offset? at}) {
    final box = _newTextBox(at ?? _controller.viewCenter, blocks: blocks);
    _controller
      ..setTool(CanvasTool.select)
      ..addElement(box)
      ..select(box.id);
  }

  /// Takes the picture or PDF page on block [block] of the box [boxId] out
  /// of it, to lie where it is, [local] in the box's own units, as part of
  /// the page's background. A box left empty goes with it.
  void _embedToBackground(String boxId, int block, Rect local) {
    final box = _controller.document.elementById(boxId);
    if (box is! TextElement || block >= box.blocks.length) return;
    final embed = box.blocks[block].embed;
    if (embed == null) return;
    final center = box.frame.localToPage.apply(
      local.center.dx,
      local.center.dy,
    );
    final picture = embed.toElement(
      frame: Frame(
        x: center.x - local.width / 2,
        y: center.y - local.height / 2,
        width: local.width,
        height: local.height,
        rotation: box.frame.rotation,
      ),
      now: DateTime.now().millisecondsSinceEpoch,
    );
    final rest = RichTextEditing.deleteEmbed(box.blocks, block).blocks;
    if (TextBoxEditor.isEmpty(rest)) {
      if (_editingId == boxId) _stopEditing();
      _controller.removeElements(<String>{boxId});
    } else {
      _controller.replaceElement(box.copyWith(blocks: rest));
    }
    // One undo step for all of it.
    _controller
      ..addElement(picture, recordUndo: false)
      ..setBackground(picture.id, background: true, recordUndo: false);
  }

  /// The menu a right-click on the page opens, at [page], [global] on
  /// screen: the Home tab's text formatting, cutting, copying and pasting,
  /// setting a picture or PDF page as the background or taking it out, and
  /// deleting.
  ///
  /// What was right-clicked is picked first, so the menu acts on it: a box
  /// by its band, too, as a box.
  Future<void> _onContextMenu(Offset page, Offset global) async {
    final hit = _controller.hitTest(page);
    final background = hit == null ? _controller.backgroundAt(page) : null;
    if (hit == null) {
      _stopEditing();
      _controller.clearSelection();
    } else if (hit.id == _editingId ||
        !_controller.selection.contains(hit.id)) {
      _stopEditing();
      _controller.select(hit.id);
    }
    final selected = _controller.selectedElements;
    final picture = selected.length == 1 && selected.single.asEmbed != null
        ? selected.single
        : null;
    final canPaste = await NoteClipboard.read() != null;
    if (!mounted) return;
    final some = selected.isNotEmpty;
    await showCommandMenu(
      context,
      global,
      header: _menuToolbar,
      <List<MenuCommand>>[
        <MenuCommand>[
          MenuCommand(
            'Cut',
            some ? () => unawaited(_copySelection(cut: true)) : null,
            shortcut: EditorKey.cut.keys,
          ),
          MenuCommand(
            'Copy',
            some ? () => unawaited(_copySelection()) : null,
            shortcut: EditorKey.copy.keys,
          ),
          MenuCommand(
            'Paste',
            canPaste ? () => unawaited(_paste(at: page)) : null,
            shortcut: EditorKey.paste.keys,
          ),
          MenuCommand(
            'Paste text only',
            canPaste ? () => unawaited(_paste(at: page, textOnly: true)) : null,
            shortcut: EditorKey.pasteText.keys,
          ),
        ],
        <MenuCommand>[
          if (picture != null)
            MenuCommand(
              'Set picture as background',
              () => _controller.setBackground(picture.id, background: true),
            ),
          if (background != null)
            MenuCommand(
              'Set picture as background',
              () => _controller.setBackground(background.id, background: false),
              checked: true,
            ),
        ],
        <MenuCommand>[
          if (some)
            MenuCommand(
              'Delete',
              _deleteSelection,
              shortcut: EditorKey.deleteSelection.keys,
            ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- shortcuts

  /// Whether a page is showing, for the page's commands to act on.
  bool get _pageShowing => _ready && widget.aiScope == null;

  /// The page's own commands, run from their shortcuts wherever the
  /// keyboard is, and from the command palette.
  late final Map<AppCommand, CommandAction> _pageCommands =
      <AppCommand, CommandAction>{
        AppCommand.save: CommandAction(_saveNow, enabled: () => _ready),
        AppCommand.toggleRibbon: CommandAction(
          ref.read(ribbonProvider.notifier).toggleCollapsed,
        ),
        for (final (command, tool) in _tools)
          command: CommandAction(
            () => _useTool(tool),
            enabled: () => _pageShowing,
          ),
        AppCommand.insertTextBox: CommandAction(
          _ribbonCommands.onInsertTextBox,
          enabled: () => _pageShowing,
        ),
        AppCommand.insertPicture: CommandAction(
          _ribbonCommands.onInsertImage,
          enabled: () => _pageShowing,
        ),
        AppCommand.insertPdf: CommandAction(
          _ribbonCommands.onInsertPdf,
          enabled: () => _pageShowing,
        ),
        AppCommand.zoomIn: CommandAction(
          _ribbonCommands.onZoomIn,
          enabled: () => _pageShowing,
        ),
        AppCommand.zoomOut: CommandAction(
          _ribbonCommands.onZoomOut,
          enabled: () => _pageShowing,
        ),
        AppCommand.actualSize: CommandAction(
          _ribbonCommands.onActualSize,
          enabled: () => _pageShowing,
        ),
        AppCommand.fitPage: CommandAction(
          _ribbonCommands.onFitPage,
          enabled: () => _pageShowing,
        ),
      };

  static const List<(AppCommand, CanvasTool)> _tools =
      <(AppCommand, CanvasTool)>[
        (AppCommand.selectTool, CanvasTool.select),
        (AppCommand.pen, CanvasTool.pen),
        (AppCommand.highlighter, CanvasTool.highlighter),
        (AppCommand.eraser, CanvasTool.eraser),
      ];

  /// Page-level shortcuts: those of editing what is on the page, and the
  /// page's commands bound to keys the window does not catch — plain
  /// letters, and those typing takes. A text box being edited has them
  /// first, so typing never switches tools.
  Map<ShortcutActivator, VoidCallback> _shortcuts(
    ShortcutBindings bindings,
  ) => <ShortcutActivator, VoidCallback>{
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
    const SingleActivator(LogicalKeyboardKey.keyM): _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.keyM, control: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.equal, alt: true):
        _formulaShortcut,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
        unawaited(_copySelection()),
    const SingleActivator(LogicalKeyboardKey.keyX, control: true): () =>
        unawaited(_copySelection(cut: true)),
    const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
        unawaited(_paste()),
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      shift: true,
    ): () =>
        unawaited(_paste(textOnly: true)),
    const SingleActivator(LogicalKeyboardKey.keyA, control: true):
        _selectEverything,
    for (final (key, direction)
        in _arrows) ...<ShortcutActivator, VoidCallback>{
      SingleActivator(key): () => _nudge(direction),
      SingleActivator(key, shift: true): () => _nudge(direction * 10),
    },
    for (final MapEntry(key: command, value: action) in _pageCommands.entries)
      for (final chord in bindings.of(command))
        if (!chord.worksAnywhere) chord.activator: action.run,
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

  /// Selects everything on the page. Reached from a text box only where it
  /// had nothing left to select, whose caret goes as the page takes over.
  void _selectEverything() {
    final editing = _editingId != null;
    _stopEditing();
    _controller.setTool(CanvasTool.select);
    if (!editing) {
      _controller.selectEverything();
      return;
    }
    // A box left with nothing in it is removed after this frame; selecting
    // once it has gone keeps the handles from flashing round the caret.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.selectEverything();
    });
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
    ref.listen(revealRequestProvider, (_, _) => _meetRevealRequest());
    ref.listen<MathMode>(
      mathSyntaxProvider,
      (_, syntax) => _textController.formulaSyntax.value = syntax,
    );
    final highlight = ref.watch(searchHighlightProvider);
    _proofreader = ref.watch(proofreaderProvider);

    return Column(
      children: <Widget>[
        // The ribbon works on the page, so it rests while the AI shows.
        Ribbon(
          commands: _ribbonCommands,
          enabled: _ready && widget.aiScope == null,
        ),
        Expanded(
          child: (widget.around ?? _alone)(
            context,
            // A row even while the cheat sheet is closed, so opening it
            // leaves the page, and the formula being typed on it, as it is.
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _page(highlight)),
                if (ref.watch(cheatSheetProvider)) ...<Widget>[
                  const VerticalDivider(width: 1),
                  CheatSheet(onInsert: _ready ? _insertMath : null),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _page(SearchTerms? highlight) {
    final pageId = widget.pageId;
    final aiScope = widget.aiScope;
    if (aiScope != null) return AiView(scope: aiScope);
    if (pageId == null) return const _NoPageSelected();
    if (_loading) return const Loading();
    return Column(
      children: <Widget>[
        if (_error != null) _ErrorBanner(error: _error!),
        if (_ready) Expanded(child: _scrolled(_pageArea(pageId, highlight))),
      ],
    );
  }

  /// [page] with a scrollbar beneath it and another, or the page drawn
  /// small, down its right-hand side.
  Widget _scrolled(Widget page) {
    final corner = ColoredBox(color: context.tones.mix(0.02));
    final minimap = ref.watch(minimapProvider);
    return Column(
      children: <Widget>[
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: page),
              if (minimap) ...<Widget>[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: PageMinimap.width,
                  child: PageMinimap(controller: _controller),
                ),
              ] else
                PageScrollbar(controller: _controller, axis: Axis.vertical),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: PageScrollbar(
                controller: _controller,
                axis: Axis.horizontal,
              ),
            ),
            // The corner where the bars meet.
            SizedBox.square(dimension: PageScrollbar.thickness, child: corner),
            if (minimap)
              SizedBox(
                width: PageMinimap.width + 1 - PageScrollbar.thickness,
                height: PageScrollbar.thickness,
                child: corner,
              ),
          ],
        ),
      ],
    );
  }

  /// The page, and over it the preview of the formula being typed.
  Widget _pageArea(String pageId, SearchTerms? highlight) => Stack(
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
  );

  Widget _canvas(String pageId, SearchTerms? highlight) => CallbackShortcuts(
    bindings: _shortcuts(ref.watch(shortcutsProvider)),
    child: Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      child: CommandMenuHeader(
        header: _menuToolbar,
        child: InfiniteCanvas(
          controller: _controller,
          claimsPointer: _claimsPointer,
          grips: _grips,
          onEmptyTap: _onEmptyTap,
          onCanvasPress: _onCanvasPress,
          onElementDoubleTap: _onElementDoubleTap,
          onContextMenu: (page, global) =>
              unawaited(_onContextMenu(page, global)),
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
          selectionColor: context.tones.paperEmphasis,
        ),
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

  /// What marks the words spelled wrongly in the text boxes, if anything.
  Proofreader? _proofreader;

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
      selected: _controller.selection.contains(id),
      startsInFormula: isEditing && _editingStartsInFormula,
      interactive: _controller.tool == CanvasTool.select,
      highlight: element is TextElement ? highlight : null,
      mark: _revealed?.elementId == id ? _revealed!.words : null,
      proofreader: element is TextElement ? _proofreader : null,
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
      selected: built.selected,
      controller: _textController,
      interactive: built.interactive,
      startInFormula: built.startsInFormula,
      highlight: built.highlight,
      mark: built.mark,
      proofreader: built.proofreader,
      onMatchPlaced: built.placesMatch
          ? (local) => _revealMatch(element, local)
          : null,
      onStartEditing: () => _startEditing(id),
      onChanged: (blocks, {required recordUndo}) =>
          _onTextChanged(id, blocks, recordUndo: recordUndo),
      onSizeChanged: (size) => _onTextSizeChanged(id, size),
      onExit: _stopEditing,
      onPasteElements: _pasteFromBox,
      onEmbedToBackground: (block, local) =>
          _embedToBackground(id, block, local),
      pageId: widget.pageId,
      onOpenLink: (uri) => unawaited(ref.read(noteLinksProvider).open(uri)),
    );
  }
}

/// What an element's widget is built from: built from the same again, it is
/// the same widget.
typedef _ElementBuild = ({
  NoteElement element,
  bool isEditing,
  bool selected,
  bool startsInFormula,
  bool interactive,
  SearchTerms? highlight,
  WordsMark? mark,
  Proofreader? proofreader,
  bool placesMatch,
});

/// Where the page goes while none is open: what to do instead.
class _NoPageSelected extends ConsumerWidget {
  const _NoPageSelected();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final bindings = ref.watch(shortcutsProvider);
    Widget line(AppCommand command, String what) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 170,
            child: Text(
              what,
              style: TextStyle(fontSize: 13, color: tones.muted),
            ),
          ),
          SizedBox(
            width: 120,
            child: KeyHint(
              bindings.of(command).firstOrNull?.label ?? '',
              color: tones.text,
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: tones.base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            line(AppCommand.goTo, 'Go to a page'),
            line(AppCommand.newPage, 'New page'),
            line(AppCommand.search, 'Search every page'),
            line(AppCommand.commands, 'Every command'),
            line(AppCommand.settings, 'Settings'),
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
    final tones = context.tones;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tones.base,
        border: Border(bottom: BorderSide(color: tones.strongLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text('$error', style: TextStyle(fontSize: 12, color: tones.text)),
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
