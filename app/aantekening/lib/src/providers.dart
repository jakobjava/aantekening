/// Application-wide providers.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'files/notes_location.dart';
import 'shell/list_order.dart';
import 'shell/tabs.dart';

/// The notes, open: their folder, and this computer's index of it.
final storeProvider = FutureProvider<AantekeningStore>((ref) async {
  final store = await AantekeningStore.open(
    notesFolder: await ref.watch(notesFolderProvider.future),
    indexFolder: await ref.watch(indexFolderProvider.future),
  );
  ref.onDispose(store.close);
  return store;
});

/// A count bumped after a kind of change, to refresh what depends on it.
///
/// Cheaper and more predictable than having every mutation know which queries
/// to invalidate, and it keeps the panes consistent with one another.
class Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// Bumped after any change to the notebook tree: a notebook, section or page
/// added, moved, renamed or deleted.
final libraryRevisionProvider = NotifierProvider<Revision, int>(Revision.new);

/// Bumped after what is written on a page is saved, to refresh only what
/// shows it — the page list's previews, and search results — not the
/// notebooks and sections, which are as they were, every few seconds of
/// typing.
final pageContentsRevisionProvider = NotifierProvider<Revision, int>(
  Revision.new,
);

/// The notebook, section or page the tab showing has chosen in its
/// sidebar, or null for none.
class TabSelection extends Notifier<String?> {
  TabSelection(this._choice);

  final TabChoice _choice;

  @override
  String? build() =>
      ref.watch(tabsProvider.select((tabs) => tabs.current.chosen(_choice)));

  void select(String? id) => ref
      .read(tabsProvider.notifier)
      .updateCurrent((tab) => tab.choosing(_choice, id));
}

final selectedNotebookProvider = NotifierProvider<TabSelection, String?>(
  () => TabSelection(TabChoice.notebook),
);
final selectedSectionProvider = NotifierProvider<TabSelection, String?>(
  () => TabSelection(TabChoice.section),
);
final selectedPageProvider = NotifierProvider<TabSelection, String?>(
  () => TabSelection(TabChoice.page),
);

/// Every notebook, in display order.
final notebooksProvider = FutureProvider<List<Notebook>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final order = ref.watch(listOrderProvider(OrderedList.notebooks));
  final store = await ref.watch(storeProvider.future);
  return _ordered(
    ref,
    order,
    await store.library.listNotebooks(),
    store.library.notebookChanges,
  );
});

/// [items] in [order]; ordered by when each last changed, that is when it
/// or any page in it did, as [changes] tells.
Future<List<T>> _ordered<T extends TreeNode>(
  Ref ref,
  ListOrder order,
  List<T> items,
  Future<Map<String, int>> Function() changes,
) async {
  if (!order.byChange) return order.sort(items);
  ref.watch(pageContentsRevisionProvider);
  final changed = await changes();
  return order.sort(
    items,
    changedAt: (item) => changed[item.id] ?? item.updatedAt,
  );
}

/// Every section of a notebook, at any depth, in their tree, each level in
/// the order the sections are listed in.
final sectionTreeProvider = FutureProvider.family<Hierarchy<Section>, String>((
  ref,
  notebookId,
) async {
  ref.watch(libraryRevisionProvider);
  final order = ref.watch(listOrderProvider(OrderedList.sections));
  final store = await ref.watch(storeProvider.future);
  return Section.hierarchy(
    await _ordered(
      ref,
      order,
      await store.library.listAllSections(notebookId),
      () => store.library.sectionChanges(notebookId),
    ),
  );
});

/// One section.
final sectionProvider = FutureProvider.family<Section?, String>((
  ref,
  sectionId,
) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.library.findSection(sectionId);
});

/// The pages of a section, in their tree, each level in the order the
/// pages are listed in.
final pageTreeProvider = FutureProvider.family<Hierarchy<PageRef>, String>((
  ref,
  sectionId,
) async {
  ref
    ..watch(libraryRevisionProvider)
    ..watch(pageContentsRevisionProvider);
  final order = ref.watch(listOrderProvider(OrderedList.pages));
  final store = await ref.watch(storeProvider.future);
  return PageRef.hierarchy(order.sort(await store.pages.listPages(sectionId)));
});

/// One page's metadata, its title and date among them.
final pageProvider = FutureProvider.family<PageRef?, String>((
  ref,
  pageId,
) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.pages.findPage(pageId);
});

/// What the tab showing is searching for.
class SearchQuery extends Notifier<String> {
  @override
  String build() =>
      ref.watch(tabsProvider.select((tabs) => tabs.current.search));

  void set(String value) => ref
      .read(tabsProvider.notifier)
      .updateCurrent((tab) => tab.search == value ? tab : tab.searching(value));
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Results for the current search text.
final searchResultsProvider = FutureProvider<List<SearchHit>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return const <SearchHit>[];

  ref
    ..watch(libraryRevisionProvider)
    ..watch(pageContentsRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.search.search(query);
});

/// The bytes of an imported image or PDF.
///
/// Kept a while after it stops showing ([KeepAWhile]), so the same picture
/// placed on several pages, or scrolled away from and back to, is read from
/// disk once; but not for the rest of the session, which a notebook of
/// photographs would fill memory with.
final assetBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, assetId) async {
      ref.keepAWhile();
      final store = await ref.watch(storeProvider.future);
      return store.assets.readBytes(assetId);
    });

/// What a provider made kept after nothing watches it any more, for a
/// while: in case it is wanted again soon, as a picture scrolled away from
/// and back to is.
extension KeepAWhile on Ref {
  void keepAWhile([Duration time = const Duration(minutes: 1)]) {
    final keep = keepAlive();
    Timer? letGo;
    onCancel(() => letGo = Timer(time, keep.close));
    onResume(() => letGo?.cancel());
    onDispose(() => letGo?.cancel());
  }
}

/// What is known of an imported asset: its name, kind and size.
final assetRefProvider = FutureProvider.family<AssetRef?, String>((
  ref,
  assetId,
) async {
  final store = await ref.watch(storeProvider.future);
  return store.assets.find(assetId);
});

/// The file holding an imported asset, for renderers that read from disk —
/// such as the PDF engine, which should not need a large document copied into
/// memory first.
final assetFileProvider = FutureProvider.family<File?, String>((
  ref,
  assetId,
) async {
  final store = await ref.watch(storeProvider.future);
  final asset = await store.assets.find(assetId);
  if (asset == null) return null;
  final file = store.assets.fileFor(asset);
  return file.existsSync() ? file : null;
});
