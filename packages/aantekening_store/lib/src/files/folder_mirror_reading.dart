part of 'folder_mirror.dart';

/// Reading into the database what changed in the folder: each file changed
/// since, parents before what they hold, with the triggers paused; a copy a
/// sync service made kept as a page of its own; a file gone missing written
/// again.
extension _Reading on FolderMirror {
  /// Reads every file changed by another copy of the notes, as
  /// [FolderMirror.scan] says.
  Future<FolderChanges> _readChanged() async {
    if (!folder.isAvailable) {
      _report('The notes folder cannot be found: ${folder.path}');
      return const FolderChanges();
    }
    _found = const FolderChanges();
    final damaged = <String>[];
    final seen = <String>{};
    final waiting = <_Arrival>[];
    // Listed away from the window, and checked against the records read in
    // one go: only what changed is read here.
    final listing = await away(_listing, folder.path, heavy: true);
    final records = _allRecords();

    for (final listed in listing) {
      seen.add(listed.key);
      // As it was last written or read here: nothing to do. Only a thing's
      // own file has a record; a sync service's copy of one never does.
      final record = records[listed.key];
      if (record != null &&
          record.size == listed.size &&
          record.modified == listed.modified) {
        continue;
      }
      final entry = folder.entryOf(listed);
      final path = entry.file.path;
      // One file that cannot be read — or put in — must not keep every
      // other from being read: it is said to be damaged, and left.
      try {
        final stat = entry.file.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        final bytes = NotesFolder.read(entry.file);
        if (bytes == null) continue;
        final digest = sha256.convert(bytes).toString();
        if (!entry.isCopy && record?.digest == digest) {
          _remember(path, entry.kind, entry.id!, stat, digest);
          continue;
        }
        final file = EntityFile.decode(bytes);
        if (file == null || file.kind != entry.kind) {
          damaged.add(path);
          continue;
        }
        if (entry.isCopy) {
          await _readCopy(entry, file);
        } else if (file.id == entry.id) {
          waiting.add(_Arrival(entry, file, stat, digest));
        } else {
          damaged.add(path);
        }
      } on Object {
        damaged.add(path);
      }
    }

    // Parents before what they hold; what cannot go in yet — its section
    // not arrived — waits for a later look.
    waiting.sort((a, b) => _order(a.file).compareTo(_order(b.file)));
    var progress = true;
    while (waiting.isNotEmpty && progress) {
      progress = false;
      for (final arrival in List.of(waiting)) {
        bool applied;
        try {
          applied = _apply(arrival);
        } on Object {
          damaged.add(arrival.path);
          applied = true;
        }
        if (applied) {
          waiting.remove(arrival);
          progress = true;
        }
      }
    }

    _rewriteMissing(records, seen);
    final found = FolderChanges(
      pages: _found.pages,
      library: _found.library,
      ai: _found.ai,
      damaged: damaged,
    );
    if (!found.isEmpty && !_changes.isClosed) _changes.add(found);
    return found;
  }

  static List<ListedFile> _listing(String path) => NotesFolder.listing(path);

  static int _order(EntityFile file) => switch (file) {
    NotebookFile() => 0,
    SectionFile(:final section) => 1 + (section.parentId == null ? 0 : 1),
    PageFile(:final page) => 3 + (page.parentId == null ? 0 : 1),
    Tombstone(:final kind) => 10 - kind.index,
    RowsFile() => 6,
  };

  /// Puts what [arrival] brings into the database, reporting whether it
  /// could go in now.
  bool _apply(_Arrival arrival) {
    final file = arrival.file;
    final kind = file.kind;
    final pendingHere = _db.select(
      'SELECT 1 FROM mirror_outbox WHERE kind = ? AND id = ?',
      <Object?>[kind.name, file.id],
    ).isNotEmpty;
    if (pendingHere) {
      // Changed here too, and not yet written: this copy's version wins,
      // the other is kept as a page of its own when it is written over.
      return true;
    }
    if (!_canApply(file)) return false;
    _paused(() {
      switch (file) {
        case NotebookFile(:final notebook):
          _library.putNotebook(notebook);
          _found = _with(library: true);
        case SectionFile(:final section):
          _library.putSection(section);
          _found = _with(library: true);
        case PageFile():
          _pages.putPage(file);
          _found = _with(library: true, page: file.id);
        case RowsFile():
          _putRows(file);
          _found = _with(ai: true);
        case Tombstone(:final kind, :final id):
          switch (kind) {
            case EntityKind.notebook:
              _bin.purgeNotebook(id);
            case EntityKind.section:
              _bin.purgeSection(id);
            case EntityKind.page:
              _bin.purgePage(id);
            case EntityKind.thread:
              _db.run('DELETE FROM ai_threads WHERE id = ?', <Object?>[id]);
            case EntityKind.item:
              _db.run('DELETE FROM ai_items WHERE id = ?', <Object?>[id]);
          }
          _found = _with(library: true, ai: true);
      }
      _remember(arrival.path, kind, file.id, arrival.stat, arrival.digest);
    });
    return true;
  }

