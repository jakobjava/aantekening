part of 'folder_mirror.dart';

/// Watching the folder and the outbox: writing what changed once it has
/// been still a moment, and reading what changed in the folder once a sync
/// service has stopped writing to it.
extension _Watching on FolderMirror {
  /// Starts writing and reading by themselves, as
  /// [FolderMirror.startAutomatically] says.
  void _startWatching(Duration every) {
    // Nothing is checked while nothing waits to be written: a change
    // queued starts the checking, which stops once all is written.
    _queued ??= _db.raw.updates
        .where(
          (update) =>
              update.tableName == 'mirror_outbox' &&
              update.kind != SqliteUpdateKind.delete,
        )
        .listen((_) => _wake());
    _wake();
    _looker ??= Timer.periodic(every, (_) => unawaited(scan()));
    // Each kind's folder is watched by itself: not every system can watch
    // a folder and all the folders in it at once.
    if (_watches.isEmpty) {
      for (final kind in EntityKind.values) {
        try {
          final directory = folder.folderOf(kind)..createSync(recursive: true);
          _watches.add(
            directory
                .watch()
                .map(
                  // A file written beside where it goes and moved there, as
                  // sync services write, arrives where it is moved to.
                  (event) => event is FileSystemMoveEvent
                      ? event.destination ?? event.path
                      : event.path,
                )
                .where(NotesFolder.looksLikeEntity)
                .listen(_touch, onError: (Object _) {}),
          );
        } on FileSystemException {
          // Where the folder cannot be watched, it is looked at every minute.
        }
      }
    }
  }

  /// Notes that [path] changed in the folder, to be read once changes
  /// settle: sync services write in bursts.
  void _touch(String path) {
    _touched.add(path);
    _settle?.cancel();
    _settle = Timer(const Duration(seconds: 2), () {
      final touched = List.of(_touched);
      _touched.clear();
      // Files this copy of the notes wrote itself need no looking at.
      if (!touched.every(_known)) unawaited(scan());
    });
  }

  /// Whether the file at [path] is as it was last written or read here.
  bool _known(String path) {
    try {
      return _matches(_record(path), File(path).statSync());
    } on FileSystemException {
      return false;
    }
  }

  /// Starts checking each second for what waits to be written.
  void _wake() {
    if (_closed) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Writes what changed once it stops changing, and at the latest after a
  /// few seconds; stops checking once nothing waits.
  void _tick() {
    if (_closed) return;
    if (_resting > 0) {
      _resting--;
      return;
    }
    final rows = _db.select(
      'SELECT COALESCE(MAX(seq), 0) AS seq, COUNT(*) AS n FROM mirror_outbox',
    );
    final seq = integer(rows.first, 'seq');
    final pending = integer(rows.first, 'n');
    // What waits only until it changes wakes the checking again when it
    // does.
    if (pending <= _stuck.length) {
      _lastSeq = seq;
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    if (seq == _lastSeq || ++_waited >= 5) {
      _waited = 0;
      unawaited(flush());
    }
    _lastSeq = seq;
  }
}
