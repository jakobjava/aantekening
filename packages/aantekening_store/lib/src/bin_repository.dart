/// The bin: what was deleted, until it is restored or deleted for good.
library;

import 'database.dart';
import 'library_repository.dart';
import 'page_repository.dart';
import 'row_read.dart';

/// What the bin holds: a notebook, section or page deleted, with everything
/// that went with it.
enum BinKind { notebook, section, page }

final class BinEntry {
  const BinEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.deletedAt,
    required this.place,
    required this.pages,
  });

  final BinKind kind;
  final String id;
  final String title;
  final int deletedAt;

  /// Where it was: its notebook and the sections above it.
  final List<String> place;

  /// How many pages went with it, itself among them for a page.
  final int pages;
}

/// Lists, restores and deletes for good what is in the bin.
///
/// Deleting a notebook, section or page only marks it deleted, and with it
/// what it holds; nothing leaves the workspace until it is deleted from the
/// bin. Deleting from the bin then deletes the rows — the notes folder
/// keeps a note that they were, so every other copy lets them go too — and
/// the pictures and files nothing shows any more.
class BinRepository {
  BinRepository(
    this._db,
    this._library,
    this._pages, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final LibraryRepository _library;
  final PageRepository _pages;
  final DateTime Function() _clock;

  /// Everything in the bin, what was deleted last first: each notebook,
  /// section and page deleted by itself — not those that went with one.
  Future<List<BinEntry>> list() async {
    final entries = <BinEntry>[
      for (final row in _db.select(
        'SELECT id, title, deleted_at FROM notebooks '
        'WHERE deleted_at IS NOT NULL',
      ))
        BinEntry(
          kind: BinKind.notebook,
          id: str(row, 'id'),
          title: str(row, 'title'),
          deletedAt: integer(row, 'deleted_at'),
          place: const <String>[],
          pages: _count(
            'SELECT COUNT(*) AS n FROM pages p '
            'JOIN sections s ON s.id = p.section_id WHERE s.notebook_id = ?',
            str(row, 'id'),
          ),
        ),
      for (final row in _db.select(
        'SELECT s.id, s.title, s.deleted_at FROM sections s '
        'LEFT JOIN sections parent ON parent.id = s.parent_id '
        'WHERE s.deleted_at IS NOT NULL '
        'AND (parent.deleted_at IS NULL OR parent.deleted_at != s.deleted_at)',
      ))
        BinEntry(
          kind: BinKind.section,
          id: str(row, 'id'),
          title: str(row, 'title'),
          deletedAt: integer(row, 'deleted_at'),
          place: _sectionPlace(str(row, 'id'), includeSelf: false),
          pages: _sectionPages(str(row, 'id')).length,
        ),
      for (final row in _db.select(
        'SELECT p.id, p.title, p.section_id, p.deleted_at FROM pages p '
        'LEFT JOIN pages parent ON parent.id = p.parent_id '
        'WHERE p.deleted_at IS NOT NULL '
        'AND (parent.deleted_at IS NULL OR parent.deleted_at != p.deleted_at)',
      ))
        BinEntry(
          kind: BinKind.page,
          id: str(row, 'id'),
          title: str(row, 'title'),
          deletedAt: integer(row, 'deleted_at'),
          place: _sectionPlace(str(row, 'section_id'), includeSelf: true),
          pages: _db
              .subtree(
                'pages',
                str(row, 'id'),
                deletedAt: integer(row, 'deleted_at'),
              )
              .length,
        ),
    ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return entries;
  }

  /// Puts [entry] back where it was, with what went with it; and the
  /// section and notebook it was in, if they have been deleted since.
  Future<void> restore(BinEntry entry) => restoreItem(entry.kind, entry.id);

  /// Puts the [kind] [id] back where it was, as [restore] does.
  Future<void> restoreItem(BinKind kind, String id) async {
    final now = _clock().millisecondsSinceEpoch;
    switch (kind) {
      case BinKind.notebook:
        await _library.restoreNotebook(id);
      case BinKind.section:
        _restoreAbove(id, now, includeSelf: false);
        await _library.restoreSection(id);
      case BinKind.page:
        final section = _db.select(
          'SELECT section_id FROM pages WHERE id = ?',
          <Object?>[id],
        );
        if (section.isEmpty) return;
        _restoreAbove(str(section.first, 'section_id'), now, includeSelf: true);
        await _pages.restorePage(id);
    }
  }

  /// Deletes [entry], and everything that went with it, for good.
  Future<void> purge(BinEntry entry) async {
    _db.transaction(() {
      switch (entry.kind) {
        case BinKind.notebook:
          purgeNotebook(entry.id);
        case BinKind.section:
          purgeSection(entry.id);
        case BinKind.page:
          final deletedAt = _db.select(
            'SELECT deleted_at FROM pages WHERE id = ?',
            <Object?>[entry.id],
          );
          if (deletedAt.isEmpty) return;
          for (final id
              in _db
                  .subtree(
                    'pages',
                    entry.id,
                    deletedAt: intOrNull(deletedAt.first, 'deleted_at'),
                  )
                  .reversed) {
            purgePage(id);
          }
      }
    });
  }

  /// Deletes everything in the bin for good, returning how many pages went.
  Future<int> empty() async {
    var pages = 0;
    for (final entry in await list()) {
      pages += entry.pages;
      await purge(entry);
    }
    return pages;
  }

  /// Deletes notebook [id], its sections and their pages, for good.
  ///
  /// Synchronous, as the notes folder's own deletions are.
  void purgeNotebook(String id) {
    _db.transaction(() {
      for (final row in _db.select(
        'SELECT id FROM sections WHERE notebook_id = ? AND parent_id IS NULL',
        <Object?>[id],
      )) {
        purgeSection(str(row, 'id'));
      }
      _forgetAiAbout(id);
      _db.run('DELETE FROM notebooks WHERE id = ?', <Object?>[id]);
    });
  }

  /// Deletes section [id], the sections beneath it and their pages, for
  /// good.
  void purgeSection(String id) {
    _db.transaction(() {
      final sections = _db.subtree('sections', id);
      for (final section in sections.reversed) {
        for (final row in _db.select(
          'SELECT id FROM pages WHERE section_id = ? ORDER BY parent_id IS NULL',
          <Object?>[section],
        )) {
          purgePage(str(row, 'id'));
        }
        _forgetAiAbout(section);
        _db.run('DELETE FROM sections WHERE id = ?', <Object?>[section]);
      }
    });
  }

  /// Deletes page [id] for good; its subpages move up to its parent, as
  /// they are deleted separately if they are to go too.
  void purgePage(String id) {
    _db.transaction(() {
      final page = _db.select(
        'SELECT rowid AS rid, parent_id FROM pages WHERE id = ?',
        <Object?>[id],
      );
      if (page.isEmpty) return;
      _db.run('UPDATE pages SET parent_id = ? WHERE parent_id = ?', <Object?>[
        strOrNull(page.first, 'parent_id'),
        id,
      ]);
      _db.run('DELETE FROM page_search WHERE rowid = ?', <Object?>[
        integer(page.first, 'rid'),
      ]);
      _forgetAiAbout(id);
      // Its body, tags, embeddings and links to pictures cascade.
      _db.run('DELETE FROM pages WHERE id = ?', <Object?>[id]);
    });
  }

  /// The conversations and kept items about [scope], which go with it.
  void _forgetAiAbout(String scope) {
    _db.run('DELETE FROM ai_threads WHERE scope_id = ?', <Object?>[scope]);
    _db.run('DELETE FROM ai_items WHERE scope_id = ?', <Object?>[scope]);
  }

  int _count(String sql, String id) =>
      integer(_db.select(sql, <Object?>[id]).first, 'n');

  List<String> _sectionPages(String sectionId) => <String>[
    for (final section in _db.subtree('sections', sectionId))
      for (final row in _db.select(
        'SELECT id FROM pages WHERE section_id = ?',
        <Object?>[section],
      ))
        str(row, 'id'),
  ];

  /// The notebook and sections above section [sectionId], the section
  /// itself too with [includeSelf], as their titles.
  List<String> _sectionPlace(String sectionId, {required bool includeSelf}) {
    final titles = <String>[];
    String? notebookId;
    String? id = sectionId;
    var first = true;
    while (id != null) {
      final rows = _db.select(
        'SELECT title, parent_id, notebook_id FROM sections WHERE id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) break;
      if (!first || includeSelf) titles.insert(0, str(rows.first, 'title'));
      notebookId = str(rows.first, 'notebook_id');
      id = strOrNull(rows.first, 'parent_id');
      first = false;
    }
    if (notebookId != null) {
      final notebook = _db.select(
        'SELECT title FROM notebooks WHERE id = ?',
        <Object?>[notebookId],
      );
      if (notebook.isNotEmpty) titles.insert(0, str(notebook.first, 'title'));
    }
    return titles;
  }

  void _restoreNotebook(String id, int now) => _db.run(
    'UPDATE notebooks SET deleted_at = NULL, updated_at = ? '
    'WHERE id = ? AND deleted_at IS NOT NULL',
    <Object?>[now, id],
  );

  /// Restores the notebook and the sections above section [sectionId] —
  /// the section too with [includeSelf] — that are in the bin, so what is
  /// restored has somewhere to be.
  void _restoreAbove(String sectionId, int now, {required bool includeSelf}) {
    String? id = sectionId;
    var first = true;
    while (id != null) {
      final rows = _db.select(
        'SELECT parent_id, notebook_id FROM sections WHERE id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return;
      if (!first || includeSelf) {
        _db.run(
          'UPDATE sections SET deleted_at = NULL, updated_at = ? '
          'WHERE id = ? AND deleted_at IS NOT NULL',
          <Object?>[now, id],
        );
      }
      _restoreNotebook(str(rows.first, 'notebook_id'), now);
      id = strOrNull(rows.first, 'parent_id');
      first = false;
    }
  }
}
