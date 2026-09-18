/// Reads and writes the organisational tree: notebooks and nested sections.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'row_read.dart';

/// Stores notebooks and sections.
///
/// Every method is asynchronous even though SQLite is synchronous here. That
/// keeps the public API unchanged when the connection later moves onto a
/// background isolate, which is the planned answer to large-workspace
/// scalability.
class LibraryRepository {
  LibraryRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
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
      position: await _nextNotebookPosition(),
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
  Future<Section?> findSection(String id) async {
    final rows = _db.select('SELECT * FROM sections WHERE id = ?', <Object?>[
      id,
    ]);
    return rows.isEmpty ? null : _section(rows.first);
  }

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
      position: await _nextSectionPosition(notebookId, parentId),
      createdAt: now,
      updatedAt: now,
      color: color,
    );
    _db.run(
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
    if (parentId != null && await _isDescendantOrSelf(parentId, sectionId)) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'a section cannot be moved inside itself',
      );
    }
    final target = position ?? await _nextSectionPosition(notebookId, parentId);
    _db.transaction(() {
      _db.run(
        'UPDATE sections SET notebook_id = ?, parent_id = ?, position = ?, '
        'updated_at = ? WHERE id = ?',
        <Object?>[notebookId, parentId, target, _now, sectionId],
      );
      // Descendants follow their parent to the new notebook.
      _db.run(
        'WITH RECURSIVE subtree(id) AS ('
        '  SELECT id FROM sections WHERE parent_id = ?'
        '  UNION ALL'
        '  SELECT s.id FROM sections s JOIN subtree ON s.parent_id = subtree.id'
        ') '
        'UPDATE sections SET notebook_id = ? WHERE id IN (SELECT id FROM subtree)',
        <Object?>[sectionId, notebookId],
      );
    });
  }

  /// Moves a section and its subtree to the recycle bin.
  Future<void> deleteSection(String id) async {
    _db.run('UPDATE sections SET deleted_at = ? WHERE id = ?', <Object?>[
      _now,
      id,
    ]);
  }

  /// Restores a section from the recycle bin.
  Future<void> restoreSection(String id) async {
    _db.run(
      'UPDATE sections SET deleted_at = NULL, updated_at = ? WHERE id = ?',
      <Object?>[_now, id],
    );
  }

  /// Whether [candidate] is [ancestor] or sits anywhere beneath it.
  Future<bool> _isDescendantOrSelf(String candidate, String ancestor) async {
    if (candidate == ancestor) return true;
    final rows = _db.select(
      'WITH RECURSIVE ancestors(id, parent_id) AS ('
      '  SELECT id, parent_id FROM sections WHERE id = ?'
      '  UNION ALL'
      '  SELECT s.id, s.parent_id FROM sections s '
      '    JOIN ancestors a ON s.id = a.parent_id'
      ') SELECT 1 FROM ancestors WHERE id = ? LIMIT 1',
      <Object?>[candidate, ancestor],
    );
    return rows.isNotEmpty;
  }

  Future<double> _nextSectionPosition(
    String notebookId,
    String? parentId,
  ) async {
    final rows = parentId == null
        ? _db.select(
            'SELECT MAX(position) AS m FROM sections '
            'WHERE notebook_id = ? AND parent_id IS NULL',
            <Object?>[notebookId],
          )
        : _db.select(
            'SELECT MAX(position) AS m FROM sections '
            'WHERE notebook_id = ? AND parent_id = ?',
            <Object?>[notebookId, parentId],
          );
    final max = rows.first['m'];
    return max == null ? 0 : FractionalIndex.after((max as num).toDouble());
  }

  Future<double> _nextNotebookPosition() async {
    final rows = _db.select('SELECT MAX(position) AS m FROM notebooks');
    final max = rows.first['m'];
    return max == null ? 0 : FractionalIndex.after((max as num).toDouble());
  }

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
