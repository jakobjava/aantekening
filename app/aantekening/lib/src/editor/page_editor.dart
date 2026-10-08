/// The page editor: the canvas, its keys, and autosave.
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
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ai/ai_view.dart';
import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/shortcuts.dart';
import '../files/attached_files.dart';
import '../files/notes_keeper.dart';
import '../files/notes_location.dart';
import '../input_trace.dart';
import '../links/note_links.dart';
import '../look/controls.dart';
import '../look/floating_pane.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/editor_mode.dart';
import '../modes/key_catch.dart';
import '../modes/key_guide.dart';
import '../modes/mode_keys.dart';
import '../providers.dart';
import '../search/search_session.dart';
import '../shell/library_actions.dart';
import '../shell/new_page_choice.dart';
import '../shell/tabs.dart';
import '../spelling/proofreader.dart';
import '../spelling/spelling.dart';
import 'element_views.dart';
import 'focus_glide.dart';
import 'jump_labels.dart';
import 'latex_dialog.dart';
import 'media_import.dart';
import 'note_clipboard.dart';
import 'page_commands.dart';
import 'page_layers.dart';
import 'page_minimap.dart';
import 'page_status.dart';
import 'page_title.dart';
import 'palette.dart';
import 'pen_preferences.dart';
import 'printout_place.dart';
import 'sheet_choices.dart';
import 'spatial_focus.dart';
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
part 'page_editor_keys.dart';
part 'page_editor_media.dart';
part 'page_editor_modes.dart';
part 'page_editor_storage.dart';
part 'page_editor_text.dart';

/// Edits the page that is open, laid out among whatever [around] puts beside
/// it, with the keys of the mode it is in and the menu of all it can do.
///
/// The editor stays as other pages are opened, loading each in turn, so the
/// tool in hand and the pens stay as they were. It owns the
/// [CanvasController] directly rather than holding it in a provider: its
/// lifetime is exactly this widget's, which guarantees a final save.
class PageEditor extends ConsumerStatefulWidget {
  const PageEditor({
    required this.pageId,
    this.aiScope,
    this.active = true,
    this.obscured = EdgeInsets.zero,
    super.key,
  });

  /// Whether it has the keys: its commands are the page's, the status line
  /// shows its page, and the window's mode is its. With the window split,
  /// the other is not.
  final bool active;

  /// How much of the editor, from each of its edges, lies under what floats
  /// over it — the status line: the page scrolls out from under it at the
  /// top, and nothing else of the editor lies beneath it.
  final EdgeInsets obscured;

  /// The page open, or null for none.
  final String? pageId;

  /// What the AI is being asked about, when it is shown in place of the
  /// page — or null while the page is.
  final NoteLink? aiScope;

  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  /// Rebuilds the page after [change], for the parts of it kept in other
  /// files of this library, which cannot call [setState] themselves.
  void _update(VoidCallback change) {
    setState(change);
    _syncMode();
  }

