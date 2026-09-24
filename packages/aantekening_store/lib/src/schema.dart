/// The SQLite schema and its forward migrations.
library;

import 'package:sqlite3/sqlite3.dart';

/// Applies and upgrades the database schema.
///
/// The schema version is tracked in SQLite's own `user_version` pragma, so no
/// bootstrap table is needed and an empty file and a current database take the
/// same code path.
abstract final class Schema {
  /// The schema version this build expects.
  static const int version = 3;

  /// Migrations indexed by the version they produce.
  ///
  /// Each entry runs inside the caller's transaction and must be additive or
  /// self-contained; to change an existing table, create the new one, copy the
  /// rows across and drop the old one within the same migration.
  static final List<void Function(Database db)> _migrations =
      <void Function(Database db)>[_v1, _v2, _v3];

  /// Brings [db] up to [version], running only the migrations it still needs.
  ///
  /// Throws [StateError] if the file was written by a newer build, which would
  /// otherwise risk silent data loss.
  static void migrate(Database db) {
    final current = db.userVersion;
    if (current > version) {
      throw StateError(
        'Database schema v$current was written by a newer version of '
        'aantekening; this build understands up to v$version.',
      );
    }
    if (current == version) return;

    db.execute('BEGIN');
    try {
      for (var next = current; next < version; next++) {
        _migrations[next](db);
      }
      db.userVersion = version;
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The initial schema.
  static void _v1(Database db) {
    db.execute('''
      CREATE TABLE notebooks (
        id          TEXT    PRIMARY KEY,
        title       TEXT    NOT NULL,
        position    REAL    NOT NULL,
        color       INTEGER,
        icon        TEXT,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        deleted_at  INTEGER
      ) STRICT;
    ''');
    db.execute(
      'CREATE INDEX idx_notebooks_order ON notebooks(deleted_at, position);',
    );

    // parent_id makes sections self-nesting, so subsections (and deeper) are
    // one recursive table rather than a table per level.
    db.execute('''
      CREATE TABLE sections (
        id          TEXT    PRIMARY KEY,
        notebook_id TEXT    NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
        parent_id   TEXT             REFERENCES sections(id)  ON DELETE CASCADE,
        title       TEXT    NOT NULL,
        position    REAL    NOT NULL,
        color       INTEGER,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        deleted_at  INTEGER
      ) STRICT;
    ''');
    db.execute('''
      CREATE INDEX idx_sections_siblings
        ON sections(notebook_id, parent_id, deleted_at, position);
    ''');

    db.execute('''
      CREATE TABLE pages (
        id          TEXT    PRIMARY KEY,
        section_id  TEXT    NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
        parent_id   TEXT             REFERENCES pages(id)    ON DELETE CASCADE,
        title       TEXT    NOT NULL,
        position    REAL    NOT NULL,
        preview     TEXT    NOT NULL DEFAULT '',
        revision    INTEGER NOT NULL DEFAULT 0,
        color       INTEGER,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL,
        deleted_at  INTEGER
      ) STRICT;
    ''');
    db.execute('''
      CREATE INDEX idx_pages_siblings
        ON pages(section_id, parent_id, deleted_at, position);
    ''');
    db.execute('''
      CREATE INDEX idx_pages_recent
        ON pages(deleted_at, updated_at DESC, id DESC);
    ''');

    // Bodies live in their own table so that listing and navigating notebooks
    // never pulls page contents into memory: a query over `pages` touches only
    // small rows, and SQLite never has to skip past multi-megabyte blobs.
    db.execute('''
      CREATE TABLE page_bodies (
        page_id        TEXT    PRIMARY KEY REFERENCES pages(id) ON DELETE CASCADE,
        format_version INTEGER NOT NULL,
        revision       INTEGER NOT NULL,
        encoding       TEXT    NOT NULL,
        body           BLOB    NOT NULL
      ) STRICT;
    ''');

    // Assets are content-addressed: importing the same PDF into ten pages
    // stores one copy, and the unique hash makes deduplication a single insert.
    db.execute('''
      CREATE TABLE assets (
        id            TEXT    PRIMARY KEY,
        sha256        TEXT    NOT NULL UNIQUE,
        mime_type     TEXT    NOT NULL,
        byte_size     INTEGER NOT NULL,
        original_name TEXT,
        created_at    INTEGER NOT NULL
      ) STRICT;
    ''');
    db.execute('''
      CREATE TABLE page_assets (
        page_id  TEXT NOT NULL REFERENCES pages(id)  ON DELETE CASCADE,
        asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        PRIMARY KEY (page_id, asset_id)
      ) STRICT;
    ''');
    db.execute('CREATE INDEX idx_page_assets_asset ON page_assets(asset_id);');

    // The FTS index is keyed by `pages.rowid`, so updating a page's entry is a
    // primary-key delete plus an insert rather than a scan for its page id.
    db.execute('''
      CREATE VIRTUAL TABLE page_search USING fts5(
        title,
        body,
        tokenize = 'unicode61 remove_diacritics 2'
      );
    ''');

    db.execute('''
      CREATE TABLE tags (
        id    TEXT PRIMARY KEY,
        name  TEXT NOT NULL,
        color INTEGER
      ) STRICT;
    ''');
    db.execute('CREATE UNIQUE INDEX idx_tags_name ON tags(name);');
    db.execute('''
      CREATE TABLE page_tags (
        page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
        tag_id  TEXT NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
        PRIMARY KEY (page_id, tag_id)
      ) STRICT;
    ''');
    db.execute('CREATE INDEX idx_page_tags_tag ON page_tags(tag_id);');

    // Semantic search: one row per chunk of a page, embedded by a locally run
    // model. Vectors are raw little-endian float32 blobs so they can be scored
    // without a per-row decode.
    db.execute('''
      CREATE TABLE embeddings (
        page_id     TEXT    NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
        chunk_index INTEGER NOT NULL,
        model       TEXT    NOT NULL,
        dimensions  INTEGER NOT NULL,
        vector      BLOB    NOT NULL,
        text        TEXT    NOT NULL,
        created_at  INTEGER NOT NULL,
        PRIMARY KEY (page_id, chunk_index, model)
      ) STRICT;
    ''');

    db.execute('''
      CREATE TABLE meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      ) STRICT;
    ''');
  }

  /// What the AI makes, kept apart from the notes: conversations about a
  /// notebook, section or page, and what of them was kept.
  ///
  /// Nothing here is part of a page, and nothing a page holds comes from
  /// here: the notes are only ever what the person wrote. A conversation or
  /// a kept answer belongs to the notebook, section or page it is about,
  /// named by `scope_kind` and `scope_id` rather than by a foreign key, since
  /// that may be any of three tables.
  static void _v2(Database db) {
    db.execute('''
      CREATE TABLE ai_threads (
        id         TEXT    PRIMARY KEY,
        scope_kind TEXT    NOT NULL
                   CHECK (scope_kind IN ('notebook', 'section', 'page')),
        scope_id   TEXT    NOT NULL,
        title      TEXT    NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      ) STRICT;
    ''');
    db.execute(
      'CREATE INDEX idx_ai_threads_scope '
      'ON ai_threads(scope_kind, scope_id, updated_at);',
    );

    // One question and its answer. `messages` is the turn as the model had
    // it, to go on from; `answer` is what was shown.
    db.execute('''
      CREATE TABLE ai_turns (
        id         TEXT    PRIMARY KEY,
        thread_id  TEXT    NOT NULL REFERENCES ai_threads(id) ON DELETE CASCADE,
        position   INTEGER NOT NULL,
        question   TEXT    NOT NULL,
        answer     TEXT    NOT NULL,
        messages   TEXT    NOT NULL,
        provider   TEXT    NOT NULL,
        model      TEXT    NOT NULL,
        usage      TEXT,
        created_at INTEGER NOT NULL
      ) STRICT;
    ''');
    db.execute(
      'CREATE INDEX idx_ai_turns_thread ON ai_turns(thread_id, position);',
    );

    // What was kept to come back to: a summary, flashcards, an answer.
    db.execute('''
      CREATE TABLE ai_items (
        id         TEXT    PRIMARY KEY,
        scope_kind TEXT    NOT NULL
                   CHECK (scope_kind IN ('notebook', 'section', 'page')),
        scope_id   TEXT    NOT NULL,
        kind       TEXT    NOT NULL,
        title      TEXT    NOT NULL,
        body       TEXT    NOT NULL,
        turn_id    TEXT    REFERENCES ai_turns(id) ON DELETE SET NULL,
        provider   TEXT    NOT NULL,
        model      TEXT    NOT NULL,
        position   REAL    NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      ) STRICT;
    ''');
    db.execute(
      'CREATE INDEX idx_ai_items_scope '
      'ON ai_items(scope_kind, scope_id, position);',
    );
  }

  static void _v3(Database db) {
    // How each card of a set of flashcards is learnt: when it is due, and
    // what the spacing of its reviews has come to, as JSON the AI package
    // reads. Kept apart from the set, so remaking or editing the set does
    // not lose it.
    db.execute('''
      CREATE TABLE ai_reviews (
        item_id    TEXT    NOT NULL REFERENCES ai_items(id) ON DELETE CASCADE,
        card_id    TEXT    NOT NULL,
        state      TEXT    NOT NULL,
        due_at     INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, card_id)
      ) STRICT;
    ''');
  }
}
