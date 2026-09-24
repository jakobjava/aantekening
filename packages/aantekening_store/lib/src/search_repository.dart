/// Full-text search across the workspace.
library;

import 'package:aantekening_core/aantekening_core.dart';

import 'database.dart';
import 'fts_query.dart';
import 'row_read.dart';

/// Delimiters wrapped around matched terms inside a snippet.
///
/// Non-printing control characters are used rather than markup so that a note
/// which itself contains `<mark>` cannot forge a highlight. The UI splits on
/// these when building the styled result text.
abstract final class SnippetMarkers {
  static const String start = '';
  static const String end = '';
  static const String ellipsis = '…';
}

/// Queries the FTS5 index.
class SearchRepository {
  SearchRepository(this._db);

  final AantekeningDatabase _db;

  /// Relative importance of a title match versus a body match in the ranking.
  ///
  /// A page called "Fourier transform" should outrank one that merely mentions
  /// the phrase in passing.
  static const double _titleWeight = 12;
  static const double _bodyWeight = 1;

  /// Searches page titles and contents for [query].
  ///
  /// Returns an empty list when [query] holds nothing searchable, rather than
  /// every page, so an empty search box shows no results instead of the whole
  /// workspace.
  Future<List<SearchHit>> search(
    String query, {
    int limit = 50,
    String? notebookId,
    String? sectionId,
    bool prefixLastTerm = true,
    bool matchAny = false,
  }) async {
    final match = FtsQuery.build(
      query,
      prefixLastTerm: prefixLastTerm,
      matchAny: matchAny,
    );
    if (match == null) return const <SearchHit>[];

    final filters = StringBuffer();
    final filterParameters = <Object?>[];
    if (notebookId != null) {
      filters.write(' AND s.notebook_id = ?');
      filterParameters.add(notebookId);
    }
    if (sectionId != null) {
      filters.write(' AND p.section_id = ?');
      filterParameters.add(sectionId);
    }

    final rows = _db.select(
      '''
      SELECT
        p.id           AS page_id,
        p.title        AS title,
        p.section_id   AS section_id,
        s.notebook_id  AS notebook_id,
        snippet(page_search, 1, ?, ?, ?, 14) AS snippet,
        bm25(page_search, $_titleWeight, $_bodyWeight) AS rank
      FROM page_search
      JOIN pages p     ON p.rowid = page_search.rowid
      JOIN sections s  ON s.id = p.section_id
      JOIN notebooks n ON n.id = s.notebook_id
      WHERE page_search MATCH ?
        AND p.deleted_at IS NULL
        AND s.deleted_at IS NULL
        AND n.deleted_at IS NULL
        $filters
      ORDER BY rank
      LIMIT ?
    ''',
      <Object?>[
        SnippetMarkers.start,
        SnippetMarkers.end,
        SnippetMarkers.ellipsis,
        match,
        ...filterParameters,
        limit,
      ],
    );

    return <SearchHit>[
      for (final row in rows)
        SearchHit(
          pageId: str(row, 'page_id'),
          title: str(row, 'title'),
          snippet: str(row, 'snippet'),
          // bm25 is negative and better the lower it is; flip it so callers can
          // treat score as "higher is more relevant".
          score: -real(row, 'rank'),
          sectionId: strOrNull(row, 'section_id'),
          notebookId: strOrNull(row, 'notebook_id'),
        ),
    ];
  }

  /// Counts the pages matching [query], for result summaries.
  Future<int> count(String query, {String? notebookId}) async {
    final match = FtsQuery.build(query);
    if (match == null) return 0;

    final rows = notebookId == null
        ? _db.select(
            'SELECT COUNT(*) AS c FROM page_search '
            'JOIN pages p ON p.rowid = page_search.rowid '
            'WHERE page_search MATCH ? AND p.deleted_at IS NULL',
            <Object?>[match],
          )
        : _db.select(
            'SELECT COUNT(*) AS c FROM page_search '
            'JOIN pages p ON p.rowid = page_search.rowid '
            'JOIN sections s ON s.id = p.section_id '
            'WHERE page_search MATCH ? AND p.deleted_at IS NULL '
            'AND s.notebook_id = ?',
            <Object?>[match, notebookId],
          );
    return integer(rows.first, 'c');
  }
}
