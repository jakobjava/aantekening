/// LZX decompression, as Microsoft cabinets use it.
library;

import 'dart:typed_data';

import '../bytes.dart';

/// Decompresses one LZX stream — a cabinet folder — frame by frame.
///
/// Written from Microsoft's description of the format ([MS-PATCH] "LZX
/// DELTA Compression and Decompression", which LZX in cabinets is the
/// original of): a sliding window of 2^[windowBits] bytes; blocks that are
/// verbatim, aligned-offset or stored; Huffman trees sent as the difference
/// from the block before, themselves coded by a small "pretree"; and three
/// repeated match offsets carried from block to block.
///
/// Each cabinet data block is one frame: its compressed bytes decode to
/// the number of bytes the block says, 32 KiB for all but the last, and
/// blocks may continue from one frame into the next.
final class LzxDecoder {
  LzxDecoder(int windowBits)
    : assert(windowBits >= 15 && windowBits <= 21),
      _window = Uint8List(1 << windowBits),
      _positionSlots = _slotsFor(windowBits) {
    _mainLengths = Uint8List(_literals + 8 * _positionSlots);
  }

  static const int _literals = 256;
  static const int _lengthSymbols = 249;
  static const int _pretreeSymbols = 20;
  static const int _alignedSymbols = 8;

  static int _slotsFor(int windowBits) => switch (windowBits) {
    20 => 42,
    21 => 50,
    _ => windowBits * 2,
  };

  final Uint8List _window;
  final int _positionSlots;
  int _windowPosition = 0;

  late final Uint8List _mainLengths;
  final Uint8List _lengthLengths = Uint8List(_lengthSymbols);

  int _r0 = 1, _r1 = 1, _r2 = 1;

  bool _started = false;
  int _translationSize = 0;
  int _framesOffset = 0;

  _BlockType? _blockType;
  int _blockRemaining = 0;
  int _blockLength = 0;
  _HuffmanTable? _mainTree;
  _HuffmanTable? _lengthTree;
  _HuffmanTable? _alignedTree;

  /// Decodes the next frame, [input], into its [outputLength] bytes.
  Uint8List decodeFrame(Uint8List input, int outputLength) {
    if (outputLength > _window.length) {
      throw FormatDamage('An LZX frame is larger than its window');
    }
    final bits = _BitReader(input);
    if (!_started) {
      _started = true;
      if (bits.read(1) == 1) _translationSize = bits.read(32);
    }

    final frameStart = _windowPosition;
    var decoded = 0;
    while (decoded < outputLength) {
      if (_blockRemaining == 0) {
        // A stored block of an odd length is padded to an even one.
        if (_blockType == _BlockType.stored && _blockLength.isOdd) {
          bits.skipRawByte();
        }
        _readBlockHeader(bits);
      }
      final wanted = outputLength - decoded;
      final advanced = _blockType == _BlockType.stored
          ? _copyStored(bits, wanted)
          : _decodeTokens(bits, wanted);
      decoded += advanced;
      _blockRemaining -= advanced;
    }

    // The frame as it lies in the window, which it may run off the end of
    // and on at the start.
    final output = Uint8List(outputLength);
    final first = _window.length - frameStart < outputLength
        ? _window.length - frameStart
        : outputLength;
    output
      ..setRange(0, first, _window, frameStart)
      ..setRange(first, outputLength, _window);
    if (_translationSize != 0 &&
        outputLength > 10 &&
        _framesOffset < 0x40000000) {
      _undoE8Translation(output, _framesOffset);
    }
    _framesOffset += outputLength;
    return output;
  }

  void _readBlockHeader(_BitReader bits) {
    final type = bits.read(3);
    final length = (bits.read(16) << 8) | bits.read(8);
    if (length == 0) throw FormatDamage('An LZX block is empty');
    _blockLength = _blockRemaining = length;
    switch (type) {
      case 1:
        _blockType = _BlockType.verbatim;
        _alignedTree = null;
        _readMainAndLengthTrees(bits);
      case 2:
        _blockType = _BlockType.aligned;
        final aligned = Uint8List(_alignedSymbols);
        for (var i = 0; i < _alignedSymbols; i++) {
          aligned[i] = bits.read(3);
        }
        _alignedTree = _HuffmanTable.of(aligned);
        _readMainAndLengthTrees(bits);
      case 3:
        _blockType = _BlockType.stored;
        bits.alignToWord();
        _r0 = bits.readRawU32();
        _r1 = bits.readRawU32();
        _r2 = bits.readRawU32();
      default:
        throw FormatDamage('LZX block type $type does not exist');
    }
  }

