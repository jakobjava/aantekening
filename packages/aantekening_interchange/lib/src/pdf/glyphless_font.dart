/// A TrueType font of no glyphs to see: what a PDF's text is written in
/// when it lies unseen over a picture of itself, as a scan read by machine
/// keeps its text, so that it is read, searched and selected as text.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The font: every character in it is half as wide as it is high, and
/// draws nothing.
///
/// A PDF maps each character it writes to the one glyph there is to draw
/// (its CIDToGIDMap), and back to what it is (its ToUnicode map), so any
/// character of any script can be written in it — and none is ever seen.
abstract final class GlyphlessFont {
  /// Its name, as a PDF names it.
  static const String name = 'GlyphLessFont';

  /// How many units of the font its height is.
  static const int unitsPerEm = 1000;

  /// How wide each character is, in units of the font.
  static const int advance = 500;

  /// The font file.
  static final Uint8List bytes = _build();

  static Uint8List _build() {
    final tables = <String, Uint8List>{
      'OS/2': _os2(),
      'cmap': _cmap(),
      // Neither glyph draws anything; four bytes, as a reader may refuse
      // a table of none.
      'glyf': Uint8List(4),
      'head': _head(),
      'hhea': _hhea(),
      'hmtx':
          (_Bytes()
                ..u16(advance)
                ..i16(0)
                ..u16(advance)
                ..i16(0))
              .bytes,
      // Where each glyph begins, in two-byte words: both empty.
      'loca':
          (_Bytes()
                ..u16(0)
                ..u16(0)
                ..u16(0))
              .bytes,
      'maxp': _maxp(),
      'name': _name(),
      'post': _post(),
    };
    final tags = tables.keys.toList()..sort();
    final count = tags.length;
    var power = 1;
    var log = 0;
    while (power * 2 <= count) {
      power *= 2;
      log++;
    }
    final out = _Bytes()
      ..u32(0x00010000)
      ..u16(count)
      ..u16(power * 16)
      ..u16(log)
      ..u16(count * 16 - power * 16);
    var offset = 12 + count * 16;
    final placed = <(String, int)>[];
    for (final tag in tags) {
      final table = tables[tag]!;
      out
        ..letters(tag)
        ..u32(_checksum(table))
        ..u32(offset)
        ..u32(table.length);
      placed.add((tag, offset));
      offset += (table.length + 3) & ~3;
    }
    for (final tag in tags) {
      out
        ..add(tables[tag]!)
        ..pad();
    }
    final font = out.bytes;
    // The head table says what the whole font sums to, so it sums to a
    // number TrueType names.
    final head = placed.firstWhere((entry) => entry.$1 == 'head').$2;
    final adjustment = (0xB1B0AFBA - _checksum(font)) & 0xFFFFFFFF;
    ByteData.sublistView(font).setUint32(head + 8, adjustment);
    return font;
  }

  static Uint8List _head() =>
      (_Bytes()
            ..u32(0x00010000)
            ..u32(0x00010000)
            // What the font sums to, set once it is whole.
            ..u32(0)
            ..u32(0x5F0F3CF5)
            ..u16(0x000B)
            ..u16(unitsPerEm)
            // Made and changed: no time in particular.
            ..u32(0)
            ..u32(0)
            ..u32(0)
            ..u32(0)
            ..i16(0)
            ..i16(0)
            ..i16(advance)
            ..i16(unitsPerEm)
            ..u16(0)
            ..u16(3)
            ..i16(2)
            // Where glyphs begin is in two-byte words.
            ..i16(0)
            ..i16(0))
          .bytes;

  static Uint8List _hhea() =>
      (_Bytes()
            ..u32(0x00010000)
            ..i16(unitsPerEm)
            ..i16(0)
            ..i16(0)
            ..u16(advance)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..i16(1)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..i16(0)
            ..u16(2))
          .bytes;

