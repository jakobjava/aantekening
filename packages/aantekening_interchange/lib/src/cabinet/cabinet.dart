/// Reading Microsoft cabinet (.cab) archives, which a OneNote .onepkg is.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../bytes.dart';
import 'lzx.dart';

/// Somewhere to read bytes from at any offset: a file, or bytes in memory.
abstract interface class RandomSource {
  int get length;

  /// The [count] bytes at [offset].
  Uint8List readAt(int offset, int count);
}

/// A [RandomSource] over bytes in memory.
final class BytesSource implements RandomSource {
  BytesSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Uint8List readAt(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > _bytes.length) {
      throw FormatDamage('The archive ends before its contents do');
    }
    return Uint8List.sublistView(_bytes, offset, offset + count);
  }
}

/// A [RandomSource] over an open file, read as it is needed rather than
/// all at once.
final class FileSource implements RandomSource {
  FileSource(this._file) : length = _file.lengthSync();

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Uint8List readAt(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw FormatDamage('The archive ends before its contents do');
    }
    _file.setPositionSync(offset);
    return _file.readSync(count);
  }
}

/// One file in a cabinet.
final class CabinetFile {
  const CabinetFile({
    required this.name,
    required this.size,
    required this.folder,
    required this.offset,
  });

  /// Its path inside the cabinet, with `/` between its parts.
  final String name;
  final int size;

  /// Which folder — compressed stream — holds it, and where in that
  /// stream's uncompressed bytes it starts.
  final int folder;
  final int offset;
}

/// A cabinet archive: a header, folders of compressed data, and the files
/// laid end to end in those folders' uncompressed bytes.
///
/// Stored, MSZIP and LZX folders can be read; every data block's checksum
/// is checked, so a damaged archive fails rather than giving damaged files.
final class Cabinet {
  Cabinet._(this._source, this._folders, this.files, this._dataReserve);

