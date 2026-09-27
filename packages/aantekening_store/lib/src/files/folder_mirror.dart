/// Keeping the notes folder and the database in step, both ways.
library;

import 'dart:async';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../bin_repository.dart';
import '../database.dart';
import '../library_repository.dart';
import '../page_repository.dart';
import '../row_read.dart';
import 'entity_files.dart';
import 'notes_folder.dart';

/// What the mirror found in the folder that other copies of the notes had
/// changed, and put into the database.
final class FolderChanges {
  const FolderChanges({
    this.pages = const <String>{},
    this.library = false,
    this.ai = false,
    this.damaged = const <String>[],
  });

  /// Pages whose contents changed.
  final Set<String> pages;

  /// Whether any notebook, section or page was added, moved, renamed or
  /// deleted.
  final bool library;

  /// Whether a conversation or kept item changed.
  final bool ai;

  /// Files that could not be read, by path.
  final List<String> damaged;

  bool get isEmpty => pages.isEmpty && !library && !ai && damaged.isEmpty;
}

/// How the folder is doing: how much is waiting to be written to it, and
/// what went wrong last, if anything did.
final class MirrorStatus {
  const MirrorStatus({required this.pending, this.lastWritten, this.problem});

  final int pending;
  final DateTime? lastWritten;
  final String? problem;
}

