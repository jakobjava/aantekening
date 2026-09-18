/// The application window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_editor.dart';
import '../providers.dart';
import 'sidebar.dart';

/// The ribbon across the top, and beneath it the sidebar and the open page.
///
/// The ribbon belongs to the page editor, which spans the window so the
/// ribbon can; the sidebar is laid out beside the page, beneath it.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);

    return Scaffold(
      body: store.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _WorkspaceError(error: error),
        data: (_) => PageEditor(
          pageId: ref.watch(selectedPageProvider),
          around: (context, page) => Sidebar(page: page),
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
