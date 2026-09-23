/// The application window.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_editor.dart';
import '../preferences.dart';
import '../providers.dart';
import 'sidebar.dart';
import 'tab_strip.dart';
import 'tabs.dart';

/// The ribbon across the top, and beneath it the tabs, and beneath those
/// the sidebar and the page of the tab showing.
///
/// The ribbon belongs to the page editor, which spans the window so the
/// ribbon can; the tabs, the sidebar and the page are laid out beneath it.
/// There is one editor and one sidebar, which show whichever tab is showing:
/// what each tab has open is kept by [tabsProvider].
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    unawaited(_forgetMissing());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// The keys that open, close and step through tabs, taken from the
  /// keyboard itself rather than through the focus, since they work
  /// wherever the focus is — even nowhere, as it is once the panel that had
  /// it goes with the tab left. Not while a dialog is over the window.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    for (final MapEntry(key: activator, value: action) in TabStrip.shortcuts(
      ref.read(tabsProvider.notifier),
    ).entries) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        action();
        return true;
      }
    }
    return false;
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
    final store = ref.watch(storeProvider);

    return Scaffold(
      body: store.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _WorkspaceError(error: error),
        data: (_) => PageEditor(
          pageId: ref.watch(selectedPageProvider),
          around: (context, page) => Column(
            children: <Widget>[
              const TabStrip(),
              Expanded(child: Sidebar(page: page)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 36),
            const SizedBox(height: 12),
            const Text('The workspace could not be opened.'),
            const SizedBox(height: 8),
            SelectableText(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
