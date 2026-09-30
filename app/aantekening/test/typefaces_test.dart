import 'dart:io';

import 'package:aantekening/src/editor/text/text_styles.dart';
import 'package:aantekening/src/editor/text/typefaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text set in Consolas is drawn to its measure where it is '
      'not installed', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader(RichTextStyles.consolasMeasure)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(
              File('fonts/InconsolataAantekening-Regular.ttf')
                  .readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    });
    expect(RichTextStyles.typefacesFor('Consolas'), <String>[
      RichTextStyles.consolasMeasure,
    ]);

    const size = 100.0;
    final text = TextPainter(
      text: const TextSpan(
        text: 'Wellenberg\nWellenberg',
        style: TextStyle(
          fontFamily: RichTextStyles.consolasMeasure,
          fontSize: size,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final line = text.computeLineMetrics().first;
    // Consolas's: each letter 1126/2048 of the size wide, lines
    // 2398/2048 high, and the baseline where OneNote sets it, 1696/2048
    // down — measured against the printouts text was typed on.
    expect(text.width / 10 / size, closeTo(1126 / 2048, 0.001));
    expect(line.height / size, closeTo(2398 / 2048, 0.002));
    expect(line.baseline / size, closeTo(1696 / 2048, 0.002));
    text.dispose();
  });

  test('reads the families fontconfig lists, each once, in order', () {
    const listing =
        'Noto Sans,Noto Sans Light\n'
        'DejaVu Sans\n'
        'noto serif\n'
        'Noto Sans\n'
        '.Hidden Face\n'
        'Fira\\-Code\n'
        '\n';
    expect(Typefaces.fromFontconfig(listing), <String>[
      'DejaVu Sans',
      'Fira-Code',
      'Noto Sans',
      'noto serif',
    ]);
  });

  test("reads the families in Windows' list of fonts, without styles", () {
    const listing = r'''
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
    Arial (TrueType)    REG_SZ    arial.ttf
    Arial Bold Italic (TrueType)    REG_SZ    arialbi.ttf
    Arial Narrow (TrueType)    REG_SZ    ARIALN.TTF
    Cambria & Cambria Math (TrueType)    REG_SZ    cambria.ttc
    Segoe UI Semibold (TrueType)    REG_SZ    seguisb.ttf
    Bahnschrift (TrueType)    REG_SZ    bahnschrift.ttf
    Modern (All res)    REG_SZ    modern.fon

HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts
    Inter Regular (OpenType)    REG_SZ    C:\Users\me\Inter.otf
''';
    expect(Typefaces.fromRegistry(listing), <String>[
      'Arial',
      'Arial Narrow',
      'Bahnschrift',
      'Cambria',
      'Cambria Math',
      'Inter',
      'Modern',
      'Segoe UI',
    ]);
  });
}
