import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:test/test.dart';

/// [width] by [height] pixels, as Flutter gives them, of a pattern with
/// flat parts, edges and noise in it, and a part half see-through.
Uint8List pattern(int width, int height) {
  final random = math.Random(7);
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final at = (y * width + x) * 4;
      final noisy = x > width ~/ 2;
      pixels
        ..[at] = noisy ? random.nextInt(256) : (x * 7) & 0xFF
        ..[at + 1] = noisy ? random.nextInt(256) : y & 0xFF
        ..[at + 2] = (x ^ y) & 0xFF
        ..[at + 3] = 255;
    }
  }
  return pixels;
}

/// What [image]'s rows were before they were filtered and deflated, as a
/// reader of the PDF gets them back.
Uint8List unfiltered(PdfImage image) {
  final filtered = ZLibDecoder().convert(image.data);
  final stride = image.width * 3;
  final out = Uint8List(stride * image.height);
  for (var row = 0; row < image.height; row++) {
    final filter = filtered[row * (stride + 1)];
    for (var i = 0; i < stride; i++) {
      final value = filtered[row * (stride + 1) + 1 + i];
      final a = i >= 3 ? out[row * stride + i - 3] : 0;
      final b = row > 0 ? out[(row - 1) * stride + i] : 0;
      final c = i >= 3 && row > 0 ? out[(row - 1) * stride + i - 3] : 0;
      final int predicted;
      switch (filter) {
        case 1:
          predicted = a;
        case 2:
          predicted = b;
        case 4:
          final p = a + b - c;
          final pa = (p - a).abs();
          final pb = (p - b).abs();
          final pc = (p - c).abs();
          predicted = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
        default:
          fail('filter $filter');
      }
      out[row * stride + i] = (value + predicted) & 0xFF;
    }
  }
  return out;
}

/// The PDF [write] writes.
Uint8List pdfOf(void Function(PdfWriter writer) write) {
  final bytes = BytesBuilder();
  write(PdfWriter(bytes.add));
  return bytes.takeBytes();
}

