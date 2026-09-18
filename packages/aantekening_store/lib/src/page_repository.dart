/// Reads and writes pages: their metadata, their JSON bodies and the derived
/// search index.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'row_read.dart';

/// How a page body is stored in the `page_bodies` table.
abstract final class BodyEncoding {
  static const String json = 'json';
  static const String gzippedJson = 'json+gzip';

  /// Bodies at least this large are compressed.
  ///
  /// Below roughly this size gzip's header and the round trip cost more than
  /// the space they save, and short pages are exactly the ones that must open
  /// instantly.
  static const int compressionThreshold = 4096;
}

/// Stores pages and keeps the full-text index in step with them.
class PageRepository {
  PageRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final DateTime Function() _clock;

  /// How much of a page's text is kept as the list preview.
  static const int previewLength = 240;

  int get _now => _clock().millisecondsSinceEpoch;

  // -------------------------------------------------------------- page lookup

  /// Lists the pages of [sectionId], or the subpages of [parentId] when given.
  Future<List<PageRef>> listPages(
    String sectionId, {
    String? parentId,
    bool topLevelOnly = false,
    bool includeDeleted = false,
  }) async {
    final deletedClause = includeDeleted ? '' : 'AND deleted_at IS NULL ';
    final ResultSet rows;
    if (parentId != null) {
      rows = _db.select(
        'SELECT * FROM pages WHERE section_id = ? AND parent_id = ? '
        '$deletedClause ORDER BY position, id',
        <Object?>[sectionId, parentId],
      );
    } else if (topLevelOnly) {
      rows = _db.select(
        'SELECT * FROM pages WHERE section_id = ? AND parent_id IS NULL '
        '$deletedClause ORDER BY position, id',
        <Object?>[sectionId],
      );
    } else {
      rows = _db.select(
        'SELECT * FROM pages WHERE section_id = ? '
        '$deletedClause ORDER BY position, id',
        <Object?>[sectionId],
      );
    }
    return <PageRef>[for (final row in rows) _pageRef(row)];
  }

  /// Fetches a page's metadata, or null when it does not exist.
  Future<PageRef?> findPage(String id) async => _findPage(id);

  /// Every live page whose section and notebook are live too: the whole
  /// workspace, for views that show all of it at once.
  Future<List<PageRef>> listAllPages() async {
    final rows = _db.select(
      'SELECT p.* FROM pages p '
      'JOIN sections s ON s.id = p.section_id '
      'JOIN notebooks n ON n.id = s.notebook_id '
      'WHERE p.deleted_at IS NULL AND s.deleted_at IS NULL '
      'AND n.deleted_at IS NULL '
      'ORDER BY p.position, p.id',
    );
    return <PageRef>[for (final row in rows) _pageRef(row)];
  }

  /// The most recently edited pages across the whole workspace.
  Future<List<PageRef>> recentPages({int limit = 20}) async {
    final rows = _db.select(
      // Timestamps are millisecond-granular, so two pages saved in the same
      // tick would otherwise come back in arbitrary order and the list would
      // reshuffle between reads. Identifiers are ULIDs, so `id DESC` is a
      // stable tiebreak that still reads as newest-first.
      'SELECT * FROM pages WHERE deleted_at IS NULL '
      'ORDER BY updated_at DESC, id DESC LIMIT ?',
      <Object?>[limit],
    );
    return <PageRef>[for (final row in rows) _pageRef(row)];
  }

  // ------------------------------------------------------------ page creation

  /// Creates an empty page at the end of [sectionId].
  Future<PageRef> createPage({
    required String sectionId,
    String title = '',
    String? parentId,
  }) async {
    final now = _now;
    final page = PageRef(
      id: Ulid.generate(),
      sectionId: sectionId,
      title: title,
      position: _nextPagePosition(sectionId, parentId),
      createdAt: now,
      updatedAt: now,
      parentId: parentId,
    );
    _db.transaction(() {
      _db.run(
        'INSERT INTO pages '
        '(id, section_id, parent_id, title, position, preview, revision, '
        ' color, created_at, updated_at, deleted_at) '
        "VALUES (?, ?, ?, ?, ?, '', 0, NULL, ?, ?, NULL)",
        <Object?>[
          page.id,
          page.sectionId,
          page.parentId,
          page.title,
          page.position,
          page.createdAt,
          page.updatedAt,
        ],
      );
      _writeBody(page.id, PageDocument.empty(id: page.id));
      _reindex(page.id, page.title, '');
    });
    return page;
  }

