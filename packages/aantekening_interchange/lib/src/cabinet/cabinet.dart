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
  Cabinet._(
    this._source,
    this._folders,
    this.files,
    this._dataReserve,
    this._limit,
  );

  /// Reads the directory of the cabinet in [source], which is unpacked to
  /// at most [limit] bytes, by default [unpackedLimit] of its length.
  factory Cabinet.read(RandomSource source, {int? limit}) {
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

    // Each entry is sixteen bytes and its name, of 256 bytes at most —
    // though a little more is let be.
    final directory = ByteReader(
      source.readAt(
        filesOffset,
        _min(source.length - filesOffset, fileCount * (16 + 1024)),
      ),
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
    return Cabinet._(
      source,
      folders,
      files,
      dataReserve,
      limit ?? unpackedLimit(source.length),
    );
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// The most a cabinet of [length] bytes is unpacked to: far more than
  /// any notebook compresses by, far less than LZX can make out of next
  /// to nothing — 32 KiB out of a few bytes — which would fill the disk.
  static int unpackedLimit(int length) => (256 << 20) + 100 * length;

  /// [name] with backslashes as slashes, and with no part that would climb
  /// out of the folder it is extracted to — nor any Windows would read as
  /// one that does: it drops the dots and spaces a part ends in, so `.. `
  /// and `...` are `..` to it.
  static String _normalise(String name) => <String>[
    for (final part in name.split(RegExp(r'[/\\]')))
      if (part.replaceFirst(RegExp(r'[. ]+$'), '') case final kept
          when kept.isNotEmpty)
        kept,
  ].join('/');

  final RandomSource _source;
  final List<_Folder> _folders;
  final List<CabinetFile> files;
  final int _dataReserve;
  final int _limit;

  /// Decompresses every folder, handing each file's bytes to [onBytes] in
  /// order, a piece at a time, and calling [onFile] once each file is
  /// complete.
  void read({
    required void Function(CabinetFile file, Uint8List bytes) onBytes,
    void Function(CabinetFile file)? onFile,
    void Function(int done, int total)? onProgress,
  }) {
    final total = files.fold<int>(0, (sum, file) => sum + file.size);
    final limit = _limit;
    if (total > limit) {
      throw FormatDamage(
        'The cabinet says it holds more than it can: '
        '${total >> 20} MiB in ${_source.length >> 20} MiB',
      );
    }
    var done = 0;
    var decoded = 0;
    // The files of each folder, gathered once rather than looked for
    // among them all for each.
    final byFolder = <int, List<CabinetFile>>{};
    for (final file in files) {
      (byFolder[file.folder] ??= <CabinetFile>[]).add(file);
    }
    for (var index = 0; index < _folders.length; index++) {
      final inFolder = byFolder[index];
      if (inFolder == null) continue;
      inFolder.sort((a, b) => a.offset.compareTo(b.offset));
      var next = 0;
      var position = 0;
      for (final frame in _frames(_folders[index])) {
        final frameEnd = position + frame.length;
        decoded += frame.length;
        if (decoded > limit) {
          throw FormatDamage('The cabinet unpacks to more than it can hold');
        }
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
  /// in, and returns their paths by name: a file named as one before it is
  /// numbered, as `Notes (2).one`, and one with no name at all left out.
  Map<String, String> extractTo(
    Directory directory, {
    void Function(int done, int total)? onProgress,
  }) {
    final paths = <String, String>{};
    final open = Map<CabinetFile, RandomAccessFile?>.identity();
    RandomAccessFile? sink(CabinetFile file) => open.putIfAbsent(file, () {
      if (file.name.isEmpty) return null;
      var name = file.name;
      for (var n = 2; paths.containsKey(name); n++) {
        final extension = p.url.extension(file.name);
        name =
            '${file.name.substring(0, file.name.length - extension.length)} '
            '($n)$extension';
      }
      final path = p.joinAll(<String>[directory.path, ...name.split('/')]);
      if (!p.isWithin(directory.path, path)) return null;
      paths[name] = path;
      File(path).parent.createSync(recursive: true);
      return File(path).openSync(mode: FileMode.write);
    });
    try {
      read(
        onBytes: (file, bytes) => sink(file)?.writeFromSync(bytes),
        onFile: (file) => sink(file)
          ?..flushSync()
          ..closeSync(),
        onProgress: onProgress,
      );
    } finally {
      for (final file in open.values.nonNulls) {
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
