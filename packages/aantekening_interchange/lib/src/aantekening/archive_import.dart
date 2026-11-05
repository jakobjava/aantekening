/// Bringing back notebooks, sections and pages exported from this app.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../importer.dart';

/// Reads an export of this app's, as the store writes them: what was
/// exported, as it was, pages keeping their identity where they can.
final class AantekeningImporter implements NotesImporter {
  const AantekeningImporter();

  @override
  String get name => 'aantekening';

  @override
  String get description =>
      'Notebooks, sections or pages exported from aantekening, here or on '
      'another computer, exactly as they were.';

  @override
  List<String> get extensions => const <String>['aantekening', 'zip'];

  @override
  ImportSource get source => ImportSource.file;

  /// Notebooks go on their own, sections into the notebook open, pages
  /// into the section open, as they were exported.
  @override
  ImportTarget get target => ImportTarget.newNotebook;

  @override
  NotesDraft read(List<String> paths, ImportWork work) {
    final notebooks = <NotebookDraft>[];
    final sections = <SectionDraft>[];
    final pages = <PageDraft>[];
    final assets = <String, AssetDraft>{};
    for (final path in paths) {
      work.progress('Reading ${p.basename(path)}');
      final draft = _read(path, work);
      notebooks.addAll(draft.notebooks);
      sections.addAll(draft.sections);
      pages.addAll(draft.pages);
      assets.addAll(draft.assets);
    }
    return NotesDraft(
      notebooks: notebooks,
      sections: sections,
      pages: pages,
      assets: assets,
    );
  }

  static NotesDraft _read(String path, ImportWork work) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      // What the entries may unpack to, taken together.
      var left = inflatedLimit(input.length);
      Uint8List unpack(ArchiveFile file) {
        final bytes = _unpack(file, left);
        left -= bytes.length;
        return bytes;
      }

      final manifest = archive.findFile(exportManifestName);
      if (manifest == null) {
        throw FormatDamage('${p.basename(path)} is not an export of notes');
      }
      final list = jsonDecode(utf8.decode(unpack(manifest)));
      if (list is! Map<String, Object?>) {
        throw FormatDamage('${p.basename(path)} is damaged');
      }

