/// The search panel: find pages across the workspace, and step through them
/// with what was found shown on the page itself.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../shell/library_actions.dart';
import '../shell/library_menu.dart';
import '../shell/library_pane.dart';
import '../shell/sidebar_state.dart';
import '../theme.dart';

/// What the search panel is looking for, to be shown wherever it occurs on
/// the page: the terms of its query while the panel is open, or null.
final searchHighlightProvider = Provider<SearchTerms?>((ref) {
  final open = ref.watch(
    sidebarProvider.select((state) => state.open == SidebarTab.search),
  );
  if (!open) return null;
  final terms = SearchTerms.parse(ref.watch(searchQueryProvider));
  return terms.isEmpty ? null : terms;
});

/// A search field over the pages that match it.
///
/// Typing opens the best match, with the words found highlighted on the page
/// and the view on the first of them; Enter and Shift+Enter, or the arrows
/// beside the count, step through the other pages that match.
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  /// How long typing pauses before the search runs.
  static const Duration typingPause = Duration(milliseconds: 250);

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  late final TextEditingController _query = TextEditingController(
    text: ref.read(searchQueryProvider),
  );
  Timer? _typing;

  /// The page showing, as an index into the results.
  int _current = 0;

  @override
  void dispose() {
    _typing?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    setState(() {});
    _typing?.cancel();
    _typing = Timer(SearchPanel.typingPause, () => unawaited(_search(text)));
  }

  /// Runs [text] and opens its best match.
  Future<void> _search(String text) async {
    ref.read(searchQueryProvider.notifier).set(text);
    final hits = await ref.read(searchResultsProvider.future);
    if (!mounted || _query.text != text) return;
    setState(() => _current = 0);
    if (hits.isNotEmpty) _open(hits.first);
  }

  void _clear() {
    _typing?.cancel();
    _query.clear();
    ref.read(searchQueryProvider.notifier).set('');
    setState(() => _current = 0);
  }

  /// Opens the page [by] results after the one showing, wrapping around.
  void _step(int by) {
    final hits = ref.read(searchResultsProvider).value;
    if (hits == null || hits.isEmpty) return;
    final index = (_current + by) % hits.length;
    setState(() => _current = index);
    _open(hits[index]);
  }

  void _open(SearchHit hit) {
    final notebookId = hit.notebookId;
    final sectionId = hit.sectionId;
    if (notebookId == null || sectionId == null) return;
    ref
        .read(libraryActionsProvider)
        .openPage(
          notebookId: notebookId,
          sectionId: sectionId,
          pageId: hit.pageId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = ref.watch(searchResultsProvider);
    final hits = results.value ?? const <SearchHit>[];
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;
    final current = hits.isEmpty ? 0 : _current.clamp(0, hits.length - 1);

    // ListTile paints its selection tint and ink onto the nearest Material.
    return Material(
      color: AppTheme.paneColor(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter): () => _step(1),
                const SingleActivator(
                  LogicalKeyboardKey.enter,
                  shift: true,
                ): () =>
                    _step(-1),
                const SingleActivator(LogicalKeyboardKey.escape): _clear,
              },
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search all notes',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: 'Clear  (Esc)',
                          onPressed: _clear,
                        ),
                ),
                onChanged: _changed,
              ),
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      results.isLoading && results.value == null
                          ? 'SEARCHING…'
                          : switch (hits.length) {
                              0 => 'NO MATCHES',
                              1 => '1 PAGE',
                              _ => '${current + 1} OF ${hits.length} PAGES',
                            },
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                    tooltip: 'Previous page  (Shift+Enter)',
                    onPressed: hits.length > 1 ? () => _step(-1) : null,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    tooltip: 'Next page  (Enter)',
                    onPressed: hits.length > 1 ? () => _step(1) : null,
                  ),
                ],
              ),
            ),
          Expanded(
            child: results.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => PaneMessage('$error', error: true),
              data: (hits) => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: hits.length,
                itemBuilder: (context, index) => _HitTile(
                  hit: hits[index],
                  selected: index == current,
                  onTap: () {
                    setState(() => _current = index);
                    _open(hits[index]);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.selected,
    required this.onTap,
  });

  final SearchHit hit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      title: Text(
        pageTitleOrPlaceholder(hit.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text.rich(
        highlightedSnippet(hit.snippet, scheme),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

/// Converts a snippet's marker characters into styled spans.
///
/// SQLite marks the matched terms with two control characters chosen because
/// they cannot occur in a note, so a page containing markup cannot fake a
/// highlight.
TextSpan highlightedSnippet(String snippet, ColorScheme scheme) {
  final children = <InlineSpan>[];
  var index = 0;

  while (index < snippet.length) {
    final start = snippet.indexOf(SnippetMarkers.start, index);
    if (start < 0) {
      children.add(TextSpan(text: snippet.substring(index)));
      break;
    }
    if (start > index) {
      children.add(TextSpan(text: snippet.substring(index, start)));
    }

    final end = snippet.indexOf(SnippetMarkers.end, start + 1);
    if (end < 0) {
      children.add(TextSpan(text: snippet.substring(start + 1)));
      break;
    }
    children.add(
      TextSpan(
        text: snippet.substring(start + 1, end),
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
    );
    index = end + 1;
  }

  return TextSpan(
    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
    children: children,
  );
}
