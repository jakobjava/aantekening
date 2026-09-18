/// Application-wide providers.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the workspace lives on disk.
///
/// A single directory holds the database and the attachment store, so the whole
/// workspace can be copied, synced or backed up as one folder.
final workspaceDirectoryProvider = FutureProvider<String>((ref) async {
  final override = Platform.environment['AANTEKENING_HOME'];
  if (override != null && override.isNotEmpty) return override;

  final base = await getApplicationSupportDirectory();
  return p.join(base.path, 'workspace');
});

/// The open workspace.
final storeProvider = FutureProvider<AantekeningStore>((ref) async {
  final directory = await ref.watch(workspaceDirectoryProvider.future);
  final store = await AantekeningStore.open(directory);
  ref.onDispose(store.close);
  return store;
});

/// Bumped after any change to the notebook tree, to refresh the lists that
/// depend on it.
///
/// Cheaper and more predictable than having every mutation know which queries
/// to invalidate, and it keeps the panes consistent with one another.
class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final libraryRevisionProvider = NotifierProvider<LibraryRevision, int>(
  LibraryRevision.new,
);

/// A nullable selection held in the navigation panes.
class SelectionId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedNotebookProvider = NotifierProvider<SelectionId, String?>(
  SelectionId.new,
);
final selectedSectionProvider = NotifierProvider<SelectionId, String?>(
  SelectionId.new,
);
final selectedPageProvider = NotifierProvider<SelectionId, String?>(
  SelectionId.new,
);

/// Every notebook, in display order.
final notebooksProvider = FutureProvider<List<Notebook>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.library.listNotebooks();
});

/// Every section of a notebook, at any depth.
final sectionsProvider = FutureProvider.family<List<Section>, String>((
  ref,
  notebookId,
) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.library.listAllSections(notebookId);
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

/// The pages of a section.
final pagesProvider = FutureProvider.family<List<PageRef>, String>((
  ref,
  sectionId,
) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.pages.listPages(sectionId);
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

/// The current search text.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Results for the current search text.
final searchResultsProvider = FutureProvider<List<SearchHit>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return const <SearchHit>[];

  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  return store.search.search(query);
});

/// The bytes of an imported image or PDF.
///
/// Keyed by asset id and cached by Riverpod, so the same picture placed on
/// several pages is read from disk once per session.
final assetBytesProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  assetId,
) async {
  final store = await ref.watch(storeProvider.future);
  return store.assets.readBytes(assetId);
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

/// Settings for the local AI features.
class AiSettingsController extends Notifier<AiSettings> {
  @override
  AiSettings build() => const AiSettings();

  void update(AiSettings settings) => state = settings;
}

final aiSettingsProvider = NotifierProvider<AiSettingsController, AiSettings>(
  AiSettingsController.new,
);

/// A client for the configured local model runtime.
final modelClientProvider = Provider<LocalModelClient>((ref) {
  final settings = ref.watch(aiSettingsProvider);
  final client = OllamaClient(settings: settings);
  ref.onDispose(client.close);
  return client;
});

/// Whether a local runtime is reachable, so the UI can offer or hide the AI
/// features without the user having to find out by trying them.
final modelAvailabilityProvider = FutureProvider<bool>((ref) async {
  final settings = ref.watch(aiSettingsProvider);
  if (!settings.enabled) return false;
  return ref.watch(modelClientProvider).isAvailable();
});

/// The models the runtime has installed.
final availableModelsProvider = FutureProvider<List<ModelInfo>>((ref) async {
  final available = await ref.watch(modelAvailabilityProvider.future);
  if (!available) return const <ModelInfo>[];
  return ref.watch(modelClientProvider).listModels();
});