/// Writes every change to the notes folder, and reads into the database
/// every change another copy of the notes — on another computer, through
/// a sync service — made to it.
///
/// Writing: triggers put each notebook, section, page, conversation and
/// kept item changed into an outbox in the transaction that changed it;
/// [flush] writes each one's file and takes it out. A file changed by
/// someone else since it was last written or read is not written over
/// blindly: a page in it that differs is kept, as a page of its own, first.
///
/// Reading: [scan] looks at every file, reads those changed since, and
/// puts what they hold into the database — notebooks before their
/// sections, sections before their pages — with the triggers paused, so it
/// is not written back. A copy a sync service made of a file, when both
/// sides changed it, becomes a page of its own rather than being lost; a
/// file gone missing is written again from the database. Nothing a file
/// holds is taken from the database because the file is not there: only
/// the note a deletion leaves, a [Tombstone], deletes.
final class FolderMirror {
  FolderMirror(
    this._db,
    this.folder,
    this._library,
    this._pages,
    this._bin, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final NotesFolder folder;
  final LibraryRepository _library;
  final PageRepository _pages;
  final BinRepository _bin;
  final DateTime Function() _clock;

  /// One flush or scan at a time: both work on what was written last.
  Future<void> _running = Future<void>.value();

  final StreamController<FolderChanges> _changes =
      StreamController<FolderChanges>.broadcast();
  final StreamController<MirrorStatus> _status =
      StreamController<MirrorStatus>.broadcast();

  Timer? _ticker;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _settle;
  int _lastSeq = -1;
  DateTime? _lastWritten;
  String? _problem;
  var _closed = false;

  /// Changes read from the folder, as they are.
  Stream<FolderChanges> get changes => _changes.stream;

  /// How the folder is doing, each time that changes.
  Stream<MirrorStatus> get statuses => _status.stream;

  MirrorStatus get status => MirrorStatus(
    pending: _pendingCount(),
    lastWritten: _lastWritten,
    problem: _problem,
  );

  int _pendingCount() =>
      integer(_db.select('SELECT COUNT(*) AS n FROM mirror_outbox').first, 'n');

  /// Queues everything for writing, as putting notes in a folder for the
  /// first time does.
  void enqueueAll() {
    _db.transaction(() {
      for (final (table, kind) in const <(String, String)>[
        ('notebooks', 'notebook'),
        ('sections', 'section'),
        ('pages', 'page'),
        ('ai_threads', 'thread'),
        ('ai_items', 'item'),
      ]) {
        _db.run(
          'INSERT INTO mirror_outbox (kind, id, seq) '
          "SELECT '$kind', id, (SELECT COALESCE(MAX(seq), 0) + 1 "
          '  FROM mirror_outbox) FROM $table WHERE true '
          'ON CONFLICT (kind, id) DO NOTHING',
        );
      }
    });
  }

  /// Writes and reads by themselves: what changes is written once it has
  /// been still a moment, and the folder is looked at every [every] and
  /// whenever something in it changes.
  void startAutomatically({Duration every = const Duration(minutes: 1)}) {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _looker ??= Timer.periodic(every, (_) => unawaited(scan()));
    try {
      _watch ??= folder.directory
          .watch(recursive: true)
          .where((event) => NotesFolder.looksLikeEntity(event.path))
          .listen((_) {
            _settle?.cancel();
            // Sync services write in bursts; they are read once they settle.
            _settle = Timer(
              const Duration(seconds: 2),
              () => unawaited(scan()),
            );
          }, onError: (Object _) {});
    } on FileSystemException {
      // Where the folder cannot be watched, it is looked at every minute.
    }
  }

  Timer? _looker;

  /// Writes what changed once it stops changing, and at the latest after a
  /// few seconds.
  void _tick() {
    if (_closed) return;
    final rows = _db.select(
      'SELECT COALESCE(MAX(seq), 0) AS seq, COUNT(*) AS n FROM mirror_outbox',
    );
    final seq = integer(rows.first, 'seq');
    final pending = integer(rows.first, 'n');
    if (pending == 0) {
      _lastSeq = seq;
      return;
    }
    if (seq == _lastSeq || ++_waited >= 5) {
      _waited = 0;
      unawaited(flush());
    }
    _lastSeq = seq;
  }

  int _waited = 0;

  /// Runs [work] after whatever flush or scan is running.
  Future<T> _serially<T>(Future<T> Function() work) {
    final result = _running.then((_) => work());
    _running = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  // ------------------------------------------------------------- writing

  /// Writes every change waiting to the folder.
  ///
  /// A file that cannot be written now — the folder is on a drive taken
  /// out, or locked by a sync service — stays waiting, and is tried again.
  Future<void> flush() => _serially(() async {
    while (true) {
      final rows = _db.select(
        'SELECT kind, id, seq FROM mirror_outbox ORDER BY seq LIMIT 64',
      );
      if (rows.isEmpty) break;
      var wrote = false;
      for (final row in rows) {
        final kind = EntityKind.named(str(row, 'kind'));
        final id = str(row, 'id');
        final seq = integer(row, 'seq');
        try {
          if (kind != null) await _write(kind, id);
          _db.run(
            'DELETE FROM mirror_outbox WHERE kind = ? AND id = ? AND seq = ?',
            <Object?>[str(row, 'kind'), id, seq],
          );
          wrote = true;
        } on FileSystemException catch (error) {
          _report('Could not write to the notes folder: ${error.message}');
          return;
        } on Object catch (error) {
          // Something that cannot be written as it is; the rest still can.
          _report('Could not write $kind $id to the notes folder: $error');
        }
      }
      if (!wrote) break;
    }
    _lastWritten = _clock();
    _report(null);
  });

  void _report(String? problem) {
    _problem = problem;
    if (!_status.isClosed) _status.add(status);
  }

  /// The file [kind] [id] is kept in now, or a tombstone if it is gone.
  EntityFile _current(EntityKind kind, String id) {
    final now = _clock().millisecondsSinceEpoch;
    final EntityFile? file = switch (kind) {
      EntityKind.notebook => _one(
        'SELECT * FROM notebooks WHERE id = ?',
        id,
        (row) => NotebookFile(LibraryRepository.notebookOf(row)),
      ),
      EntityKind.section => _one(
        'SELECT * FROM sections WHERE id = ?',
        id,
        (row) => SectionFile(LibraryRepository.sectionOf(row)),
      ),
      EntityKind.page => _pages.pageFile(id),
      EntityKind.thread => _rows(
        kind,
        'ai_threads',
        'ai_turns',
        'thread_id',
        id,
      ),
      EntityKind.item => _rows(kind, 'ai_items', 'ai_reviews', 'item_id', id),
    };
    return file ?? Tombstone(kind, id, now);
  }

  EntityFile? _one(String sql, String id, EntityFile Function(Row row) read) {
    final rows = _db.select(sql, <Object?>[id]);
    return rows.isEmpty ? null : read(rows.first);
  }

  RowsFile? _rows(
    EntityKind kind,
    String table,
    String children,
    String column,
    String id,
  ) {
    final rows = _db.select('SELECT * FROM $table WHERE id = ?', <Object?>[id]);
    if (rows.isEmpty) return null;
    return RowsFile(kind, _rowMap(rows.first), <Map<String, Object?>>[
      for (final child in _db.select(
        'SELECT * FROM $children WHERE $column = ?',
        <Object?>[id],
      ))
        _rowMap(child),
    ]);
  }

  static Map<String, Object?> _rowMap(Row row) => <String, Object?>{
    for (final column in row.keys) column: row[column],
  };

  Future<void> _write(EntityKind kind, String id) async {
    final file = _current(kind, id);
    final bytes = file.encode();
    final path = folder.pathFor(kind, id);
    final digest = sha256.convert(bytes).toString();
    final record = _record(path);
    final disk = File(path);
    final stat = disk.statSync();
    final exists = stat.type == FileSystemEntityType.file;

    if (exists && !_matches(record, stat)) {
      // Changed by someone else since it was last written or read here.
      final theirs = NotesFolder.read(disk);
      if (theirs != null) {
        final theirDigest = sha256.convert(theirs).toString();
        if (theirDigest == digest) {
          _remember(path, kind, id, disk.statSync(), digest);
          return;
        }
        if (record == null || theirDigest != record.digest) {
          _keepTheirs(EntityFile.decode(theirs), file);
        }
      }
    } else if (exists && record?.digest == digest) {
      return;
    }
    await NotesFolder.writeAtomically(path, bytes);
    _remember(path, kind, id, File(path).statSync(), digest);
  }

  /// Keeps [theirs], a page another copy of the notes wrote that is about
  /// to be written over by [ours], as a page of its own if they differ.
  void _keepTheirs(EntityFile? theirs, EntityFile ours) {
    if (theirs is! PageFile || ours is! PageFile) return;
    if (theirs.document.encode() == ours.document.encode() &&
        theirs.page.title == ours.page.title) {
      return;
    }
    _keepAsCopy(theirs);
  }

  /// Adds the page [copy] holds as a page of its own, beside the page it is
  /// a copy of, so that neither version is lost; returns its id, or null
  /// if its section is not here.
  String? _keepAsCopy(PageFile copy) {
    final id = Ulid.generate();
    final page = copy.page;
    final sectionExists = _db.select(
      'SELECT 1 FROM sections WHERE id = ?',
      <Object?>[page.sectionId],
    ).isNotEmpty;
    if (!sectionExists) return null;
    final parentExists =
        page.parentId != null &&
        _db.select('SELECT 1 FROM pages WHERE id = ?', <Object?>[
          page.parentId,
        ]).isNotEmpty;
    _pages.putPage(
      PageFile(
        page: PageRef(
          id: id,
          sectionId: page.sectionId,
          parentId: parentExists ? page.parentId : null,
          title: '${page.title} (other version)',
          position: page.position + 1e-6,
          createdAt: page.createdAt,
          updatedAt: _clock().millisecondsSinceEpoch,
          preview: page.preview,
          revision: page.revision,
          color: page.color,
        ),
        document: PageDocument(
          id: id,
          revision: copy.document.revision,
          canvas: copy.document.canvas,
          elements: copy.document.elements,
        ),
        assets: copy.assets,
        tags: copy.tags,
      ),
    );
    _found = _with(library: true, page: id);
    return id;
  }

  // ------------------------------------------------------------- reading

  /// What [scan] has found so far, handed on when it finishes.
  FolderChanges _found = const FolderChanges();

  /// Reads into the database every file of the folder changed by another
  /// copy of the notes, returning what changed.
  Future<FolderChanges> scan() => _serially(() async {
    if (!folder.isAvailable) {
      _report('The notes folder cannot be found: ${folder.path}');
      return const FolderChanges();
    }
    _found = const FolderChanges();
    final damaged = <String>[];
    final seen = <String>{};
    final waiting = <_Arrival>[];

    for (final entry in folder.entries()) {
      final path = entry.file.path;
      seen.add(path);
      final stat = entry.file.statSync();
      final record = _record(path);
      if (!entry.isCopy && _matches(record, stat)) continue;
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
        _readCopy(entry, file);
      } else if (file.id == entry.id) {
        waiting.add(_Arrival(entry, file, stat, digest));
      } else {
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
        if (_apply(arrival)) {
          waiting.remove(arrival);
          progress = true;
        }
      }
    }

    _rewriteMissing(seen);
    folder.removeLeftovers();
    final found = FolderChanges(
      pages: _found.pages,
      library: _found.library,
      ai: _found.ai,
      damaged: damaged,
    );
    if (!found.isEmpty && !_changes.isClosed) _changes.add(found);
    return found;
  });

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
    final columns = <String>{
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
  void _readCopy(FolderEntry entry, EntityFile file) {
    if (file is PageFile) {
      final ours = _pages.pageFile(file.id);
      if (ours == null ||
          ours.document.encode() != file.document.encode() ||
          ours.page.title != file.page.title) {
        // Kept by the triggers, so it is written as a file of its own.
        if (_keepAsCopy(file) == null) return;
      }
    }
    try {
      entry.file.deleteSync();
    } on FileSystemException {
      // Looked at again next time.
    }
  }

  /// Queues for writing again everything whose file was written or read
  /// here but has gone from the folder.
  void _rewriteMissing(Set<String> seen) {
    final present = <String>{for (final path in seen) _key(path)};
    for (final row in _db.select('SELECT path, kind, id FROM mirror_files')) {
      final path = str(row, 'path');
      if (present.contains(path)) continue;
      _db.run('DELETE FROM mirror_files WHERE path = ?', <Object?>[path]);
      _db.run(
        'INSERT INTO mirror_outbox (kind, id, seq) VALUES (?, ?, '
        '(SELECT COALESCE(MAX(seq), 0) + 1 FROM mirror_outbox)) '
        'ON CONFLICT (kind, id) DO NOTHING',
        <Object?>[str(row, 'kind'), str(row, 'id')],
      );
    }
  }

  // ------------------------------------------------------------ records

  /// [path] as the records keep it: from the folder, with forward
  /// slashes, so the folder can move without its files seeming new.
  String _key(String path) =>
      p.relative(path, from: folder.path).replaceAll(r'\', '/');

  _Record? _record(String path) {
    final rows = _db.select(
      'SELECT size, modified, digest FROM mirror_files WHERE path = ?',
      <Object?>[_key(path)],
    );
    if (rows.isEmpty) return null;
    return _Record(
      integer(rows.first, 'size'),
      integer(rows.first, 'modified'),
      str(rows.first, 'digest'),
    );
  }

  static bool _matches(_Record? record, FileStat stat) =>
      record != null &&
      stat.type == FileSystemEntityType.file &&
      record.size == stat.size &&
      record.modified == stat.modified.millisecondsSinceEpoch;

  void _remember(
    String path,
    EntityKind kind,
    String id,
    FileStat stat,
    String digest,
  ) => _db.run(
    'INSERT INTO mirror_files (path, kind, id, size, modified, digest) '
    'VALUES (?, ?, ?, ?, ?, ?) '
    'ON CONFLICT (path) DO UPDATE SET kind = excluded.kind, '
    '  id = excluded.id, size = excluded.size, '
    '  modified = excluded.modified, digest = excluded.digest',
    <Object?>[
      _key(path),
      kind.name,
      id,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
      digest,
    ],
  );

  /// Writes what is waiting, and stops looking at the folder.
  Future<void> close() async {
    _closed = true;
    _ticker?.cancel();
    _looker?.cancel();
    _settle?.cancel();
    await _watch?.cancel();
    await flush();
    // Not waited for: a stream's close finishes only once every listener
    // has heard it, and one paused — a screen not showing — never does.
    unawaited(_changes.close());
    unawaited(_status.close());
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

final class _Record {
  const _Record(this.size, this.modified, this.digest);

  final int size;
  final int modified;
  final String digest;
}