  void _readMainAndLengthTrees(_BitReader bits) {
    _updateLengths(bits, _mainLengths, 0, _literals);
    _updateLengths(bits, _mainLengths, _literals, _mainLengths.length);
    _mainTree = _HuffmanTable.of(_mainLengths);
    if (_mainTree == null) throw FormatDamage('An LZX main tree is empty');
    _updateLengths(bits, _lengthLengths, 0, _lengthSymbols);
    // The length tree may be empty, if no match in the block is long.
    _lengthTree = _HuffmanTable.of(_lengthLengths);
  }

  /// Reads the pretree, then with it the new code lengths of [lengths]
  /// from [from] to [to], each sent as its difference from the last.
  static void _updateLengths(
    _BitReader bits,
    Uint8List lengths,
    int from,
    int to,
  ) {
    final pretreeLengths = Uint8List(_pretreeSymbols);
    for (var i = 0; i < _pretreeSymbols; i++) {
      pretreeLengths[i] = bits.read(4);
    }
    final pretree = _HuffmanTable.of(pretreeLengths);
    if (pretree == null) throw FormatDamage('An LZX pretree is empty');

    int delta(int previous, int code) => (17 + previous - code) % 17;
    void fill(int at, int count, int value) {
      if (at + count > to) throw FormatDamage('An LZX run is too long');
      lengths.fillRange(at, at + count, value);
    }

    var i = from;
    while (i < to) {
      final code = pretree.decode(bits);
      switch (code) {
        case < 17:
          lengths[i] = delta(lengths[i], code);
          i++;
        case 17:
          final count = bits.read(4) + 4;
          fill(i, count, 0);
          i += count;
        case 18:
          final count = bits.read(5) + 20;
          fill(i, count, 0);
          i += count;
        case 19:
          final count = bits.read(1) + 4;
          final next = pretree.decode(bits);
          if (next > 16) throw FormatDamage('An LZX pretree code is wrong');
          fill(i, count, delta(lengths[i], next));
          i += count;
        default:
          throw FormatDamage('An LZX pretree code is wrong');
      }
    }
  }

  /// Copies what is left of a stored block in this frame, up to [wanted]
  /// bytes, returning how many.
  int _copyStored(_BitReader bits, int wanted) {
    final count = [
      wanted,
      _blockRemaining,
      bits.remainingRawBytes,
    ].reduce((a, b) => a < b ? a : b);
    if (count == 0) throw FormatDamage('An LZX stored block is cut short');
    for (var i = 0; i < count; i++) {
      _put(bits.readRawByte());
    }
    return count;
  }

  /// Decodes literals and matches until the block ends or [wanted] bytes
  /// are out, returning how many were.
  int _decodeTokens(_BitReader bits, int wanted) {
    final main = _mainTree!;
    final limit = wanted < _blockRemaining ? wanted : _blockRemaining;
    var produced = 0;
    while (produced < limit) {
      final symbol = main.decode(bits);
      if (symbol < _literals) {
        _put(symbol);
        produced++;
        continue;
      }
      final token = symbol - _literals;
      var length = token & 7;
      if (length == 7) {
        final lengths = _lengthTree;
        if (lengths == null) throw FormatDamage('An LZX length is missing');
        length += lengths.decode(bits);
      }
      length += 2;
      final slot = token >> 3;
      final int offset;
      switch (slot) {
        case 0:
          offset = _r0;
        case 1:
          offset = _r1;
          _r1 = _r0;
          _r0 = offset;
        case 2:
          offset = _r2;
          _r2 = _r0;
          _r0 = offset;
        default:
          offset = _readOffset(bits, slot);
          _r2 = _r1;
          _r1 = _r0;
          _r0 = offset;
      }
      if (produced + length > _blockRemaining) {
        throw FormatDamage('An LZX match runs past its block');
      }
      _copyMatch(offset, length);
      produced += length;
    }
    return produced;
  }

  int _readOffset(_BitReader bits, int slot) {
    final footer = _footerBits(slot);
    final aligned = _alignedTree;
    int extra;
    if (aligned != null && footer >= 3) {
      extra = (bits.read(footer - 3) << 3) + aligned.decode(bits);
    } else {
      extra = bits.read(footer);
    }
    return _basePositions[slot] + extra - 2;
  }

  static int _footerBits(int slot) =>
      slot < 4 ? 0 : (slot >= 36 ? 17 : (slot - 2) >> 1);

  /// Where each position slot's offsets start: every slot covers
  /// 2^footer bits of offsets after the one before it.
  static final List<int> _basePositions = () {
    final bases = List<int>.filled(290, 0);
    for (var slot = 1; slot < bases.length; slot++) {
      bases[slot] = bases[slot - 1] + (1 << _footerBits(slot - 1));
    }
    return bases;
  }();

  void _put(int byte) {
    _window[_windowPosition] = byte;
    _windowPosition = (_windowPosition + 1) & (_window.length - 1);
  }

