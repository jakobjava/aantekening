/// Keeping the notes folder and the database in step, both ways.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../away.dart';
import '../bin_repository.dart';
import '../database.dart';
import '../library_repository.dart';
import '../page_repository.dart';
import '../rescue.dart';
import '../row_read.dart';
import 'entity_files.dart';
import 'notes_folder.dart';

part 'folder_mirror_reading.dart';
part 'folder_mirror_records.dart';
part 'folder_mirror_watching.dart';
part 'folder_mirror_writing.dart';

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
  final List<StreamSubscription<String>> _watches =
      <StreamSubscription<String>>[];
  Timer? _settle;
  int _lastSeq = -1;
  DateTime? _lastWritten;
  String? _problem;
  var _closed = false;

  // ------------------------------------------------------------ watching

  Timer? _looker;
  StreamSubscription<SqliteUpdate>? _queued;

  /// The files changed in the folder since it was last looked at for them.
  final Set<String> _touched = <String>{};

  int _waited = 0;

  /// How many more checks go by before writing is tried again, after the
  /// folder could not be written to: a drive taken out stays out a while.
  int _resting = 0;

  // ------------------------------------------------------------- writing

  /// What could not be written as it was, by kind and id: the change it
  /// was at, and why. Tried again once it changes.
  final Map<String, (int, String)> _stuck = <String, (int, String)>{};

  // ------------------------------------------------------------- reading

  /// What [scan] has found so far, handed on when it finishes.
  FolderChanges _found = const FolderChanges();

  /// The columns of each table rows have been put into.
  final Map<String, Set<String>> _columns = <String, Set<String>>{};

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
  void startAutomatically({Duration every = const Duration(minutes: 1)}) =>
      _startWatching(every);

  /// Runs [work] after whatever flush or scan is running.
  Future<T> _serially<T>(Future<T> Function() work) {
    final result = _running.then((_) => work());
    _running = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Writes every change waiting to the folder.
  ///
  /// A file that cannot be written now — the folder is on a drive taken
  /// out, or locked by a sync service — stays waiting, and is tried again
  /// in a while. One that cannot be written as it is stays waiting too, but
  /// is tried again only once it changes, or the app starts again, rather
  /// than again and again; it is never let go unwritten.
  Future<void> flush() => _serially(_writeWaiting);

  void _report(String? problem) {
    _problem = problem;
    if (!_status.isClosed) _status.add(status);
  }

  /// Reads into the database every file of the folder changed by another
  /// copy of the notes, returning what changed.
  Future<FolderChanges> scan() => _serially(_readChanged);

  /// Writes what is waiting, and stops looking at the folder.
  Future<void> close() async {
    _closed = true;
    _ticker?.cancel();
    await _queued?.cancel();
    _looker?.cancel();
    _settle?.cancel();
    for (final watch in _watches) {
      await watch.cancel();
    }
    await flush();
    // Not waited for: a stream's close finishes only once every listener
    // has heard it, and one paused — a screen not showing — never does.
    unawaited(_changes.close());
    unawaited(_status.close());
  }
}
