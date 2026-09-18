/// The storage facade: one object that owns the connection and the
/// repositories built on it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'asset_store.dart';
import 'database.dart';
import 'embedding_repository.dart';
import 'library_repository.dart';
import 'page_repository.dart';
import 'search_repository.dart';

/// Owns a workspace on disk: its database, its assets and the repositories that
/// read them.
///
/// A workspace is a directory, not a single file, so that the database stays
/// small and fast while attachments live beside it as ordinary files the user
/// can back up, sync or inspect.
class AantekeningStore {
  AantekeningStore._({
    required this.directory,
    required this.database,
    required this.library,
    required this.pages,
    required this.search,
    required this.embeddings,
    required this.assets,
  });

  /// File name of the database inside a workspace directory.
  static const String databaseFileName = 'aantekening.sqlite';

  /// Subdirectory holding content-addressed attachments.
  static const String assetsDirectoryName = 'assets';

  /// Opens, creating it if needed, the workspace rooted at [directory].
  static Future<AantekeningStore> open(String directory) async {
    final root = Directory(directory);
    await root.create(recursive: true);
    final assetsDirectory = Directory(p.join(directory, assetsDirectoryName));
    await assetsDirectory.create(recursive: true);

    final database = AantekeningDatabase.open(
      p.join(directory, databaseFileName),
    );
    return AantekeningStore._(
      directory: directory,
      database: database,
      library: LibraryRepository(database),
      pages: PageRepository(database),
      search: SearchRepository(database),
      embeddings: EmbeddingRepository(database),
      assets: AssetStore(database, assetsDirectory),
    );
  }

  /// Opens an in-memory workspace for tests and previews.
  ///
  /// Assets still need somewhere to live, so [assetDirectory] should point at a
  /// temporary directory the caller cleans up.
  static AantekeningStore inMemory({Directory? assetDirectory}) {
    final database = AantekeningDatabase.inMemory();
    final assets =
        assetDirectory ??
        Directory.systemTemp.createTempSync('aantekening_assets_');
    return AantekeningStore._(
      directory: ':memory:',
      database: database,
      library: LibraryRepository(database),
      pages: PageRepository(database),
      search: SearchRepository(database),
      embeddings: EmbeddingRepository(database),
      assets: AssetStore(database, assets),
    );
  }

  /// The workspace directory, or `:memory:` for an in-memory store.
  final String directory;

  final AantekeningDatabase database;

  /// Notebooks and sections.
  final LibraryRepository library;

  /// Pages, their bodies and the search index.
  final PageRepository pages;

  /// Full-text search.
  final SearchRepository search;

  /// Embeddings for semantic search.
  final EmbeddingRepository embeddings;

  /// Imported images and PDFs.
  final AssetStore assets;

  /// Closes the connection. The store is unusable afterwards.
  Future<void> close() async => database.close();
}
