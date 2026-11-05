/// Exporting notebooks, sections and pages in this app's own form, to be
/// brought back — here or on another computer — as they were.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:archive/archive_io.dart';

import 'asset_store.dart';
import 'away.dart';
import 'database.dart';
import 'library_repository.dart';
import 'page_repository.dart';
import 'row_read.dart';

/// Writes an export: a zip of the files the notes folder keeps for what is
/// exported, their pictures and files, and a list of what was exported.
///
/// ```text
/// aantekening-export.json   {"kind": "aantekening export", "notebooks":
///                           [...], "sections": [...], "pages": [...]}
/// notebooks/<id>.json, sections/<id>.json, pages/<id>.json.gz
/// assets/<ab>/<sha-256>
/// ```
///
/// Nothing is lost: an export read back is what was exported, down to the
/// identity of its pages, so links between them still lead there.
final class ArchiveExport {
  ArchiveExport(this._db, this._pages, this._assets);

  final AantekeningDatabase _db;
  final PageRepository _pages;
  final AssetStore _assets;

  static const String manifestName = exportManifestName;

  /// Writes the notebooks [notebooks], sections [sections] and pages
  /// [pages] — each with everything in it that is not in the bin — to the
  /// zip [target].
  Future<void> write(
    String target, {
    List<String> notebooks = const <String>[],
    List<String> sections = const <String>[],
    List<String> pages = const <String>[],
  }) async {
    final files = <String, EntityFile>{};
    final sectionIds = <String>[];
    for (final id in notebooks) {
      final row = _db.select('SELECT * FROM notebooks WHERE id = ?', <Object?>[
        id,
      ]);
      if (row.isEmpty) continue;
      files['notebooks/$id.json'] = NotebookFile(
        LibraryRepository.notebookOf(row.first),
      );
      sectionIds.addAll(<String>[
        for (final section in _db.select(
          'SELECT id FROM sections WHERE notebook_id = ? AND parent_id IS NULL '
          'AND deleted_at IS NULL',
          <Object?>[id],
        ))
          str(section, 'id'),
      ]);
    }
    final pageIds = <String>[];
    for (final root in <String>[...sections, ...sectionIds]) {
      for (final id in _db.subtree('sections', root, live: true)) {
        final row = _db.select('SELECT * FROM sections WHERE id = ?', <Object?>[
          id,
        ]);
        files['sections/$id.json'] = SectionFile(
          LibraryRepository.sectionOf(row.first),
        );
        pageIds.addAll(<String>[
          for (final page in _db.select(
            'SELECT id FROM pages WHERE section_id = ? AND parent_id IS NULL '
            'AND deleted_at IS NULL',
            <Object?>[id],
          ))
            str(page, 'id'),
        ]);
      }
    }
    // Pages are read and written one at a time, a long one away from the
    // window: all of them at once could be more than there is memory for.
    final exportedPages = <String>{
      for (final root in <String>[...pages, ...pageIds])
        ..._db.subtree('pages', root, live: true),
    };
    final assets = <String>{};

    final partial = File('$target.tmp');
    final encoder = ZipFileEncoder()..create(partial.path);
    var written = false;
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(
          manifestName,
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'kind': 'aantekening export',
            'format': EntityFile.format,
            'notebooks': notebooks,
            'sections': sections,
            'pages': pages,
          }),
        ),
      );
      for (final entry in files.entries) {
        encoder.addArchiveFile(
          ArchiveFile.bytes(entry.key, entry.value.encode()),
        );
      }
      for (final id in exportedPages) {
        final file = _pages.pageFile(id);
        if (file == null) continue;
        assets.addAll(file.assets.map((asset) => asset.sha256));
        encoder.addArchiveFile(
          ArchiveFile.bytes(
            'pages/${EntityKind.page.fileName(id)}',
            await away(_encoded, file, heavy: file.isHeavy),
          ),
        );
      }
      for (final sha in assets) {
        final file = _assets.fileForHash(sha);
        if (file.existsSync()) {
          encoder.addFileSync(
            file,
            'assets/${sha.substring(0, 2)}/$sha',
            ZipFileEncoder.store,
          );
        }
      }
      encoder.closeSync();
      await partial.rename(target);
      written = true;
    } finally {
      // Not written whole — a file that could not be read, a target that
      // cannot be written over: nothing is left of it beside the target.
      if (!written) {
        try {
          encoder.closeSync();
        } on Object {
          // Closed already.
        }
        if (partial.existsSync()) partial.deleteSync();
      }
    }
  }

  static Uint8List _encoded(EntityFile file) => file.encode();
}
