/// The page editor: ribbon, canvas and autosave.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart'
    show LatexText;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ai/ai_view.dart';
import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/editor_keys.dart';
import '../commands/shortcuts.dart';
import '../files/attached_files.dart';
import '../files/notes_keeper.dart';
import '../files/notes_location.dart';
import '../input_trace.dart';
import '../links/note_links.dart';
import '../look/controls.dart';
import '../look/icons.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../providers.dart';
import '../search/search_panel.dart';
import '../shell/library_actions.dart';
import '../shell/new_page_choice.dart';
import '../spelling/proofreader.dart';
import '../spelling/spelling.dart';
import 'element_views.dart';
import 'latex_dialog.dart';
import 'media_import.dart';
import 'note_clipboard.dart';
import 'page_minimap.dart';
import 'page_title.dart';
import 'pen_preferences.dart';
import 'printout_place.dart';
import 'ribbon/mini_toolbar.dart';
import 'ribbon/ribbon.dart';
import 'sheet_choices.dart';
import 'text/box_formatting.dart';
import 'text/cheat_sheet.dart';
import 'text/formula_window.dart'
    show FormulaWindow, editTikzSource, formulaWindowProvider;
import 'text/math_syntax.dart';
import 'text/math_templates.dart';
import 'text/text_box_controller.dart';
import 'text/text_box_editor.dart';
import 'trackpad.dart';

