/// The lowest layer of a OneNote file: its header, and the lists of file
/// nodes everything else is written in ([MS-ONESTORE] 2.3–2.4).
library;

import 'dart:typed_data';

import '../bytes.dart';

/// A reference to a chunk of the file: where it starts and how long it is.
final class FileChunk {
  const FileChunk(this.offset, this.length, {this.isNil = false});

  final int offset;
  final int length;

  /// Whether it points nowhere, as a list with no next fragment does.
  final bool isNil;

  bool get isEmpty => isNil || (offset == 0 && length == 0);

  static FileChunk read64x32(ByteReader reader) {
    final offset = reader.u64();
    final length = reader.u32();
    return FileChunk(offset, length, isNil: offset == -1 && length == 0);
  }
}

/// One file node: its type, the bytes of its fields, and, for a node that
/// points at more of the file, what it points at.
final class FileNode {
  FileNode(this.id, this.fields, {this.chunk, this.children});

  /// The FileNodeID, which says what the node is.
  final int id;

  /// The node's own fields, after any chunk reference.
  final ByteReader fields;

  /// The chunk a node of base type 1 points at.
  final FileChunk? chunk;

  /// The list a node of base type 2 points at.
  final List<FileNode>? children;
}

/// File node ids ([MS-ONESTORE] 2.4.3).
abstract final class NodeId {
  static const objectSpaceManifestRoot = 0x004;
  static const objectSpaceManifestListReference = 0x008;
  static const objectSpaceManifestListStart = 0x00C;
  static const revisionManifestListReference = 0x010;
  static const revisionManifestListStart = 0x014;
  static const revisionManifestStart4 = 0x01B;
  static const revisionManifestEnd = 0x01C;
  static const revisionManifestStart6 = 0x01E;
  static const revisionManifestStart7 = 0x01F;
  static const globalIdTableStart = 0x021;
  static const globalIdTableStart2 = 0x022;
  static const globalIdTableEntry = 0x024;
  static const globalIdTableEntry2 = 0x025;
  static const globalIdTableEntry3 = 0x026;
  static const globalIdTableEnd = 0x028;
  static const objectDeclarationWithRefCount = 0x02D;
  static const objectDeclarationWithRefCount2 = 0x02E;
  static const objectRevisionWithRefCount = 0x041;
  static const objectRevisionWithRefCount2 = 0x042;
  static const rootObjectReference2 = 0x059;
  static const rootObjectReference3 = 0x05A;
  static const revisionRoleDeclaration = 0x05C;
  static const revisionRoleAndContextDeclaration = 0x05D;
  static const objectDeclarationFileData3RefCount = 0x072;
  static const objectDeclarationFileData3LargeRefCount = 0x073;
  static const objectDataEncryptionKeyV2 = 0x07C;
  static const objectInfoDependencyOverrides = 0x084;
  static const dataSignatureGroupDefinition = 0x08C;
  static const fileDataStoreListReference = 0x090;
  static const fileDataStoreObjectReference = 0x094;
  static const objectDeclaration2RefCount = 0x0A4;
  static const objectDeclaration2LargeRefCount = 0x0A5;
  static const objectGroupListReference = 0x0B0;
  static const objectGroupStart = 0x0B4;
  static const objectGroupEnd = 0x0B8;
  static const hashedChunkDescriptor2 = 0x0C2;
  static const readOnlyObjectDeclaration2RefCount = 0x0C4;
  static const readOnlyObjectDeclaration2LargeRefCount = 0x0C5;
  static const chunkTerminator = 0x0FF;
}

/// The two kinds of revision store file.
enum StoreKind { section, tableOfContents }

/// The header of a revision store file, and the committed file node lists
/// it leads to.
final class StoreFile {
  StoreFile._(this.kind, this.rootList, this.bytes);

  static final Guid _sectionType = Guid.parse(
    '7B5C52E4-D88C-4DA7-AEB1-5378D02996D3',
  );
  static final Guid _tocType = Guid.parse(
    '43FF2FA1-EFD9-4C76-9EE2-10EA5722765F',
  );
  static final Guid _revisionStoreFormat = Guid.parse(
    '109ADD3F-911B-49F5-A5D0-1791EDC8AED8',
  );
  static final Guid _packagingFormat = Guid.parse(
    '638DE92F-A6D4-4BC1-9A36-B3FC2511A5B7',
  );

  /// Reads the header and the root file node list of [bytes].
  factory StoreFile.read(Uint8List bytes) {
    final reader = ByteReader(bytes);
    if (bytes.length < 1024) throw FormatDamage('Not a OneNote file');
    final type = reader.guid();
    final kind = type == _sectionType
        ? StoreKind.section
        : type == _tocType
        ? StoreKind.tableOfContents
        : throw FormatDamage('Not a OneNote file');
    reader.position = 32;
    final legacyVersion = reader.guid();
    final format = reader.guid();
    if (format == _packagingFormat ||
        (format == _revisionStoreFormat && !legacyVersion.isNil)) {
      throw FormatDamage(
        'This file was saved by OneNote online. Export the notebook from '
        'OneNote on a computer, as a .onepkg, and import that.',
      );
    }
    if (format != _revisionStoreFormat) {
      throw FormatDamage('This OneNote file is of a version not read');
    }
    reader.position = 96;
    final transactions = reader.u32();
    reader.position = 160;
    final transactionLog = FileChunk.read64x32(reader);
    final rootListChunk = FileChunk.read64x32(reader);
    if (_embedsPackage(bytes, transactionLog)) {
      throw FormatDamage(
        'This OneNote file is in the format newer versions of OneNote keep '
        'notebooks in online, which is not read yet.',
      );
    }

    final committed = _committedNodeCounts(
      ByteReader(bytes),
      transactionLog,
      transactions,
    );
    final lists = _ListReader(ByteReader(bytes), committed);
    final root = rootListChunk.isEmpty
        ? const <FileNode>[]
        : lists.read(rootListChunk);
    return StoreFile._(kind, root, bytes);
  }

