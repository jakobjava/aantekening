/// Where the notes are kept on this computer — the notes folder chosen for
/// them, and the index beside the app — and moving them elsewhere.
library;

import 'dart:io';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../preferences.dart';
import '../providers.dart';
import '../shell/tabs.dart';

/// The preference naming the notes folder chosen, if one is.
const String notesFolderKey = 'notesFolder';

/// This computer's own folder for the app, which the notes are kept in
/// until another folder is chosen for them.
final supportFolderProvider = FutureProvider<String>(
  (ref) async => (await getApplicationSupportDirectory()).path,
);

/// The folder the notes are kept in.
///
/// `AANTEKENING_HOME` sets it for the session, as it did the workspace
/// before notes had folders of their own.
final notesFolderProvider = FutureProvider<String>((ref) async {
  final override = Platform.environment['AANTEKENING_HOME'];
  if (override != null && override.isNotEmpty) return override;
  final preferences = await ref.watch(preferencesProvider.future);
  final chosen = preferences[notesFolderKey];
  if (chosen is String && chosen.isNotEmpty) return chosen;
  return p.join(await ref.watch(supportFolderProvider.future), 'workspace');
});

/// Where this computer keeps the index of each notes folder: beside the
/// app, never in the notes folder, which a sync service may be copying.
final indexFolderProvider = FutureProvider<String>((ref) async {
  final override = Platform.environment['AANTEKENING_HOME'];
  if (override != null && override.isNotEmpty) return '$override.index';
  return p.join(await ref.watch(supportFolderProvider.future), 'index');
});

/// What a folder chosen for the notes holds.
enum FolderContents {
  /// Nothing: the notes can be moved into it.
  empty,

  /// Notes already: they can be opened.
  notes,

  /// Other things: the notes go into a folder of their own inside it.
  other,
}

FolderContents contentsOf(String folder) {
  final notes = NotesFolder(folder);
  if (notes.readIdentity() != null) return FolderContents.notes;
  return notes.isEmpty ? FolderContents.empty : FolderContents.other;
}

/// The folder notes put into [folder] go in: [folder] itself, unless it
/// holds other things, when a folder of their own inside it.
String notesFolderIn(String folder) =>
    contentsOf(folder) == FolderContents.other
    ? p.join(folder, 'aantekening notes')
    : folder;

/// Moving the notes to another folder, or opening the notes in one.
class NotesLocation {
  const NotesLocation(this._ref);

  final Ref _ref;

  /// Copies every note file from the notes folder to [target], which must
  /// be empty, checking each arrived whole; then keeps the notes there.
  ///
  /// The folder they were in is left as it was, to be deleted once the
  /// person is sure: moving notes never deletes any.
  Future<void> moveTo(String target) async {
    final store = await _ref.read(storeProvider.future);
    await store.mirror?.flush();
    final source = store.directory;
    final destination = NotesFolder(target);
    if (!destination.isEmpty) {
      throw FileSystemException('The folder is not empty', target);
    }
    for (final entity in Directory(source).listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source);
      final parts = p.split(relative);
      // Only the notes: not leftovers of writes, nor a database from
      // before notes folders.
      if (parts.any((part) => part.startsWith('.')) ||
          relative.startsWith(AantekeningStore.legacyDatabaseName)) {
        continue;
      }
      final copy = File(p.join(target, relative));
      await copy.parent.create(recursive: true);
      await entity.copy(copy.path);
      if (await copy.length() != await entity.length()) {
        throw FileSystemException('A file did not copy whole', copy.path);
      }
    }
    await _keepAt(target);
  }

  /// Keeps the notes in [folder] from now on — the notes already there, or
  /// new ones if there are none.
  Future<void> openAt(String folder) => _keepAt(folder);

  Future<void> _keepAt(String? folder) async {
    await _flush();
    final preferences = await _ref.read(preferencesProvider.future);
    await preferences.set(notesFolderKey, folder);
    _ref.invalidate(notesFolderProvider);
    // No tab goes on showing a page these notes do not have.
    final store = await _ref.read(storeProvider.future);
    await _ref.read(tabsProvider.notifier).forgetMissing(store);
    _ref.read(libraryRevisionProvider.notifier).bump();
  }

  Future<void> _flush() async {
    final store = await _ref.read(storeProvider.future);
    await store.mirror?.flush();
  }
}

final notesLocationProvider = Provider<NotesLocation>(NotesLocation.new);

/// How the notes folder is doing — what is waiting to be written, and any
/// problem writing it — as it changes.
final folderStatusProvider = StreamProvider<MirrorStatus>((ref) async* {
  final store = await ref.watch(storeProvider.future);
  final mirror = store.mirror;
  if (mirror == null) return;
  yield mirror.status;
  yield* mirror.statuses;
});

/// Changes other copies of the notes made to the folder, as they are read.
final folderChangesProvider = StreamProvider<FolderChanges>((ref) async* {
  final store = await ref.watch(storeProvider.future);
  final mirror = store.mirror;
  if (mirror != null) yield* mirror.changes;
});
