/// The files the notes folder keeps: one for each notebook, section, page,
/// conversation with the AI and thing kept from one.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';

/// A kind of thing the notes folder keeps a file for, and the folder it
/// keeps them in.
enum EntityKind {
  notebook('notebooks', compressed: false),
  section('sections', compressed: false),
  page('pages', compressed: true),
  thread('conversations', compressed: false),
  item('kept', compressed: false);

  const EntityKind(this.folder, {required this.compressed});

  final String folder;

  /// Whether its files are gzipped: pages, which hold handwriting, are.
  final bool compressed;

  /// The name of the file keeping the thing [id] of this kind.
  String fileName(String id) => compressed ? '$id.json.gz' : '$id.json';

  static EntityKind? named(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// How pages are compressed, in the notes folder and in the index: at a
/// level that writes a page of handwriting four times as fast as gzip's
/// default, for a file about a seventh larger. Pages are written each time
/// someone stops writing for a moment.
final GZipCodec pageCompression = GZipCodec(level: 4);

/// What one file of the notes folder holds.
sealed class EntityFile {
  const EntityFile();

  EntityKind get kind;
  String get id;

  /// The file's bytes: JSON, gzipped for the kinds that are.
  Uint8List encode() {
    final json = utf8.encode(_json());
    return Uint8List.fromList(
      kind.compressed ? pageCompression.encode(json) : json,
    );
  }

  String _json();

  /// Reads a file's [bytes], gzipped or not; null if they are not one this
  /// build understands — damaged, cut short, or from a newer build.
  static EntityFile? decode(Uint8List bytes) {
    try {
      final text = bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B
          ? utf8.decode(gzip.decode(bytes))
          : utf8.decode(bytes);
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) return null;
      if (readInt(json, 'format', 1) > format) return null;
      final kind = EntityKind.named(readString(json, 'kind'));
      if (kind == null) return null;
      if (json['purgedAt'] != null) {
        return Tombstone(
          kind,
          readString(json, 'id'),
          readInt(json, 'purgedAt'),
        );
      }
      return switch (kind) {
        EntityKind.notebook => NotebookFile(
          Notebook.fromJson(readObject(json, 'notebook')),
        ),
        EntityKind.section => SectionFile(
          Section.fromJson(readObject(json, 'section')),
        ),
        EntityKind.page => PageFile(
          page: PageRef.fromJson(readObject(json, 'page')),
          document: PageDocument.fromJson(readObject(json, 'document')),
          assets: <AssetRef>[
            for (final asset in readObjectList(json, 'assets'))
              AssetRef.fromJson(asset),
          ],
          tags: readStringList(json, 'tags'),
        ),
        EntityKind.thread || EntityKind.item => RowsFile(
          kind,
          readObject(json, 'row'),
          readObjectList(json, 'children'),
        ),
      };
    } on Object {
      // Whatever a damaged file — or one from a build that writes what
      // this one cannot take — makes reading it throw, it is not one this
      // build understands.
      return null;
    }
  }

  /// The version of the files this build writes.
  static const int format = 1;

  static String _header(EntityKind kind) =>
      '{"kind":${jsonEncode(kind.name)},"format":$format';
}

final class NotebookFile extends EntityFile {
  const NotebookFile(this.notebook);

  final Notebook notebook;

  @override
  EntityKind get kind => EntityKind.notebook;

  @override
  String get id => notebook.id;

  @override
  String _json() =>
      '${EntityFile._header(kind)},"notebook":${jsonEncode(notebook.toJson())}}';
}

final class SectionFile extends EntityFile {
  const SectionFile(this.section);

  final Section section;

  @override
  EntityKind get kind => EntityKind.section;

  @override
  String get id => section.id;

  @override
  String _json() =>
      '${EntityFile._header(kind)},"section":${jsonEncode(section.toJson())}}';
}

/// A page whole: where it is and what it is called, its tags, the
/// pictures and files it shows — so their bytes, in the folder's assets,
/// can be found — and its contents.
final class PageFile extends EntityFile {
  PageFile({
    required this.page,
    PageDocument? document,
    this.assets = const <AssetRef>[],
    this.tags = const <String>[],
    this.documentJson,
  }) : assert(document != null || documentJson != null),
       _document = document;

  final PageRef page;
  final List<AssetRef> assets;
  final List<String> tags;

  /// The document already written as JSON, in UTF-8, as the database
  /// keeps it: put in the file as it is, it is neither written again nor
  /// read until [document] is asked for.
  final List<int>? documentJson;

  /// The page's contents.
  PageDocument get document =>
      _document ??= PageDocument.decode(utf8.decode(documentJson!));
  PageDocument? _document;

  @override
  Uint8List encode() {
    final json = documentJson;
    if (json == null) return super.encode();
    return pageCompression.encode(
          (BytesBuilder(copy: false)
                ..add(utf8.encode(_head()))
                ..add(json)
                ..addByte(0x7D))
              .takeBytes(),
        )
        as Uint8List;
  }

  @override
  EntityKind get kind => EntityKind.page;

  @override
  String get id => page.id;

  @override
  String _json() => '${_head()}${document.encode()}}';

  /// All the file holds up to its document.
  String _head() =>
      '${EntityFile._header(kind)},'
      '"page":${jsonEncode(page.toJson())},'
      '"tags":${jsonEncode(tags)},'
      '"assets":${jsonEncode(<Object?>[for (final asset in assets) asset.toJson()])},'
      '"document":';
}

/// A conversation with the AI and its turns, or a kept item and how its
/// cards are being learnt: rows as the database has them.
final class RowsFile extends EntityFile {
  const RowsFile(this.kind, this.row, this.children);

  @override
  final EntityKind kind;
  final Map<String, Object?> row;
  final List<Map<String, Object?>> children;

  @override
  String get id => readString(row, 'id');

  @override
  String _json() =>
      '${EntityFile._header(kind)},"row":${jsonEncode(row)},'
      '"children":${jsonEncode(children)}}';
}

/// What is left of something deleted for good: that it was, and when, so
/// every copy of the notes lets it go.
final class Tombstone extends EntityFile {
  const Tombstone(this.kind, this.id, this.purgedAt);

  @override
  final EntityKind kind;

  @override
  final String id;
  final int purgedAt;

  @override
  String _json() =>
      '${EntityFile._header(kind)},"id":${jsonEncode(id)},"purgedAt":$purgedAt}';
}
