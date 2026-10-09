/// The storage facade: one object that owns the connection and the
/// repositories built on it.
library;

import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'ai_repository.dart';
import 'archive_export.dart';
import 'asset_store.dart';
import 'bin_repository.dart';
import 'database.dart';
import 'draft_storing.dart';
import 'files/folder_mirror.dart';
import 'files/notes_folder.dart';
import 'library_repository.dart';
import 'page_repository.dart';
import 'rescue.dart';
import 'search_repository.dart';

/// The notes are open in another window of the app already.
final class NotesInUse implements Exception {
  const NotesInUse();

  @override
  String toString() =>
      'These notes are open in another aantekening window. Close this one '
      'and go on in that one, or close that one and start aantekening again.';
}

/// The notes, open: the notes folder that keeps them, and the database
/// that is its index — for finding, searching and working on them at once.
///
/// The folder is what the notes are: a file for each notebook, section and
/// page, and their pictures and files, where the person chose — a folder a
/// sync service keeps on all their computers, if they like. The database is
/// this computer's own, kept apart from the folder, never synced: a sync
/// service copying a database it is writing is how databases are damaged.
/// What is written to one is written to the other ([FolderMirror]); either
/// can be made again from the other.
class AantekeningStore {
  AantekeningStore._({
    required this.directory,
    required this.database,
    required this.library,
    required this.pages,
    required this.search,
    required this.assets,
    required this.ai,
    required this.bin,
    required this.drafts,
    required this.rescue,
    this.folder,
    this.mirror,
  });

  /// The database's name in a notes folder from before notes folders,
  /// which was the database's folder too.
  static const String legacyDatabaseName = 'aantekening.sqlite';

  /// Opens the notes in [notesFolder], keeping their index in
  /// [indexFolder]: making the folder if it is not there, and putting in it
  /// the notes a database from before notes folders held, if it holds one.
  ///
  /// With [automatic], changes are written to the folder as they are made,
  /// and changes to it read as they arrive; otherwise only when asked.
  static Future<AantekeningStore> open({
    required String notesFolder,
    required String indexFolder,
    bool automatic = true,
  }) async {
    final folder = NotesFolder(notesFolder);
    await folder.directory.create(recursive: true);
    await folder.assets.create(recursive: true);
    await Directory(indexFolder).create(recursive: true);

    var identity = folder.readIdentity();
    final firstTime = identity == null;
    identity ??= NotesFolder.newIdentity();
    final databasePath = p.join(indexFolder, '$identity.sqlite');
    // Only one window at a time works on the notes: two would each write
    // what the other just wrote, and read it back as another computer's.
    final lock = _lockIndex(p.join(indexFolder, '$identity.lock'));
    final AantekeningDatabase database;
    try {
      if (firstTime) _adoptLegacyDatabase(notesFolder, databasePath);
      database = _openIndex(databasePath);
    } on Object {
      lock.closeSync();
      rethrow;
    }
    final store = _assemble(
      database,
      notesFolder,
      AssetStore(database, folder.assets),
      Rescue(p.join(indexFolder, 'rescued', identity)),
      folder: folder,
    ).._lock = lock;
    final mirror = store.mirror!;
    // What was not written before the app last stopped is written first,
    // so that what arrived meanwhile does not seem to be the only version.
    await mirror.flush();
    await mirror.scan();
    if (firstTime) {
      mirror.enqueueAll();
      await mirror.flush();
      await folder.writeIdentity(identity);
    }
    // What could not be saved last time goes back into the notes; a page
    // that cannot be put back yet stays rescued, and must not keep the
    // notes from opening.
    try {
      store.rescued = await store.rescue.restore(store.pages, store.library);
    } on Object {
      store.rescued = const <PageRef>[];
    }
    if (automatic) mirror.startAutomatically();
    return store;
  }

  /// Opens a throwaway workspace in memory, with no notes folder, for tests
  /// and previews.
  ///
  /// Assets still need somewhere to live, so [assetDirectory] should point at a
  /// temporary directory the caller cleans up.
  static AantekeningStore inMemory({Directory? assetDirectory}) {
    final database = AantekeningDatabase.inMemory();
    final assets =
        assetDirectory ??
        Directory.systemTemp.createTempSync('aantekening_assets_');
    return _assemble(
      database,
      ':memory:',
      AssetStore(database, assets),
      Rescue(p.join(assets.path, 'rescued')),
    );
  }

  static AantekeningStore _assemble(
    AantekeningDatabase database,
    String directory,
    AssetStore assets,
    Rescue rescue, {
    NotesFolder? folder,
  }) {
    final pages = PageRepository(database);
    final library = LibraryRepository(database, pages);
    final bin = BinRepository(database, library, pages);
    return AantekeningStore._(
      directory: directory,
      database: database,
      library: library,
      pages: pages,
      search: SearchRepository(database),
      assets: assets,
      ai: AiRepository(database),
      bin: bin,
      drafts: DraftStoring(database, library, pages, assets),
      rescue: rescue,
      folder: folder,
      mirror: folder == null
          ? null
          : FolderMirror(database, folder, library, pages, bin),
    );
  }

