/// The application window.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../commands/command_keys.dart';
import '../commands/editor_keys.dart';
import '../commands/key_chord.dart';
import '../commands/shortcuts.dart';
import '../editor/page_editor.dart';
import '../files/notes_keeper.dart';
import '../look/controls.dart';
import '../look/floating_pane.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../preferences.dart';
import '../providers.dart';
import '../search/search_line.dart';
import 'recent_pages.dart';
import 'status_line.dart';
import 'tabs.dart';
import 'window_commands.dart';

/// The page of the tab showing, filling the window, with the status line
/// floating over its top or its foot — and nothing else, until it is
/// summoned: the menu, the picker, the search line.
///
/// There is one editor, which shows whichever tab is showing: what each tab
/// has open is kept by [tabsProvider].
///
/// Every shortcut with Ctrl, Alt or Meta is caught here, wherever the
/// keyboard is, and run as the command it is bound to; Alt and a digit
/// shows that tab.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final VoidCallback _unregister;

  @override
  void initState() {
    super.initState();
    unawaited(_forgetMissing());
    _unregister = ref
        .read(commandHandlersProvider)
        .register(windowCommands(context, ref));
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  /// Shows the tab Alt and a digit number.
  bool _showTab(KeyChord chord) {
    final tab = EditorKey.showTab.chords.indexOf(chord);
    if (tab < 0) return false;
    ref.read(tabsProvider.notifier).showNumber(tab + 1);
    return true;
  }

  /// Once the workspace and the tabs kept from the last session have been
  /// read, lets no tab show what is no longer there.
  Future<void> _forgetMissing() async {
    final AantekeningStore store;
    try {
      store = await ref.read(storeProvider.future);
    } on Object {
      // The window says why the notes could not be opened.
      return;
    }
    await ref.read(preferencesProvider.future);
    if (!mounted) return;
    await ref.read(tabsProvider.notifier).forgetMissing(store);
  }

  @override
  Widget build(BuildContext context) {
    // Go to offers the pages opened lately first.
    ref.listen<String?>(selectedPageProvider, (_, pageId) {
      if (pageId != null) ref.read(recentPagesProvider.notifier).visit(pageId);
    });
    final store = ref.watch(storeProvider);
    final top = ref.watch(statusLinePlaceProvider) == StatusLinePlace.top;

    return NotesKeeper(
      child: CommandKeys(
        onChord: _showTab,
        child: Scaffold(
          body: store.when(
            loading: () => const Loading(),
            error: (error, stack) => EmptyMessage(
              switch (error) {
                NotesInUse() => 'aantekening is open already.',
                NotesFolderMissing() => 'The notes cannot be found.',
                _ => 'The workspace could not be opened.',
              },
              detail: '$error',
              actions: <Widget>[
                PillButton(
                  'Try again',
                  lit: true,
                  onPressed: () => ref.invalidate(storeProvider),
                ),
                if (error is NotesFolderMissing)
                  PillButton(
                    'Start new notes there',
                    onPressed: () => unawaited(startNewNotes(ref)),
                  ),
              ],
            ),
            data: (_) => Stack(
              children: <Widget>[
                Positioned.fill(child: _Panes(top: top)),
                // Floating clear of the window's edges.
                Positioned(
                  left: StatusLine.margin,
                  right: StatusLine.margin,
                  top: top ? StatusLine.margin : null,
                  bottom: top ? null : StatusLine.margin,
                  child: const StatusLine(),
                ),
                if (ref.watch(searchLineProvider))
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(StatusLine.margin),
                      child: FloatingPane(
                        pane: Pane.search,
                        natural: SearchLine.natural,
                        // On the page's side of the status line.
                        position: (area, size) => Offset(
                          (area.width - size.width) / 2,
                          top
                              ? StatusLine.height + _searchGap
                              : area.height -
                                    StatusLine.height -
                                    _searchGap -
                                    size.height,
                        ),
                        minSize: const Size(280, SearchLine.height),
                        child: const SearchLine(),
                      ),
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

/// What [tab] asks the AI about, while it shows the AI.
NoteLink? _aiScope(NoteTab tab) => tab.ai
    ? aiScopeOf(
        notebookId: tab.notebookId,
        sectionId: tab.sectionId,
        pageId: tab.pageId,
      )
    : null;

/// How far the search line opens from the status line.
const double _searchGap = 8;

/// The page of the tab showing — or, the window split, it and the page of
/// the tab beside it, side by side or one above the other, in the order of
/// their tabs. A click in the one without the keys gives it them, and the
/// line between them is dragged to share the window out otherwise.
class _Panes extends ConsumerStatefulWidget {
  const _Panes({required this.top});

  /// Whether the status line lies along the top, rather than the foot.
  final bool top;

  @override
  ConsumerState<_Panes> createState() => _PanesState();
}

class _PanesState extends ConsumerState<_Panes> {
  /// The first pane's share while the line between them is dragged, saved
  /// once it is let go; and the share, and how far the pointer has moved,
  /// since it was taken hold of.
  double? _dragged;
  double _from = SplitShare.even;
  double _moved = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(tabsProvider);
    final under = widget.top
        ? const EdgeInsets.only(top: StatusLine.reach)
        : const EdgeInsets.only(bottom: StatusLine.reach);
    final beside = tabs.beside;
    if (beside == null) {
      return _Pane(slot: _Slot.first, index: tabs.active, obscured: under);
    }
    final first = math.min(tabs.active, beside);
    final second = math.max(tabs.active, beside);
    // Side by side, both lie under the status line; one above the other,
    // only the one at its edge does.
    final stacked = tabs.stacked;
    EdgeInsets obscured(_Slot slot) => !stacked
        ? under
        : (slot == _Slot.first) == widget.top
        ? under
        : EdgeInsets.zero;
    final saved = ref.watch(splitShareProvider);
    final share = _dragged ?? saved;
    final axis = stacked ? Axis.vertical : Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final whole = stacked ? constraints.maxHeight : constraints.maxWidth;
        final room = math.max(whole - _SplitLine.thickness, 0.0);
        final firstExtent = (room * share).roundToDouble();
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Flex(
              direction: axis,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: stacked ? null : firstExtent,
                  height: stacked ? firstExtent : null,
                  child: _Pane(
                    slot: _Slot.first,
                    index: first,
                    obscured: obscured(_Slot.first),
                  ),
                ),
                if (stacked)
                  const Divider(height: _SplitLine.thickness)
                else
                  const VerticalDivider(width: _SplitLine.thickness),
                Expanded(
                  child: _Pane(
                    slot: _Slot.second,
                    index: second,
                    obscured: obscured(_Slot.second),
                  ),
                ),
              ],
            ),
            _SplitLine(
              axis: axis,
              at: firstExtent,
              onDragStart: () {
                _from = share;
                _moved = 0;
              },
              onDrag: (moved) => setState(() {
                _moved += moved;
                _dragged = room == 0
                    ? share
                    : SplitShare.clamp(_from + _moved / room);
              }),
              onDragEnd: () {
                final dragged = _dragged;
                if (dragged == null) return;
                ref.read(splitShareProvider.notifier).set(dragged);
                setState(() => _dragged = null);
              },
              onReset: () =>
                  ref.read(splitShareProvider.notifier).set(SplitShare.even),
            ),
          ],
        );
      },
    );
  }
}

/// Where the line between two panes is taken hold of: a strip wider than
/// it is, over its middle, which shows it is taken in the accent.
class _SplitLine extends StatefulWidget {
  const _SplitLine({
    required this.axis,
    required this.at,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
  });

  /// How thick the line drawn between the panes is.
  static const double thickness = 1;

  /// How wide the strip it is taken hold of by is.
  static const double reach = 9;

  /// The way the panes lie along.
  final Axis axis;

  /// How far along the line lies.
  final double at;

  final VoidCallback onDragStart;

  /// Called with how far the pointer moved along [axis], as it drags the
  /// line.
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  /// Called on a double click: half each again.
  final VoidCallback onReset;

  @override
  State<_SplitLine> createState() => _SplitLineState();
}

class _SplitLineState extends State<_SplitLine> {
  bool _held = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final across = widget.axis == Axis.horizontal;
    final start = widget.at + _SplitLine.thickness / 2 - _SplitLine.reach / 2;
    void let() {
      setState(() => _held = false);
      widget.onDragEnd();
    }

    final strip = MouseRegion(
      cursor: across
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // From where it was pressed, so the line keeps under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: widget.onReset,
        onPanStart: (_) {
          setState(() => _held = true);
          widget.onDragStart();
        },
        onPanUpdate: (details) =>
            widget.onDrag(across ? details.delta.dx : details.delta.dy),
        onPanEnd: (_) => let(),
        onPanCancel: let,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.quick,
            width: across ? 3 : double.infinity,
            height: across ? double.infinity : 3,
            color: _held || _hovered
                ? context.tones.emphasis
                : context.tones.emphasis.withValues(alpha: 0),
          ),
        ),
      ),
    );
    return across
        ? Positioned(
            left: start,
            top: 0,
            bottom: 0,
            width: _SplitLine.reach,
            child: strip,
          )
        : Positioned(
            top: start,
            left: 0,
            right: 0,
            height: _SplitLine.reach,
            child: strip,
          );
  }
}