  void _copyMatch(int offset, int length) {
    if (offset <= 0 || offset > _window.length) {
      throw FormatDamage('An LZX match points outside its window');
    }
    final mask = _window.length - 1;
    var from = (_windowPosition - offset) & mask;
    for (var i = 0; i < length; i++) {
      _window[_windowPosition] = _window[from];
      _windowPosition = (_windowPosition + 1) & mask;
      from = (from + 1) & mask;
    }
  }

  /// Undoes the x86 call translation an encoder may apply: the address
  /// after each 0xE8 byte was made absolute, and is made relative again.
  void _undoE8Translation(Uint8List data, int offset) {
    final end = data.length - 10;
    var i = 0;
    while (i < end) {
      if (data[i] != 0xE8) {
        i++;
        continue;
      }
      final current = offset + i;
      final view = ByteData.sublistView(data, i + 1, i + 5);
      final absolute = view.getInt32(0, Endian.little);
      if (absolute >= -current && absolute < _translationSize) {
        final relative = absolute >= 0
            ? absolute - current
            : absolute + _translationSize;
        view.setInt32(0, relative, Endian.little);
      }
      i += 5;
    }
  }
}

enum _BlockType { verbatim, aligned, stored }

/// Bits read most significant first from 16-bit little-endian words, as
/// LZX writes them; and, within stored blocks, bytes read directly.
///
/// Words are taken into a buffer a few at a time, so that looking at the
/// next bits and taking them is a shift and a mask, not a loop.
final class _BitReader {
  _BitReader(this._bytes);

  final Uint8List _bytes;

  /// Where the next word not yet in [_buffer] starts.
  int _position = 0;

  /// The bits taken in and not yet read: the low [_count] bits.
  int _buffer = 0;
  int _count = 0;

  /// Takes in words until at least [count] bits wait. Past the end, zeros:
  /// the last code of a frame may be followed by fewer padding bits than
  /// the widest code a tree has.
  void _fill(int count) {
    while (_count < count) {
      final word = _position + 1 < _bytes.length
          ? _bytes[_position] | (_bytes[_position + 1] << 8)
          : 0;
      _position += 2;
      _buffer = (_buffer << 16) | word;
      _count += 16;
    }
  }

  void _skip(int count) {
    _count -= count;
    _buffer &= (1 << _count) - 1;
  }

  /// Reads [count] bits, up to 32.
  int read(int count) {
    if (count == 0) return 0;
    _fill(count);
    final value = _buffer >> (_count - count);
    _skip(count);
    return value;
  }

  /// The next [count] bits, up to 32, without reading them.
  int peek(int count) {
    _fill(count);
    return _buffer >> (_count - count);
  }

  /// Moves to the start of the next word: a stored block's header is
  /// followed by one to sixteen bits of padding, never none.
  void alignToWord() {
    final partial = _count % 16;
    if (partial == 0) {
      read(16);
    } else {
      _skip(partial);
    }
  }

  /// Gives back the whole words taken in and not read, for bytes to be
  /// read from where the bits stopped. Only at the start of a word.
  void _giveBack() {
    _position -= _count ~/ 8;
    _buffer = 0;
    _count = 0;
  }

  /// A 32-bit little-endian value from the next two words.
  int readRawU32() {
    final low = read(16);
    return low | (read(16) << 16);
  }

  int get remainingRawBytes {
    _giveBack();
    return _position < _bytes.length ? _bytes.length - _position : 0;
  }

  int readRawByte() {
    _giveBack();
    if (_position >= _bytes.length) {
      throw FormatDamage('An LZX stored block is cut short');
    }
    return _bytes[_position++];
  }

  void skipRawByte() {
    _giveBack();
    _position++;
  }
}

/// A canonical Huffman code, decoded by looking up as many bits as its
/// longest code has.
final class _HuffmanTable {
  _HuffmanTable._(this._lengths, this._table, this._bits);

  /// The table for code [lengths], or null if every length is zero.
  static _HuffmanTable? of(Uint8List lengths) {
    var longest = 0;
    for (final length in lengths) {
      if (length > longest) longest = length;
    }
    if (longest == 0) return null;
    final table = Uint16List(1 << longest);
    var position = 0;
    for (var bits = 1; bits <= longest; bits++) {
      final span = 1 << (longest - bits);
      for (var symbol = 0; symbol < lengths.length; symbol++) {
        if (lengths[symbol] != bits) continue;
        if (position + span > table.length) {
          throw FormatDamage('An LZX Huffman code is over-full');
        }
        table.fillRange(position, position + span, symbol);
        position += span;
      }
    }
    if (position != table.length) {
      throw FormatDamage('An LZX Huffman code is incomplete');
    }
    return _HuffmanTable._(Uint8List.fromList(lengths), table, longest);
  }

  final Uint8List _lengths;
  final Uint16List _table;
  final int _bits;

  int decode(_BitReader reader) {
    final symbol = _table[reader.peek(_bits)];
    reader._skip(_lengths[symbol]);
    return symbol;
  }
}
