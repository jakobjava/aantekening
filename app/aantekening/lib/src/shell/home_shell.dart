/// The application window.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../commands/command_keys.dart';
import '../commands/editor_keys.dart';
import '../commands/key_chord.dart';
import '../commands/shortcuts.dart';
import '../editor/page_editor.dart';
import '../look/controls.dart';
import '../preferences.dart';
import '../providers.dart';
import 'recent_pages.dart';
import 'sidebar.dart';
import 'tab_strip.dart';
import 'tabs.dart';
import 'window_commands.dart';

/// The ribbon across the top, and beneath it the tabs, and beneath those
/// the sidebar and the page of the tab showing.
///
/// The ribbon belongs to the page editor, which spans the window so the
/// ribbon can; the tabs, the sidebar and the page are laid out beneath it.
/// There is one editor and one sidebar, which show whichever tab is showing:
/// what each tab has open is kept by [tabsProvider].
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

    return CommandKeys(
      onChord: _showTab,
      child: Scaffold(
        body: store.when(
          loading: () => const Loading(),
          error: (error, stack) => EmptyMessage(
            'The workspace could not be opened.',
            detail: '$error',
          ),
          data: (_) => PageEditor(
            pageId: ref.watch(selectedPageProvider),
            aiScope: _aiScope(ref.watch(tabsProvider.select((t) => t.current))),
            around: (context, page) => Column(
              children: <Widget>[
                const TabStrip(),
                Expanded(child: Sidebar(page: page)),
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
