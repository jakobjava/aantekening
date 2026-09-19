/// Reads and writes the organisational tree: notebooks and nested sections.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'page_repository.dart';
import 'row_read.dart';

/// Stores notebooks and sections.
///
/// Every method is asynchronous even though SQLite is synchronous here. That
/// keeps the public API unchanged when the connection later moves onto a
/// background isolate, which is the planned answer to large-workspace
/// scalability.
class LibraryRepository {
  LibraryRepository(this._db, this._pages, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;

  /// The pages sections hold, which copying a section copies too.
  final PageRepository _pages;

  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- notebooks

  /// Lists notebooks in display order.
  Future<List<Notebook>> listNotebooks({bool includeDeleted = false}) async {
    final rows = _db.select(
      includeDeleted
          ? 'SELECT * FROM notebooks ORDER BY position, id'
          : 'SELECT * FROM notebooks WHERE deleted_at IS NULL '
                'ORDER BY position, id',
    );
    return <Notebook>[for (final row in rows) _notebook(row)];
  }

  /// Fetches one notebook, or null when it does not exist.
  Future<Notebook?> findNotebook(String id) async {
    final rows = _db.select('SELECT * FROM notebooks WHERE id = ?', <Object?>[
      id,
    ]);
    return rows.isEmpty ? null : _notebook(rows.first);
  }

  /// Creates a notebook at the end of the list.
  Future<Notebook> createNotebook({
    required String title,
    int? color,
    String? icon,
  }) async {
    final now = _now;
    final notebook = Notebook(
      id: Ulid.generate(),
      title: title,
      position: _nextNotebookPosition(),
      createdAt: now,
      updatedAt: now,
      color: color,
      icon: icon,
    );
    _db.run(
      'INSERT INTO notebooks '
      '(id, title, position, color, icon, created_at, updated_at, deleted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, NULL)',
      <Object?>[
        notebook.id,
        notebook.title,
        notebook.position,
        notebook.color,
        notebook.icon,
        notebook.createdAt,
        notebook.updatedAt,
      ],
    );
    return notebook;
  }

  /// Persists changes to [notebook], stamping it as modified now.
  Future<void> updateNotebook(Notebook notebook) async {
    _db.run(
      'UPDATE notebooks SET title = ?, position = ?, color = ?, icon = ?, '
      'updated_at = ?, deleted_at = ? WHERE id = ?',
      <Object?>[
        notebook.title,
        notebook.position,
        notebook.color,
        notebook.icon,
        _now,
        notebook.deletedAt,
        notebook.id,
      ],
    );
  }

  /// Renames a notebook.
  Future<void> renameNotebook(String id, String title) async {
    _db.run(
      'UPDATE notebooks SET title = ?, updated_at = ? WHERE id = ?',
      <Object?>[title, _now, id],
    );
  }

  /// Moves a notebook to the recycle bin.
  ///
  /// Sections and pages are left untouched; they are filtered out of listings
  /// by joining against their notebook, which keeps deleting a large notebook a
  /// single-row write.
  Future<void> deleteNotebook(String id) async {
    _db.run('UPDATE notebooks SET deleted_at = ? WHERE id = ?', <Object?>[
      _now,
      id,
    ]);
  }

  /// Restores a notebook from the recycle bin.
  Future<void> restoreNotebook(String id) async {
    _db.run(
      'UPDATE notebooks SET deleted_at = NULL, updated_at = ? WHERE id = ?',
      <Object?>[_now, id],
    );
  }

  // ----------------------------------------------------------------- sections

  /// Lists the direct children of [parentId] within [notebookId], or the
  /// notebook's top-level sections when [parentId] is null.
  Future<List<Section>> listSections(
    String notebookId, {
    String? parentId,
    bool includeDeleted = false,
  }) async {
    final deletedClause = includeDeleted ? '' : 'AND deleted_at IS NULL ';
    final rows = parentId == null
        ? _db.select(
            'SELECT * FROM sections WHERE notebook_id = ? AND parent_id IS NULL '
            '$deletedClause ORDER BY position, id',
            <Object?>[notebookId],
          )
        : _db.select(
            'SELECT * FROM sections WHERE notebook_id = ? AND parent_id = ? '
            '$deletedClause ORDER BY position, id',
            <Object?>[notebookId, parentId],
          );
    return <Section>[for (final row in rows) _section(row)];
  }

  /// Lists every section in [notebookId] at any depth.
  ///
  /// The sidebar renders the whole tree at once, so it is cheaper to fetch the
  /// notebook's sections in one query and assemble the hierarchy in Dart than
  /// to issue a query per level.
  Future<List<Section>> listAllSections(
    String notebookId, {
    bool includeDeleted = false,
  }) async {
    final rows = _db.select(
      'SELECT * FROM sections WHERE notebook_id = ? '
      '${includeDeleted ? '' : 'AND deleted_at IS NULL '}'
      'ORDER BY position, id',
      <Object?>[notebookId],
    );
    return <Section>[for (final row in rows) _section(row)];
  }

  /// Fetches one section, or null when it does not exist.
  Future<Section?> findSection(String id) async => _findSection(id);

  /// Creates a section, nested under [parentId] when one is given.
  Future<Section> createSection({
    required String notebookId,
    required String title,
    String? parentId,
    int? color,
  }) async {
    final now = _now;
    final section = Section(
      id: Ulid.generate(),
      notebookId: notebookId,
      title: title,
      parentId: parentId,
      position: _nextSectionPosition(notebookId, parentId),
      createdAt: now,
      updatedAt: now,
      color: color,
    );
    _insertSection(section);
    return section;
  }

  /// Persists changes to [section].
  Future<void> updateSection(Section section) async {
    _db.run(
      'UPDATE sections SET notebook_id = ?, parent_id = ?, title = ?, '
      'position = ?, color = ?, updated_at = ?, deleted_at = ? WHERE id = ?',
      <Object?>[
        section.notebookId,
        section.parentId,
        section.title,
        section.position,
        section.color,
        _now,
        section.deletedAt,
        section.id,
      ],
    );
  }

  /// Renames a section.
  Future<void> renameSection(String id, String title) async {
    _db.run(
      'UPDATE sections SET title = ?, updated_at = ? WHERE id = ?',
      <Object?>[title, _now, id],
    );
  }

  /// Re-parents [sectionId] and places it at [position] among its new siblings.
  ///
  /// Throws [ArgumentError] when the move would put a section inside its own
  /// subtree, which would orphan that subtree from the notebook root.
  Future<void> moveSection(
    String sectionId, {
    required String notebookId,
    String? parentId,
    double? position,
  }) async {
    if (parentId != null && _isDescendantOrSelf(parentId, sectionId)) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'a section cannot be moved inside itself',
      );
    }
    final target = position ?? _nextSectionPosition(notebookId, parentId);
    _db.transaction(() {
      _db.run(
        'UPDATE sections SET notebook_id = ?, parent_id = ?, position = ?, '
        'updated_at = ? WHERE id = ?',
        <Object?>[notebookId, parentId, target, _now, sectionId],
      );
      // Subsections follow their section to its new notebook.
      for (final id in _subtree(sectionId).skip(1)) {
        _db.run('UPDATE sections SET notebook_id = ? WHERE id = ?', <Object?>[
          notebookId,
          id,
        ]);
      }
    });
  }

  /// Copies a section, with its subsections and every page in them, into
  /// [notebookId] — under [parentId] when given — at the end; returns the
  /// copy.
  ///
  /// Throws [ArgumentError] when [parentId] is the section or one of its
  /// subsections, which would copy the section into itself without end.
  Future<Section> copySection(
    String sectionId, {
    required String notebookId,
    String? parentId,
  }) async => _db.transaction(() {
    if (parentId != null && _isDescendantOrSelf(parentId, sectionId)) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'a section cannot be copied into itself',
      );
    }
    final source = _findSection(sectionId);
    if (source == null) {
      throw ArgumentError.value(sectionId, 'sectionId', 'no such section');
    }
    return _copyTree(
      source,
      notebookId: notebookId,
      parentId: parentId,
      position: _nextSectionPosition(notebookId, parentId),
    );
  });

  /// Moves a section and its subtree to the recycle bin. Returns the sections
  /// it deleted; their pages go with them, hidden with their sections.
  Future<List<String>> deleteSection(String id) async => _db.transaction(() {
    // Subsections deleted earlier keep their own time, so restoring this
    // section does not bring them back with it.
    final deleted = _subtree(id, live: true);
    final now = _now;
    for (final section in deleted) {
      _db.run('UPDATE sections SET deleted_at = ? WHERE id = ?', <Object?>[
        now,
        section,
      ]);
    }
    return deleted;
  });

  /// Restores a section from the recycle bin, with the subsections deleted
  /// along with it.
  Future<void> restoreSection(String id) async {
    final deletedAt = _findSection(id)?.deletedAt;
    if (deletedAt == null) return;
    _db.transaction(() {
      final now = _now;
      for (final section in _subtree(id, deletedAt: deletedAt)) {
        _db.run(
          'UPDATE sections SET deleted_at = NULL, updated_at = ? WHERE id = ?',
          <Object?>[now, section],
        );
      }
    });
  }

  void _insertSection(Section section) => _db.run(
    'INSERT INTO sections '
    '(id, notebook_id, parent_id, title, position, color, created_at, '
    ' updated_at, deleted_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)',
    <Object?>[
      section.id,
      section.notebookId,
      section.parentId,
      section.title,
      section.position,
      section.color,
      section.createdAt,
      section.updatedAt,
    ],
  );

  Section? _findSection(String id) {
    final rows = _db.select('SELECT * FROM sections WHERE id = ?', <Object?>[
      id,
    ]);
    return rows.isEmpty ? null : _section(rows.first);
  }

  /// [sectionId] and the sections beneath it; see
  /// [AantekeningDatabase.subtree].
  List<String> _subtree(
    String sectionId, {
    bool live = false,
    int? deletedAt,
  }) => _db.subtree('sections', sectionId, live: live, deletedAt: deletedAt);

  /// Copies [source], its pages and its live subsections into [notebookId],
  /// under [parentId] at [position]; subsections keep their order.
  Section _copyTree(
    Section source, {
    required String notebookId,
    required String? parentId,
    required double position,
  }) {
    final children = <Section>[
      for (final row in _db.select(
        'SELECT * FROM sections WHERE parent_id = ? AND deleted_at IS NULL '
        'ORDER BY position, id',
        <Object?>[source.id],
      ))
        _section(row),
    ];
    final now = _now;
    final copy = Section(
      id: Ulid.generate(),
      notebookId: notebookId,
      parentId: parentId,
      title: source.title,
      position: position,
      color: source.color,
      createdAt: now,
      updatedAt: now,
    );
    _insertSection(copy);
    _pages.copySectionPages(source.id, copy.id);
    for (final child in children) {
      _copyTree(
        child,
        notebookId: notebookId,
        parentId: copy.id,
        position: child.position,
      );
    }
    return copy;
  }

  /// Whether [candidate] is [ancestor] or sits anywhere beneath it.
  bool _isDescendantOrSelf(String candidate, String ancestor) =>
      _subtree(ancestor).contains(candidate);

  double _nextSectionPosition(String notebookId, String? parentId) =>
      _db.nextPosition(
        'sections',
        'notebook_id = ? AND parent_id IS ?',
        <Object?>[notebookId, parentId],
      );

  double _nextNotebookPosition() =>
      _db.nextPosition('notebooks', '1', const <Object?>[]);

  static Notebook _notebook(Row row) => Notebook(
    id: str(row, 'id'),
    title: str(row, 'title'),
    position: real(row, 'position'),
    createdAt: integer(row, 'created_at'),
    updatedAt: integer(row, 'updated_at'),
    color: intOrNull(row, 'color'),
    deletedAt: intOrNull(row, 'deleted_at'),
    icon: strOrNull(row, 'icon'),
  );

  static Section _section(Row row) => Section(
    id: str(row, 'id'),
    notebookId: str(row, 'notebook_id'),
    title: str(row, 'title'),
    position: real(row, 'position'),
    createdAt: integer(row, 'created_at'),
    updatedAt: integer(row, 'updated_at'),
    parentId: strOrNull(row, 'parent_id'),
    color: intOrNull(row, 'color'),
    deletedAt: intOrNull(row, 'deleted_at'),
  );
}
