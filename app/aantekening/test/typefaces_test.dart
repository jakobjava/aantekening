import 'package:aantekening/src/editor/text/typefaces.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
