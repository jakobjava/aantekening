import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

/// The words of [text], on a line [y] from the top, each a word's width
/// apart from [x] on — as a PDF's text layer gives them.
List<SheetGlyph> line(String text, {required double y, double x = 0}) {
  final out = <SheetGlyph>[];
  var at = x;
  for (final word in text.split(' ')) {
    final width = word.length * 6.0;
    out.add((text: word, box: Aabb(at, y, at + width, y + 12)));
    at += width + 4;
  }
  return out;
}

SheetTyping typed(String text, double x, double y, {double height = 16}) =>
    (text: text, box: Aabb(x, y - 2, x + 200, y - 2 + height));

const Aabb sheet = Aabb(0, 0, 600, 800);

void main() {
  test('a sheet reads top down, whatever order its text was held in', () {
    final read = SheetReading.read(sheet, <SheetGlyph>[
      ...line('Second line', y: 40),
      ...line('Klasse:', y: 0, x: 300),
      ...line('First', y: 0),
    ], const <SheetTyping>[]);
    expect(read, 'First   Klasse:\nSecond line');
  });

  test('what was typed into a blank stands in it, the blank left out', () {
    final read = SheetReading.read(
      sheet,
      <SheetGlyph>[
        ...line('Name: ____________', y: 0),
        ...line('Klasse: ______', y: 0, x: 200),
      ],
      <SheetTyping>[typed('Max', 40, 0, height: 14)],
    );
    expect(read, 'Name: ⟦Max⟧ Klasse: ______');
  });

  test('a word typed into a gap in a sentence reads in the sentence', () {
    final glyphs = <SheetGlyph>[
      ...line('Die', y: 0),
      ...line('des Körpers ändert sich.', y: 0, x: 140),
    ];
    final read = SheetReading.read(sheet, glyphs, <SheetTyping>[
      (text: 'Bewegungsrichtung', box: const Aabb(30, -2, 130, 13)),
    ]);
    expect(read, 'Die ⟦Bewegungsrichtung⟧ des Körpers ändert sich.');
  });

  test('an answer of many lines stands under its task, filling its rules', () {
    final read = SheetReading.read(
      sheet,
      <SheetGlyph>[
        ...line('Beobachtung:', y: 0),
        ...line('______________________', y: 24),
        ...line('______________________', y: 48),
        ...line('Erklärung:', y: 72),
        ...line('______________________', y: 96),
      ],
      <SheetTyping>[typed('Es wird gelb.\nDann grün.', 0, 24, height: 30)],
    );
    expect(
      read,
      'Beobachtung:\n⟦Es wird gelb.\nDann grün.⟧\nErklärung:\n'
      '______________________',
    );
  });

  test('typing between lines stands between them', () {
    final read = SheetReading.read(
      sheet,
      <SheetGlyph>[...line('Aufgabe 1', y: 0), ...line('Aufgabe 2', y: 200)],
      <SheetTyping>[typed(r'$v = 3\,m/s$', 20, 100)],
    );
    expect(read, 'Aufgabe 1\n⟦\$v = 3\\,m/s\$⟧\nAufgabe 2');
  });

  test('a formula whose box reaches up to a label stands under it', () {
    final read = SheetReading.read(
      sheet,
      <SheetGlyph>[...line('Frequenz:', y: 0), ...line('Weiter', y: 120)],
      <SheetTyping>[
        (text: r'$f = \frac{1}{T}$', box: const Aabb(0, 2, 200, 50)),
      ],
    );
    expect(read, 'Frequenz:\n⟦\$f = \\frac{1}{T}\$⟧\nWeiter');
  });

  test('a word drawn twice, as a PDF fakes bold, reads once', () {
    final word = line('MERKE:', y: 0);
    final read = SheetReading.read(sheet, <SheetGlyph>[
      ...word,
      ...word,
    ], const <SheetTyping>[]);
    expect(read, 'MERKE:');
  });

  test('typing on a sheet without text is listed by where it stands', () {
    final read = SheetReading.read(sheet, const <SheetGlyph>[], <SheetTyping>[
      typed('labour', 300, 400),
      typed('in sales', 60, 80),
    ]);
    expect(
      read,
      '- 10% down, 10% across: ⟦in sales⟧\n'
      '- 50% down, 50% across: ⟦labour⟧',
    );
  });
}