  static Uint8List _maxp() {
    final out = _Bytes()
      ..u32(0x00010000)
      ..u16(2);
    // Points, contours and all the hinter's room: none, but for the two
    // zones TrueType asks for.
    for (final value in const <int>[0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0]) {
      out.u16(value);
    }
    return out.bytes;
  }

  /// Every character to the one glyph there is, for a reader that looks
  /// characters up in the font rather than in the PDF's map.
  static Uint8List _cmap() =>
      (_Bytes()
            ..u16(0)
            ..u16(1)
            ..u16(3)
            ..u16(1)
            ..u32(12)
            // Format 4: one segment, up to the last character, to glyph 0.
            ..u16(4)
            ..u16(24)
            ..u16(0)
            ..u16(2)
            ..u16(2)
            ..u16(0)
            ..u16(0)
            ..u16(0xFFFF)
            ..u16(0)
            ..u16(0xFFFF)
            ..u16(1)
            ..u16(0))
          .bytes;

  static Uint8List _name() {
    final strings = <int, String>{1: name, 2: 'Regular', 4: name, 6: name};
    final out = _Bytes()
      ..u16(0)
      ..u16(strings.length)
      ..u16(6 + strings.length * 12);
    final text = _Bytes();
    for (final MapEntry(key: id, value: value) in strings.entries) {
      final encoded = _Bytes();
      for (final unit in value.codeUnits) {
        encoded.u16(unit);
      }
      out
        ..u16(3)
        ..u16(1)
        ..u16(0x0409)
        ..u16(id)
        ..u16(encoded.length)
        ..u16(text.length);
      text.add(encoded.bytes);
    }
    return (out..add(text.bytes)).bytes;
  }

  static Uint8List _post() =>
      (_Bytes()
            ..u32(0x00030000)
            ..u32(0)
            ..i16(-100)
            ..i16(50)
            ..u32(1)
            ..u32(0)
            ..u32(0)
            ..u32(0)
            ..u32(0))
          .bytes;

  static Uint8List _os2() {
    final out = _Bytes()
      ..u16(1)
      ..i16(advance)
      ..u16(400)
      ..u16(5)
      ..u16(0);
    // Sub- and superscripts, and the strike-out line.
    for (final value in const <int>[
      650, 600, 0, 75, 650, 600, 0, 350, 50, 300, //
    ]) {
      out.i16(value);
    }
    out
      ..i16(0)
      ..add(Uint8List(10))
      // The ranges of characters it covers: all it is asked for.
      ..u32(0xFFFFFFFF)
      ..u32(0xFFFFFFFF)
      ..u32(0xFFFFFFFF)
      ..u32(0x7FFFFFFF)
      ..letters('NONE')
      ..u16(0x0040)
      ..u16(0)
      ..u16(0xFFFF)
      ..i16(unitsPerEm)
      ..i16(0)
      ..i16(0)
      ..u16(unitsPerEm)
      ..u16(0)
      ..u32(1)
      ..u32(0);
    return out.bytes;
  }

  /// What [bytes] sum to, four at a time, as TrueType sums its tables.
  static int _checksum(Uint8List bytes) {
    var sum = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      var word = 0;
      for (var j = 0; j < 4; j++) {
        word = (word << 8) | (i + j < bytes.length ? bytes[i + j] : 0);
      }
      sum = (sum + word) & 0xFFFFFFFF;
    }
    return sum;
  }
}

/// Bytes written big end first, as TrueType writes them.
class _Bytes {
  final BytesBuilder _out = BytesBuilder();

  int get length => _out.length;
  Uint8List get bytes => _out.toBytes();

  void u16(int value) => _out.add(<int>[(value >> 8) & 0xFF, value & 0xFF]);
  void i16(int value) => u16(value & 0xFFFF);
  void u32(int value) => _out.add(<int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
  void letters(String text) => _out.add(ascii.encode(text));
  void add(List<int> bytes) => _out.add(bytes);

  /// Zeros up to the next four bytes.
  void pad() {
    while (_out.length % 4 != 0) {
      _out.addByte(0);
    }
  }
}
