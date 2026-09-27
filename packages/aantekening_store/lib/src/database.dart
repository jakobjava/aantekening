/// The database connection: pragmas, statement caching and transactions.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// A tuned SQLite connection with a prepared-statement cache.
///
/// This is the only place that talks to sqlite3 directly. Repositories go
/// through it so that connection settings, statement reuse and transaction
/// nesting are decided once.
class AantekeningDatabase {
  AantekeningDatabase._(this._db);

  /// Opens (or creates) the database at [path].
  factory AantekeningDatabase.open(String path) =>
      AantekeningDatabase._(sqlite3.open(path)).._configure(persistent: true);

  /// Opens a throwaway in-memory database, used by tests and previews.
  factory AantekeningDatabase.inMemory() =>
      AantekeningDatabase._(sqlite3.openInMemory())
        .._configure(persistent: false);

  final Database _db;
  final Map<String, PreparedStatement> _statements =
      <String, PreparedStatement>{};

  int _transactionDepth = 0;
  bool _closed = false;

  /// The underlying connection, for queries that need the raw API.
  Database get raw => _db;

  /// Sets the connection up, or closes it if it cannot be: a database too
  /// damaged to set up must not stay open, or Windows will not let it be
  /// moved aside.
  void _configure({required bool persistent}) {
    try {
      _setUp(persistent: persistent);
    } catch (_) {
      _db.close();
      rethrow;
    }
  }

  void _setUp({required bool persistent}) {
    if (persistent) {
      // WAL lets reads proceed while a save is in flight, which is what keeps
      // typing responsive during an autosave.
      _db.execute('PRAGMA journal_mode = WAL;');
      // Every committed change reaches the disk before the commit returns,
      // so not even a power cut loses what was saved: the notes folder is
      // written from here, and must not be written from what then vanishes.
      _db.execute('PRAGMA synchronous = FULL;');
      _db.execute('PRAGMA mmap_size = 268435456;'); // 256 MiB
    }
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA temp_store = MEMORY;');
    _db.execute('PRAGMA cache_size = -32000;'); // 32 MiB page cache
    _db.execute('PRAGMA busy_timeout = 5000;');

    _assertFts5Available();
    Schema.migrate(_db);
  }

  /// Full-text search is not optional, so fail loudly at startup rather than
  /// with an obscure "no such module" when the user first searches.
  void _assertFts5Available() {
    try {
      _db.execute('CREATE VIRTUAL TABLE temp.fts5_probe USING fts5(probe);');
      _db.execute('DROP TABLE temp.fts5_probe;');
    } on SqliteException catch (error) {
      throw StateError(
        'This SQLite build lacks the FTS5 module, which aantekening requires '
        'for search: ${error.message}',
      );
    }
  }

  /// Returns a cached prepared statement for [sql].
  ///
  /// Reusing statements skips re-parsing and re-planning on every call, which
  /// matters most for the per-keystroke queries: search and autosave.
  PreparedStatement statement(String sql) =>
      _statements[sql] ??= _db.prepare(sql, persistent: true);

  /// Runs a query and returns its rows.
  ResultSet select(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) => statement(sql).select(parameters);

  /// Runs a statement that returns no rows.
  void run(String sql, [List<Object?> parameters = const <Object?>[]]) =>
      statement(sql).execute(parameters);

  /// [id] and the rows beneath it in [table], which nests its rows through
  /// its `parent_id` column, parents before what lies beneath them: every
  /// one, only the live ones with [live], or only those deleted at
  /// [deletedAt] — deleted along with it.
  List<String> subtree(
    String table,
    String id, {
    bool live = false,
    int? deletedAt,
  }) {
    final condition = live
        ? 'WHERE t.deleted_at IS NULL'
        : deletedAt != null
        ? 'WHERE t.deleted_at = ?'
        : '';
    final rows = select(
      'WITH RECURSIVE subtree(id, depth) AS ('
      '  SELECT ?, 0'
      '  UNION ALL'
      '  SELECT t.id, s.depth + 1 FROM $table t '
      '  JOIN subtree s ON t.parent_id = s.id $condition'
      ') SELECT id FROM subtree ORDER BY depth',
      <Object?>[id, ?deletedAt],
    );
    return <String>[for (final row in rows) row['id'] as String];
  }

  /// The position after every row of [table] matching [where], for a row
  /// added at the end of them.
  double nextPosition(String table, String where, List<Object?> parameters) {
    final max = select(
      'SELECT MAX(position) AS m FROM $table WHERE $where',
      parameters,
    ).first['m'];
    return max == null ? 0 : FractionalIndex.after((max as num).toDouble());
  }

  /// Runs [body] inside a transaction, rolling back if it throws.
  ///
  /// Nested calls reuse the outermost transaction via savepoints, so a
  /// repository method that needs atomicity can be called on its own or as part
  /// of a larger unit of work without either caller knowing about the other.
  T transaction<T>(T Function() body) {
    final depth = _transactionDepth;
    final savepoint = 'sp_$depth';
    _db.execute(depth == 0 ? 'BEGIN' : 'SAVEPOINT $savepoint');
    _transactionDepth = depth + 1;
    try {
      final result = body();
      _db.execute(depth == 0 ? 'COMMIT' : 'RELEASE $savepoint');
      return result;
    } catch (_) {
      _db.execute(depth == 0 ? 'ROLLBACK' : 'ROLLBACK TO $savepoint');
      rethrow;
    } finally {
      _transactionDepth = depth;
    }
  }

  /// Whether the app that last had the database open closed it, rather
  /// than stopping with it open.
  bool get closedCleanly {
    final rows = select("SELECT value FROM meta WHERE key = 'session'");
    return rows.isEmpty || rows.first['value'] != 'open';
  }

  /// Whether SQLite finds the database whole. Slow on a large one: asked
  /// only after it was not closed cleanly.
  bool get isIntact {
    final rows = _db.select('PRAGMA quick_check;');
    return rows.length == 1 && rows.first.values.first == 'ok';
  }

  void markOpen() => _db.execute(
    "INSERT INTO meta (key, value) VALUES ('session', 'open') "
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value;',
  );

  void markClosed() => _db.execute(
    "INSERT INTO meta (key, value) VALUES ('session', 'closed') "
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value;',
  );

  /// Reclaims space and rebuilds statistics.
  ///
  /// Worth running occasionally after bulk deletions; it rewrites the file, so
  /// it is never on a hot path.
  void compact() {
    _db.execute('PRAGMA incremental_vacuum;');
    _db.execute('ANALYZE;');
  }

  /// Closes the connection and disposes every cached statement.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final statement in _statements.values) {
      statement.close();
    }
    _statements.clear();
    _db.close();
  }
}
