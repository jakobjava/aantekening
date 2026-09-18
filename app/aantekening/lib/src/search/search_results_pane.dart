/// Search results, shown in place of the page list while a query is active.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Lists full-text matches for the current query.
class SearchResultsPane extends ConsumerWidget {
  const SearchResultsPane({super.key, this.width = AppTheme.pageListPaneWidth});

  /// Fixed pane width, or null to fill the available space — which is what the
  /// compact layout needs when the panes move into a drawer.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final results = ref.watch(searchResultsProvider);

    // ListTile paints its selection tint and ink onto the nearest Material.
    return Material(
      color: AppTheme.paneColor(scheme).withValues(alpha: 0.6),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Text(
                results.maybeWhen(
                  data: (hits) => hits.isEmpty
                      ? 'NO MATCHES'
                      : '${hits.length} MATCH${hits.length == 1 ? '' : 'ES'}',
                  orElse: () => 'SEARCHING…',
                ),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: results.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$error', style: TextStyle(color: scheme.error)),
                ),
                data: (hits) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: hits.length,
                  itemBuilder: (context, index) => _HitTile(hit: hits[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HitTile extends ConsumerWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(
        hit.title.trim().isEmpty ? 'Untitled page' : hit.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text.rich(
        highlightedSnippet(hit.snippet, scheme),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // Opening a result also reveals where it lives, so the surrounding
        // notebook and section stay in step with what is on screen.
        if (hit.notebookId != null) {
          ref.read(selectedNotebookProvider.notifier).select(hit.notebookId);
        }
        if (hit.sectionId != null) {
          ref.read(selectedSectionProvider.notifier).select(hit.sectionId);
        }
        ref.read(selectedPageProvider.notifier).select(hit.pageId);
      },
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
