/// Bringing back notebooks, sections and pages exported from this app.
library;

import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../bytes.dart';
import '../importer.dart';

/// Reads an export of this app's ([ArchiveExport]): what was exported, as
/// it was, pages keeping their identity where they can.
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
      final manifest = archive.findFile(ArchiveExport.manifestName);
      if (manifest == null) {
        throw FormatDamage('${p.basename(path)} is not an export of notes');
      }
      final list = jsonDecode(utf8.decode(manifest.readBytes()!));
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
        final entity = EntityFile.decode(file.readBytes()!);
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
          final bytes = assetFiles[asset.sha256]?.readBytes();
          if (bytes == null) continue;
          final (_, draft) = work.keep(
            bytes,
            name: asset.originalName,
            mime: asset.mimeType,
          );
          assets[asset.id] = draft;
        }
      }

      List<PageDraft> pagesIn(String sectionId, String? parentId) {
        final here =
            pageFiles.values
                .where(
                  (file) =>
                      file.page.sectionId == sectionId &&
                      file.page.parentId == parentId,
                )
                .toList()
              ..sort((a, b) => a.page.position.compareTo(b.page.position));
        return <PageDraft>[for (final file in here) _page(file, pagesIn)];
      }

      SectionDraft sectionDraft(Section section) => SectionDraft(
        title: section.title,
        color: section.color,
        pages: pagesIn(section.id, null),
        sections: <SectionDraft>[
          for (final child in _sorted(
            sections.values.where((each) => each.parentId == section.id),
          ))
            sectionDraft(child),
        ],
      );

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
                    sections.values.where(
                      (each) => each.notebookId == id && each.parentId == null,
                    ),
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
            if (pageFiles[id] case final page?) _page(page, pagesIn),
        ],
        assets: assets,
      );
    } finally {
      input.closeSync();
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
