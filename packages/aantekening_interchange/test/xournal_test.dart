import 'dart:convert';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('xopp_'));
  tearDown(() => folder.deleteSync(recursive: true));

  File document(String name, String pages, {String? into}) {
    final xml =
        '<?xml version="1.0" standalone="no"?>'
        '<xournal creator="xournalpp 1.2.2" fileversion="4">'
        '<title>Xournal++ document</title>$pages</xournal>';
    final path = p.join(into ?? folder.path, name);
    File(path).parent.createSync(recursive: true);
    return File(path)..writeAsBytesSync(gzip.encode(utf8.encode(xml)));
  }

  final pixel = base64.encode(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0]);

  NotesDraft read(List<String> paths, {bool folders = false}) =>
      XournalImporter(folders: folders).read(
        paths,
        ImportWork(Directory(p.join(folder.path, 'work'))..createSync()),
      );

  test('brings a document over as a page, its pages one beneath the other', () {
    final file = document(
      'Waves.xopp',
      '<page width="600" height="800">'
          '<background type="solid" color="#ffffffff" style="lined"/>'
          '<layer>'
          '<stroke tool="pen" color="#ff0000ff" width="1.5 1.5 0.6">'
          '10 20 30 40</stroke>'
          '<text font="Sans" size="12" x="72" y="72" color="#000000ff">'
          'Two\nlines</text>'
          '</layer></page>'
          '<page width="600" height="800"><layer>'
          '<stroke tool="highlighter" color="#ffff0080" width="12">'
          '0 0 100 0</stroke>'
          '<image left="0" top="0" right="72" bottom="36">$pixel</image>'
          r'<teximage text="\(\frac{1}{2}\)" left="72" top="72" right="144" bottom="108">'
          '$pixel</teximage>'
          '</layer></page>',
    );
    final draft = read(<String>[file.path]);
    final page = draft.pages.single;
    expect(page.title, 'Waves');
    expect(page.document.canvas.background.kind, PageBackgroundKind.ruled);
    final elements = page.document.elements;

    final pen = (elements[0] as InkElement).strokes.single;
    expect(pen.color, 0xFFFF0000);
    expect(pen.width, closeTo(2, 1e-9), reason: 'points in page units');
    expect(pen.xAt(1), closeTo(40, 1e-4));
    expect(pen.pressureAt(1), closeTo(0, 1e-9), reason: 'pressed lightly');

    final text = elements[1] as TextElement;
    // The text, not the box around it, starts where Xournal++ had it.
    expect(text.frame.x + TextElement.sidePadding, closeTo(96, 1e-9));
    expect(text.frame.y + TextElement.grabBand, closeTo(96, 1e-9));
    expect(text.blocks.map((block) => block.plainText), <String>[
      'Two',
      'lines',
    ]);
    expect(text.blocks.first.runs.single.marks.font, 'Sans');

    final highlighter = (elements[2] as InkElement).strokes.single;
    expect(highlighter.tool, InkTool.highlighter);
    expect(highlighter.color, 0x80FFFF00);
    // The second page starts beneath the first, and a gap.
    expect(highlighter.yAt(0), closeTo(800 * 96 / 72 + 24, 1e-4));

    expect(elements[3], isA<ImageElement>());
    final formula = elements[4] as TextElement;
    expect(formula.blocks.single.runs.single.text, r'\frac{1}{2}');
    expect(formula.blocks.single.runs.single.math, MathMode.latex);
    expect(draft.assets, hasLength(1));
  });

  test('keeps the picture of a formula only TeX itself could set', () {
    final file = document(
      'Matrix.xopp',
      '<page width="600" height="800"><layer>'
          r'<teximage text="\(\vcenter{\halign{#\cr 1\cr}}\)" left="0" top="0" right="10" bottom="10">'
          '$pixel</teximage></layer></page>',
    );
    final element = read(<String>[
      file.path,
    ]).pages.single.document.elements.single;
    expect(element, isA<ImageElement>());
  });

  test('sets the PDF a document annotates beneath each of its pages', () {
    final pdf = File(p.join(folder.path, 'lecture.pdf'))
      ..writeAsBytesSync(utf8.encode('%PDF-1.4 fake'));
    final file = document(
      'Lecture.xopp',
      '<page width="600" height="800">'
          '<background type="pdf" domain="absolute" filename="${pdf.path}" pageno="1"/>'
          '<layer/></page>'
          '<page width="600" height="800">'
          '<background type="pdf" pageno="2"/><layer/></page>',
    );
    final draft = read(<String>[file.path]);
    final pages = draft.pages.single.document.elements.cast<PdfElement>();
    expect(pages.map((page) => page.pageIndex), <int>[0, 1]);
    expect(pages.every((page) => page.locked), isTrue);
    expect(pages.first.assetId, pages.last.assetId, reason: 'kept once');
    expect(draft.assets.values.single.mimeType, 'application/pdf');
  });

  test('reads a folder of documents as a notebook of sections', () {
    final root = p.join(folder.path, 'Physics');
    document(
      'Waves.xopp',
      '<page width="10" height="10"/>',
      into: p.join(root, 'Optics'),
    );
    document(
      '2025-10-24 15-15 - Lenses.xopp',
      '<page width="10" height="10"/>',
      into: p.join(root, 'Optics'),
    );
    document(
      'Forces.xopp',
      '<page width="10" height="10"/>',
      into: p.join(root, 'Mechanics'),
    );
    final notebook = read(<String>[root], folders: true).notebooks.single;
    expect(notebook.title, 'Physics');
    expect(notebook.sections.map((section) => section.title), <String>[
      'Mechanics',
      'Optics',
    ]);
    expect(notebook.sections.last.pages.map((page) => page.title), <String>[
      'Lenses',
      'Waves',
    ]);
  });

  test('says which documents it could not read', () {
    final broken = File(p.join(folder.path, 'broken.xopp'))
      ..writeAsStringSync('not xml at all <');
    final draft = read(<String>[broken.path]);
    expect(draft.pages, isEmpty);
    expect(draft.warnings.single, contains('broken.xopp'));
  });
}
