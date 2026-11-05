import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  group('media types', () {
    test('are read from what the bytes begin with before their name', () {
      final png = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0]);
      final pdf = Uint8List.fromList('%PDF-1.7'.codeUnits);
      expect(mimeTypeOf(png, name: 'picture.jpg'), 'image/png');
      expect(mimeTypeOf(pdf), 'application/pdf');
    });

    test('are told by one table of names, whichever way a file came', () {
      final unknown = Uint8List.fromList(<int>[1, 2, 3]);
      for (final (name, type) in <(String, String)>[
        ('a.GIF', 'image/gif'),
        ('a.webp', 'image/webp'),
        ('a.bmp', 'image/bmp'),
        ('a.txt', 'text/plain'),
        ('a.jpeg', 'image/jpeg'),
        ('a.xyz', 'application/octet-stream'),
      ]) {
        expect(mimeTypeOf(unknown, name: name), type);
        expect(mimeTypeOfName('/tmp/$name'), type);
      }
    });

    test('look only at the last part of a path', () {
      expect(
        mimeTypeOfName(r'C:\Users\someone\Lecture.PDF'),
        'application/pdf',
      );
      expect(
        mimeTypeOfName('/tmp/notes.d/picture'),
        'application/octet-stream',
      );
      expect(mimeTypeOfName('/home/someone/.png'), 'application/octet-stream');
      expect(mimeTypeOfName(''), 'application/octet-stream');
    });

    test('know gzip by its first two bytes', () {
      expect(isGzipped(Uint8List.fromList(<int>[0x1F, 0x8B, 8])), isTrue);
      expect(isGzipped(Uint8List.fromList(<int>[0x1F, 0x8B])), isFalse);
      expect(isGzipped(Uint8List.fromList('{"kind"'.codeUnits)), isFalse);
    });
  });
}
