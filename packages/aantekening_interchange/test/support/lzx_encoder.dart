/// A small LZX encoder and cabinet writer, for testing the decoder: it
/// writes every kind of block and tree the decoder reads, simply rather
/// than well.
library;

import 'dart:typed_data';

/// Writes bits most significant first into 16-bit little-endian words.
final class BitWriter {
  final BytesBuilder _bytes = BytesBuilder();
  int _word = 0;
  int _count = 0;

  bool get aligned => _count == 0;

  void write(int value, int bits) {
    for (var i = bits - 1; i >= 0; i--) {
      _word = (_word << 1) | ((value >> i) & 1);
      if (++_count == 16) {
        _bytes
          ..addByte(_word & 0xFF)
          ..addByte(_word >> 8);
        _word = 0;
        _count = 0;
      }
    }
  }

  void align() {
    if (_count > 0) write(0, 16 - _count);
  }

  void raw(List<int> bytes) {
    assert(aligned);
    _bytes.add(bytes);
  }

  Uint8List take() {
    align();
    return _bytes.takeBytes();
  }
}

/// A complete prefix code over [used] of [size] symbols: as many as it can
/// one bit shorter, the rest the same length.
Uint8List flatLengths(int size, Set<int> used) {
  final symbols = used.toList()..sort();
  while (symbols.length < 2) {
    symbols.add(
      List<int>.generate(
        size,
        (i) => i,
      ).firstWhere((s) => !symbols.contains(s)),
    );
  }
  symbols.sort();
  var k = 0;
  while ((1 << k) < symbols.length) {
    k++;
  }
  final short = (1 << k) - symbols.length;
  final lengths = Uint8List(size);
  for (var i = 0; i < symbols.length; i++) {
    lengths[symbols[i]] = i < short ? k - 1 : k;
  }
  return lengths;
}

/// The canonical codes of [lengths], as the decoder assigns them.
List<int> canonicalCodes(Uint8List lengths) {
  final codes = List<int>.filled(lengths.length, 0);
  var code = 0;
  var longest = 0;
  for (final length in lengths) {
    if (length > longest) longest = length;
  }
  for (var bits = 1; bits <= longest; bits++) {
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      if (lengths[symbol] == bits) codes[symbol] = code++;
    }
    code <<= 1;
  }
  return codes;
}

int _footerBits(int slot) => slot < 4 ? 0 : (slot >= 36 ? 17 : (slot - 2) >> 1);

final List<int> _bases = () {
  final bases = List<int>.filled(52, 0);
  for (var slot = 1; slot < bases.length; slot++) {
    bases[slot] = bases[slot - 1] + (1 << _footerBits(slot - 1));
  }
  return bases;
}();

/// A literal, or a match of [length] bytes [offset] back.
typedef _Token = ({int literal, int length, int offset});

/// The kinds of block the encoder writes, in turn.
enum TestBlock { verbatim, aligned, stored }