  // ------------------------------------------------------------ page contents

  /// Loads a page's document, or null when the page has no body.
  Future<PageDocument?> loadDocument(String pageId) async =>
      _readDocument(pageId);

  PageDocument? _readDocument(String pageId) {
    final rows = _db.select(
      'SELECT encoding, body FROM page_bodies WHERE page_id = ?',
      <Object?>[pageId],
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final bytes = row['body'] as List<int>;
    final encoding = str(row, 'encoding');
    final source = switch (encoding) {
      BodyEncoding.gzippedJson => utf8.decode(gzip.decode(bytes)),
      BodyEncoding.json => utf8.decode(bytes),
      _ => throw PageFormatException('Unknown body encoding "$encoding"'),
    };
    return PageDocument.decode(source);
  }

  /// Saves [document] as the contents of [pageId].
  ///
  /// The body, the page's metadata, its search-index entry and its asset links
  /// are updated in one transaction, so the index can never describe a version
  /// of the page that is not on disk.
  ///
  /// The title becomes [title] when one is given and is otherwise left as it
  /// is: a page's title is what it is named, in its title field or when it is
  /// renamed, never something taken from its text.
  Future<PageRef> saveDocument(
    String pageId,
    PageDocument document, {
    String? title,
  }) async {
    final text = document.extractSearchText();
    final preview = _buildPreview(text);
    final now = _now;

    return _db.transaction(() {
      // Read in the same transaction as the write, so a rename made while
      // this save was on its way is kept rather than written over.
      final existing = _findPage(pageId);
      if (existing == null) {
        throw StateError('Cannot save unknown page $pageId');
      }
      final resolvedTitle = title ?? existing.title;
      _writeBody(pageId, document);
      _db.run(
        'UPDATE pages SET title = ?, preview = ?, revision = ?, updated_at = ? '
        'WHERE id = ?',
        <Object?>[resolvedTitle, preview, document.revision, now, pageId],
      );
      _reindex(pageId, resolvedTitle, text);
      _syncAssets(pageId, document.referencedAssetIds);
      return existing.copyWith(
        title: resolvedTitle,
        preview: preview,
        revision: document.revision,
        updatedAt: now,
      );
    });
  }

  /// Renames a page without touching its body.
  Future<void> renamePage(String pageId, String title) async {
    _db.transaction(() {
      _db.run(
        'UPDATE pages SET title = ?, updated_at = ? WHERE id = ?',
        <Object?>[title, _now, pageId],
      );
      final rowId = _rowIdOf(pageId);
      if (rowId == null) return;
      // Re-index with the stored body text so the title change is searchable
      // without decoding and re-extracting the whole document.
      final rows = _db.select(
        'SELECT body FROM page_search WHERE rowid = ?',
        <Object?>[rowId],
      );
      final body = rows.isEmpty ? '' : str(rows.first, 'body');
      _reindex(pageId, title, body);
    });
  }

  /// Sets the date and time shown beneath a page's title, as milliseconds
  /// since the epoch: when the page was created, until someone changes it, as
  /// OneNote lets them.
  Future<void> setPageDate(String pageId, int timestamp) async {
    _db.run(
      'UPDATE pages SET created_at = ?, updated_at = ? WHERE id = ?',
      <Object?>[timestamp, _now, pageId],
    );
  }

  // ------------------------------------------------------------- organisation

  /// Moves a page, with its subpages, into [sectionId]: under [parentId] when
  /// given, and after the page [after] when given, which must then be one of
  /// its new siblings; otherwise at the end.
  ///
  /// Throws [ArgumentError] when [parentId] is the page or one of its
  /// subpages, which would cut the page off from its section.
  Future<void> movePage(
    String pageId, {
    required String sectionId,
    String? parentId,
    String? after,
  }) async {
    _db.transaction(() {
      final subtree = _subtree(pageId);
      if (parentId != null && subtree.contains(parentId)) {
        throw ArgumentError.value(
          parentId,
          'parentId',
          'a page cannot become a subpage of itself',
        );
      }
      final position = _positionFor(sectionId, parentId, after);
      final now = _now;
      _db.run(
        'UPDATE pages SET section_id = ?, parent_id = ?, position = ?, '
        'updated_at = ? WHERE id = ?',
        <Object?>[sectionId, parentId, position, now, pageId],
      );
      // Subpages follow their page to its new section.
      for (final id in subtree.skip(1)) {
        _db.run(
          'UPDATE pages SET section_id = ?, updated_at = ? WHERE id = ?',
          <Object?>[sectionId, now, id],
        );
      }
    });
  }

  /// Copies a page, with its subpages, into [sectionId], placed as
  /// [movePage] places a page; returns the copy.
  ///
  /// The copy has the page's title, date and contents, and a new identity.
  Future<PageRef> copyPage(
    String pageId, {
    required String sectionId,
    String? parentId,
    String? after,
  }) async => _db.transaction(() {
    final source = _findPage(pageId);
    if (source == null) {
      throw ArgumentError.value(pageId, 'pageId', 'no such page');
    }
    return _copyTree(
      source,
      sectionId: sectionId,
      parentId: parentId,
      position: _positionFor(sectionId, parentId, after),
    );
  });

  /// Copies every live page of [fromSectionId] into [toSectionId], each with
  /// its subpages, in the same order: the pages of a section being copied.
  ///
  /// Synchronous so that copying a whole section can do it within its own
  /// transaction.
  void copySectionPages(String fromSectionId, String toSectionId) {
    _db.transaction(() {
      final rows = _db.select(
        'SELECT * FROM pages WHERE section_id = ? AND parent_id IS NULL '
        'AND deleted_at IS NULL ORDER BY position, id',
        <Object?>[fromSectionId],
      );
      for (final row in rows) {
        final page = _pageRef(row);
        _copyTree(
          page,
          sectionId: toSectionId,
          parentId: null,
          position: page.position,
        );
      }
    });
  }

  /// Moves a page and its subpages to the recycle bin and drops them out of
  /// search results. Returns the pages it deleted.
  Future<List<String>> deletePage(String pageId) async => _db.transaction(() {
    // Subpages deleted earlier keep their own time, so restoring this page
    // does not bring them back with it.
    final deleted = _subtree(pageId, live: true);
    final now = _now;
    for (final id in deleted) {
      _db.run('UPDATE pages SET deleted_at = ? WHERE id = ?', <Object?>[
        now,
        id,
      ]);
      final rowId = _rowIdOf(id);
      if (rowId != null) {
        _db.run('DELETE FROM page_search WHERE rowid = ?', <Object?>[rowId]);
      }
    }
    return deleted;
  });

  /// Restores a page from the recycle bin, with the subpages deleted along
  /// with it, and puts them back in the index.
  Future<void> restorePage(String pageId) async {
    final page = _findPage(pageId);
    final deletedAt = page?.deletedAt;
    if (page == null || deletedAt == null) return;

    _db.transaction(() {
      final now = _now;
      for (final id in _subtree(pageId, deletedAt: deletedAt)) {
        _db.run(
          'UPDATE pages SET deleted_at = NULL, updated_at = ? WHERE id = ?',
          <Object?>[now, id],
        );
        final restored = _findPage(id)!;
        _reindex(
          id,
          restored.title,
          _readDocument(id)?.extractSearchText() ?? '',
        );
      }
    });
  }

  /// Permanently removes a page and everything derived from it.
  Future<void> purgePage(String pageId) async {
    _db.transaction(() {
      final rowId = _rowIdOf(pageId);
      if (rowId != null) {
        _db.run('DELETE FROM page_search WHERE rowid = ?', <Object?>[rowId]);
      }
      // page_bodies, page_assets, page_tags and embeddings cascade.
      _db.run('DELETE FROM pages WHERE id = ?', <Object?>[pageId]);
    });
  }

  /// Rebuilds the entire full-text index from the stored bodies.
  ///
  /// Needed after changing how text is extracted, and as a repair path if the
  /// index is ever suspected of being stale.
  Future<int> rebuildSearchIndex() async {
    final rows = _db.select(
      'SELECT id, title FROM pages WHERE deleted_at IS NULL',
    );
    var count = 0;
    for (final row in rows) {
      final pageId = str(row, 'id');
      final document = await loadDocument(pageId);
      if (document == null) continue;
      _db.transaction(() {
        _reindex(pageId, str(row, 'title'), document.extractSearchText());
      });
      count++;
    }
    _db.run('INSERT INTO page_search(page_search) VALUES (?)', <Object?>[
      'optimize',
    ]);
    return count;
  }

  // ------------------------------------------------------------------ helpers

  void _writeBody(String pageId, PageDocument document) {
    final bytes = utf8.encode(document.encode());
    final compress = bytes.length >= BodyEncoding.compressionThreshold;
    final stored = compress ? gzip.encode(bytes) : bytes;
    _db.run(
      'INSERT INTO page_bodies (page_id, format_version, revision, encoding, body) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(page_id) DO UPDATE SET '
      '  format_version = excluded.format_version, '
      '  revision = excluded.revision, '
      '  encoding = excluded.encoding, '
      '  body = excluded.body',
      <Object?>[
        pageId,
        PageDocument.currentFormatVersion,
        document.revision,
        compress ? BodyEncoding.gzippedJson : BodyEncoding.json,
        stored,
      ],
    );
  }

  /// Replaces a page's search-index entry.
  ///
  /// The FTS table is keyed by `pages.rowid`, so this is a primary-key delete
  /// plus an insert instead of a scan for the page's text identifier.
  void _reindex(String pageId, String title, String body) {
    final rowId = _rowIdOf(pageId);
    if (rowId == null) return;
    _db.run('DELETE FROM page_search WHERE rowid = ?', <Object?>[rowId]);
    _db.run(
      'INSERT INTO page_search(rowid, title, body) VALUES (?, ?, ?)',
      <Object?>[rowId, title, body],
    );
  }

  void _syncAssets(String pageId, Set<String> assetIds) {
    _db.run('DELETE FROM page_assets WHERE page_id = ?', <Object?>[pageId]);
    for (final assetId in assetIds) {
      _db.run(
        'INSERT OR IGNORE INTO page_assets (page_id, asset_id) VALUES (?, ?)',
        <Object?>[pageId, assetId],
      );
    }
  }

  int? _rowIdOf(String pageId) {
    final rows = _db.select(
      'SELECT rowid AS rid FROM pages WHERE id = ?',
      <Object?>[pageId],
    );
    return rows.isEmpty ? null : integer(rows.first, 'rid');
  }

  PageRef? _findPage(String id) {
    final rows = _db.select('SELECT * FROM pages WHERE id = ?', <Object?>[id]);
    return rows.isEmpty ? null : _pageRef(rows.first);
  }

  /// [pageId] and the pages beneath it, parents before their subpages: every
  /// one, only the live ones with [live], or only those deleted at
  /// [deletedAt] — deleted along with it.
  List<String> _subtree(String pageId, {bool live = false, int? deletedAt}) {
    final condition = live
        ? 'WHERE p.deleted_at IS NULL'
        : deletedAt != null
        ? 'WHERE p.deleted_at = ?'
        : '';
    final rows = _db.select(
      'WITH RECURSIVE subtree(id, depth) AS ('
      '  SELECT ?, 0'
      '  UNION ALL'
      '  SELECT p.id, s.depth + 1 FROM pages p '
      '  JOIN subtree s ON p.parent_id = s.id $condition'
      ') SELECT id FROM subtree ORDER BY depth',
      <Object?>[pageId, ?deletedAt],
    );
    return <String>[for (final row in rows) str(row, 'id')];
  }

  /// Where a page goes among the pages of [sectionId] under [parentId]: after
  /// the page [after], before whichever came next, or else at the end.
  double _positionFor(String sectionId, String? parentId, String? after) {
    if (after == null) return _nextPagePosition(sectionId, parentId);
    final anchor = _findPage(after);
    if (anchor == null) {
      throw ArgumentError.value(after, 'after', 'no such page');
    }
    final rows = _db.select(
      'SELECT MIN(position) AS m FROM pages WHERE section_id = ? '
      'AND parent_id IS ? AND position > ? AND deleted_at IS NULL',
      <Object?>[sectionId, parentId, anchor.position],
    );
    final next = rows.first['m'];
    return FractionalIndex.insert(
      previous: anchor.position,
      next: next == null ? null : (next as num).toDouble(),
    );
  }

  /// Copies [source] and its live subpages to [sectionId], under [parentId]
  /// at [position]; subpages keep their order beneath the copy.
  PageRef _copyTree(
    PageRef source, {
    required String sectionId,
    required String? parentId,
    required double position,
  }) {
    // Listed before the copy is made, which may itself be one of them when a
    // page is copied beneath one of its own subpages.
    final children = <PageRef>[
      for (final row in _db.select(
        'SELECT * FROM pages WHERE parent_id = ? AND deleted_at IS NULL '
        'ORDER BY position, id',
        <Object?>[source.id],
      ))
        _pageRef(row),
    ];
    final copy = PageRef(
      id: Ulid.generate(),
      sectionId: sectionId,
      parentId: parentId,
      title: source.title,
      position: position,
      preview: source.preview,
      revision: source.revision,
      color: source.color,
      createdAt: source.createdAt,
      updatedAt: _now,
    );
    _db.run(
      'INSERT INTO pages '
      '(id, section_id, parent_id, title, position, preview, revision, '
      ' color, created_at, updated_at, deleted_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)',
      <Object?>[
        copy.id,
        copy.sectionId,
        copy.parentId,
        copy.title,
        copy.position,
        copy.preview,
        copy.revision,
        copy.color,
        copy.createdAt,
        copy.updatedAt,
      ],
    );
    final document = _readDocument(source.id);
    final body = PageDocument(
      id: copy.id,
      revision: document?.revision ?? 0,
      canvas: document?.canvas ?? CanvasSettings.defaults,
      elements: document?.elements ?? const <NoteElement>[],
    );
    _writeBody(copy.id, body);
    _reindex(copy.id, copy.title, body.extractSearchText());
    _syncAssets(copy.id, body.referencedAssetIds);
    _db.run(
      'INSERT INTO page_tags (page_id, tag_id) '
      'SELECT ?, tag_id FROM page_tags WHERE page_id = ?',
      <Object?>[copy.id, source.id],
    );

    for (final child in children) {
      _copyTree(
        child,
        sectionId: sectionId,
        parentId: copy.id,
        position: child.position,
      );
    }
    return copy;
  }

  double _nextPagePosition(String sectionId, String? parentId) {
    final rows = parentId == null
        ? _db.select(
            'SELECT MAX(position) AS m FROM pages '
            'WHERE section_id = ? AND parent_id IS NULL',
            <Object?>[sectionId],
          )
        : _db.select(
            'SELECT MAX(position) AS m FROM pages WHERE parent_id = ?',
            <Object?>[parentId],
          );
    final max = rows.first['m'];
    return max == null ? 0 : FractionalIndex.after((max as num).toDouble());
  }

  static String _buildPreview(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length <= previewLength
        ? collapsed
        : '${collapsed.substring(0, previewLength)}…';
  }

  static PageRef _pageRef(Row row) => PageRef(
    id: str(row, 'id'),
    sectionId: str(row, 'section_id'),
    title: str(row, 'title'),
    position: real(row, 'position'),
    createdAt: integer(row, 'created_at'),
    updatedAt: integer(row, 'updated_at'),
    parentId: strOrNull(row, 'parent_id'),
    preview: str(row, 'preview'),
    revision: integer(row, 'revision'),
    color: intOrNull(row, 'color'),
    deletedAt: intOrNull(row, 'deleted_at'),
  );
}