part 'page_editor_chrome.dart';
part 'page_editor_clipboard.dart';
part 'page_editor_commands.dart';
part 'page_editor_elements.dart';
part 'page_editor_media.dart';
part 'page_editor_storage.dart';
part 'page_editor_text.dart';

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
  /// Rebuilds the page after [change], for the parts of it kept in other
  /// files of this library, which cannot call [setState] themselves.
  void _update(VoidCallback change) => setState(change);

  /// The words a followed link points at, marked in their text box until
  /// something else is picked.
  ({String elementId, WordsMark words})? _revealed;

  /// What [_firstMatchIn] last looked through, and what it found.
  PageDocument? _matchedDocument;

  SearchTerms? _matchedTerms;

  String? _firstMatch;

  /// What each element's widget was last built from, and the widget.
  ///
  /// The canvas asks for every visible element's widget whenever the view
  /// moves. Handing back the same widget for an unchanged element lets the
  /// framework skip rebuilding it, so panning and zooming never re-lay out
  /// text or re-typeset formulas.
  final Map<String, (_ElementBuild, Widget)> _elementWidgets =
      <String, (_ElementBuild, Widget)>{};

  /// How large each TikZ picture on the page was last drawn, unscaled.
  final Map<String, Size> _tikzDrawn = <String, Size>{};

  /// The TikZ pictures whose source has just changed, each with the size
  /// of its frame then: fitted to their new drawings once drawn.
  final Map<String, Size> _tikzChanged = <String, Size>{};

  /// What marks the words spelled wrongly in the text boxes, if anything.
  Proofreader? _proofreader;

  static const List<(AppCommand, CanvasTool)> _tools =
      <(AppCommand, CanvasTool)>[
        (AppCommand.selectTool, CanvasTool.select),
        (AppCommand.lassoTool, CanvasTool.lasso),
        (AppCommand.pen, CanvasTool.pen),
        (AppCommand.highlighter, CanvasTool.highlighter),
        (AppCommand.shapes, CanvasTool.shape),
        (AppCommand.eraser, CanvasTool.eraser),
      ];

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
        AppCommand.insertLatex: CommandAction(
          _ribbonCommands.onInsertLatex,
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
        AppCommand.pageLayout: CommandAction(
          _toggleLayout,
          enabled: () => _pageShowing,
        ),
        AppCommand.addSheet: CommandAction(
          () => unawaited(_addSheet(after: _controller.currentSheet)),
          enabled: () => _pageShowing && _controller.fold != null,
        ),
        AppCommand.moveSheetUp: CommandAction(
          () => _moveSheet(-1),
          enabled: () => _pageShowing && _canMoveSheet(-1),
        ),
        AppCommand.moveSheetDown: CommandAction(
          () => _moveSheet(1),
          enabled: () => _pageShowing && _canMoveSheet(1),
        ),
        AppCommand.deleteSheet: CommandAction(
          _deleteSheet,
          enabled: () => _pageShowing && (_controller.fold?.count ?? 0) > 1,
        ),
      };

  /// Zoom step for the keyboard shortcuts and toolbar buttons.
  static const double _zoomStep = 1.25;

  final CanvasController _controller = CanvasController();
  final TextBoxEditorController _textController = TextBoxEditorController();
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'Canvas');
  final ValueNotifier<bool> _saving = ValueNotifier<bool>(false);
  late final BoxFormatting _boxFormatting = BoxFormatting(_controller);

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
    onInsertLatex: () => unawaited(_insertLatex()),
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

  /// The version of the page [_autosave] was last set off by: what the
  /// view does, scrolling or zooming, does not put the save off.
  PageDocument? _autosaveFor;
  late final VoidCallback _stopTracingView;

  /// The text box with the caret, if any.
  String? _editingId;

  /// The boxes that are only a caret placed on the paper: nothing has been
  /// written at them yet. They show nothing, are picked by nothing, are kept
  /// out of history and are not saved; the first thing written makes one a
  /// box, recorded as arriving then ([CanvasController.replacePlaceholder]),
  /// and one left with nothing written goes as typing ends.
  final Set<String> _placed = <String>{};

  /// Whether the box [id] is only a caret placed on the paper: one of
  /// [_placed], but for one a formula is being typed at, which shows as the
  /// box it will be. Presses, and selections dragged across the page, pass
  /// over a caret to what lies beneath it.
  bool _onlyCaret(String id) =>
      _placed.contains(id) && !(id == _editingId && _formulaOpen);

  /// The caret the box being typed in was, before the first thing written
  /// at it made it a box: put back where undo takes the box away while it
  /// is typed in, so the words go and the caret stays.
  TextElement? _caretBefore;

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

  /// What went wrong opening or saving the page, said above it.
  String? _error;

  /// Held in fields rather than read through `ref` when saving, because the
  /// final save runs from [dispose], where `ref` may no longer be used.
  AantekeningStore? _store;
  late final Revision _libraryRevision;
  late final Revision _contentsRevision;
  late final VoidCallback _unregisterCommands;
  late final VoidCallback _unregisterSave;

  @override
  void initState() {
    super.initState();
    _libraryRevision = ref.read(libraryRevisionProvider.notifier);
    _contentsRevision = ref.read(pageContentsRevisionProvider.notifier);
    _unregisterCommands = ref
        .read(commandHandlersProvider)
        .register(_pageCommands);
    _unregisterSave = ref.read(openSavesProvider).register(_saveOpenPage);
    ref.listenManual<AsyncValue<FolderChanges>>(
      folderChangesProvider,
      (_, next) => _onChangedElsewhere(next.value),
    );
    _controller
      ..passesOver = _onlyCaret
      ..addListener(_onCanvasChanged);
    _stopTracingView = traceViewOf(_controller);
    _textController.formulaField.addListener(_onFormulaChanged);
    // The syntax formulas are typed in is the person's preference, which a
    // text box can switch too.
    _textController
      ..formulaSyntax.value = ref.read(mathSyntaxProvider)
      ..formulaSyntax.addListener(_onSyntaxChosen)
      ..formulaWindow = ref.read(formulaWindowProvider);
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
    _placed.clear();
    _caretBefore = null;
    _elementWidgets.clear();
    _tikzDrawn.clear();
    _tikzChanged.clear();
    if (widget.pageId != null) unawaited(_load());
  }

  @override
  void dispose() {
    _unregisterCommands();
    _unregisterSave();
    _autosave?.cancel();
    _controller.removeListener(_onCanvasChanged);
    _stopTracingView();
    _disposed = true;
    final pageId = widget.pageId;
    if (pageId != null && _ready && _controller.isDirty) {
      unawaited(_persist(pageId, _controller.document));
    }
    _textController.formulaField.removeListener(_onFormulaChanged);
    _textController.formulaSyntax.removeListener(_onSyntaxChosen);
    _controller.dispose();
    _textController.dispose();
    _canvasFocus.dispose();
    _saving.dispose();
    super.dispose();
  }

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
    ref.listen<FormulaWindow>(
      formulaWindowProvider,
      (_, limit) => _textController.formulaWindow = limit,
    );
    final highlight = ref.watch(searchHighlightProvider);
    _proofreader = ref.watch(proofreaderProvider);

    return Column(
      children: <Widget>[
        // The ribbon works on the page, so it rests while the AI shows.
        Ribbon(
          commands: _ribbonCommands,
          // Greyed out only while no page is chosen: switching from one page
          // to the next, it stays as it is.
          enabled: widget.pageId != null && widget.aiScope == null,
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
        if (_error case final error?) _ErrorBanner(error: error),
        if (_ready) Expanded(child: _scrolled(_canvas(pageId, highlight))),
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

  Widget _canvas(String pageId, SearchTerms? highlight) {
    final pen = ref.watch(penPreferencesProvider);
    _controller.inkSmoothing = pen.smoothing.pixels;
    return CallbackShortcuts(
      bindings: _shortcuts(ref.watch(shortcutsProvider)),
      child: Focus(
        focusNode: _canvasFocus,
        autofocus: true,
        child: CommandMenuHeader(
          header: _menuToolbar,
          child: InfiniteCanvas(
            controller: _controller,
            claimsPointer: _claimsPointer,
            overlay: ValueListenableBuilder<Widget?>(
              valueListenable: _textController.formulaField,
              builder: (context, field, _) => field ?? const SizedBox.shrink(),
            ),
            grips: _grips,
            onEmptyTap: _onEmptyTap,
            onCanvasPress: _onCanvasPress,
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
            deskColor: context.tones.desk,
            afterSheets: SmallButton(
              '+  Add sheet',
              tooltip: ref
                  .watch(shortcutsProvider)
                  .tooltip(AppCommand.addSheet, describe: true),
              onPressed: () => unawaited(
                _addSheet(after: (_controller.fold?.count ?? 1) - 1),
              ),
            ),
            penButtons: pen.buttons,
            shapesOnHold: pen.shapesOnHold,
            touchpadFingers: touchpadFingers,
          ),
        ),
      ),
    );
  }
}

/// What an element's widget is built from: built from the same again, it is
/// the same widget.
typedef _ElementBuild = ({
  NoteElement element,
  bool isEditing,
  bool selected,
  bool grouped,
  bool caretOnly,
  bool startsInFormula,
  bool interactive,
  SearchTerms? highlight,
  WordsMark? mark,
  Proofreader? proofreader,
  bool placesMatch,
});
