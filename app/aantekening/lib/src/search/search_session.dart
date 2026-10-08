/// A search under way: what it is looking for, which of the pages it found
/// is showing, and stepping from one to the next.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../shell/library_actions.dart';

/// What is being searched for, to be shown wherever it occurs on the page:
/// the terms of the query, or null while there is none.
final searchHighlightProvider = Provider<SearchTerms?>((ref) {
  final terms = SearchTerms.parse(ref.watch(searchQueryProvider));
  return terms.isEmpty ? null : terms;
});

/// Which of the pages found is showing, as an index into the results; it
/// starts again from the first with each new query.
class SearchSession extends Notifier<int> {
  @override
  int build() {
    ref.watch(searchQueryProvider);
    return 0;
  }

  /// Searches for [text] and opens its best match.
  Future<void> search(String text) async {
    ref.read(searchQueryProvider.notifier).set(text);
    final hits = await ref.read(searchResultsProvider.future);
    if (ref.read(searchQueryProvider) != text) return;
    state = 0;
    if (hits.isNotEmpty) _open(hits.first);
  }

  /// Opens the page [by] results after the one showing, going round from
  /// either end.
  void step(int by) {
    final hits = ref.read(searchResultsProvider).value;
    if (hits == null || hits.isEmpty) return;
    show((state + by) % hits.length);
  }

  /// Opens the result at [index].
  void show(int index) {
    final hits = ref.read(searchResultsProvider).value;
    if (hits == null || index >= hits.length) return;
    state = index;
    _open(hits[index]);
  }

  /// Searches for nothing: nothing is marked on the page any longer.
  void clear() => ref.read(searchQueryProvider.notifier).set('');

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
}

final searchSessionProvider = NotifierProvider<SearchSession, int>(
  SearchSession.new,
);