      final notebooks = <String, Notebook>{};
      final sections = <String, Section>{};
      final pageFiles = <String, PageFile>{};
      final assetFiles = <String, ArchiveFile>{};
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final name = file.name;
        if (name.startsWith('assets/')) {
          assetFiles[p.basename(name)] = file;
          continue;
        }
        final entity = EntityFile.decode(_ungzip(unpack(file)));
        switch (entity) {
          case NotebookFile(:final notebook):
            notebooks[notebook.id] = notebook;
          case SectionFile(:final section) when !section.isDeleted:
            sections[section.id] = section;
          case PageFile(:final page) when !page.isDeleted:
            pageFiles[page.id] = entity;
          default:
            break;
        }
      }

      final assets = <String, AssetDraft>{};
      for (final page in pageFiles.values) {
        for (final asset in page.assets) {
          if (assets.containsKey(asset.id)) continue;
          final file = assetFiles[asset.sha256];
          if (file == null) continue;
          final bytes = unpack(file);
          final (_, draft) = work.keep(
            bytes,
            name: asset.originalName,
            mime: asset.mimeType,
          );
          assets[asset.id] = draft;
        }
      }

      // The sections and pages being built, each within the one before it:
      // one that is its own parent, or its parent's, is not built again
      // within itself.
      final building = <String>{};

      // What is in each section and beneath each page, gathered once
      // rather than looked for among them all for each.
      final pagesUnder = <(String, String?), List<PageFile>>{};
      for (final file in pageFiles.values) {
        (pagesUnder[(file.page.sectionId, file.page.parentId)] ??= <PageFile>[])
            .add(file);
      }
      final sectionsUnder = <String, List<Section>>{};
      final sectionsAtTop = <String, List<Section>>{};
      for (final section in sections.values) {
        final parentId = section.parentId;
        (parentId == null
                ? sectionsAtTop[section.notebookId] ??= <Section>[]
                : sectionsUnder[parentId] ??= <Section>[])
            .add(section);
      }

      List<PageDraft> pagesIn(String sectionId, String? parentId) {
        final here = <PageFile>[...?pagesUnder[(sectionId, parentId)]]
          ..sort((a, b) => a.page.position.compareTo(b.page.position));
        final drafts = <PageDraft>[];
        for (final file in here) {
          if (!building.add(file.page.id)) continue;
          drafts.add(_page(file, pagesIn));
          building.remove(file.page.id);
        }
        return drafts;
      }

      PageDraft page(PageFile file) {
        building.add(file.page.id);
        final draft = _page(file, pagesIn);
        building.remove(file.page.id);
        return draft;
      }

      SectionDraft sectionDraft(Section section) {
        building.add(section.id);
        final draft = SectionDraft(
          title: section.title,
          color: section.color,
          pages: pagesIn(section.id, null),
          sections: <SectionDraft>[
            for (final child in _sorted(
              (sectionsUnder[section.id] ?? const <Section>[]).where(
                (each) => !building.contains(each.id),
              ),
            ))
              sectionDraft(child),
          ],
        );
        building.remove(section.id);
        return draft;
      }

      List<String> ids(String key) => <String>[
        for (final id in (list[key] as List<Object?>?) ?? const <Object?>[])
          if (id is String) id,
      ];

      return NotesDraft(
        notebooks: <NotebookDraft>[
          for (final id in ids('notebooks'))
            if (notebooks[id] case final notebook?)
              NotebookDraft(
                title: notebook.title,
                color: notebook.color,
                sections: <SectionDraft>[
                  for (final top in _sorted(
                    sectionsAtTop[id] ?? const <Section>[],
                  ))
                    sectionDraft(top),
                ],
              ),
        ],
        sections: <SectionDraft>[
          for (final id in ids('sections'))
            if (sections[id] case final top?) sectionDraft(top),
        ],
        pages: <PageDraft>[
          for (final id in ids('pages'))
            if (pageFiles[id] case final file?) page(file),
        ],
        assets: assets,
      );
    } finally {
      input.closeSync();
    }
  }

  /// The bytes of [file], unpacked to no more than [limit] of them.
  static Uint8List _unpack(ArchiveFile file, int limit) {
    final raw =
        file.rawContent?.getStream(decompress: false).toUint8List() ??
        Uint8List(0);
    return switch (file.compression) {
      CompressionType.deflate => inflateAtMost(raw, limit, raw: true),
      CompressionType.none || null when raw.length <= limit => raw,
      CompressionType.none || null => throw FormatDamage(
        'The export unpacks to more than ${limit >> 20} MiB',
      ),
      CompressionType.bzip2 => throw FormatDamage(
        '${file.name} is compressed in a way not read',
      ),
    };
  }

  /// A page file's [bytes] ungzipped, as [EntityFile.decode] would — but
  /// to a limit — or as they are if they are not gzipped, or damaged.
  static Uint8List _ungzip(Uint8List bytes) {
    if (!isGzipped(bytes)) {
      return bytes;
    }
    try {
      return inflateAtMost(bytes, inflatedLimit(bytes.length));
    } on FormatException {
      return bytes;
    }
  }

  static List<Section> _sorted(Iterable<Section> sections) =>
      sections.toList()..sort((a, b) => a.position.compareTo(b.position));

  static PageDraft _page(
    PageFile file,
    List<PageDraft> Function(String sectionId, String? parentId) pagesIn,
  ) => PageDraft(
    title: file.page.title,
    createdAt: file.page.createdAt,
    document: file.document,
    id: file.page.id,
    subpages: pagesIn(file.page.sectionId, file.page.id),
  );
}