  /// Reads the directory of the cabinet in [source].
  factory Cabinet.read(RandomSource source) {
    final header = ByteReader(source.readAt(0, _min(source.length, 1 << 16)));
    if (header.u32() != 0x4643534D) {
      throw FormatDamage('Not a cabinet archive');
    }
    header.skip(4 + 4 + 4);
    final filesOffset = header.u32();
    header.skip(4 + 2);
    final folderCount = header.u16();
    final fileCount = header.u16();
    final flags = header.u16();
    header.skip(4);
    if (flags & 0x3 != 0) {
      throw FormatDamage('Cabinets spread over several files are not read');
    }
    var folderReserve = 0;
    var dataReserve = 0;
    if (flags & 0x4 != 0) {
      final headerReserve = header.u16();
      folderReserve = header.u8();
      dataReserve = header.u8();
      header.skip(headerReserve);
    }
    final folders = <_Folder>[
      for (var i = 0; i < folderCount; i++)
        () {
          final folder = _Folder(
            dataOffset: header.u32(),
            blockCount: header.u16(),
            compression: header.u16(),
          );
          header.skip(folderReserve);
          return folder;
        }(),
    ];

    final directory = ByteReader(
      source.readAt(filesOffset, _min(source.length - filesOffset, 1 << 20)),
    );
    final files = <CabinetFile>[];
    for (var i = 0; i < fileCount; i++) {
      final size = directory.u32();
      final offset = directory.u32();
      final folder = directory.u16();
      directory.skip(4 + 2);
      final nameStart = directory.position;
      while (directory.u8() != 0) {}
      final raw = Uint8List.sublistView(
        directory.bytes,
        nameStart,
        directory.position - 1,
      );
      // Names marked as UTF-8 (attribute 0x80) are; unmarked ones are too,
      // as often as not, and are read as UTF-8 when they are valid UTF-8.
      final name = utf8OrLatin(raw);
      if (folder >= folders.length) {
        throw FormatDamage('A file in the cabinet is in no folder');
      }
      files.add(
        CabinetFile(
          name: _normalise(name),
          size: size,
          folder: folder,
          offset: offset,
        ),
      );
    }
    return Cabinet._(source, folders, files, dataReserve);
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// [name] with backslashes as slashes, and with no part that would climb
  /// out of the folder it is extracted to.
  static String _normalise(String name) => <String>[
    for (final part in name.split(RegExp(r'[/\\]')))
      if (part.isNotEmpty && part != '.' && part != '..') part,
  ].join('/');

  final RandomSource _source;
  final List<_Folder> _folders;
  final List<CabinetFile> files;
  final int _dataReserve;

  /// Decompresses every folder, handing each file's bytes to [onBytes] in
  /// order, a piece at a time, and calling [onFile] once each file is
  /// complete.
  void read({
    required void Function(CabinetFile file, Uint8List bytes) onBytes,
    void Function(CabinetFile file)? onFile,
    void Function(int done, int total)? onProgress,
  }) {
    final total = files.fold<int>(0, (sum, file) => sum + file.size);
    var done = 0;
    for (var index = 0; index < _folders.length; index++) {
      final inFolder = files.where((file) => file.folder == index).toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));
      if (inFolder.isEmpty) continue;
      var next = 0;
      var position = 0;
      for (final frame in _frames(_folders[index])) {
        final frameEnd = position + frame.length;
        while (next < inFolder.length) {
          final file = inFolder[next];
          final start = file.offset > position ? file.offset : position;
          final end = file.offset + file.size < frameEnd
              ? file.offset + file.size
              : frameEnd;
          if (start < end) {
            onBytes(
              file,
              Uint8List.sublistView(frame, start - position, end - position),
            );
            done += end - start;
          }
          if (file.offset + file.size <= frameEnd) {
            onFile?.call(file);
            next++;
          } else {
            break;
          }
        }
        onProgress?.call(done, total);
        position = frameEnd;
        if (next == inFolder.length) break;
      }
      if (next < inFolder.length) {
        throw FormatDamage('The cabinet ends before ${inFolder[next].name}');
      }
    }
  }

  /// Writes every file beneath [directory], keeping the folders they are
  /// in, and returns their paths by name.
  Map<String, String> extractTo(
    Directory directory, {
    void Function(int done, int total)? onProgress,
  }) {
    final paths = <String, String>{};
    final open = <String, RandomAccessFile>{};
    RandomAccessFile sink(CabinetFile file) => open.putIfAbsent(file.name, () {
      final path = p.joinAll(<String>[directory.path, ...file.name.split('/')]);
      paths[file.name] = path;
      File(path).parent.createSync(recursive: true);
      return File(path).openSync(mode: FileMode.write);
    });
    try {
      read(
        onBytes: (file, bytes) => sink(file).writeFromSync(bytes),
        onFile: (file) => sink(file)
          ..flushSync()
          ..closeSync(),
        onProgress: onProgress,
      );
    } finally {
      for (final file in open.values) {
        try {
          file.closeSync();
        } on FileSystemException {
          // Closed already, when it was finished.
        }
      }
    }
    return paths;
  }

  /// The uncompressed data blocks of [folder], one after another.
  Iterable<Uint8List> _frames(_Folder folder) sync* {
    final decode = switch (folder.compression & 0xF) {
      0 => (Uint8List data, int size) => data,
      1 => _MszipDecoder().decodeBlock,
      3 => LzxDecoder((folder.compression >> 8) & 0x1F).decodeFrame,
      final other => throw FormatDamage(
        'Cabinet compression $other is not read',
      ),
    };
    var offset = folder.dataOffset;
    for (var i = 0; i < folder.blockCount; i++) {
      final header = ByteReader(_source.readAt(offset, 8));
      final checksum = header.u32();
      final compressedSize = header.u16();
      final size = header.u16();
      offset += 8 + _dataReserve;
      final data = _source.readAt(offset, compressedSize);
      offset += compressedSize;
      if (checksum != 0 &&
          _checksum(
                Uint8List.sublistView(header.bytes, 4, 8),
                _checksum(data, 0),
              ) !=
              checksum) {
        throw FormatDamage('A block of the cabinet is damaged');
      }
      yield decode(data, size);
    }
  }

  /// The cabinet checksum of [data], starting from [seed].
  static int _checksum(Uint8List data, int seed) {
    var sum = seed;
    final words = data.length >> 2;
    final view = ByteData.sublistView(data);
    for (var i = 0; i < words; i++) {
      sum ^= view.getUint32(i * 4, Endian.little);
    }
    var tail = 0;
    final at = words * 4;
    switch (data.length & 3) {
      case 3:
        tail = (data[at] << 16) | (data[at + 1] << 8) | data[at + 2];
      case 2:
        tail = (data[at] << 8) | data[at + 1];
      case 1:
        tail = data[at];
    }
    return (sum ^ tail) & 0xFFFFFFFF;
  }
}

final class _Folder {
  const _Folder({
    required this.dataOffset,
    required this.blockCount,
    required this.compression,
  });

  final int dataOffset;
  final int blockCount;
  final int compression;
}

/// MSZIP: each block is "CK" and a deflate stream whose dictionary is the
/// block before it.
final class _MszipDecoder {
  Uint8List _previous = Uint8List(0);

  Uint8List decodeBlock(Uint8List data, int size) {
    if (data.length < 2 || data[0] != 0x43 || data[1] != 0x4B) {
      throw FormatDamage('An MSZIP block has no signature');
    }
    final inflated = ZLibDecoder(
      raw: true,
      dictionary: _previous.isEmpty ? null : _previous,
    ).convert(Uint8List.sublistView(data, 2));
    if (inflated.length != size) {
      throw FormatDamage('An MSZIP block has the wrong length');
    }
    return _previous = Uint8List.fromList(inflated);
  }
}
