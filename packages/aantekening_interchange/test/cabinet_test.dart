import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_interchange/src/cabinet/lzx.dart';
import 'package:test/test.dart';

import 'support/lzx_encoder.dart';

/// Text with enough repetition for matches, and enough variety for every
/// kind of match offset.
Uint8List sampleText(int length, {int seed = 1}) {
  final random = math.Random(seed);
  const words = <String>[
    'notebook', 'section', 'page', 'formula', 'integral', 'Gauß', //
    'Übergang', 'matrix', 'OneNote', 'x', 'the', 'of', '∫', 'π',
  ];
  final out = BytesBuilder();
  while (out.length < length) {
    if (random.nextInt(40) == 0) {
      // Now and then, bytes a text would not have.
      out.add(
        List<int>.generate(random.nextInt(64), (_) => random.nextInt(256)),
      );
    } else {
      out.add(
        '${words[random.nextInt(words.length)]} '.codeUnits
            .map((unit) => unit & 0xFF)
            .toList(),
      );
    }
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, length));
}

Uint8List decodeAll(List<(Uint8List, int)> frames, int windowBits) {
  final decoder = LzxDecoder(windowBits);
  final out = BytesBuilder();
  for (final (data, size) in frames) {
    out.add(decoder.decodeFrame(data, size));
  }
  return out.takeBytes();
}