/// Encodes [input] as LZX with a window of 2^[windowBits] bytes, in blocks
/// of [blockSize] bytes of the kinds [blocks] cycles through; returns each
/// 32 KiB frame's compressed bytes with its uncompressed size.
List<(Uint8List, int)> encodeLzx(
  Uint8List input, {
  int windowBits = 16,
  int blockSize = 20000,
  List<TestBlock> blocks = const <TestBlock>[TestBlock.verbatim],
}) {
  final slots = switch (windowBits) {
    20 => 42,
    21 => 50,
    _ => windowBits * 2,
  };
  final mainLengths = Uint8List(256 + 8 * slots);
  final lengthLengths = Uint8List(249);
  var r0 = 1, r1 = 1, r2 = 1;

  // Tokens: greedy matching against earlier text, never across a frame.
  final tokens = <_Token>[];
  final frameOf = <int>[];
  final last = <int, int>{};
  var i = 0;
  while (i < input.length) {
    final frameEnd = ((i ~/ 32768) + 1) * 32768;
    _Token token = (literal: input[i], length: 1, offset: 0);
    if (i + 3 <= input.length) {
      final key = input[i] | (input[i + 1] << 8) | (input[i + 2] << 16);
      final previous = last[key];
      if (previous != null && i - previous < (1 << windowBits) - 3) {
        var length = 0;
        while (length < 257 &&
            i + length < input.length &&
            i + length < frameEnd &&
            input[previous + length] == input[i + length]) {
          length++;
        }
        if (length >= 3) {
          token = (literal: -1, length: length, offset: i - previous);
        }
      }
      last[key] = i;
    }
    tokens.add(token);
    frameOf.add(i ~/ 32768);
    i += token.length;
  }

  final writer = BitWriter()..write(0, 1); // No E8 translation.
  final frames = <(Uint8List, int)>[];
  var produced = 0;
  var tokenIndex = 0;
  var blockNumber = 0;

  void endFrameIfFull() {
    if (produced > 0 && produced % 32768 == 0) {
      frames.add((writer.take(), 32768));
    }
  }

  while (tokenIndex < tokens.length) {
    final kind = blocks[blockNumber++ % blocks.length];
    // The tokens of this block.
    final start = tokenIndex;
    var size = 0;
    while (tokenIndex < tokens.length && size < blockSize) {
      size += tokens[tokenIndex++].length;
    }
    final blockTokens = tokens.sublist(start, tokenIndex);

    if (kind == TestBlock.stored) {
      // Stored blocks here stay inside one frame.
      final bytes = <int>[];
      for (final token in blockTokens) {
        final from = produced + bytes.length;
        bytes.addAll(input.sublist(from, from + token.length));
      }
      final frameLeft = 32768 - produced % 32768;
      if (bytes.length > frameLeft) {
        tokenIndex = start;
        blockNumber++;
        continue;
      }
      writer
        ..write(3, 3)
        ..write(bytes.length >> 8, 16)
        ..write(bytes.length & 0xFF, 8);
      if (writer.aligned) {
        writer.write(0, 16);
      } else {
        writer.align();
      }
      for (final r in <int>[r0, r1, r2]) {
        writer.raw(<int>[r & 0xFF, (r >> 8) & 0xFF, (r >> 16) & 0xFF, r >> 24]);
      }
      writer.raw(bytes);
      if (bytes.length.isOdd) writer.raw(<int>[0]);
      produced += bytes.length;
      endFrameIfFull();
      continue;
    }

    // Work out the symbols, as the decoder will read them.
    var s0 = r0, s1 = r1, s2 = r2;
    final symbols = <({int main, int? length, int slot, int footer})>[];
    for (final token in blockTokens) {
      if (token.literal >= 0) {
        symbols.add((main: token.literal, length: null, slot: -1, footer: 0));
        continue;
      }
      final int slot;
      var footer = 0;
      if (token.offset == s0) {
        slot = 0;
      } else if (token.offset == s1) {
        slot = 1;
        s1 = s0;
        s0 = token.offset;
      } else if (token.offset == s2) {
        slot = 2;
        s2 = s0;
        s0 = token.offset;
      } else {
        final formatted = token.offset + 2;
        var found = 3;
        while (_bases[found + 1] <= formatted) {
          found++;
        }
        slot = found;
        footer = formatted - _bases[slot];
        s2 = s1;
        s1 = s0;
        s0 = token.offset;
      }
      final header = token.length - 2 < 7 ? token.length - 2 : 7;
      symbols.add((
        main: 256 + slot * 8 + header,
        length: header == 7 ? token.length - 9 : null,
        slot: slot,
        footer: footer,
      ));
    }

    final newMain = flatLengths(mainLengths.length, <int>{
      for (final symbol in symbols) symbol.main,
    });
    final lengthUsed = <int>{
      for (final symbol in symbols)
        if (symbol.length != null) symbol.length!,
    };
    final newLength = lengthUsed.isEmpty
        ? Uint8List(249)
        : flatLengths(249, lengthUsed);
    final aligned = kind == TestBlock.aligned
        ? flatLengths(8, <int>{
            for (final symbol in symbols)
              if (symbol.slot >= 3 && _footerBits(symbol.slot) >= 3)
                symbol.footer & 7,
          })
        : null;

    writer
      ..write(kind == TestBlock.aligned ? 2 : 1, 3)
      ..write(size >> 8, 16)
      ..write(size & 0xFF, 8);
    if (aligned != null) {
      for (final length in aligned) {
        writer.write(length, 3);
      }
    }
    _writeLengths(writer, mainLengths, newMain, 0, 256);
    _writeLengths(writer, mainLengths, newMain, 256, mainLengths.length);
    _writeLengths(writer, lengthLengths, newLength, 0, 249);

    final mainCodes = canonicalCodes(newMain);
    final lengthCodes = canonicalCodes(newLength);
    final alignedCodes = aligned == null ? null : canonicalCodes(aligned);
    for (var t = 0; t < symbols.length; t++) {
      final symbol = symbols[t];
      final frameBefore = produced ~/ 32768;
      writer.write(mainCodes[symbol.main], newMain[symbol.main]);
      if (symbol.length != null) {
        writer.write(lengthCodes[symbol.length!], newLength[symbol.length!]);
      }
      if (symbol.slot >= 3) {
        final bits = _footerBits(symbol.slot);
        if (aligned != null && bits >= 3) {
          writer
            ..write(symbol.footer >> 3, bits - 3)
            ..write(
              alignedCodes![symbol.footer & 7],
              aligned[symbol.footer & 7],
            );
        } else {
          writer.write(symbol.footer, bits);
        }
      }
      produced += blockTokens[t].length;
      assert(produced ~/ 32768 == frameBefore || produced % 32768 == 0);
      endFrameIfFull();
    }
    r0 = s0;
    r1 = s1;
    r2 = s2;
  }
  if (produced % 32768 != 0) frames.add((writer.take(), produced % 32768));
  return frames;
}

