import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening/src/files/pdf_export.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'worksheet_render_test.dart' show redPng, stroke;

/// A page of a PDF, as a reader draws it: how large it is, in points, and
/// its pictures' pixels put together, one under another.
class ReadPage {
  ReadPage(this.width, this.height, this.pixels, this.pixelWidth);

  final double width;
  final double height;
  final Uint8List pixels;
  final int pixelWidth;

  int get pixelHeight => pixels.length ~/ (pixelWidth * 3);

  /// The colour at [x], [y] page units from the paper's corner, drawn
  /// [dpi] pixels to an inch.
  (int, int, int) at(double x, double y, {double dpi = 150}) {
    final px = (x * dpi / 96).round();
    final py = (y * dpi / 96).round();
    final i = (py * pixelWidth + px) * 3;
    return (pixels[i], pixels[i + 1], pixels[i + 2]);
  }

  /// Whether anything darker than paper is drawn from page unit [top] to
  /// [bottom] down the paper.
  bool inkBetween(double top, double bottom, {double dpi = 150}) {
    final from = (top * dpi / 96).round();
    final to = (bottom * dpi / 96).round().clamp(0, pixelHeight);
    for (var i = from * pixelWidth * 3; i < to * pixelWidth * 3; i++) {
      if (pixels[i] < 140) return true;
    }
    return false;
  }
}

/// The pages of [pdf], their pictures read back as a reader reads them.
List<ReadPage> readPdf(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final images = <int, (int, int, Uint8List)>{};
  for (final match in RegExp(
    r'(\d+) 0 obj\n<< /Type /XObject /Subtype /Image /Width (\d+) '
    r'/Height (\d+) .*?/Length (\d+) >>\nstream\n',
  ).allMatches(text)) {
    final width = int.parse(match.group(2)!);
    final height = int.parse(match.group(3)!);
    final length = int.parse(match.group(4)!);
    final data = pdf.sublist(match.end, match.end + length);
    images[int.parse(match.group(1)!)] = (
      width,
      height,
      unfilter(ZLibDecoder().convert(data), width, height),
    );
  }
  final pages = <ReadPage>[];
  for (final match in RegExp(
    r'/Type /Page /Parent 2 0 R /MediaBox \[0 0 ([\d.]+) ([\d.]+)\] '
    '/Resources << /XObject << (.*?) >> >>',
  ).allMatches(text)) {
    final placed = <(int, int, Uint8List)>[
      for (final image in RegExp(
        r'/Im\d+ (\d+) 0 R',
      ).allMatches(match.group(3)!))
        images[int.parse(image.group(1)!)]!,
    ];
    // Each strip but the last a row longer, the next drawn over it.
    final width = placed.first.$1;
    final rows = BytesBuilder();
    for (final (index, (_, height, rgb)) in placed.indexed) {
      final kept = index == placed.length - 1 ? height : height - 1;
      rows.add(rgb.sublist(0, kept * width * 3));
    }
    pages.add(
      ReadPage(
        double.parse(match.group(1)!),
        double.parse(match.group(2)!),
        rows.takeBytes(),
        width,
      ),
    );
  }
  return pages;
}

/// [filtered] rows of RGB, PNG's filters undone.
Uint8List unfilter(List<int> filtered, int width, int height) {
  final stride = width * 3;
  final out = Uint8List(stride * height);
  for (var row = 0; row < height; row++) {
    final filter = filtered[row * (stride + 1)];
    for (var i = 0; i < stride; i++) {
      final value = filtered[row * (stride + 1) + 1 + i];
      final a = i >= 3 ? out[row * stride + i - 3] : 0;
      final b = row > 0 ? out[(row - 1) * stride + i] : 0;
      final c = i >= 3 && row > 0 ? out[(row - 1) * stride + i - 3] : 0;
      final p = a + b - c;
      final predicted = switch (filter) {
        1 => a,
        2 => b,
        _ =>
          (p - a).abs() <= (p - b).abs() && (p - a).abs() <= (p - c).abs()
              ? a
              : (p - b).abs() <= (p - c).abs()
              ? b
              : c,
      };
      out[row * stride + i] = (value + predicted) & 0xFF;
    }
  }
  return out;
}