  final StoreKind kind;
  final List<FileNode> rootList;
  final Uint8List bytes;

  /// Whether the file carries its contents as a package after its
  /// transaction log, with only an empty revision store around it.
  static bool _embedsPackage(Uint8List bytes, FileChunk log) {
    final at = log.offset + log.length;
    if (log.isEmpty || at + 64 > bytes.length) return false;
    return Guid(Uint8List.sublistView(bytes, at + 48, at + 64)) ==
        _packagingFormat;
  }

  /// How many nodes of each file node list were committed, by list id: a
  /// list may hold nodes past these that a save was interrupted before
  /// committing, which are not part of the file ([MS-ONESTORE] 2.3.3).
  static Map<int, int> _committedNodeCounts(
    ByteReader file,
    FileChunk log,
    int transactions,
  ) {
    final counts = <int, int>{};
    var chunk = log;
    var seen = 0;
    while (!chunk.isEmpty && seen < transactions) {
      final fragment = file.at(chunk.offset, chunk.length);
      final entries = (chunk.length - 12) ~/ 8;
      for (var i = 0; i < entries && seen < transactions; i++) {
        final list = fragment.u32();
        final value = fragment.u32();
        if (list == 0x1) {
          seen++;
        } else {
          counts[list] = value;
        }
      }
      fragment.position = chunk.length - 12;
      chunk = FileChunk.read64x32(fragment);
    }
    return counts;
  }
}

/// Reads file node lists, stopping each at the nodes committed to it.
final class _ListReader {
  _ListReader(this._file, this._committed);

  final ByteReader _file;
  final Map<int, int> _committed;
  int _depth = 0;

  static const int _fragmentMagic = 0xA4567AB1F5F7F4C4;
  static const int _fragmentFooter = 0x8BC215C38233BA4B;

  List<FileNode> read(FileChunk first) {
    if (++_depth > 64) throw FormatDamage('File node lists nest too deep');
    try {
      final nodes = <FileNode>[];
      var chunk = first;
      var sequence = 0;
      int? listId;
      var left = 0;
      final visited = <int>{};
      while (!chunk.isEmpty) {
        if (!visited.add(chunk.offset)) {
          throw FormatDamage('A file node list loops back on itself');
        }
        final fragment = _file.at(chunk.offset, chunk.length);
        if (fragment.u64() != _fragmentMagic) {
          throw FormatDamage('A file node list is damaged');
        }
        final id = fragment.u32();
        if (fragment.u32() != sequence++) {
          throw FormatDamage('A file node list is out of order');
        }
        if (listId == null) {
          listId = id;
          left = _committed[id] ?? 0x7FFFFFFF;
        }
        final end = chunk.length - 20;
        while (left > 0 && fragment.position + 4 <= end) {
          final node = _readNode(fragment);
          if (node == null) break;
          if (node.id == NodeId.chunkTerminator) break;
          nodes.add(node);
          left--;
        }
        fragment.position = end;
        final next = FileChunk.read64x32(fragment);
        if (fragment.u64() != _fragmentFooter) {
          throw FormatDamage('A file node list fragment is damaged');
        }
        if (left == 0) break;
        chunk = next;
      }
      return nodes;
    } finally {
      _depth--;
    }
  }

  /// The next node of [fragment], or null for the zero padding that ends
  /// one.
  FileNode? _readNode(ByteReader fragment) {
    final start = fragment.position;
    final header = fragment.u32();
    final id = header & 0x3FF;
    if (id == 0) return null;
    final size = (header >> 10) & 0x1FFF;
    final offsetFormat = (header >> 23) & 0x3;
    final lengthFormat = (header >> 25) & 0x3;
    final baseType = (header >> 27) & 0xF;
    if (size < 4) throw FormatDamage('A file node has no size');
    final body = fragment.at(start + 4, size - 4);
    fragment.position = start + size;

    FileChunk? chunk;
    List<FileNode>? children;
    if (baseType == 1 || baseType == 2) {
      chunk = _readChunk(body, offsetFormat, lengthFormat);
      if (baseType == 2 && !chunk.isEmpty) children = read(chunk);
    }
    return FileNode(id, body, chunk: chunk, children: children);
  }

  /// A FileNodeChunkReference, in whichever of its compact forms the node
  /// header says.
  static FileChunk _readChunk(ByteReader body, int offsetFormat, int length) {
    final (int offset, bool offsetNil) = switch (offsetFormat) {
      0 => (() {
        final value = body.u64();
        return (value, value == -1);
      })(),
      1 => (() {
        final value = body.u32();
        return (value, value == 0xFFFFFFFF);
      })(),
      2 => (() {
        final value = body.u16();
        return (value * 8, value == 0xFFFF);
      })(),
      _ => (() {
        final value = body.u32();
        return (value * 8, value == 0xFFFFFFFF);
      })(),
    };
    final size = switch (length) {
      0 => body.u32(),
      1 => body.u64(),
      2 => body.u8() * 8,
      _ => body.u16() * 8,
    };
    return FileChunk(offset, size, isNil: offsetNil && size == 0);
  }
}
