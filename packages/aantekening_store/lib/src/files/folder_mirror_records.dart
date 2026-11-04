part of 'folder_mirror.dart';

/// The records of the files written or read here, in `mirror_files`: each
/// one's size, time and digest, by which a file is known to be as it was
/// left, or to have been changed by someone else since.
extension _Records on FolderMirror {
  /// [path] as the records keep it: from the folder, with forward
  /// slashes, so the folder can move without its files seeming new.
  String _key(String path) =>
      p.relative(path, from: folder.path).replaceAll(r'\', '/');

  /// Every file as it was last written or read here, by its key.
  Map<String, _Record> _allRecords() => <String, _Record>{
    for (final row in _db.select(
      'SELECT path, kind, id, size, modified, digest FROM mirror_files',
    ))
      str(row, 'path'): _Record(
        integer(row, 'size'),
        integer(row, 'modified'),
        str(row, 'digest'),
        kind: str(row, 'kind'),
        id: str(row, 'id'),
      ),
  };

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

  /// How long after a file is written another write to it may still bear
  /// the same time: a file system stamps files from a clock that moves on
  /// only every few milliseconds, and FAT's every two seconds.
  static const Duration _sameTime = Duration(seconds: 3);

  /// What a file's time is remembered as where it cannot be told apart
  /// from a write made just after it: never what a file bears, so the file
  /// is read and its contents compared the next time it is looked at.
  static const int _unsure = -1;

  /// Remembers [path] as it is now: its size, time and [digest]. A file
  /// written so lately that another write could bear the same time and
  /// size — two computers writing a page within a tick of each other — is
  /// remembered as one to read again, as git treats an entry racily clean:
  /// else the later write would seem to be the earlier, and be passed over
  /// for good.
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
      _clock().difference(stat.modified) < _sameTime
          ? _unsure
          : stat.modified.millisecondsSinceEpoch,
      digest,
    ],
  );
}

/// Whether the file [stat] describes is as [record] remembers it.
bool _matches(_Record? record, FileStat stat) =>
    record != null &&
    stat.type == FileSystemEntityType.file &&
    record.size == stat.size &&
    record.modified == stat.modified.millisecondsSinceEpoch;

final class _Record {
  const _Record(this.size, this.modified, this.digest, {this.kind, this.id});

  final int size;
  final int modified;
  final String digest;

  /// What the file is of, when read with every record.
  final String? kind;
  final String? id;
}