/// A text box of [lines] lines of X, from [y] down.
TextElement linesBox(String id, double y, int lines, {int z = 0}) =>
    TextElement(
      id: id,
      frame: Frame(x: 48, y: y, width: 500, height: lines * 30.0),
      createdAt: 0,
      updatedAt: 0,
      z: z,
      blocks: <TextBlock>[
        for (var i = 0; i < lines; i++) TextBlock.plain('XXXXXXXXXXXX'),
      ],
    );

void main() {
  late AantekeningStore store;
  late Directory folder;
  late Notebook notebook;
  late Section section;

  setUp(() async {
    folder = Directory.systemTemp.createTempSync('aantekening_pdf_test_');
    store = AantekeningStore.inMemory(
      assetDirectory: Directory('${folder.path}/assets'),
    );
    notebook = await store.library.createNotebook(title: 'School');
    section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Physics',
    );
  });

  tearDown(() async {
    await store.close();
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  /// A page of [section] — or [inSection] — titled [title], holding
  /// [elements], shown as [canvas] has it.
  Future<PageRef> page(
    String title,
    List<NoteElement> elements, {
    CanvasSettings canvas = CanvasSettings.defaults,
    Section? inSection,
    String? parentId,
  }) async {
    final made = await store.pages.createPage(
      sectionId: (inSection ?? section).id,
      title: title,
      parentId: parentId,
    );
    return store.pages.saveDocument(
      made.id,
      PageDocument(id: made.id, elements: elements, canvas: canvas),
    );
  }

  /// [node] saved as a PDF as [choices] has it, read back.
  Future<(List<ReadPage>, String)> save(
    WidgetTester tester,
    TreeNode node, {
    PdfChoices choices = const PdfChoices(quality: PdfQuality.small),
  }) async => (await tester.runAsync(() async {
    final path = '${folder.path}/out.pdf';
    final contents = await PdfContents.of(store, node);
    expect(await writePdf(store, contents, path, choices: choices), isTrue);
    expect(File('$path.part').existsSync(), isFalse);
    final bytes = File(path).readAsBytesSync();
    return (readPdf(bytes), latin1.decode(bytes));
  }))!;

  testWidgets('a page without sheets is cut onto A4 between its lines', (
    tester,
  ) async {
    final long = await page('Notes', <NoteElement>[linesBox('text', 40, 90)]);
    final (pages, _) = await save(tester, long);
    expect(pages.length, greaterThan(1));
    for (final read in pages) {
      expect(read.width, closeTo(595.3, 0.1));
      expect(read.height, closeTo(841.9, 0.1));
      expect(read.pixelWidth, 1240, reason: 'A4 at 150 pixels to an inch');
      expect(read.inkBetween(0, 1123), isTrue, reason: 'text on each page');
      // The margin at the foot of each page is blank: no line cut there.
      expect(read.inkBetween(1123 - 40, 1123), isFalse);
    }
  });

  testWidgets('a long page without sheets can be saved as one', (tester) async {
    final long = await page('Notes', <NoteElement>[linesBox('text', 40, 90)]);
    final (pages, _) = await save(
      tester,
      long,
      choices: const PdfChoices(
        print: CanvasPrint.whole,
        quality: PdfQuality.small,
      ),
    );
    expect(pages, hasLength(1));
    expect(pages.single.height, greaterThan(841.9), reason: 'longer than A4');
  });

  testWidgets('a page shown as sheets is saved a sheet to a page, its '
      'writing on the sheet it is on', (tester) async {
    final sheets = Sheets(
      templates: <SheetTemplate>[SheetTemplate.lined, SheetTemplate.blank],
    );
    final paper = await page('Sheets', <NoteElement>[
      stroke('line', 200, sheets.topOf(1) + 300),
    ], canvas: CanvasSettings(layout: NoteLayout.pages, sheets: sheets));
    final (pages, _) = await save(tester, paper);
    expect(pages, hasLength(2));
    final (_, _, blue) = pages[1].at(230, 300);
    final (red, _, _) = pages[1].at(230, 300);
    expect((red, blue), (0, 255), reason: 'the stroke, on the second sheet');
    expect(pages[0].at(230, 300), (255, 255, 255));
    // The first sheet's rules, a light blue-grey, and none on the second.
    final rule = pages[0].at(400, 3 * 32);
    expect(rule.$3, lessThan(255));
    expect(rule.$3, greaterThan(rule.$1), reason: 'bluish');
    expect(pages[1].at(400, 3 * 32), (255, 255, 255));
  });

  testWidgets('a picture is drawn where it lies, beneath the ink over it', (
    tester,
  ) async {
    final assetId = (await tester.runAsync(
      () => store.assets.importBytes(redPng, mimeType: 'image/png'),
    ))!.id;
    final drawing = await page('Picture', <NoteElement>[
      ImageElement(
        id: 'picture',
        frame: const Frame(x: 40, y: 40, width: 300, height: 300),
        createdAt: 0,
        updatedAt: 0,
        fit: MediaFit.stretch,
        assetId: assetId,
      ),
      stroke('over', 60, 150),
    ]);
    final (pages, _) = await save(tester, drawing);
    // Near the page's corner, it lies on the paper as on the page.
    final read = pages.single;
    expect(read.at(300, 300), (255, 0, 0), reason: 'the picture');
    expect(read.at(90, 150), (0, 0, 255), reason: 'the ink over it');
    expect(read.at(500, 600), (255, 255, 255), reason: 'paper beside it');
  });

  testWidgets('a section is saved with its pages and subsections as '
      'bookmarks, in the order the panes list them', (tester) async {
    final first = await page('Waves', <NoteElement>[linesBox('a', 40, 3)]);
    await page('Interference', <NoteElement>[
      linesBox('b', 40, 3),
    ], parentId: first.id);
    final inner = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Optics',
      parentId: section.id,
    );
    await page('Lenses', <NoteElement>[], inSection: inner);
    await store.library.createSection(notebookId: notebook.id, title: 'Empty');

    final contents = await PdfContents.of(store, notebook);
    expect(
      <String>[for (final page in contents.pages) page.title],
      <String>['Waves', 'Interference', 'Lenses'],
    );
    expect(
      contents.marks,
      hasLength(1),
      reason: 'an empty section leads nowhere',
    );
    final physics = contents.marks.single;
    expect(physics.title, 'Physics');
    expect(
      <String>[for (final mark in physics.children) mark.title],
      <String>['Waves', 'Optics'],
    );
    expect(physics.children.first.children.single.title, 'Interference');
    expect(physics.children.last.page, 2);

    final (pages, text) = await save(tester, notebook);
    expect(pages, hasLength(3));
    expect(text, contains('/PageMode /UseOutlines'));
    String utf16(String title) =>
        '<FEFF${title.codeUnits.map((unit) => unit.toRadixString(16).padLeft(4, '0').toUpperCase()).join()}>';
    for (final title in <String>['School', 'Physics', 'Optics', 'Lenses']) {
      expect(text, contains(utf16(title)));
    }
  });

  testWidgets('a PDF stopped leaves nothing behind', (tester) async {
    final notes = await page('Notes', <NoteElement>[linesBox('a', 40, 3)]);
    final path = '${folder.path}/stopped.pdf';
    final written = await tester.runAsync(
      () async => writePdf(
        store,
        await PdfContents.of(store, notes),
        path,
        choices: const PdfChoices(quality: PdfQuality.small),
        stopped: () => true,
      ),
    );
    expect(written, isFalse);
    expect(File(path).existsSync(), isFalse);
    expect(File('$path.part').existsSync(), isFalse);
  });
}