/// Sends [next]'s lengths from [from] to [to] as changes from [previous],
/// through a pretree, and makes them [previous] for the next block.
void _writeLengths(
  BitWriter writer,
  Uint8List previous,
  Uint8List next,
  int from,
  int to,
) {
  final codes = <(int, int?)>[]; // Pretree code, and its extra bits.
  var i = from;
  while (i < to) {
    var zeros = 0;
    while (i + zeros < to && next[i + zeros] == 0 && zeros < 51) {
      zeros++;
    }
    if (zeros >= 20) {
      codes.add((18, zeros - 20));
      i += zeros;
      continue;
    }
    if (zeros >= 4) {
      codes.add((17, zeros - 4));
      i += zeros;
      continue;
    }
    codes.add(((17 + previous[i] - next[i]) % 17, null));
    i++;
  }
  final pretree = flatLengths(20, <int>{for (final code in codes) code.$1});
  final pretreeCodes = canonicalCodes(pretree);
  for (final length in pretree) {
    writer.write(length, 4);
  }
  for (final (code, extra) in codes) {
    writer.write(pretreeCodes[code], pretree[code]);
    if (code == 17) writer.write(extra!, 4);
    if (code == 18) writer.write(extra!, 5);
  }
  previous.setRange(from, to, next.sublist(from, to));
}

/// The cabinet checksum of [data], from [seed].
int cabinetChecksum(Uint8List data, int seed) {
  var sum = seed;
  final view = ByteData.sublistView(data);
  final words = data.length >> 2;
  for (var i = 0; i < words; i++) {
    sum ^= view.getUint32(i * 4, Endian.little);
  }
  final at = words * 4;
  final tail = switch (data.length & 3) {
    3 => (data[at] << 16) | (data[at + 1] << 8) | data[at + 2],
    2 => (data[at] << 8) | data[at + 1],
    1 => data[at],
    _ => 0,
  };
  return (sum ^ tail) & 0xFFFFFFFF;
}

/// A cabinet of [files], by name, in one folder compressed with
/// [compression] (0 stored, 3 LZX) from the frames [encode] makes.
Uint8List writeCabinet(
  Map<String, Uint8List> files, {
  required int compression,
  required List<(Uint8List, int)> Function(Uint8List all) encode,
  bool checksums = true,
}) {
  final all = BytesBuilder(copy: false);
  for (final file in files.values) {
    all.add(file);
  }
  final frames = encode(all.takeBytes());

  final names = <List<int>>[
    for (final name in files.keys) <int>[...name.codeUnits.expand(_utf8), 0],
  ];
  const headerSize = 36;
  const folderSize = 8;
  final filesSize = names.fold<int>(0, (sum, name) => sum + 16 + name.length);
  final dataStart = headerSize + folderSize + filesSize;
  final out = BytesBuilder();
  final dataSize = frames.fold<int>(
    0,
    (sum, frame) => sum + 8 + frame.$1.length,
  );

  void u8(int v) => out.addByte(v & 0xFF);
  void u16(int v) {
    u8(v);
    u8(v >> 8);
  }

  void u32(int v) {
    u16(v & 0xFFFF);
    u16(v >> 16);
  }

  out.add('MSCF'.codeUnits);
  u32(0);
  u32(dataStart + dataSize);
  u32(0);
  u32(headerSize + folderSize);
  u32(0);
  u8(3);
  u8(1);
  u16(1);
  u16(files.length);
  u16(0);
  u16(0);
  u16(0);
  // The folder.
  u32(dataStart);
  u16(frames.length);
  u16(compression);
  // The files.
  var offset = 0;
  var index = 0;
  for (final entry in files.entries) {
    u32(entry.value.length);
    u32(offset);
    u16(0);
    u16(0);
    u16(0);
    u16(0x80);
    out.add(names[index++]);
    offset += entry.value.length;
  }
  // The data blocks.
  for (final (data, size) in frames) {
    final sizes = Uint8List(4)
      ..buffer.asByteData().setUint16(0, data.length, Endian.little)
      ..buffer.asByteData().setUint16(2, size, Endian.little);
    u32(checksums ? cabinetChecksum(sizes, cabinetChecksum(data, 0)) : 0);
    out.add(sizes);
    out.add(data);
  }
  return out.takeBytes();
}

Iterable<int> _utf8(int unit) sync* {
  if (unit < 0x80) {
    yield unit;
  } else if (unit < 0x800) {
    yield 0xC0 | (unit >> 6);
    yield 0x80 | (unit & 0x3F);
  } else {
    yield 0xE0 | (unit >> 12);
    yield 0x80 | ((unit >> 6) & 0x3F);
    yield 0x80 | (unit & 0x3F);
  }
}
