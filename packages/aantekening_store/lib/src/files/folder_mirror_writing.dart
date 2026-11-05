part of 'folder_mirror.dart';

/// Writing what waits in the outbox to the folder: each thing's file as the
/// database has it now, and the other version of a page kept, as a page of
/// its own, before a file someone else changed is written over.
extension _Writing on FolderMirror {
  /// Writes every change waiting to the folder, as [FolderMirror.flush]
  /// says.
  Future<void> _writeWaiting() async {
    String? problem;
    // Read on from the last one read, by its change and then its name:
    // what was queued in one go, as everything is at first, shares one.
    (int, String, String) after = (-1, '', '');
    while (true) {
      final rows = _db.select(
        'SELECT kind, id, seq FROM mirror_outbox '
        'WHERE (seq, kind, id) > (?, ?, ?) '
        'ORDER BY seq, kind, id LIMIT 64',
        <Object?>[after.$1, after.$2, after.$3],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final name = str(row, 'kind');
        final id = str(row, 'id');
        final seq = integer(row, 'seq');
        after = (seq, name, id);
        final key = '$name/$id';
        if (_stuck[key] case (final at, final error) when at == seq) {
          problem ??= error;
          continue;
        }
        final kind = EntityKind.named(name);
        try {
          if (kind != null) await _write(kind, id);
        } on FileSystemException catch (error) {
          _resting = 30;
          _report('Could not write to the notes folder: ${error.message}');
          return;
        } on Object catch (error) {
          problem = 'Could not write $name $id to the notes folder: $error';
          _stuck[key] = (seq, problem);
          continue;
        }
        _stuck.remove(key);
        _db.run(
          'DELETE FROM mirror_outbox WHERE kind = ? AND id = ? AND seq = ?',
          <Object?>[name, id, seq],
        );
      }
    }
    _lastWritten = _clock();
    _report(problem);
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
    final (bytes, digest) = await away(
      _encode,
      file,
      heavy: file is PageFile && file.isHeavy,
    );
    final path = folder.pathFor(kind, id);
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
          // What a newer version wrote holds what this one may not know
          // of: it waits, and is said to, rather than being written over.
          if (EntityFile.isNewer(theirs)) {
            throw const FormatException(
              'a newer version of aantekening wrote it there; update this '
              'one to change it here',
            );
          }
          await _keepTheirs(EntityFile.decode(theirs), file);
        }
      }
    } else if (exists && record?.digest == digest) {
      return;
    }
    await NotesFolder.writeAtomically(path, bytes);
    _remember(path, kind, id, File(path).statSync(), digest);
  }

  /// [file]'s bytes and their digest, once it is sure what it holds can
  /// be read back: a page's contents damaged in the index must not be
  /// written over a good file, and from there to every computer.
  ///
  /// A long page, kept gzipped, is whole if it unpacks — its check of what
  /// it holds passed — to as much as gzip says it held; a short one is
  /// read as JSON.
  static (Uint8List, String) _encode(EntityFile file) {
    if (file is PageFile) {
      final whole = switch ((file.documentGzipped, file.documentJson)) {
        (final gzipped?, final json?) => _unpackedWhole(gzipped, json),
        (null, final json?) =>
          jsonDecode(utf8.decode(json)) is Map<String, Object?>,
        _ => true,
      };
      if (!whole) {
        throw const FormatException('The page is damaged in the index');
      }
    }
    final bytes = file.encode();
    return (bytes, sha256.convert(bytes).toString());
  }

  /// Whether [json] is all [gzipped] held: as long as its last four bytes
  /// say. Cut short, gzip unpacks what there is and says nothing.
  static bool _unpackedWhole(List<int> gzipped, List<int> json) {
    final at = gzipped.length - 4;
    if (at < 0) return false;
    final size =
        gzipped[at] |
        gzipped[at + 1] << 8 |
        gzipped[at + 2] << 16 |
        gzipped[at + 3] << 24;
    return size == json.length & 0xFFFFFFFF;
  }

  /// Keeps [theirs], a page another copy of the notes wrote that is about
  /// to be written over by [ours], as a page of its own if they differ —
  /// or if [ours] is the page deleted for good here, which it was changed
  /// elsewhere since.
  Future<void> _keepTheirs(EntityFile? theirs, EntityFile ours) async {
    if (theirs is! PageFile) return;
    if (ours is! Tombstone) {
      if (ours is! PageFile) return;
      if (theirs.document.encode() == ours.document.encode() &&
          theirs.page.title == ours.page.title) {
        return;
      }
    }
    final kept = await _keepAsCopy(theirs);
    // Kept while writing, not reading: said at once, as no scan says it.
    if (!_changes.isClosed) {
      _changes.add(FolderChanges(pages: <String>{kept}, library: true));
    }
  }

  /// Adds the page [copy] holds as a page of its own, beside the page it is
  /// a copy of, so that neither version is lost — or, if its section is
  /// not here, in a notebook of rescued pages; returns its id.
  Future<String> _keepAsCopy(PageFile copy) async {
    final id = Ulid.generate();
    final page = copy.page;
    final sectionExists = _db.select(
      'SELECT 1 FROM sections WHERE id = ?',
      <Object?>[page.sectionId],
    ).isNotEmpty;
    final sectionId = sectionExists
        ? page.sectionId
        : (await Rescue.rescuedSection(_library)).id;
    final parentExists =
        page.parentId != null &&
        _db.select('SELECT 1 FROM pages WHERE id = ?', <Object?>[
          page.parentId,
        ]).isNotEmpty;
    _pages.putPage(
      PageFile(
        page: PageRef(
          id: id,
          sectionId: sectionId,
          parentId: parentExists && sectionExists ? page.parentId : null,
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
    return id;
  }
}
