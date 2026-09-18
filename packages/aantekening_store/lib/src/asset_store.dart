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
    await file.writeAsBytes(bytes, flush: true);

    final asset = AssetRef(
      id: Ulid.generate(),
      sha256: digest,
      mimeType: mimeType,
      byteSize: bytes.length,
      createdAt: _clock().millisecondsSinceEpoch,
      originalName: originalName,
    );
    _db.run(
      'INSERT INTO assets '
      '(id, sha256, mime_type, byte_size, original_name, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        asset.id,
        asset.sha256,
        asset.mimeType,
        asset.byteSize,
        asset.originalName,
        asset.createdAt,
      ],
    );
    return asset;
  }

  /// Imports the contents of [file].
  Future<AssetRef> importFile(File file, {String? mimeType}) async {
    final bytes = await file.readAsBytes();
    return importBytes(
      bytes,
      mimeType: mimeType ?? mimeTypeForPath(file.path),
      originalName: p.basename(file.path),
    );
  }

  /// Fetches asset metadata by identifier.
  Future<AssetRef?> find(String assetId) async {
    final rows = _db.select('SELECT * FROM assets WHERE id = ?', <Object?>[
      assetId,
    ]);
    return rows.isEmpty ? null : _asset(rows.first);
  }

  /// Fetches asset metadata by content hash.
  Future<AssetRef?> findByHash(String sha256Hex) async {
    final rows = _db.select('SELECT * FROM assets WHERE sha256 = ?', <Object?>[
      sha256Hex,
    ]);
    return rows.isEmpty ? null : _asset(rows.first);
  }

  /// The file backing [asset].
  ///
  /// Returned rather than its bytes so that callers can stream a large PDF into
  /// the renderer instead of holding it in memory.
  File fileFor(AssetRef asset) => File(_pathForHash(asset.sha256));

  /// Reads an asset's bytes, or null when it is unknown or its file is missing.
  Future<Uint8List?> readBytes(String assetId) async {
    final asset = await find(assetId);
    if (asset == null) return null;
    final file = fileFor(asset);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  /// Deletes assets that no live page references any more.
  ///
  /// Returns the number of assets removed. Called after emptying the recycle
  /// bin, never on a hot path.
  Future<int> collectGarbage() async {
    final rows = _db.select('''
      SELECT a.id AS id, a.sha256 AS sha256
      FROM assets a
      WHERE NOT EXISTS (
        SELECT 1 FROM page_assets pa
        JOIN pages p ON p.id = pa.page_id
        WHERE pa.asset_id = a.id AND p.deleted_at IS NULL
      )
    ''');

    var removed = 0;
    for (final row in rows) {
      final file = File(_pathForHash(str(row, 'sha256')));
      if (file.existsSync()) {
        await file.delete();
      }
      _db.run('DELETE FROM assets WHERE id = ?', <Object?>[str(row, 'id')]);
      removed++;
    }
    return removed;
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
  String _pathForHash(String digest) =>
      p.join(rootDirectory.path, digest.substring(0, 2), digest);

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

  static AssetRef _asset(Row row) => AssetRef(
    id: str(row, 'id'),
    sha256: str(row, 'sha256'),
    mimeType: str(row, 'mime_type'),
    byteSize: integer(row, 'byte_size'),
    createdAt: integer(row, 'created_at'),
    originalName: strOrNull(row, 'original_name'),
  );
}
