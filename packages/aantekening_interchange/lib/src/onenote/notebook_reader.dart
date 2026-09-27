/// Reading a OneNote notebook laid out in a folder, as a .onepkg unpacks:
/// its table of contents, its sections and its section groups.
library;

import 'dart:io';
import 'dart:typed_data';

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

  final notebook = <OneEntry>[];
  for (final name in order) {
    final section = sections[name];
    final group = groups[name];
    if (section != null) {
      onSection?.call(p.basenameWithoutExtension(name));
      notebook.add(_readSectionFile(section, directory));
    } else if (group != null) {
      notebook.add(
        OneSectionGroup(name, readNotebookFolder(group, onSection: onSection)),
      );
    }
  }
  return notebook;
}

OneEntry _readSectionFile(File file, Directory notebook) {
  final name = p.basenameWithoutExtension(file.path);
  try {
    final store = RevisionStore.read(
      file.readAsBytesSync(),
      externalFile: (reference) => _externalFile(notebook, reference),
    );
    return readSection(store, name);
  } on FormatDamage catch (damage) {
    return OneUnreadableSection(name, damage.message);
  } on FileSystemException catch (error) {
    return OneUnreadableSection(name, error.message);
  }
}

/// A file a section keeps beside itself rather than in itself, found by
/// its name anywhere in the notebook's folder.
Uint8List? _externalFile(Directory notebook, String reference) {
  final name = p.basename(reference.replaceAll(r'\', '/'));
  for (final entity in notebook.listSync(recursive: true)) {
    if (entity is File && p.basename(entity.path) == name) {
      return entity.readAsBytesSync();
    }
  }
  return null;
}

/// The names of the sections and groups a table of contents lists, in its
/// order: each name the file or folder it is kept in.
List<String> _tableOfContents(File file) {
  try {
    final store = RevisionStore.read(file.readAsBytesSync());
    if (store.kind != StoreKind.tableOfContents) return const <String>[];
    final entries = <(int, String)>[];
    void visit(ExGuid? id, int depth) {
      final object = store.root[id];
      if (object == null || depth > 16) return;
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
    }

    visit(store.root.contentRoot, 0);
    // A name listed twice is where it was listed last.
    final seen = <String>{};
    final latest = <(int, int, String)>[
      for (var i = entries.length - 1; i >= 0; i--)
        if (seen.add(entries[i].$2)) (entries[i].$1, i, entries[i].$2),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2 - b.$2);
    return <String>[for (final entry in latest) entry.$3];
  } on FormatDamage {
    return const <String>[];
  }
}
