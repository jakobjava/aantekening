/// Backups: every file of the notes folder, in one zip, somewhere else.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'files/entity_files.dart';
import 'files/notes_folder.dart';

/// Making, listing, pruning and restoring backups of a notes folder.
///
/// A backup is a zip of the folder as it is: its notes as their files,
/// their pictures and files, and the note of which notes they are. It is
/// written beside where it goes and checked before it is moved there, so
/// a backup in the list is a whole one. Everything here reads and writes
/// only files, so it can run away from the window, in an isolate.
abstract final class Backups {
  static const String _prefix = 'aantekening backup ';

  /// Backs up the notes folder at [notesFolder] into the folder [into],
  /// returning the backup's path.
  static String create(String notesFolder, String into, {DateTime? at}) {
    final folder = NotesFolder(notesFolder);
    final when = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        '$_prefix${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}.${two(when.minute)}.${two(when.second)}.zip';
    Directory(into).createSync(recursive: true);
    final target = p.join(into, name);
    final temporary = p.join(into, '.$name.tmp');

    final files = <(File, String)>[
      for (final entity in folder.directory.listSync(recursive: true))
        if (entity is File && _belongs(folder, entity))
          (entity, p.relative(entity.path, from: notesFolder)),
    ];
    final encoder = ZipFileEncoder()..create(temporary);
    try {
      for (final (file, relative) in files) {
        // Pages are gzipped already, and pictures compressed their own way.
        final stored =
            relative.endsWith('.gz') ||
            p.split(relative).first == NotesFolder.assetsName;
        encoder.addFileSync(
          file,
          relative.replaceAll(r'\', '/'),
          stored ? ZipFileEncoder.store : ZipFileEncoder.gzip,
        );
      }
    } finally {
      encoder.closeSync();
    }
    if (!_isWhole(temporary, files)) {
      File(temporary).deleteSync();
      throw FileSystemException('The backup could not be checked', target);
    }
    File(temporary).renameSync(target);
    return target;
  }

  /// Whether the zip at [path] holds each of [files] whole: every one read
  /// back, the same length as it was and with the checksum it was written
  /// with — a backup in the list must be one that restores.
  static bool _isWhole(String path, List<(File, String)> files) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final sizes = <String, int>{
        for (final (file, relative) in files)
          relative.replaceAll(r'\', '/'): file.lengthSync(),
      };
      var count = 0;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        count++;
        final bytes = entry.readBytes();
        final crc = entry.crc32;
        if (bytes == null ||
            bytes.length != sizes[entry.name] ||
            (crc != null && getCrc32(bytes) != crc)) {
          return false;
        }
        entry.clear();
      }
      return count == files.length;
    } on Object {
      return false;
    } finally {
      input.closeSync();
    }
  }

  /// Whether [file] is part of the notes: not a leftover of a write, nor
  /// something else kept in the folder.
  static bool _belongs(NotesFolder folder, File file) {
    final relative = p.relative(file.path, from: folder.path);
    final parts = p.split(relative);
    if (parts.any((part) => part.startsWith('.'))) return false;
    if (parts.length == 1) return parts.single == NotesFolder.markerName;
    return parts.first == NotesFolder.assetsName ||
        EntityKind.values.any((kind) => kind.folder == parts.first);
  }

  /// The backups in [folder], the newest first.
  static List<File> list(String folder) {
    final directory = Directory(folder);
    if (!directory.existsSync()) return const <File>[];
    return <File>[
      for (final entity in directory.listSync())
        if (entity is File &&
            p.basename(entity.path).startsWith(_prefix) &&
            entity.path.endsWith('.zip'))
          entity,
    ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
  }

  /// Deletes all but the newest [keep] backups in [folder].
  static void prune(String folder, {required int keep}) {
    for (final old in list(folder).skip(keep)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // Kept, for now.
      }
    }
  }

  /// Unpacks backup [backup] into the empty folder [into], as notes of
  /// their own: they are given an identity of their own, so that opening
  /// them does not mix them up with the notes they were a backup of.
  static Future<void> restore(String backup, String into) async {
    final target = NotesFolder(into);
    if (!target.isEmpty) {
      throw FileSystemException(
        'A backup is restored to an empty folder',
        into,
      );
    }
    await extractFileToDisk(backup, into);
    if (target.readIdentity() == null) {
      throw FileSystemException('This is not a backup of notes', backup);
    }
    await target.writeIdentity(NotesFolder.newIdentity());
  }
}