  /// Holds the file at [path] for as long as the notes are open here,
  /// throwing [NotesInUse] if another window holds it. The system lets go
  /// of it however the app stops, a crash too.
  static RandomAccessFile _lockIndex(String path) {
    final file = File(path).openSync(mode: FileMode.append);
    try {
      file.lockSync();
    } on FileSystemException {
      file.closeSync();
      throw const NotesInUse();
    }
    return file;
  }

  /// Opens the index at [path]. An index a crash left damaged is set aside,
  /// not used: a new one is made, and filled again from the notes folder.
  static AantekeningDatabase _openIndex(String path) {
    AantekeningDatabase? database;
    try {
      database = AantekeningDatabase.open(path);
      if (database.closedCleanly || database.isIntact) {
        database.markOpen();
        return database;
      }
    } on SqliteException {
      // Damaged past opening; set aside below.
    }
    database?.close();
    final damaged = '$path.damaged-${DateTime.now().millisecondsSinceEpoch}';
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (file.existsSync()) file.renameSync('$damaged$suffix');
    }
    return AantekeningDatabase.open(path)..markOpen();
  }

  /// Moves a database from before notes folders, kept in [notesFolder]
  /// itself, to be the index at [target]; what it holds is then written to
  /// the folder as files. The old file stays, renamed, as a safeguard.
  static void _adoptLegacyDatabase(String notesFolder, String target) {
    final legacy = File(p.join(notesFolder, legacyDatabaseName));
    if (!legacy.existsSync() || File(target).existsSync()) return;
    final old = sqlite3.open(legacy.path);
    try {
      // A copy consistent with the database's journal, in one file.
      old.execute('VACUUM INTO ?', <Object?>[target]);
    } finally {
      old.close();
    }
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final file = File('${legacy.path}$suffix');
      if (file.existsSync()) {
        file.renameSync('${legacy.path}.before-notes-folder$suffix');
      }
    }
  }

  /// The notes folder's path, or `:memory:` for an in-memory store.
  final String directory;

  final AantekeningDatabase database;

  /// Notebooks and sections.
  final LibraryRepository library;

  /// Pages, their bodies and the search index.
  final PageRepository pages;

  /// Full-text search.
  final SearchRepository search;

  /// Imported images and PDFs.
  final AssetStore assets;

  /// Conversations with the AI and what was kept of them, apart from the
  /// notes.
  final AiRepository ai;

  /// What was deleted, until it is restored or deleted for good.
  final BinRepository bin;

  /// Storing notes read from elsewhere.
  final DraftStoring drafts;

  /// Where a page that could not be saved is kept until it can be.
  final Rescue rescue;

  /// The pages put back from [rescue] as the notes were opened: what could
  /// not be saved the last time.
  List<PageRef> rescued = const <PageRef>[];

  /// Keeps [document], the contents of the page it belongs to, where
  /// nothing can lose them, when they could not be saved: to be put back
  /// into the notes the next time they are opened.
  Future<File> rescuePage(PageDocument document) async {
    PageRef? page;
    try {
      page = await pages.findPage(document.id);
    } on Object {
      // The index itself may be what failed; the contents are what matter.
    }
    return rescue.keep(document, page: page);
  }

  /// Writing notebooks, sections and pages out in this app's own form.
  ArchiveExport get exports => ArchiveExport(database, pages, assets);

  /// The notes folder, or null for a store in memory.
  final NotesFolder? folder;

  /// What keeps the folder and the database in step, or null for a store
  /// in memory.
  final FolderMirror? mirror;

  /// Writes what is waiting to the notes folder, and closes the connection.
  /// The store is unusable afterwards; closing it again does nothing.
  Future<void> close() => _closing ??= () async {
    try {
      await mirror?.close();
      database
        ..markClosed()
        ..close();
    } finally {
      _unlock();
    }
  }();

  Future<void>? _closing;

  /// What keeps another window from opening these notes meanwhile.
  RandomAccessFile? _lock;

  void _unlock() {
    final lock = _lock;
    _lock = null;
    if (lock == null) return;
    try {
      lock
        ..unlockSync()
        ..closeSync();
    } on FileSystemException {
      // Let go of by the system as the app stops.
    }
  }

  /// Stops as the app does when it is killed: nothing written, nothing
  /// closed but what the system closes — the index, and what keeps the
  /// notes this window's.
  @visibleForTesting
  void abandon() {
    _closing = Future<void>.value();
    database.close();
    _unlock();
  }
}
