/// Reading little-endian binary structures.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a file is not what it claims to be, or is damaged.
class FormatDamage implements Exception {
  FormatDamage(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads little-endian values from [bytes], from [position] on.
///
/// Every read is checked against the end of the bytes, so a damaged file
/// fails with a [FormatDamage] saying where, rather than with a range error
/// or, worse, with values read from past its end.
final class ByteReader {
  ByteReader(this.bytes, [this.position = 0])
    : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _data;
  int position;

  int get length => bytes.length;
  int get remaining => bytes.length - position;
  bool get atEnd => position >= bytes.length;

  void _need(int count) {
    if (count < 0 || position + count > bytes.length) {
      throw FormatDamage(
        'Needed $count bytes at $position, but the data ends at '
        '${bytes.length}',
      );
    }
  }

  int u8() {
    _need(1);
    return bytes[position++];
  }

  int u16() {
    _need(2);
    final value = _data.getUint16(position, Endian.little);
    position += 2;
    return value;
  }

  int u32() {
    _need(4);
    final value = _data.getUint32(position, Endian.little);
    position += 4;
    return value;
  }

  int i32() {
    _need(4);
    final value = _data.getInt32(position, Endian.little);
    position += 4;
    return value;
  }

  int u64() {
    _need(8);
    final value = _data.getUint64(position, Endian.little);
    position += 8;
    return value;
  }

  double f32() {
    _need(4);
    final value = _data.getFloat32(position, Endian.little);
    position += 4;
    return value;
  }

  /// The next [count] bytes, as a view of the same memory.
  Uint8List take(int count) {
    _need(count);
    final view = Uint8List.sublistView(bytes, position, position + count);
    position += count;
    return view;
  }

  void skip(int count) {
    _need(count);
    position += count;
  }

  /// A reader over the [count] bytes at [offset], leaving this one where it
  /// is.
  ByteReader at(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > bytes.length) {
      throw FormatDamage(
        'A reference to $count bytes at $offset points past the end, '
        '${bytes.length}',
      );
    }
    return ByteReader(Uint8List.sublistView(bytes, offset, offset + count));
  }

  Guid guid() => Guid(take(16));
}

/// A GUID, compared by value.
final class Guid {
  Guid(Uint8List bytes) : _bytes = Uint8List.fromList(bytes) {
    if (bytes.length != 16) throw ArgumentError.value(bytes, 'bytes');
  }

  /// Parses the usual textual form, braces or not:
  /// `7B5C52E4-D88C-4DA7-AEB1-5378D02996D3`.
  factory Guid.parse(String text) {
    final hex = text.replaceAll(RegExp(r'[{}-]'), '');
    if (hex.length != 32) throw FormatException('Not a GUID', text);
    int byte(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    // The first three groups are stored little-endian.
    return Guid(
      Uint8List.fromList(<int>[
        byte(3), byte(2), byte(1), byte(0), //
        byte(5), byte(4),
        byte(7), byte(6),
        for (var i = 8; i < 16; i++) byte(i),
      ]),
    );
  }

  static final Guid nil = Guid(Uint8List(16));

  final Uint8List _bytes;

  /// Its sixteen bytes, as a file holds them.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  bool get isNil => _bytes.every((byte) => byte == 0);

  /// This GUID with every byte exclusive-ored with [other]'s.
  Guid xor(Guid other) => Guid(
    Uint8List.fromList(<int>[
      for (var i = 0; i < 16; i++) _bytes[i] ^ other._bytes[i],
    ]),
  );

  @override
  bool operator ==(Object other) {
    if (other is! Guid) return false;
    for (var i = 0; i < 16; i++) {
      if (other._bytes[i] != _bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() {
    String hex(int from, int to, {bool reversed = false}) {
      final part = _bytes.sublist(from, to);
      return (reversed ? part.reversed : part)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    }

    return '${hex(0, 4, reversed: true)}-${hex(4, 6, reversed: true)}-'
        '${hex(6, 8, reversed: true)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

/// Decodes UTF-16LE [bytes], dropping a terminating nul and anything after
/// it.
String utf16Text(Uint8List bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final unit = bytes[i] | (bytes[i + 1] << 8);
    if (unit == 0) break;
    units.add(unit);
  }
  return String.fromCharCodes(units);
}

/// Decodes [bytes] as UTF-8 if they are valid UTF-8, and as Windows-1252
/// otherwise: names in archives are often UTF-8 without saying so.
String utf8OrLatin(Uint8List bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes.map(windows1252));
  }
}

/// The character Windows-1252 byte [byte] stands for.
int windows1252(int byte) =>
    byte >= 0x80 && byte < 0xA0 ? _windows1252High[byte - 0x80] : byte;

const List<int> _windows1252High = <int>[
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];
