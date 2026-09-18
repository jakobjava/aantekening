/// The application window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_editor.dart';
import '../providers.dart';
import '../search/search_results_pane.dart';
import '../settings/ai_settings_sheet.dart';
import '../theme.dart';
import 'library_pane.dart';
import 'page_list_pane.dart';

/// Notebooks, pages and the open page.
///
/// On a wide window all three sit side by side: moving between notebook, page
/// and canvas is the most frequent thing anyone does here, and putting any of
/// them behind a click would be felt on every note. Below [compactBreakpoint] —
/// a phone, or a narrow window — the two navigation panes move into a drawer so
/// the canvas keeps the whole screen.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  /// Width below which the navigation panes move into a drawer.
  static const double compactBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBreakpoint;

        return Scaffold(
          drawer: compact ? const _NavigationDrawer() : null,
          body: store.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _WorkspaceError(error: error),
            data: (_) => Column(
              children: <Widget>[
                _TopBar(compact: compact),
                const Divider(height: 1),
                Expanded(
                  child: compact
                      ? const _EditorArea()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: const <Widget>[
                            LibraryPane(),
                            VerticalDivider(width: 1),
                            _NavigationList(),
                            VerticalDivider(width: 1),
                            Expanded(child: _EditorArea()),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The page list, or search results while a query is active.
class _NavigationList extends ConsumerWidget {
  const _NavigationList({this.width = AppTheme.pageListPaneWidth});

  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    return searching
        ? SearchResultsPane(width: width)
        : PageListPane(width: width);
  }
}

/// The navigation panes, stacked, for the compact layout.
class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer();

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: const <Widget>[
          Expanded(child: LibraryPane(width: null)),
          Divider(height: 1),
          Expanded(child: _NavigationList(width: null)),
        ],
      ),
    ),
  );
}

class _EditorArea extends ConsumerWidget {
  const _EditorArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageId = ref.watch(selectedPageProvider);
    return pageId == null
        ? const _NoPageSelected()
        : PageEditor(key: ValueKey<String>(pageId), pageId: pageId);
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.compact});

  final bool compact;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiAvailable = ref.watch(modelAvailabilityProvider);

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: EdgeInsets.only(left: widget.compact ? 4 : 14, right: 8),
          child: Row(
            children: <Widget>[
              if (widget.compact)
                IconButton(
                  icon: const Icon(Icons.menu_rounded, size: 20),
                  tooltip: 'Notebooks',
                  onPressed: Scaffold.of(context).openDrawer,
                )
              else
                Text(
                  'aantekening',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: scheme.onSurface,
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search all notes',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () {
                                _search.clear();
                                ref.read(searchQueryProvider.notifier).set('');
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (value) {
                      ref.read(searchQueryProvider.notifier).set(value);
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: aiAvailable.value == true ? scheme.primary : null,
                ),
                tooltip: aiAvailable.value == true
                    ? 'Local model connected'
                    : 'Local AI settings',
                onPressed: () => showAiSettingsSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
