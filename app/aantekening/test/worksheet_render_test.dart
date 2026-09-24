import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aantekening/src/ai/workspace_reader.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A solid red picture, eight pixels square.
final Uint8List redPng = Uint8List.fromList(<int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  8,
  0,
  0,
  0,
  8,
  8,
  2,
  0,
  0,
  0,
  75,
  109,
  41,
  220,
  0,
  0,
  0,
  18,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  128,
  21,
  97,
  23,
  29,
  180,
  18,
  0,
  40,
  255,
  63,
  193,
  110,
  236,
  223,
  97,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

InkElement stroke(String id, double x, double y) => InkElement(
  id: id,
  frame: Frame(x: x, y: y, width: 60, height: 4),
  createdAt: 0,
  updatedAt: 0,
  strokes: <InkStroke>[
    InkStroke(
      tool: InkTool.pen,
      color: 0xFF0000FF,
      width: 4,
      points: Float32List.fromList(<double>[x, y, 1, 0, x + 60, y, 1, 0]),
    ),
  ],
);

/// A picture's pixels, to look at one by one.
typedef Pixels = ({ByteData data, int width});

/// The colour of the pixel at [x], [y] of [pixels], as RGB.
(int, int, int) pixel(Pixels pixels, double x, double y) {
  final at = (y.round() * pixels.width + x.round()) * 4;
  return (
    pixels.data.getUint8(at),
    pixels.data.getUint8(at + 1),
    pixels.data.getUint8(at + 2),
  );
}

void main() {
  late AantekeningStore store;
  late Directory assets;
  late String pageId;
  late String assetId;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_sheet_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    final notebook = await store.library.createNotebook(title: 'School');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Physics',
    );
    pageId = (await store.pages.createPage(
      sectionId: section.id,
      title: 'Arbeitsblatt',
    )).id;
    assetId = (await store.assets.importBytes(
      redPng,
      mimeType: 'image/png',
    )).id;
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  /// Draws the visual [find] picks of the page holding [elements].
  Future<Pixels> draw(
    WidgetTester tester,
    List<NoteElement> elements,
    DigestVisual Function(PageDigest digest) find,
  ) async => (await tester.runAsync(() async {
    await store.pages.saveDocument(
      pageId,
      PageDocument(id: pageId, elements: elements),
    );
    final reader = WorkspaceReader(store);
    final digest = (await reader.digest(pageId))!;
    final part = (await reader.render(pageId, find(digest)))!;
    final codec = await ui.instantiateImageCodec(part.bytes);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (data: data!, width: image.width);
  }))!;

  testWidgets('a worksheet is drawn with what was typed and written on it', (
    tester,
  ) async {
    final image = await draw(tester, <NoteElement>[
      ImageElement(
        id: 'sheet',
        frame: const Frame(x: 0, y: 0, width: 400, height: 300),
        createdAt: 0,
        updatedAt: 0,
        assetId: assetId,
      ),
      TextElement(
        id: 'answer',
        frame: const Frame(x: 40, y: 40, width: 200, height: 40),
        createdAt: 0,
        updatedAt: 0,
        z: 1,
        blocks: <TextBlock>[TextBlock.plain('XXXXXXXX')],
      ),
      stroke('line', 100, 200),
    ], (digest) => digest.visuals.single);

    // Twelve units of margin round the sheet, at twice the size.
    (int, int, int) at(double x, double y) =>
        pixel(image, (x + 12) * 2, (y + 12) * 2);
    expect(at(300, 150), (255, 0, 0), reason: 'the sheet');
    expect(at(130, 200), (0, 0, 255), reason: 'the writing on it');
    // The answer's first line, somewhere in it dark over the red.
    final typed = <(int, int, int)>[
      for (var y = 50.0; y < 80; y += 2)
        for (var x = 44.0; x < 160; x += 2) at(x, y),
    ];
    expect(
      typed.any((c) => c.$1 + c.$2 + c.$3 < 200),
      isTrue,
      reason: 'the typed answer, over the sheet',
    );
  });

  testWidgets('a printout in a text box is drawn where it lies, with the '
      'writing over it', (tester) async {
    final image = await draw(tester, <NoteElement>[
      TextElement(
        id: 'printout',
        frame: const Frame(x: 0, y: 0, width: 320, height: 260),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          TextBlock.embedded(
            BlockEmbed(
              kind: EmbedKind.image,
              assetId: assetId,
              width: 300,
              height: 200,
            ),
          ),
        ],
      ),
      stroke('circle', 60, 150),
    ], (digest) => digest.visuals.single);

    (int, int, int) at(double x, double y) =>
        pixel(image, (x + 12) * 2, (y + 12) * 2);
    expect(at(250, 120), (255, 0, 0), reason: 'the printout');
    expect(at(90, 150), (0, 0, 255), reason: 'the writing over it');
  });
}
