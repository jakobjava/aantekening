/// The database connection: pragmas, statement caching and transactions.
library;

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
  factory AantekeningDatabase.open(String path) {
    final db = AantekeningDatabase._(sqlite3.open(path));
    db._configure(persistent: true);
    return db;
  }

  /// Opens a throwaway in-memory database, used by tests and previews.
  factory AantekeningDatabase.inMemory() {
    final db = AantekeningDatabase._(sqlite3.openInMemory());
    db._configure(persistent: false);
    return db;
  }

  final Database _db;
  final Map<String, PreparedStatement> _statements =
      <String, PreparedStatement>{};

  int _transactionDepth = 0;
  bool _closed = false;

  /// The underlying connection, for queries that need the raw API.
  Database get raw => _db;

  void _configure({required bool persistent}) {
    if (persistent) {
      // WAL lets reads proceed while a save is in flight, which is what keeps
      // typing responsive during an autosave.
      _db.execute('PRAGMA journal_mode = WAL;');
      // NORMAL only risks losing the most recent transactions on an OS crash
      // (not on an app crash), which is the right trade for an autosaving
      // editor that writes constantly.
      _db.execute('PRAGMA synchronous = NORMAL;');
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