  /// The mode last told to the window.
  EditorMode? _reportedMode;

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
        AppCommand.menu: CommandAction(
          _openMenu,
          enabled: () => widget.aiScope == null,
        ),
        AppCommand.pickedMenu: CommandAction(
          _openPickedMenu,
          enabled: () => _pageShowing,
        ),
        for (final (command, tool) in _tools)
          command: CommandAction(
            () => _selectTool(tool),
            enabled: () => _pageShowing,
          ),
        AppCommand.insertTextBox: CommandAction(
          _commands.onInsertTextBox,
          enabled: () => _pageShowing,
        ),
        AppCommand.insertPicture: CommandAction(
          _commands.onInsertImage,
          enabled: () => _pageShowing,
        ),
        AppCommand.insertPdf: CommandAction(
          _commands.onInsertPdf,
          enabled: () => _pageShowing,
        ),
        AppCommand.insertLatex: CommandAction(
          _commands.onInsertLatex,
          enabled: () => _pageShowing,
        ),
        AppCommand.zoomIn: CommandAction(
          _commands.onZoomIn,
          enabled: () => _pageShowing,
        ),
        AppCommand.zoomOut: CommandAction(
          _commands.onZoomOut,
          enabled: () => _pageShowing,
        ),
        AppCommand.actualSize: CommandAction(
          _commands.onActualSize,
          enabled: () => _pageShowing,
        ),
        AppCommand.fitPage: CommandAction(
          _commands.onFitPage,
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

  /// What has the keys in a tab with no page open.
  final FocusNode _emptyFocus = FocusNode(debugLabel: 'No page');
  final ValueNotifier<bool> _saving = ValueNotifier<bool>(false);
  late final BoxFormatting _boxFormatting = BoxFormatting(_controller);

  /// Whether a formula is being typed.
  bool _formulaOpen = false;

  /// Where on the page the menu was last opened with a right-click, or
  /// null where it was opened from the keys.
  Offset? _menuPoint;

  /// Where on the screen the keys last moved to, for the ring that glides
  /// there.
  final ValueNotifier<Rect?> _glide = ValueNotifier<Rect?>(null);

  /// Space while it is held, or null.
  _SpaceHeld? _space;

  /// The jump labels showing, or null while none are.
  Jump? _jump;

  /// Ends the keeping of what is typed for a text box on its way, typing
  /// it in if [type] and the box is there; null while nothing is kept.
  void Function({required bool type})? _endTypeOn;
  final double _trackpadPanScale = trackpadPanScale();

  /// The pen or highlighter used last, which colours and widths chosen
  /// apply to while neither is in hand.
  CanvasTool _lastInkTool = CanvasTool.pen;

  /// What the formatting of selected boxes was last worked out from.
  PageDocument? _formattedDocument;
  Set<String> _formattedSelection = const <String>{};

  late final PageCommands _commands = PageCommands(
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
  );

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
  VoidCallback? _unregisterCommands;
  late final VoidCallback _unregisterSave;

  /// What the status line shows of this page, while it has the keys.
  late final PageHandle _handle = PageHandle(
    canvas: _controller,
    saving: _saving,
    onActualSize: _commands.onActualSize,
  );
  late final ActivePage _activePage;

  @override
  void initState() {
    super.initState();
    _libraryRevision = ref.read(libraryRevisionProvider.notifier);
    _contentsRevision = ref.read(pageContentsRevisionProvider.notifier);
    _activePage = ref.read(activePageProvider.notifier);
    if (widget.active) _takeKeys();
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
    _controller.obscured = _underGlass;
    if (widget.pageId != null) unawaited(_load());
  }

  /// What of the page lies under what floats over the editor: only its top,
  /// as the scrollbar across its foot is kept clear of it.
  EdgeInsets get _underGlass => EdgeInsets.only(top: widget.obscured.top);

  /// Takes the keys: the page's commands are this one's, and the status
  /// line shows it — once the window is built, which may not change while
  /// it is.
  void _takeKeys() {
    _unregisterCommands ??= ref
        .read(commandHandlersProvider)
        .register(_pageCommands);
    _reportedMode = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !widget.active) return;
      _activePage.show(_handle);
      _syncMode();
      _canvasFocus.requestFocus();
    });
  }

  /// Lets go of the keys, for the editor beside it.
  void _leaveKeys() {
    _unregisterCommands?.call();
    _unregisterCommands = null;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => _activePage.leave(_handle),
    );
  }

  void _onSyntaxChosen() => ref
      .read(mathSyntaxProvider.notifier)
      .set(_textController.formulaSyntax.value);

  @override
  void didUpdateWidget(PageEditor old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      widget.active ? _takeKeys() : _leaveKeys();
    }
    if (old.obscured != widget.obscured) {
      // Not while the window is built: the page tells what shows it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _controller.obscured = _underGlass;
      });
    }
    if (old.aiScope != null && widget.aiScope == null && widget.active) {
      // Back from the AI, the keys are the page's again.
      _takeKeysBack();
    }
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
    _syncMode();
    if (widget.pageId != null) {
      unawaited(_load());
    } else if (widget.active && widget.aiScope == null) {
      // A page closed, the tab without one has the keys, for Space and the
      // rest.
      _takeKeysBack();
    }
  }

  /// Gives the keys back to the page — or, with none open, to the tab
  /// without one — once it is drawn.
  void _takeKeysBack() => SchedulerBinding.instance.addPostFrameCallback((_) {
    if (_disposed) return;
    (widget.pageId == null ? _emptyFocus : _canvasFocus).requestFocus();
  });

  @override
  void dispose() {
    _jump?.end();
    _endTypeOn?.call(type: false);
    _leaveKeys();
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
    _emptyFocus.dispose();
    _saving.dispose();
    _glide.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen(revealRequestProvider, (_, _) {
      if (widget.active) _meetRevealRequest();
    });
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

    // A stack even while the cheat sheet is closed, so opening it leaves the
    // page, and the formula being typed on it, as it is. It floats on glass
    // down the right of the page, as the AI does.
    const margin = 8.0;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _withAi(_page(highlight))),
        if (widget.active && ref.watch(cheatSheetProvider))
          Positioned.fill(
            child: Padding(
              padding: _floatingIn(margin),
              child: FloatingPane(
                pane: Pane.cheatSheet,
                natural: (area) => _downTheRight(area, CheatSheet.width),
                position: _atTheRight,
                minSize: const Size(220, 200),
                child: Glass(
                  child: CheatSheet(onInsert: _ready ? _insertMath : null),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// [page], and the tab's AI over it while it shows: a pane of glass
  /// along its right, the notes beside it. A click on them goes back to
  /// them.
  Widget _withAi(Widget page) {
    final scope = widget.aiScope;
    if (scope == null) return page;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: page),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (widget.active) ref.read(tabsProvider.notifier).toggleAi();
            },
          ),
        ),
        Positioned.fill(
          child: AiPane(scope: scope, obscured: widget.obscured),
        ),
      ],
    );
  }

  Widget _page(SearchTerms? highlight) {
    final pageId = widget.pageId;
    Widget clear(Widget child) =>
        Padding(padding: widget.obscured, child: child);
    if (pageId == null) {
      return clear(
        Focus(
          focusNode: _emptyFocus,
          autofocus:
              widget.active &&
              widget.aiScope == null &&
              (ModalRoute.of(context)?.isCurrent ?? true),
          onKeyEvent: _onEmptyKey,
          child: const _NoPageSelected(),
        ),
      );
    }
    if (_loading) return clear(const Loading());
    return Column(
      children: <Widget>[
        if (_error case final error?) clear(_ErrorBanner(error: error)),
        if (_ready) Expanded(child: _scrolled(_canvas(pageId, highlight))),
      ],
    );
  }

  /// What a pane floating over the page keeps clear of: [margin] from its
  /// edges, and what covers them.
  EdgeInsets _floatingIn(double margin) => EdgeInsets.fromLTRB(
    margin,
    widget.obscured.top + margin,
    margin,
    widget.obscured.bottom + margin,
  );

  /// A pane down the right of the page, [width] wide, as tall as it is.
  static BoxConstraints _downTheRight(Size area, double width) =>
      BoxConstraints.tight(Size(math.min(width, area.width), area.height));

  static Offset _atTheRight(Size area, Size pane) =>
      Offset(area.width - pane.width, 0);

  /// [page], the scrollbars floating over its right and its foot — or, for
  /// the right's, the page drawn small on a pane of glass — clear of what
  /// floats over the editor, which the page itself runs on under.
  Widget _scrolled(Widget page) {
    final minimap = ref.watch(minimapProvider);
    final obscured = widget.obscured;
    const bar = PageScrollbar.thickness;
    const margin = 8.0;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: page),
        if (minimap)
          Positioned.fill(
            child: Padding(
              padding: _floatingIn(margin) + const EdgeInsets.only(bottom: bar),
              child: FloatingPane(
                pane: Pane.minimap,
                natural: (area) => _downTheRight(area, PageMinimap.width),
                position: _atTheRight,
                minSize: const Size(80, 120),
                // A drag there moves it, not the page.
                holdsItsTop: true,
                child: Glass(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: Corners.controlRadius,
                      child: PageMinimap(controller: _controller),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Positioned(
            right: 0,
            top: obscured.top + margin,
            bottom: obscured.bottom + bar,
            child: PageScrollbar(controller: _controller, axis: Axis.vertical),
          ),
        Positioned(
          left: margin,
          right: minimap ? PageMinimap.width + 2 * margin : bar,
          bottom: obscured.bottom,
          child: PageScrollbar(controller: _controller, axis: Axis.horizontal),
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
        // Not from under what is open over the window — the picker, whose
        // search opens pages as it is typed — nor beside the one that has
        // the keys.
        autofocus:
            widget.active &&
            widget.aiScope == null &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        onKeyEvent: _onModeKey,
        child: MenuExtras(
          extras: _menuExtras,
          child: Listener(
            onPointerDown: _pressedWithKeys,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: InfiniteCanvas(
                    controller: _controller,
                    claimsPointer: _claimsPointer,
                    overlay: ValueListenableBuilder<Widget?>(
                      valueListenable: _textController.formulaField,
                      builder: (context, field, _) =>
                          field ?? const SizedBox.shrink(),
                    ),
                    grips: _grips,
                    onEmptyTap: _onEmptyTap,
                    onCanvasPress: _onCanvasPress,
                    onContextMenu: _onContextMenu,
                    elementBuilder: (context, element) => _buildElement(
                      element,
                      highlight,
                      _firstMatchIn(highlight),
                    ),
                    header: CanvasHeader(
                      frame: PageTitle.frame,
                      child: Listener(
                        // Going to the title ends typing in a text box.
                        onPointerDown: (_) =>
                            _stopEditing(refocusCanvas: false),
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
                Positioned.fill(
                  child: FocusGlide(
                    target: _glide,
                    colour: _mode.colourOn(context.tones),
                  ),
                ),
                if (_jump case final jump?)
                  Positioned.fill(
                    child: JumpLabels(
                      jump: jump,
                      colour: _mode.colourOn(context.tones),
                    ),
                  ),
              ],
            ),
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