void main() {
  group('A picture for a PDF', () {
    test('gives back its pixels exactly, laid over white', () {
      const width = 37;
      const height = 23;
      final pixels = pattern(width, height);
      // Half see-through, as Flutter gives it: the colour multiplied by it.
      pixels
        ..[0] = 0
        ..[1] = 64
        ..[2] = 128
        ..[3] = 128;
      final image = PdfImage.rgba(pixels, width, height);
      final rgb = unfiltered(image);
      for (var i = 0, j = 0; i < pixels.length; i += 4, j += 3) {
        final clear = 255 - pixels[i + 3];
        expect(
          <int>[rgb[j], rgb[j + 1], rgb[j + 2]],
          <int>[
            pixels[i] + clear,
            pixels[i + 1] + clear,
            pixels[i + 2] + clear,
          ],
          reason: 'pixel ${i ~/ 4}',
        );
      }
    });

    test('of a sheet of paper with little on it is small', () {
      const width = 800;
      const height = 1100;
      final pixels = Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 255);
      for (var y = 100; y < 1000; y += 32) {
        for (var x = 0; x < width; x++) {
          pixels[(y * width + x) * 4] = 120;
        }
      }
      final image = PdfImage.rgba(pixels, width, height);
      expect(image.data.length, lessThan(width * height * 3 ~/ 200));
    });

    test('is refused pixels that are not as many as it is large', () {
      expect(() => PdfImage.rgba(Uint8List(10), 2, 2), throwsArgumentError);
    });
  });

  group('A PDF', () {
    test('lists where each of its objects begins', () {
      final image = PdfImage.rgba(pattern(8, 8), 8, 8);
      final pdf = pdfOf(
        (writer) => writer
          ..addPage(
            width: 595,
            height: 842,
            pictures: <PdfPlacement>[
              (image: image, x: 0, y: 0, width: 595, height: 842),
            ],
          )
          ..addPage(width: 842, height: 595)
          ..finish(
            title: 'Natuurkunde — Golven',
            outline: <PdfOutline>[
              const PdfOutline(
                'Golven',
                page: 0,
                children: <PdfOutline>[PdfOutline('Interferentie', page: 1)],
              ),
            ],
          ),
      );
      final text = latin1.decode(pdf);
      expect(text, startsWith('%PDF-1.7'));
      expect(text.trimRight(), endsWith('%%EOF'));

      final start = int.parse(
        RegExp(r'startxref\n(\d+)\n').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(start), startsWith('xref\n'));
      final entries = RegExp(r'(\d{10}) (\d{5}) ([nf]) \n')
          .allMatches(text.substring(start))
          .toList();
      final size = int.parse(
        RegExp(r'/Size (\d+)').firstMatch(text)!.group(1)!,
      );
      expect(entries, hasLength(size));
      for (final (number, entry) in entries.indexed.skip(1)) {
        expect(entry.group(3), 'n', reason: 'object $number is written');
        final offset = int.parse(entry.group(1)!);
        expect(
          text.substring(offset),
          startsWith('$number 0 obj\n'),
          reason: 'object $number lies where the table says',
        );
      }

      expect(text, contains('/Type /Pages'));
      expect(text, contains('/Count 2'));
      expect(text, contains('/MediaBox [0 0 842 595]'));
      expect(text, contains('/PageMode /UseOutlines'));
      // The titles in UTF-16: the dash past ASCII too.
      String utf16(String title) =>
          '<FEFF${title.codeUnits.map((unit) => unit.toRadixString(16).padLeft(4, '0').toUpperCase()).join()}>';
      expect(text, contains('/Title ${utf16('Natuurkunde — Golven')}'));
      expect(text, contains('/Title ${utf16('Interferentie')}'));
    });

    test('draws a picture where it is placed, from the page’s top', () {
      final image = PdfImage.rgba(pattern(4, 4), 4, 4);
      final text = latin1.decode(
        pdfOf(
          (writer) => writer
            ..addPage(
              width: 600,
              height: 800,
              pictures: <PdfPlacement>[
                (image: image, x: 10, y: 20, width: 100, height: 50.5),
              ],
            )
            ..finish(),
        ),
      );
      expect(text, contains('q 100 0 0 50.5 10 729.5 cm /Im0 Do Q'));
    });

    test('lays its text unseen over the page, where it is seen', () {
      final text = latin1.decode(
        pdfOf(
          (writer) => writer
            ..addPage(
              width: 600,
              height: 800,
              text: <PdfText>[
                (text: 'Ab', x: 10, y: 20, width: 40, height: 10),
                (text: '', x: 0, y: 0, width: 5, height: 5),
              ],
            )
            ..addPage(width: 600, height: 800)
            ..finish(),
        ),
      );
      // Not painted, ten points high, its two characters and the space
      // after them, five points each, stretched to forty, its foot ten
      // points below its top.
      expect(
        text,
        contains(
          'BT 3 Tr\n/T1 10 Tf 266.667 Tz 1 0 0 1 10 770 Tm <004100620020> Tj\nET',
        ),
      );
      expect(RegExp('Tj').allMatches(text), hasLength(1), reason: 'none empty');
      expect(RegExp('/Font << /T1').allMatches(text), hasLength(1));
      expect(text, contains('/Subtype /CIDFontType2'));
      expect(text, contains('/Encoding /Identity-H'));
    });

    test('writes no font where it has no text', () {
      final text = latin1.decode(
        pdfOf(
          (writer) => writer
            ..addPage(width: 600, height: 800)
            ..finish(),
        ),
      );
      expect(text, isNot(contains('/Font')));
      expect(text, isNot(contains('/EmbeddedFiles')));
    });

    test('keeps files attached to it, named', () {
      final text = latin1.decode(
        pdfOf(
          (writer) => writer
            ..addPage(width: 600, height: 800)
            ..attach(
              'Übung.pdf',
              Uint8List.fromList(<int>[1, 2, 3]),
              mimeType: 'application/pdf',
            )
            ..attach('a.png', Uint8List(4), mimeType: 'image/png')
            ..finish(),
        ),
      );
      expect(text, contains('/Type /EmbeddedFile /Subtype /application#2Fpdf'));
      // The names in the order of their characters: "a" before "Ü".
      final names = RegExp(
        r'/EmbeddedFiles << /Names \[<FEFF(\w+)> \d+ 0 R <FEFF(\w+)>',
      ).firstMatch(text)!;
      expect(names.group(1), '0061002E0070006E0067');
      expect(names.group(2), startsWith('00DC'));
      expect(text, contains('/F <FEFF005F'), reason: 'Ü as _ for old readers');
    });

    test('refuses two files of one name', () {
      final writer = PdfWriter((_) {})..attach('a.pdf', Uint8List(1));
      expect(() => writer.attach('a.pdf', Uint8List(1)), throwsArgumentError);
    });

    group('read by Poppler and Ghostscript', () {
      final tools = <String, bool>{
        for (final tool in <String>['pdftotext', 'pdfdetach', 'gs'])
          tool: _has(tool),
      };
      late Directory folder;
      setUp(() => folder = Directory.systemTemp.createTempSync('pdf_text_'));
      tearDown(() => folder.deleteSync(recursive: true));

      File write() {
        final file = File('${folder.path}/notes.pdf');
        final image = PdfImage.rgba(pattern(4, 4), 4, 4);
        file.writeAsBytesSync(
          pdfOf(
            (writer) => writer
              ..addPage(
                width: 595,
                height: 842,
                pictures: <PdfPlacement>[
                  (image: image, x: 0, y: 0, width: 595, height: 842),
                ],
                text: <PdfText>[
                  (text: 'Kreisbewegung', x: 50, y: 50, width: 200, height: 18),
                  (
                    text: r'Name: ⟦Max⟧ — $\omega = 2\pi f$ 😀',
                    x: 50,
                    y: 100,
                    width: 300,
                    height: 12,
                  ),
                ],
              )
              ..attach(
                'Arbeitsblatt Ü.pdf',
                Uint8List.fromList(utf8.encode('x')),
              )
              ..finish(title: 'Physik'),
          ),
        );
        return file;
      }

      test('its text is read as it was written', () {
        final file = write();
        final out = Process.runSync('pdftotext', <String>[
          '-raw',
          '-enc',
          'UTF-8',
          file.path,
          '-',
        ], stdoutEncoding: utf8);
        expect(out.exitCode, 0, reason: '${out.stderr}');
        expect(out.stderr, isEmpty);
        expect(
          (out.stdout as String).trim(),
          'Kreisbewegung\nName: ⟦Max⟧ — \$\\omega = 2\\pi f\$ 😀',
        );
      }, skip: tools['pdftotext']! ? false : 'pdftotext is not installed');

      test('its files are there to save', () {
        final file = write();
        final list = Process.runSync('pdfdetach', <String>[
          '-list',
          '-enc',
          'UTF-8',
          file.path,
        ], stdoutEncoding: utf8);
        expect(list.stdout, contains('1: Arbeitsblatt Ü.pdf'));
        final saved = '${folder.path}/saved';
        Process.runSync('pdfdetach', <String>[
          '-save',
          '1',
          '-o',
          saved,
          file.path,
        ]);
        expect(File(saved).readAsStringSync(), 'x');
      }, skip: tools['pdfdetach']! ? false : 'pdfdetach is not installed');

      test('it is drawn without a warning', () {
        final file = write();
        final out = Process.runSync('gs', <String>[
          '-dNOPAUSE',
          '-dBATCH',
          '-dQUIET',
          '-sDEVICE=nullpage',
          file.path,
        ]);
        expect(out.exitCode, 0);
        expect('${out.stdout}${out.stderr}'.trim(), isEmpty);
      }, skip: tools['gs']! ? false : 'Ghostscript is not installed');
    });

    test('is finished once', () {
      final writer = PdfWriter((_) {})..finish();
      expect(writer.finish, throwsStateError);
      expect(() => writer.addPage(width: 1, height: 1), throwsStateError);
    });
  });
}

/// Whether [tool] can be run here.
bool _has(String tool) {
  try {
    return Process.runSync(Platform.isWindows ? 'where' : 'which', <String>[
          tool,
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}
