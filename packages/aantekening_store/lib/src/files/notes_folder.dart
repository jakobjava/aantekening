/// The notes folder: where the notes are kept as files, one for each thing,
/// in a folder the person chooses — one a service such as OneDrive keeps
/// in step across their computers, if they like.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;

import 'entity_files.dart';

/// A file in the notes folder: what it keeps, and whether it is the file
/// for that thing or a copy a sync service made of it.
final class FolderEntry {
  const FolderEntry(this.kind, this.file, {required this.id});

  final EntityKind kind;
  final File file;

  /// The thing its name says it keeps, or null for a file named otherwise,
  /// such as a conflicting copy — "01J…-LAPTOP.json.gz".
  final String? id;

  bool get isCopy => id == null;
}

/// The notes folder's layout, and writing to it safely.
///
/// ```text
/// Notes/
///   aantekening.json          what this folder is, and which notes
///   notebooks/<id>.json
///   sections/<id>.json
///   pages/<id>.json.gz        a page, its contents and what it shows
///   conversations/<id>.json   a conversation with the AI
///   kept/<id>.json            summaries, flashcards and answers kept
///   assets/<ab>/<sha-256>     pictures, PDFs and files, by their contents
/// ```
///
/// Every file is written whole beside where it goes and moved there, so a
/// crash, a full disk or a sync service reading it mid-write never finds
/// half of one; and nothing is ever deleted from it but what is written
/// anew: a thing deleted for good leaves a [Tombstone] where it was.
final class NotesFolder {
  NotesFolder(this.path);

  final String path;

  static const String markerName = 'aantekening.json';
  static const String assetsName = 'assets';

  Directory get directory => Directory(path);
  Directory get assets => Directory(p.join(path, assetsName));
  File get _marker => File(p.join(path, markerName));

  /// Whether the folder is there, and can be read.
  bool get isAvailable => directory.existsSync();

  /// The identity of the notes the folder holds, or null for a folder that
  /// holds none.
  String? readIdentity() {
    try {
      final json = jsonDecode(_marker.readAsStringSync());
      if (json is Map<String, Object?> && json['workspace'] is String) {
        return json['workspace']! as String;
      }
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Marks the folder as holding the notes [identity] names.
  Future<void> writeIdentity(String identity) => writeAtomically(
    _marker.path,
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'kind': 'aantekening notes',
        'format': EntityFile.format,
        'workspace': identity,
        'about':
            'The notes of aantekening. Each notebook, section and page is '
            'a file of its own; pictures and files are in assets.',
      }),
    ),
  );

  /// Whether the folder has nothing in it but, perhaps, files this app
  /// ignores: a folder notes can be put in as they are.
  bool get isEmpty {
    if (!directory.existsSync()) return true;
    return directory.listSync().every(
      (entity) => p.basename(entity.path).startsWith('.'),
    );
  }

  String pathFor(EntityKind kind, String id) =>
      p.join(path, kind.folder, kind.fileName(id));

  /// Every file of [kinds] in the folder, copies among them.
  List<FolderEntry> entries([List<EntityKind> kinds = EntityKind.values]) {
    final found = <FolderEntry>[];
    for (final kind in kinds) {
      final folder = Directory(p.join(path, kind.folder));
      if (!folder.existsSync()) continue;
      for (final entity in folder.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final id = _idOf(kind, name);
        found.add(FolderEntry(kind, entity, id: id));
      }
    }
    return found;
  }

  static final RegExp _ulid = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

  /// The id a file named [name] is the file of, or null if it is named as
  /// no thing's file is.
  static String? _idOf(EntityKind kind, String name) {
    final suffix = kind.fileName('');
    if (!name.endsWith(suffix)) return null;
    final id = name.substring(0, name.length - suffix.length);
    return _ulid.hasMatch(id) ? id : null;
  }

  /// Whether [name] is a file this folder's kinds could hold at all.
  static bool looksLikeEntity(String name) =>
      name.endsWith('.json') || name.endsWith('.json.gz');

  /// Writes [bytes] to [target] so that it holds either what it held or all
  /// of [bytes], never part: into a file beside it, flushed to the disk,
  /// then moved over it.
  static Future<void> writeAtomically(String target, List<int> bytes) async {
    final file = File(target);
    await file.parent.create(recursive: true);
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(target)}.${_random.nextInt(1 << 32)}.tmp',
      ),
    );
    try {
      final sink = await temporary.open(mode: FileMode.writeOnly);
      try {
        await sink.writeFrom(bytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temporary.rename(target);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static final math.Random _random = math.Random.secure();

  /// Removes files left from writes a crash interrupted, older than
  /// [age]: the file they were for still holds what it held before.
  void removeLeftovers({Duration age = const Duration(hours: 1)}) {
    final before = DateTime.now().subtract(age);
    for (final kind in EntityKind.values) {
      final folder = Directory(p.join(path, kind.folder));
      if (!folder.existsSync()) continue;
      for (final entity in folder.listSync()) {
        final name = p.basename(entity.path);
        if (entity is File &&
            name.startsWith('.') &&
            name.endsWith('.tmp') &&
            entity.statSync().modified.isBefore(before)) {
          try {
            entity.deleteSync();
          } on FileSystemException {
            // In use, perhaps; it goes another time.
          }
        }
      }
    }
  }

  /// Reads [file] whole, or null if it cannot be read now.
  static Uint8List? read(File file) {
    try {
      return file.readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }

  /// A new identity for notes put in a folder for the first time.
  static String newIdentity() => Ulid.generate();
}