/// Where a pane is: the first, or the only one, and the second. Its editor
/// stays with its place, so giving the keys to the other pane opens no
/// page again.
enum _Slot { first, second }

class _Pane extends ConsumerWidget {
  const _Pane({
    required this.slot,
    required this.index,
    required this.obscured,
  });

  final _Slot slot;

  /// The tab it shows.
  final int index;
  final EdgeInsets obscured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabsProvider);
    final tab = tabs.tabs[index];
    final active = index == tabs.active;
    // A page is edited in one place at a time: beside itself, it is not
    // opened a second time.
    final twice =
        !active && tab.pageId != null && tab.pageId == tabs.current.pageId;
    final editor = twice
        ? Padding(
            padding: obscured,
            child: const EmptyMessage(
              'The same page is open beside this one',
              detail: 'A page is written on in one place at a time.',
            ),
          )
        : PageEditor(
            key: ValueKey<_Slot>(slot),
            pageId: tab.pageId,
            aiScope: _aiScope(tab),
            active: active,
            obscured: obscured,
          );
    // Built the same whichever has the keys, so giving them to the other
    // pane keeps both editors as they are, and neither is drawn again.
    return Listener(
      // A click in it gives it the keys, and goes on to what was clicked.
      onPointerDown: active
          ? null
          : (_) => ref.read(tabsProvider.notifier).activate(index),
      child: editor,
    );
  }
}
