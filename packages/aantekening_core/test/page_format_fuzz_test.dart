import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

const int _now = 1758000000000;

/// A page as another computer, another version or a damaged disk may leave
/// it — any value changed to any other, any key gone, any list repeated —
/// is either refused as damaged, with an exception a reader expects, or
/// read as a page that is written and read back as it is.
///
/// `AANTEKENING_FUZZ=20000 dart test test/page_format_fuzz_test.dart`
/// tries more.
void main() {
  final rounds =
      int.tryParse(Platform.environment['AANTEKENING_FUZZ'] ?? '') ?? 1500;

  test('a damaged page is refused or read whole', () {
    final original = jsonDecode(_sample().encode()) as Map<String, Object?>;
    final random = math.Random(7);
    final unexpected = <String>{};
    var refused = 0;
    for (var round = 0; round < rounds; round++) {
      final damaged = _damage(original, random);
      final text = jsonEncode(damaged);
      final PageDocument document;
      try {
        document = PageDocument.decode(text);
      } on FormatException {
        refused++;
        continue;
      } on PageFormatException {
        refused++;
        continue;
      } on TypeError {
        refused++;
        continue;
      } on Object catch (error) {
        unexpected.add('${error.runtimeType}: $error\n  from $text');
        continue;
      }
      try {
        final again = PageDocument.decode(document.encode());
        expect(again.encode(), document.encode(), reason: text);
        document.extractSearchText();
        for (final element in document.elements) {
          element.bounds;
        }
      } on Object catch (error) {
        unexpected.add('read, then ${error.runtimeType}: $error\n  from $text');
      }
    }
    expect(
      unexpected,
      isEmpty,
      reason:
          '${unexpected.length} kinds of failure no reader expects '
          '($refused refused as damaged):\n${unexpected.take(8).join('\n')}',
    );
  });
}

/// A copy of [json] with one to three things in it damaged.
Object? _damage(Object? json, math.Random random) {
  var copy = jsonDecode(jsonEncode(json));
  for (var i = 0; i < 1 + random.nextInt(3); i++) {
    copy = _damageOne(copy, random);
  }
  return copy;
}

Object? _damageOne(Object? json, math.Random random) {
  // Somewhere in it: deeper, more often than not.
  if (json is Map<String, Object?> &&
      json.isNotEmpty &&
      random.nextInt(4) > 0) {
    final key = json.keys.elementAt(random.nextInt(json.length));
    switch (random.nextInt(6)) {
      case 0:
        json.remove(key);
      default:
        json[key] = _damageOne(json[key], random);
    }
    return json;
  }
  if (json is List<Object?> && json.isNotEmpty && random.nextInt(4) > 0) {
    final at = random.nextInt(json.length);
    switch (random.nextInt(6)) {
      case 0:
        json.removeAt(at);
      case 1:
        json.insert(at, json[at]);
      default:
        json[at] = _damageOne(json[at], random);
    }
    return json;
  }
  return _anyValue(random);
}

Object? _anyValue(math.Random random) => switch (random.nextInt(16)) {
  0 => null,
  1 => random.nextBool(),
  2 => 0,
  3 => -1,
  4 => 1 << 62,
  5 => -(1 << 62),
  6 => 1e308,
  7 => -1e308,
  8 => 1e-308,
  9 => random.nextDouble() * 1e6 - 5e5,
  10 => '',
  11 => 'x' * random.nextInt(40),
  12 => '\u0000￿\u{1F600}',
  13 => <Object?>[],
  14 => <String, Object?>{},
  _ => random.nextInt(1000),
};

PageDocument _sample() => PageDocument(
  id: 'PAGE01',
  revision: 7,
  canvas: const CanvasSettings(
    background: PageBackground(kind: PageBackgroundKind.grid, spacing: 32),
    paperWidth: 816,
  ),
  elements: <NoteElement>[
    const TextElement(
      id: 'el_text',
      frame: Frame(x: 10, y: 20, width: 300, height: 120),
      createdAt: _now,
      updatedAt: _now,
      blocks: <TextBlock>[
        TextBlock(
          kind: TextBlockKind.heading1,
          runs: <TextRun>[TextRun('Chapter', TextMarks(bold: true))],
        ),
        TextBlock(
          kind: TextBlockKind.todo,
          checked: true,
          indent: 1,
          runs: <TextRun>[
            TextRun('review '),
            TextRun.math(r'\frac{a}{b}', MathMode.latex),
          ],
        ),
      ],
    ),
    InkElement(
      id: 'el_ink',
      frame: const Frame(x: 0, y: 0, width: 100, height: 100),
      createdAt: _now,
      updatedAt: _now,
      strokes: <InkStroke>[
        InkStroke.fromPoints(
          tool: InkTool.highlighter,
          color: 0x80FFEE00,
          width: 12,
          xs: <double>[0, 10, 20],
          ys: <double>[0, 5, 0],
          pressures: <double>[0.4, 0.9, 0.5],
        ),
      ],
    ),
    const ImageElement(
      id: 'el_image',
      frame: Frame(x: 0, y: 200, width: 400, height: 300),
      createdAt: _now,
      updatedAt: _now,
      assetId: 'asset_a',
      fit: MediaFit.cover,
      altText: 'a diagram',
    ),
    const PdfElement(
      id: 'el_pdf',
      frame: Frame(x: 500, y: 0, width: 612, height: 792),
      createdAt: _now,
      updatedAt: _now,
      assetId: 'asset_b',
      pageIndex: 3,
      extractedText: 'lecture notes',
    ),
    const TikzElement(
      id: 'el_tikz',
      frame: Frame(x: 40, y: 600, width: 200, height: 100),
      createdAt: _now,
      updatedAt: _now,
      source: r'\begin{tikzpicture}\draw (0,0) -- (1,1);\end{tikzpicture}',
    ),
  ],
);
