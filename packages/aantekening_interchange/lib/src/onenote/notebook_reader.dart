/// Reading a OneNote notebook laid out in a folder, as a .onepkg unpacks:
/// its table of contents, its sections and its section groups.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../onestore/file_nodes.dart';
import '../onestore/revision_store.dart';
import 'model.dart';
import 'properties.dart';
import 'section_reader.dart';

/// The name of OneNote's own recycle bin, which a notebook carries with it.
const String _recycleBin = 'OneNote_RecycleBin';

/// Reads the notebook in [directory]: its sections and section groups in
/// the order its table of contents gives them, then any it leaves out.
///
/// A section that cannot be read is kept as an [OneUnreadableSection],
/// saying why, rather than stopping the rest.
List<OneEntry> readNotebookFolder(
  Directory directory, {
  void Function(String section)? onSection,
}) => foldNotebookFolder<OneEntry>(
  directory,
  section: (section) => section,
  group: OneSectionGroup.new,
  onSection: onSection,
);

/// Reads the notebook in [directory] as [readNotebookFolder] does, a
/// section at a time: each is made into what [section] makes of it as
/// soon as it is read, and let go, so that no more than one section's file
/// is held at once. A group is what [group] makes of its name and entries.
List<T> foldNotebookFolder<T>(
  Directory directory, {
  required T Function(OneEntry section) section,
  required T Function(String name, List<T> entries) group,
  void Function(String section)? onSection,
}) {
  final entries = directory.listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  final sections = <String, File>{
    for (final entity in entries)
      if (entity is File && p.extension(entity.path).toLowerCase() == '.one')
        p.basename(entity.path): entity,
  };
  final groups = <String, Directory>{
    for (final entity in entries)
      if (entity is Directory && p.basename(entity.path) != _recycleBin)
        p.basename(entity.path): entity,
  };
  final tocs = entries.whereType<File>().where(
    (file) => p.extension(file.path).toLowerCase() == '.onetoc2',
  );

  final order = <String>[if (tocs.isNotEmpty) ..._tableOfContents(tocs.first)];
  // What the table of contents leaves out still comes along, after it.
  for (final name in <String>[...sections.keys, ...groups.keys]) {
    if (!order.contains(name)) order.add(name);
  }

  final beside = FilesBeside(directory);
  final notebook = <T>[];
  for (final name in order) {
    final file = sections[name];
    final folder = groups[name];
    if (file != null) {
      onSection?.call(p.basenameWithoutExtension(name));
      notebook.add(section(_readSection(file, beside)));
    } else if (folder != null) {
      notebook.add(
        group(
          name,
          foldNotebookFolder<T>(
            folder,
            section: section,
            group: group,
            onSection: onSection,
          ),
        ),
      );
    }
  }
  return notebook;
}

/// Reads the section in [file], the files it keeps beside itself found in
/// [notebook] — or, a section read on its own, nowhere.
OneEntry readSectionFile(File file, {Directory? notebook}) =>
    _readSection(file, notebook == null ? null : FilesBeside(notebook));

OneEntry _readSection(File file, FilesBeside? beside) {
  final name = p.basenameWithoutExtension(file.path);
  try {
    final store = RevisionStore.read(
      file.readAsBytesSync(),
      externalFile: beside?.call,
    );
    return readSection(store, name);
  } on FormatDamage catch (damage) {
    return OneUnreadableSection(name, damage.message);
  } on FileSystemException catch (error) {
    return OneUnreadableSection(name, error.message);
  } on OutOfMemoryError {
    rethrow;
  } on Object {
    // Whatever else a damaged file runs the readers into, it is damage
    // too: this section's, not the whole notebook's.
    return OneUnreadableSection(name, 'The section is damaged');
  }
}

/// The files the sections of a notebook keep beside themselves rather than
/// in themselves, found by their names anywhere in its folder: the folder
/// is gone through once, the first time one is asked for, however many
/// files its sections refer to.
@visibleForTesting
final class FilesBeside {
  FilesBeside(this._folder);

  final Directory _folder;
  Map<String, File>? _byName;

  /// The bytes of the file [reference] names, if the folder holds one of
  /// that name: the first it lists, if it holds several.
  Uint8List? call(String reference) {
    final byName = _byName ??= _list();
    return byName[p.basename(reference.replaceAll(r'\', '/'))]
        ?.readAsBytesSync();
  }

  Map<String, File> _list() {
    final files = <String, File>{};
    for (final entity in _folder.listSync(recursive: true)) {
      if (entity is File) {
        files.putIfAbsent(p.basename(entity.path), () => entity);
      }
    }
    return files;
  }
}

/// The names of the sections and groups the table of contents in [file]
/// lists, in its order: each name the file or folder it is kept in.
List<String> _tableOfContents(File file) {
  try {
    return tableOfContents(RevisionStore.read(file.readAsBytesSync()));
  } on OutOfMemoryError {
    rethrow;
  } on Object {
    // A table of contents that cannot be read leaves the order to the
    // names: it is not needed for the rest.
    return const <String>[];
  }
}

/// The names the table of contents [store] lists, in its order.
@visibleForTesting
List<String> tableOfContents(RevisionStore store) {
  if (store.kind != StoreKind.tableOfContents) return const <String>[];
  final entries = <(int, String)>[];
  // An entry within itself is passed over; entries that list one another
  // over and over, a thousand times sixteen deep, are damage.
  final path = <ExGuid>{};
  var visits = 0;
  void visit(ExGuid? id, int depth) {
    if (++visits > 1 << 20) {
      throw FormatDamage(
        'The table of contents lists its entries over and over',
      );
    }
    final object = store.root[id];
    if (object == null || depth > 16 || !path.add(id!)) return;
    final properties = object.properties;
    final name = properties.text(Prop.folderChildFilename);
    if (name != null) {
      entries.add((
        properties.integer(Prop.notebookElementOrderingId) ?? 1 << 30,
        // OneNote escapes characters a file name may not hold.
        name.replaceAll('^M', '+').replaceAll('^J', ','),
      ));
    }
    for (final child in properties.refs(Prop.tocChildren)) {
      visit(child, depth + 1);
    }
    path.remove(id);
  }

  visit(store.root.contentRoot, 0);
  // A name listed twice is where it was listed last.
  final seen = <String>{};
  final latest = <(int, int, String)>[
    for (var i = entries.length - 1; i >= 0; i--)
      if (seen.add(entries[i].$2)) (entries[i].$1, i, entries[i].$2),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2 - b.$2);
  return <String>[for (final entry in latest) entry.$3];
}
