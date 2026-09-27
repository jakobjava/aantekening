/// Storing notes read from elsewhere: a whole import at once.
library;

import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';

import 'asset_store.dart';
import 'database.dart';
import 'files/entity_files.dart';
import 'library_repository.dart';
import 'page_repository.dart';

/// What storing an import made, to open it.
final class StoredNotes {
  const StoredNotes({
    required this.notebooks,
    required this.sections,
    required this.firstPage,
  });

  final List<String> notebooks;
  final List<String> sections;

  /// The first page stored, with the notebook and section it is in.
  final ({String notebookId, String sectionId, String pageId})? firstPage;
}

/// Stores [NotesDraft]s: their pictures and files first, then every
/// notebook, section and page in one transaction, so an import is there
/// whole or not at all.
final class DraftStoring {
  DraftStoring(
    this._db,
    this._library,
    this._pages,
    this._assets, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final LibraryRepository _library;
  final PageRepository _pages;
  final AssetStore _assets;
  final DateTime Function() _clock;

  /// Stores [draft]: its notebooks as notebooks of their own, its sections
  /// in notebook [notebookId], its pages in section [sectionId].
  Future<StoredNotes> store(
    NotesDraft draft, {
    String? notebookId,
    String? sectionId,
  }) async {
    if (draft.sections.isNotEmpty && notebookId == null) {
      throw ArgumentError('Sections need a notebook to go into');
    }
    if (draft.pages.isNotEmpty && sectionId == null) {
      throw ArgumentError('Pages need a section to go into');
    }
    final ids = <String, String>{};
    for (final entry in draft.assets.entries) {
      final asset = await _assets.importFile(
        File(entry.value.path),
        mimeType: entry.value.mimeType,
        name: entry.value.name,
      );
      ids[entry.key] = asset.id;
    }
    return _db.transaction(() {
      final writer = _Writer(this, ids, _clock().millisecondsSinceEpoch);
      final notebooks = <String>[
        for (final notebook in draft.notebooks) writer.notebook(notebook),
      ];
      final sections = <String>[
        for (final section in draft.sections)
          writer.section(section, notebookId: notebookId!, parentId: null),
      ];
      if (draft.pages.isNotEmpty) {
        final section = _db.select(
          'SELECT notebook_id FROM sections WHERE id = ?',
          <Object?>[sectionId],
        );
        if (section.isEmpty) throw ArgumentError('No section $sectionId');
        writer.notebookId = section.first['notebook_id'] as String;
        writer.pages(draft.pages, sectionId: sectionId!, parentId: null);
      }
      return StoredNotes(
        notebooks: notebooks,
        sections: sections,
        firstPage: writer.firstPage,
      );
    });
  }
}

final class _Writer {
  _Writer(this._storing, this._assetIds, this._now);

  final DraftStoring _storing;
  final Map<String, String> _assetIds;
  final int _now;
  String? notebookId;
  ({String notebookId, String sectionId, String pageId})? firstPage;

  AantekeningDatabase get _db => _storing._db;

  String notebook(NotebookDraft draft) {
    final id = Ulid.generate();
    _storing._library.putNotebook(
      Notebook(
        id: id,
        title: draft.title,
        position: _db.nextPosition('notebooks', '1', const <Object?>[]),
        createdAt: _now,
        updatedAt: _now,
        color: draft.color,
      ),
    );
    notebookId = id;
    for (final section in draft.sections) {
      this.section(section, notebookId: id, parentId: null);
    }
    return id;
  }

  String section(
    SectionDraft draft, {
    required String notebookId,
    required String? parentId,
  }) {
    final id = Ulid.generate();
    _storing._library.putSection(
      Section(
        id: id,
        notebookId: notebookId,
        parentId: parentId,
        title: draft.title,
        position: _db.nextPosition(
          'sections',
          'notebook_id = ? AND parent_id IS ?',
          <Object?>[notebookId, parentId],
        ),
        createdAt: _now,
        updatedAt: _now,
        color: draft.color,
      ),
    );
    this.notebookId = notebookId;
    pages(draft.pages, sectionId: id, parentId: null);
    for (final child in draft.sections) {
      section(child, notebookId: notebookId, parentId: id);
    }
    return id;
  }

  void pages(
    List<PageDraft> drafts, {
    required String sectionId,
    required String? parentId,
  }) {
    for (final draft in drafts) {
      final taken =
          draft.id == null ||
          _db.select('SELECT 1 FROM pages WHERE id = ?', <Object?>[
            draft.id,
          ]).isNotEmpty;
      final id = taken ? Ulid.generate() : draft.id!;
      final source = draft.document.withAssetsRenamed(_assetIds);
      final document = PageDocument(
        id: id,
        revision: source.revision,
        canvas: source.canvas,
        elements: source.elements,
      );
      _storing._pages.putPage(
        PageFile(
          page: PageRef(
            id: id,
            sectionId: sectionId,
            parentId: parentId,
            title: draft.title,
            position: _db.nextPosition(
              'pages',
              'section_id = ? AND parent_id IS ?',
              <Object?>[sectionId, parentId],
            ),
            createdAt: draft.createdAt,
            updatedAt: _now,
            preview: PageRepository.previewOf(document.extractSearchText()),
            revision: document.revision,
          ),
          document: document,
        ),
      );
      firstPage ??= (notebookId: notebookId!, sectionId: sectionId, pageId: id);
      pages(draft.subpages, sectionId: sectionId, parentId: id);
    }
  }
}