void main() {
  group('LZX', () {
    for (final windowBits in <int>[15, 16, 18, 21]) {
      test('round-trips verbatim blocks with a window of 2^$windowBits', () {
        final input = sampleText(100000, seed: windowBits);
        final frames = encodeLzx(input, windowBits: windowBits);
        expect(frames.length, 4);
        expect(decodeAll(frames, windowBits), input);
      });
    }

    test('round-trips aligned-offset and stored blocks among verbatim ones, '
        'blocks running on from one frame into the next', () {
      final input = sampleText(150000, seed: 7);
      final frames = encodeLzx(
        input,
        windowBits: 17,
        blockSize: 23000,
        blocks: const <TestBlock>[
          TestBlock.aligned,
          TestBlock.verbatim,
          TestBlock.stored,
        ],
      );
      expect(decodeAll(frames, 17), input);
    });

    test('reads a stored block of odd length and the block after it', () {
      final input = sampleText(4001, seed: 3);
      final frames = encodeLzx(
        input,
        windowBits: 15,
        blockSize: 1001,
        blocks: const <TestBlock>[TestBlock.stored, TestBlock.verbatim],
      );
      expect(decodeAll(frames, 15), input);
    });

    // Vectors from the lzxd crate (MIT or Apache 2.0).
    test('reads a stored block', () {
      final frame = Uint8List.fromList(<int>[
        0x00, 0x30, 0x30, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, //
        0x00, 0x01, 0x00, 0x00, 0x00, 0x61, 0x62, 0x63, 0x00,
      ]);
      expect(LzxDecoder(15).decodeFrame(frame, 3), 'abc'.codeUnits);
    });

    test('undoes the translation of x86 calls', () {
      final frame = Uint8List.fromList(<int>[
        0x5B, 0x80, 0x80, 0x8D, 0x00, 0x30, 0x80, 0x0A, 0x18, 0x00, 0x00, //
        0x00, 0x01, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x54, 0x68,
        0x69, 0x73, 0x20, 0x66, 0x69, 0x6C, 0x65, 0x20, 0x68, 0x61, 0x73,
        0x20, 0x61, 0x6E, 0x20, 0x45, 0x38, 0x20, 0x62, 0x79, 0x74, 0x65,
        0x20, 0x74, 0x6F, 0x20, 0x74, 0x65, 0x73, 0x74, 0x20, 0x45, 0x38,
        0x20, 0x74, 0x72, 0x61, 0x6E, 0x73, 0x6C, 0x61, 0x74, 0x69, 0x6F,
        0x6E, 0x2C, 0x20, 0x58, ...List<int>.filled(96, 0x64), 0xE8, 0x7B,
        0x00, 0x00, 0x00, 0xE8, 0x7B, 0x00, 0x00, 0x00,
        ...List<int>.filled(12, 0x64),
      ]);
      final expected = <int>[
        ...'This file has an E8 byte to test E8 translation, X'.codeUnits,
        ...List<int>.filled(96, 0x64),
        0xE8, 0xE9, 0xFF, 0xFF, 0xFF, 0xE8, 0xE4, 0xFF, 0xFF, 0xFF, //
        ...List<int>.filled(12, 0x64),
      ];
      expect(LzxDecoder(15).decodeFrame(frame, 168), expected);
    });

    test('fails on damaged data rather than reading past it', () {
      final input = sampleText(20000);
      final frames = encodeLzx(input);
      final (data, size) = frames.single;
      final damaged = Uint8List.fromList(data)..fillRange(4, 40, 0xFF);
      expect(
        () => LzxDecoder(16).decodeFrame(damaged, size),
        throwsA(isA<FormatDamage>()),
      );
    });
  });

  group('Cabinet', () {
    final files = <String, Uint8List>{
      'Open Notebook.onetoc2': sampleText(700, seed: 11),
      r'Grüppe\Einträge.one': sampleText(70000, seed: 12),
      'Leer.one': Uint8List(0),
      'Klausuren.one': sampleText(900, seed: 13),
    };

    test('reads the files of an LZX folder, names and folders kept', () {
      final cabinet = writeCabinet(
        files,
        compression: 3 | (16 << 8),
        encode: encodeLzx,
      );
      final read = Cabinet.read(BytesSource(cabinet)).contents;
      expect(read.keys, <String>[
        'Open Notebook.onetoc2',
        'Grüppe/Einträge.one',
        'Leer.one',
        'Klausuren.one',
      ]);
      expect(read['Grüppe/Einträge.one'], files[r'Grüppe\Einträge.one']);
      expect(read['Klausuren.one'], files['Klausuren.one']);
      expect(read['Leer.one'], isEmpty);
    });

    test('reads a stored folder', () {
      final cabinet = writeCabinet(
        files,
        compression: 0,
        encode: (all) => <(Uint8List, int)>[
          for (var i = 0; i < all.length; i += 32768)
            (
              all.sublist(i, math.min(i + 32768, all.length)),
              math.min(32768, all.length - i),
            ),
        ],
      );
      expect(
        Cabinet.read(BytesSource(cabinet)).contents['Open Notebook.onetoc2'],
        files['Open Notebook.onetoc2'],
      );
    });

    test('refuses a damaged block, by its checksum', () {
      final cabinet = writeCabinet(
        files,
        compression: 3 | (16 << 8),
        encode: encodeLzx,
      );
      cabinet[cabinet.length - 30] ^= 0x40;
      expect(
        () => Cabinet.read(BytesSource(cabinet)).contents,
        throwsA(isA<FormatDamage>()),
      );
    });

    test('unpacks into a folder, and never out of it', () {
      final escaping = <String, Uint8List>{
        r'..\..\outside.one': sampleText(10),
        'inside/page.one': sampleText(10, seed: 2),
      };
      final cabinet = writeCabinet(
        escaping,
        compression: 3 | (15 << 8),
        encode: (all) => encodeLzx(all, windowBits: 15),
      );
      final directory = Directory.systemTemp.createTempSync('cab_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final target = Directory('${directory.path}/into')..createSync();
      Cabinet.read(BytesSource(cabinet)).extractTo(target);
      expect(File('${target.path}/outside.one').existsSync(), isTrue);
      expect(File('${target.path}/inside/page.one').existsSync(), isTrue);
      expect(File('${directory.path}/outside.one').existsSync(), isFalse);
    });

    test('says what it is not', () {
      expect(
        () => Cabinet.read(
          BytesSource(Uint8List.fromList('PK\x03\x04'.codeUnits)),
        ),
        throwsA(isA<FormatDamage>()),
      );
    });
  });
}

extension on Cabinet {
  /// Every file's bytes, in memory.
  Map<String, Uint8List> get contents {
    final builders = <String, BytesBuilder>{};
    read(
      onBytes: (file, bytes) =>
          (builders[file.name] ??= BytesBuilder()).add(bytes),
      onFile: (file) => builders.putIfAbsent(file.name, BytesBuilder.new),
    );
    return <String, Uint8List>{
      for (final entry in builders.entries) entry.key: entry.value.takeBytes(),
    };
  }
}