  FolderChanges _with({bool library = false, bool ai = false, String? page}) =>
      FolderChanges(
        pages: page == null ? _found.pages : <String>{..._found.pages, page},
        library: _found.library || library,
        ai: _found.ai || ai,
      );

  /// Whether what [file] belongs in is there for it to go into.
  bool _canApply(EntityFile file) {
    bool exists(String table, String? id) =>
        id == null ||
        _db.select('SELECT 1 FROM $table WHERE id = ?', <Object?>[
          id,
        ]).isNotEmpty;
    return switch (file) {
      SectionFile(:final section) =>
        exists('notebooks', section.notebookId) &&
            exists('sections', section.parentId),
      PageFile(:final page) =>
        exists('sections', page.sectionId) && exists('pages', page.parentId),
      _ => true,
    };
  }

  /// Runs [change] with the triggers paused, as one transaction.
  void _paused(void Function() change) {
    _db.transaction(() {
      _db.run("UPDATE mirror_control SET value = 1 WHERE key = 'paused'");
      try {
        change();
      } finally {
        _db.run("UPDATE mirror_control SET value = 0 WHERE key = 'paused'");
      }
    });
  }

  /// Puts a conversation and its turns, or a kept item and its reviews,
  /// in place of what the database has of it.
  void _putRows(RowsFile file) {
    final (table, children, column) = switch (file.kind) {
      EntityKind.thread => ('ai_threads', 'ai_turns', 'thread_id'),
      _ => ('ai_items', 'ai_reviews', 'item_id'),
    };
    _db.run('DELETE FROM $children WHERE $column = ?', <Object?>[file.id]);
    final row = <String, Object?>{...file.row};
    // A kept answer names the turn it came from, which may not be here.
    final turn = row['turn_id'];
    if (turn != null &&
        _db.select('SELECT 1 FROM ai_turns WHERE id = ?', <Object?>[
          turn,
        ]).isEmpty) {
      row['turn_id'] = null;
    }
    _insertRow(table, row, replace: true);
    for (final child in file.children) {
      _insertRow(children, child, replace: true);
    }
  }

  /// Inserts [row] into [table], taking only the columns [table] has.
  void _insertRow(
    String table,
    Map<String, Object?> row, {
    bool replace = false,
  }) {
    final columns = _columns[table] ??= <String>{
      for (final info in _db.select('PRAGMA table_info($table)'))
        str(info, 'name'),
    };
    final keys = row.keys.where(columns.contains).toList();
    if (keys.isEmpty) return;
    _db.run(
      'INSERT ${replace ? 'OR REPLACE ' : ''}INTO $table '
      '(${keys.join(', ')}) VALUES (${List.filled(keys.length, '?').join(', ')})',
      <Object?>[for (final key in keys) row[key]],
    );
  }

  /// Reads a copy a sync service made of a file: a page that differs from
  /// the page is kept as a page of its own; then the copy goes.
  Future<void> _readCopy(FolderEntry entry, EntityFile file) async {
    if (file is PageFile) {
      final ours = _pages.pageFile(file.id);
      if (ours == null ||
          ours.document.encode() != file.document.encode() ||
          ours.page.title != file.page.title) {
        // Kept by the triggers, so it is written as a file of its own.
        _found = _with(library: true, page: await _keepAsCopy(file));
      }
    }
    try {
      entry.file.deleteSync();
    } on FileSystemException {
      // Looked at again next time.
    }
  }

  /// Queues for writing again everything whose file was written or read
  /// here — [records] — but is not among the files [present] in the folder.
  void _rewriteMissing(Map<String, _Record> records, Set<String> present) {
    for (final MapEntry(key: path, value: record) in records.entries) {
      if (present.contains(path)) continue;
      _db.run('DELETE FROM mirror_files WHERE path = ?', <Object?>[path]);
      _db.run(
        'INSERT INTO mirror_outbox (kind, id, seq) VALUES (?, ?, '
        '(SELECT COALESCE(MAX(seq), 0) + 1 FROM mirror_outbox)) '
        'ON CONFLICT (kind, id) DO NOTHING',
        <Object?>[record.kind, record.id],
      );
    }
  }
}

/// A file read from the folder, waiting to go into the database.
final class _Arrival {
  _Arrival(this.entry, this.file, this.stat, this.digest);

  final FolderEntry entry;
  final EntityFile file;
  final FileStat stat;
  final String digest;

  String get path => entry.file.path;
}
