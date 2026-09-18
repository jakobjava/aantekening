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
  Future<PageRef?> findPage(String id) async {
    final rows = _db.select('SELECT * FROM pages WHERE id = ?', <Object?>[id]);
    return rows.isEmpty ? null : _pageRef(rows.first);
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
      position: await _nextPagePosition(sectionId, parentId),
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
  Future<PageDocument?> loadDocument(String pageId) async {
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
  /// When [title] is null the existing title is kept unless it is blank, in
  /// which case one is derived from the page's first line — the same way
  /// OneNote titles a page you start typing into.
  Future<PageRef> saveDocument(
    String pageId,
    PageDocument document, {
    String? title,
  }) async {
    final existing = await findPage(pageId);
    if (existing == null) {
      throw StateError('Cannot save unknown page $pageId');
    }

    final text = document.extractSearchText();
    final preview = _buildPreview(text);
    final resolvedTitle =
        title ??
        (existing.title.trim().isEmpty ? _deriveTitle(text) : existing.title);
    final now = _now;

    return _db.transaction(() {
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

  // ------------------------------------------------------------- organisation

  /// Moves a page into [sectionId], optionally as a subpage of [parentId].
  Future<void> movePage(
    String pageId, {
    required String sectionId,
    String? parentId,
    double? position,
  }) async {
    if (parentId == pageId) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'a page cannot be its own subpage',
      );
    }
    final target = position ?? await _nextPagePosition(sectionId, parentId);
    _db.run(
      'UPDATE pages SET section_id = ?, parent_id = ?, position = ?, '
      'updated_at = ? WHERE id = ?',
      <Object?>[sectionId, parentId, target, _now, pageId],
    );
  }

  /// Moves a page to the recycle bin and drops it out of search results.
  Future<void> deletePage(String pageId) async {
    _db.transaction(() {
      _db.run('UPDATE pages SET deleted_at = ? WHERE id = ?', <Object?>[
        _now,
        pageId,
      ]);
      final rowId = _rowIdOf(pageId);
      if (rowId != null) {
        _db.run('DELETE FROM page_search WHERE rowid = ?', <Object?>[rowId]);
      }
    });
  }

  /// Restores a page from the recycle bin and puts it back in the index.
  Future<void> restorePage(String pageId) async {
    // Read the body before opening the transaction: `transaction` commits when
    // its callback returns, so an asynchronous body would commit early.
    final page = await findPage(pageId);
    if (page == null) return;
    final document = await loadDocument(pageId);
    final text = document?.extractSearchText() ?? '';

    _db.transaction(() {
      _db.run(
        'UPDATE pages SET deleted_at = NULL, updated_at = ? WHERE id = ?',
        <Object?>[_now, pageId],
      );
      _reindex(pageId, page.title, text);
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

  Future<double> _nextPagePosition(String sectionId, String? parentId) async {
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

  /// Uses the first non-empty line as the page title.
  static String _deriveTitle(String text) {
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length <= 80 ? trimmed : trimmed.substring(0, 80);
      }
    }
    return '';
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
