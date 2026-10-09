/// Content-addressed storage for imported images and PDFs.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'row_read.dart';

/// Stores binary attachments on disk and their metadata in SQLite.
///
/// Bytes live in files rather than in the database: a 40 MB lecture PDF would
/// otherwise be copied through SQLite's page cache on every read, and keeping
/// the database small is what keeps opening the app and running queries fast.
/// Files are named by the SHA-256 of their contents, so importing the same
/// document into ten pages stores one copy.
class AssetStore {
  AssetStore(this._db, this.rootDirectory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;

  /// Directory holding the content-addressed files.
  final Directory rootDirectory;

  final DateTime Function() _clock;

  /// Imports [bytes], reusing an existing asset when the contents already exist.
  Future<AssetRef> importBytes(
    Uint8List bytes, {
    required String mimeType,
    String? originalName,
  }) async {
    final digest = sha256.convert(bytes).toString();

    final existing = await findByHash(digest);
    if (existing != null) return existing;

    final file = File(_pathForHash(digest));
    await file.parent.create(recursive: true);
    // Whole or not at all under its name: written aside, then moved over,
    // so neither a crash nor the same bytes imported at once leaves a file
    // cut short where it is read.
    final aside = File('${file.path}.${Ulid.generate()}.tmp');
    try {
      await aside.writeAsBytes(bytes, flush: true);
      await aside.rename(file.path);
    } finally {
      if (await aside.exists()) await aside.delete();
    }

    final asset = AssetRef(
      id: Ulid.generate(),
      sha256: digest,
      mimeType: mimeType,
      byteSize: bytes.length,
      createdAt: _clock().millisecondsSinceEpoch,
      originalName: originalName,
    );
    // The same bytes imported twice at once are stored once, under the id
    // the first to get here gave them.
    _db.run(
      'INSERT INTO assets '
      '(id, sha256, mime_type, byte_size, original_name, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (sha256) DO NOTHING',
      <Object?>[
        asset.id,
        asset.sha256,
        asset.mimeType,
        asset.byteSize,
        asset.originalName,
        asset.createdAt,
      ],
    );
    return (await findByHash(digest))!;
  }

  /// Imports the contents of [file], named [name] — its own name, if not.
  Future<AssetRef> importFile(
    File file, {
    String? mimeType,
    String? name,
  }) async {
    final bytes = await file.readAsBytes();
    return importBytes(
      bytes,
      mimeType: mimeType ?? mimeTypeForPath(file.path),
      originalName: name ?? p.basename(file.path),
    );
  }

  /// Fetches asset metadata by identifier.
  Future<AssetRef?> find(String assetId) async {
    final rows = _db.select('SELECT * FROM assets WHERE id = ?', <Object?>[
      assetId,
    ]);
    return rows.isEmpty ? null : assetOf(rows.first);
  }

  /// Fetches asset metadata by content hash.
  Future<AssetRef?> findByHash(String sha256Hex) async {
    final rows = _db.select('SELECT * FROM assets WHERE sha256 = ?', <Object?>[
      sha256Hex,
    ]);
    return rows.isEmpty ? null : assetOf(rows.first);
  }

  /// The file backing [asset].
  ///
  /// Returned rather than its bytes so that callers can stream a large PDF into
  /// the renderer instead of holding it in memory.
  File fileFor(AssetRef asset) => fileForHash(asset.sha256);

  /// The file holding the bytes whose SHA-256 is [sha256Hex] — brought back
  /// first, if it was set aside as no page here showed it: a page another
  /// computer added may show it still.
  File fileForHash(String sha256Hex) {
    final file = File(_pathForHash(sha256Hex));
    if (!file.existsSync()) _bringBack(sha256Hex, file);
    return file;
  }

  /// Reads an asset's bytes, or null when it is unknown or its file is missing.
  Future<Uint8List?> readBytes(String assetId) async {
    final asset = await find(assetId);
    if (asset == null) return null;
    final file = fileFor(asset);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  /// Sets aside the files of assets that no page references any more —
  /// none, not even a page in the bin, which may yet be restored — and
  /// deletes for good those set aside [keepFor] ago that still none does.
  ///
  /// A file is set aside rather than deleted because the notes folder is
  /// shared: another computer may have added a page showing it that has not
  /// reached this one yet. Reading it brings it back.
  ///
  /// Returns the number of assets removed. Called after emptying the bin,
  /// never on a hot path.
  Future<int> collectGarbage({
    Duration keepFor = const Duration(days: 30),
  }) async {
    final rows = _db.select('''
      SELECT a.id AS id, a.sha256 AS sha256
      FROM assets a
      WHERE NOT EXISTS (
        SELECT 1 FROM page_assets pa WHERE pa.asset_id = a.id
      )
    ''');

    var removed = 0;
    for (final row in rows) {
      final digest = str(row, 'sha256');
      if (isDigest(digest)) {
        final file = File(_pathForHash(digest));
        if (file.existsSync()) {
          final aside = File(_asideFor(digest));
          await aside.parent.create(recursive: true);
          await file.rename(aside.path);
          // Kept for [keepFor] from now, not from when it was made.
          aside.setLastModifiedSync(_clock());
        }
      }
      _db.run('DELETE FROM assets WHERE id = ?', <Object?>[str(row, 'id')]);
      removed++;
    }
    _forgetSetAside(keepFor);
    return removed;
  }

  /// The folder files no page here shows are set aside in.
  Directory get _setAside => Directory(p.join(rootDirectory.path, '.removed'));

  String _asideFor(String digest) => p.join(_setAside.path, digest);

  /// Brings the file of [digest] back to [file] from where it was set aside,
  /// if it is there.
  void _bringBack(String digest, File file) {
    try {
      final aside = File(_asideFor(digest));
      if (!aside.existsSync()) return;
      file.parent.createSync(recursive: true);
      aside.renameSync(file.path);
    } on FileSystemException {
      // Read where it is next time.
    }
  }

  /// Deletes the files set aside longer than [keepFor] ago that no page
  /// known here shows.
  void _forgetSetAside(Duration keepFor) {
    if (!_setAside.existsSync()) return;
    final before = _clock().subtract(keepFor);
    for (final entity in _setAside.listSync()) {
      if (entity is! File) continue;
      final digest = p.basename(entity.path);
      try {
        if (!isDigest(digest) ||
            entity.statSync().modified.isAfter(before) ||
            _db.select('SELECT 1 FROM assets WHERE sha256 = ?', <Object?>[
              digest,
            ]).isNotEmpty) {
          continue;
        }
        entity.deleteSync();
      } on FileSystemException {
        // Gone another time.
      }
    }
  }

  /// Total bytes held on disk by all assets.
  Future<int> totalBytes() async {
    final rows = _db.select(
      'SELECT COALESCE(SUM(byte_size), 0) AS total FROM assets',
    );
    return integer(rows.first, 'total');
  }

  /// Fans files out over 256 subdirectories by hash prefix.
  ///
  /// A single directory holding tens of thousands of entries is slow to list on
  /// every platform this app targets.
  ///
  /// [digest] comes from the notes folder, which anyone sharing it can
  /// write to: anything but a SHA-256 is refused, so no name can lead out
  /// of the folder.
  String _pathForHash(String digest) {
    if (!isDigest(digest)) {
      throw ArgumentError.value(digest, 'digest', 'not a SHA-256');
    }
    return p.join(rootDirectory.path, digest.substring(0, 2), digest);
  }

  /// Whether [text] is a SHA-256, as assets are named by.
  static bool isDigest(String text) => _digest.hasMatch(text);

  static final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');

  /// Guesses a media type from a file extension.
  ///
  /// Only the formats the canvas can actually display are recognised; anything
  /// else is stored as opaque bytes.
  static String mimeTypeForPath(String path) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.svg' => 'image/svg+xml',
      '.pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  /// The asset a row of the assets table describes.
  static AssetRef assetOf(Row row) => AssetRef(
    id: str(row, 'id'),
    sha256: str(row, 'sha256'),
    mimeType: str(row, 'mime_type'),
    byteSize: integer(row, 'byte_size'),
    createdAt: integer(row, 'created_at'),
    originalName: strOrNull(row, 'original_name'),
  );
}
