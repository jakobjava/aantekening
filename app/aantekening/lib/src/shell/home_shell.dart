/// The application window.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
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
    final store = await ref.read(storeProvider.future);
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
              'The workspace could not be opened.',
              detail: '$error',
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
                  child: _Chrome(top: top),
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

/// What floats over the page along its top or its foot: the status line,
/// with the search line beside it, on the page's side, while it is open.
class _Chrome extends ConsumerWidget {
  const _Chrome({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = ref.watch(searchLineProvider);
    const search = Padding(padding: EdgeInsets.all(10), child: SearchLine());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (searching && !top) search,
        const StatusLine(),
        if (searching && top) search,
      ],
    );
  }
}

/// The page of the tab showing — or, the window split, it and the page of
/// the tab beside it, side by side or one above the other, in the order of
/// their tabs. The one without the keys is dimmed, and a click in it gives
/// it them.
class _Panes extends ConsumerWidget {
  const _Panes({required this.top});

  /// Whether the status line lies along the top, rather than the foot.
  final bool top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabsProvider);
    final under = top
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
        : (slot == _Slot.first) == top
        ? under
        : EdgeInsets.zero;
    return Flex(
      direction: stacked ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _Pane(
            slot: _Slot.first,
            index: first,
            obscured: obscured(_Slot.first),
          ),
        ),
        if (stacked) const Divider() else const VerticalDivider(width: 1),
        Expanded(
          child: _Pane(
            slot: _Slot.second,
            index: second,
            obscured: obscured(_Slot.second),
          ),
        ),
      ],
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
    if (active) return editor;
    return Listener(
      // A click in it gives it the keys, and goes on to what was clicked.
      onPointerDown: (_) => ref.read(tabsProvider.notifier).activate(index),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          editor,
          Positioned.fill(
            child: IgnorePointer(
              // Faded towards the paper, which is white in either mode.
              child: ColoredBox(color: Tones.paper.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}
