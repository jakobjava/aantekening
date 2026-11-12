/// Notes made up to measure the app on: a heavy page — a printout written
/// over in pen — and whole notebooks of a size a few years of study leave,
/// with pages among them heavy each in its own way.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';

// ------------------------------------------------------------- the page

/// A page made up to be heavy: a printout of eight pages, each written
/// over in pen and marked with a highlighter, with a text box beside each.
Future<String> madeUpPage(AantekeningStore store, Directory folder) async {
  final elements = await printoutWrittenOver(
    store,
    folder,
    math.Random(7),
    pages: 8,
    lines: 14,
    words: 5,
  );
  final notebook = await store.library.createNotebook(title: 'Benchmark');
  final section = await store.library.createSection(
    notebookId: notebook.id,
    title: 'Benchmark',
  );
  final ref = await store.pages.createPage(
    sectionId: section.id,
    title: 'Heavy page',
  );
  await _fill(store, ref.id, elements);
  return ref.id;
}

/// Saves [elements] as what the page [pageId] holds.
Future<void> _fill(
  AantekeningStore store,
  String pageId,
  List<NoteElement> elements,
) async {
  var document = (await store.pages.loadDocument(pageId))!;
  for (final element in elements) {
    document = document.withElementAdded(element);
  }
  await store.pages.saveDocument(pageId, document);
}

/// A printout of [pages] pages, one beneath the other, each written over
/// with [lines] lines of [words] handwritten words, the first word of every
/// sixth line marked with a highlighter instead, and a text box beside
/// each.
Future<List<NoteElement>> printoutWrittenOver(
  AantekeningStore store,
  Directory folder,
  math.Random random, {
  required int pages,
  required int lines,
  required int words,
}) async {
  const width = 816.0;
  const height = width * 842 / 595;
  const gap = 40.0;
  final pdf = File('${folder.path}/printout-$pages.pdf')
    ..writeAsBytesSync(printout(pages));
  final asset = await store.assets.importFile(pdf, mimeType: 'application/pdf');
  // As far apart as a hand writes, or as close as fits the page.
  final lineHeight = math.min(62.0, (height - 160) / lines);
  final wordWidth = math.min(140.0, (width - 100) / words);
  final elements = <NoteElement>[];
  for (var page = 0; page < pages; page++) {
    final top = 120 + page * (height + gap);
    elements
      ..add(
        PdfElement(
          id: Ulid.generate(),
          frame: Frame(x: 40, y: top, width: width, height: height),
          createdAt: 0,
          updatedAt: 0,
          assetId: asset.id,
          pageIndex: page,
          locked: true,
        ),
      )
      ..add(
        TextElement(
          id: Ulid.generate(),
          frame: Frame(x: width + 80, y: top, width: 360, height: 400),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            for (var line = 0; line < 12; line++)
              TextBlock.plain(
                'Aufgabe ${page + 1}.$line: Die Welle breitet sich mit '
                'c = λ·f aus, und ihre Energie wächst mit dem Quadrat der '
                'Amplitude.',
              ),
          ],
        ),
      );
    // Lines of handwriting, a word at a time, over the printout.
    for (var line = 0; line < lines; line++) {
      final y = top + 80 + line * lineHeight;
      for (var word = 0; word < words; word++) {
        elements.add(
          handwriting(
            random,
            Offset(90 + word * wordWidth, y),
            highlight: line % 6 == 0 && word == 0,
          ),
        );
      }
    }
  }
  return elements;
}

/// A handwritten word at [at]: a few strokes of a hundred samples, their
/// pressure rising and falling as a pen's does.
InkElement handwriting(
  math.Random random,
  Offset at, {
  required bool highlight,
}) {
  final strokes = <InkStroke>[
    for (var stroke = 0; stroke < (highlight ? 1 : 4); stroke++)
      () {
        final xs = <double>[];
        final ys = <double>[];
        final pressures = <double>[];
        const samples = 100;
        final start = at.dx + stroke * 28;
        for (var i = 0; i < samples; i++) {
          final t = i / samples;
          xs.add(
            start + t * (highlight ? 360 : 26) + random.nextDouble() * 0.6,
          );
          ys.add(
            at.dy +
                (highlight ? 0 : math.sin(t * math.pi * 6) * 9) +
                random.nextDouble() * 0.6,
          );
          pressures.add(0.4 + 0.5 * math.sin(t * math.pi));
        }
        return InkStroke.fromPoints(
          tool: highlight ? InkTool.highlighter : InkTool.pen,
          color: highlight ? 0x80FFE000 : 0xFF1A3C8C,
          width: highlight ? 14 : 2.2,
          xs: xs,
          ys: ys,
          pressures: highlight ? null : pressures,
        );
      }(),
  ];
  var bounds = strokes.first.bounds;
  for (final stroke in strokes.skip(1)) {
    bounds = bounds.union(stroke.bounds);
  }
  return InkElement(
    id: Ulid.generate(),
    frame: Frame(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    ),
    createdAt: 0,
    updatedAt: 0,
    strokes: strokes,
  );
}

/// A PDF of [pages] A4 pages, each a worksheet: lines of text, ruled boxes
/// and a curve plotted on axes, all drawn rather than pictured, as a
/// printout of a document is.
Uint8List printout(int pages) {
  final kids = <String>[for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count $pages >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var page = 0; page < pages; page++) {
    final content = StringBuffer('BT /F1 10 Tf 13 TL 50 790 Td\n');
    for (var line = 0; line < 54; line++) {
      content.writeln(
        '(Aufgabe ${page + 1}.$line  Eine Welle der Frequenz '
        'f = ${line + 2} Hz breitet sich mit c = 340 m/s aus. '
        'Bestimme die Wellenlaenge.) \'',
      );
    }
    content.writeln('ET');
    for (var box = 0; box < 6; box++) {
      content.writeln('${50 + box * 85} 60 75 40 re S');
    }
    content.write('0.2 0.3 0.7 RG 1.2 w 60 200 m');
    for (var i = 0; i <= 400; i++) {
      final x = 60 + i * 1.2;
      final y = 200 + 60 * math.sin(i / 400 * math.pi * 6) * math.exp(-i / 300);
      content.write(' ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} l');
    }
    content.writeln(' S');
    final stream = content.toString();
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R >> >> '
        '/Contents ${5 + page * 2} 0 R >>',
      )
      ..add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out
    ..write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n')
    ..writeAll(<String>[
      for (final offset in offsets)
        '${offset.toString().padLeft(10, '0')} 00000 n \n',
    ])
    ..write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
  return Uint8List.fromList(out.toString().codeUnits);
}

// ------------------------------------------------------------ the notes

/// How much the notes made up hold.
class NotesSize {
  const NotesSize({
    required this.notebooks,
    required this.sections,
    required this.pages,
    required this.strokes,
    required this.paragraphs,
    required this.boxes,
    required this.pictures,
    required this.printout,
  });

  /// From `AANTEKENING_BENCH_SIZE` in [environment] — `quick`, as it is
  /// without, or `large` — with any one of them set by a variable of its
  /// own: `AANTEKENING_BENCH_PAGES`, say.
  factory NotesSize.from(Map<String, String> environment) {
    final named = environment['AANTEKENING_BENCH_SIZE'] == 'large'
        ? large
        : quick;
    int of(String name, int otherwise) {
      final set = int.tryParse(environment['AANTEKENING_BENCH_$name'] ?? '');
      return set == null || set < 1 ? otherwise : set;
    }

    return NotesSize(
      notebooks: of('NOTEBOOKS', named.notebooks),
      sections: of('SECTIONS', named.sections),
      pages: of('PAGES', named.pages),
      strokes: of('STROKES', named.strokes),
      paragraphs: of('PARAGRAPHS', named.paragraphs),
      boxes: of('BOXES', named.boxes),
      pictures: of('PICTURES', named.pictures),
      printout: of('PRINTOUT', named.printout),
    );
  }

  /// A student's notes after a couple of years, measured in a few minutes.
  static const NotesSize quick = NotesSize(
    notebooks: 3,
    sections: 40,
    pages: 2000,
    strokes: 3000,
    paragraphs: 400,
    boxes: 40,
    pictures: 12,
    printout: 8,
  );

  /// Everything a degree leaves, and pages as heavy as any gets.
  static const NotesSize large = NotesSize(
    notebooks: 6,
    sections: 120,
    pages: 10000,
    strokes: 12000,
    paragraphs: 1500,
    boxes: 120,
    pictures: 30,
    printout: 24,
  );

  final int notebooks;

  /// The sections of all the notebooks together.
  final int sections;

  /// The pages of all the sections together, the heavy ones among them.
  final int pages;

  /// How many strokes of ink the page of handwriting holds, about.
  final int strokes;

  /// How many paragraphs the long text box holds.
  final int paragraphs;

  /// How many text boxes with formulas the page of them holds.
  final int boxes;

  /// How many pictures lie on that page too.
  final int pictures;

  /// How many pages the printout under the handwriting has.
  final int printout;

  Map<String, Object?> toJson() => <String, Object?>{
    'notebooks': notebooks,
    'sections': sections,
    'pages': pages,
    'strokes': strokes,
    'paragraphs': paragraphs,
    'boxes': boxes,
    'pictures': pictures,
    'printout': printout,
  };
}

/// The notes made up: the pages the measures open, by what is on them, and
/// what the notes hold in all.
class MadeUpNotes {
  const MadeUpNotes({
    required this.notebook,
    required this.section,
    required this.ordinary,
    required this.ink,
    required this.inkAgain,
    required this.longText,
    required this.formulas,
    required this.blank,
    required this.holds,
  });

  factory MadeUpNotes.fromJson(Map<String, Object?> json) => MadeUpNotes(
    notebook: json['notebook']! as String,
    section: json['section']! as String,
    ordinary: json['ordinary']! as String,
    ink: json['ink']! as String,
    inkAgain: json['inkAgain']! as String,
    longText: json['longText']! as String,
    formulas: json['formulas']! as String,
    blank: json['blank']! as String,
    holds: (json['holds']! as Map<String, Object?>).cast<String, int>(),
  );

  /// The titles of the heavy pages, which they are gone to by.
  static const String inkTitle = 'Handwriting over a worksheet';
  static const String inkAgainTitle = 'Second worksheet written over';
  static const String longTextTitle = 'Lecture notes without end';
  static const String formulasTitle = 'Formula sheet and images';
  static const String blankTitle = 'Blank sheet';

  /// The section with the most pages, which the pages named here are all
  /// in, and its notebook.
  final String notebook;
  final String section;

  /// A page like most: a few paragraphs. The window opens on it.
  final String ordinary;

  /// A printout written all over in pen, and another like it.
  final String ink;
  final String inkAgain;

  /// A text box of hundreds of paragraphs, and a short one above it.
  final String longText;

  /// Dozens of text boxes with formulas, and pictures among them.
  final String formulas;

  /// A page with nothing on it.
  final String blank;

  /// What the notes hold, counted: notebooks, sections, pages, and the
  /// strokes, paragraphs, boxes and pictures of the heavy pages.
  final Map<String, int> holds;

  Map<String, Object?> toJson() => <String, Object?>{
    'notebook': notebook,
    'section': section,
    'ordinary': ordinary,
    'ink': ink,
    'inkAgain': inkAgain,
    'longText': longText,
    'formulas': formulas,
    'blank': blank,
    'holds': holds,
  };
}

/// What lectures are called, the subjects they are on, and the words
/// their notes are made of: German, Dutch and English, as the notes of
/// someone studying in two countries are.
const List<String> _kinds = <String>[
  'Vorlesung',
  'Hoorcollege',
  'Lecture',
  'Übung',
  'Werkcollege',
  'Seminar',
  'Praktikum',
  'Zusammenfassung',
];

const List<String> _subjects = <String>[
  'Wellen und Schwingungen',
  'Klassieke mechanica',
  'Thermodynamics',
  'Lineare Algebra',
  'Elektrodynamik',
  'Kwantummechanica',
  'Complex analysis',
  'Statistische Physik',
  'Differentiaalvergelijkingen',
  'Optics',
  'Festkörperphysik',
  'Kansrekening',
];

const List<String> _words = <String>[
  'die',
  'Welle',
  'Energie',
  'Impuls',
  'Schwingung',
  'Frequenz',
  'Amplitude',
  'breitet',
  'sich',
  'aus',
  'und',
  'bleibt',
  'erhalten',
  'wenn',
  'das',
  'System',
  'symmetrisch',
  'ist',
  'de',
  'golf',
  'energie',
  'behoud',
  'van',
  'impuls',
  'volgt',
  'uit',
  'symmetrie',
  'het',
  'stelsel',
  'the',
  'wave',
  'momentum',
  'is',
  'conserved',
  'where',
  'laws',
  'are',
  'symmetric',
  'under',
  'translation',
  'rotation',
  'field',
  'potential',
  'gradient',
  'Lagrange',
  'Hamilton',
  'operator',
  'eigenvalue',
  'matrix',
  'vector',
  'integral',
  'Grenzwert',
  'Ableitung',
  'Reihe',
  'konvergiert',
  'bewijs',
  'stelling',
  'lemma',
  'gevolg',
  'voorbeeld',
  'entropy',
  'temperature',
  'pressure',
  'volume',
  'Wärme',
  'Arbeit',
  'Feld',
  'Ladung',
  'Strom',
  'Spannung',
];

/// Formulas as they are kept on a page, in LaTeX.
const List<String> _formulas = <String>[
  'E = mc^2',
  r'\lambda = \frac{c}{f}',
  r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
  r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}',
  r'\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}',
  r'\frac{d}{dt}\frac{\partial L}{\partial \dot q} = \frac{\partial L}{\partial q}',
  r'\nabla \times \vec{B} = \mu_0 \vec{J}',
  r'\hat{H}\psi = E\psi',
  r'e^{i\pi} + 1 = 0',
  r'\Delta S \geq 0',
];

/// A sentence of [length] of the words notes are made of.
String _sentence(math.Random random, int length) {
  final words = <String>[
    for (var i = 0; i < length; i++) _words[random.nextInt(_words.length)],
  ];
  final first = words.first;
  words[0] = '${first[0].toUpperCase()}${first.substring(1)}';
  return '${words.join(' ')}.';
}

/// A paragraph of a sentence or three, now and then with a formula in it,
/// if [formulas].
TextBlock _paragraph(math.Random random, {bool formulas = false}) {
  final text = <String>[
    for (var i = random.nextInt(3); i >= 0; i--)
      _sentence(random, 6 + random.nextInt(10)),
  ].join(' ');
  if (!formulas) return TextBlock.plain(text);
  return TextBlock(
    runs: <TextRun>[
      TextRun('$text '),
      TextRun.math(_formulas[random.nextInt(_formulas.length)], MathMode.latex),
      TextRun(' ${_sentence(random, 5)}'),
    ],
  );
}

/// Makes up notes of [size] in [store]: notebooks of sections of pages, a
/// fifth of the pages in one section, most of them a few paragraphs, some
/// with a little handwriting — and the heavy ones. The same notes each
/// time, but for their ids.
///
/// [folder] is where the files that go into them — a printout, pictures —
/// are made first.
Future<MadeUpNotes> makeUpNotes(
  AantekeningStore store,
  Directory folder,
  NotesSize size,
) async {
  final random = math.Random(11);
  const names = <String>[
    'Physik',
    'Wiskunde',
    'Notes',
    'Chemie',
    'Informatica',
    'Seminare',
  ];
  final notebooks = <Notebook>[
    for (var i = 0; i < size.notebooks; i++)
      await store.library.createNotebook(
        title: i < names.length ? names[i] : 'Notebook ${i + 1}',
      ),
  ];
  // Sections dealt out among the notebooks, every fifth one beneath the
  // one before it.
  final sections = <Section>[];
  for (var i = 0; i < math.max(size.sections, size.notebooks); i++) {
    final notebook = notebooks[i % notebooks.length];
    final above = i % 5 == 4
        ? sections
              .where((section) => section.notebookId == notebook.id)
              .lastOrNull
        : null;
    sections.add(
      await store.library.createSection(
        notebookId: notebook.id,
        title: '${_subjects[i % _subjects.length]} ${2020 + i ~/ 12}',
        parentId: above?.id,
      ),
    );
  }

  // The heavy pages, in the first section, which is the fullest too.
  final busy = sections.first;
  Future<String> page(String title) async =>
      (await store.pages.createPage(sectionId: busy.id, title: title)).id;

  // Six words of four strokes to a line, and as many lines to each page
  // of the printout as hold the strokes asked for.
  final lines = (size.strokes / (4 * size.printout * 6)).ceil().clamp(1, 40);
  final ink = await page(MadeUpNotes.inkTitle);
  final inkElements = await printoutWrittenOver(
    store,
    folder,
    math.Random(7),
    pages: size.printout,
    lines: lines,
    words: 6,
  );
  await _fill(store, ink, inkElements);
  final inkAgain = await page(MadeUpNotes.inkAgainTitle);
  await _fill(
    store,
    inkAgain,
    await printoutWrittenOver(
      store,
      folder,
      math.Random(8),
      pages: size.printout,
      lines: lines,
      words: 6,
    ),
  );

  final longText = await page(MadeUpNotes.longTextTitle);
  await _fill(store, longText, <NoteElement>[
    TextElement(
      id: Ulid.generate(),
      frame: Frame(x: 40, y: 300, width: 640, height: size.paragraphs * 44.0),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[
        for (var i = 0; i < size.paragraphs; i++)
          i % 25 == 0
              ? TextBlock.plain(
                  '${_subjects[(i ~/ 25) % _subjects.length]}, part '
                  '${i ~/ 25 + 1}',
                  kind: TextBlockKind.heading2,
                )
              : _paragraph(random, formulas: i % 9 == 4),
      ],
    ),
    // The short one above it, where it is in view in a window of any size.
    TextElement(
      id: Ulid.generate(),
      frame: const Frame(x: 40, y: 120, width: 420, height: 130),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[
        for (var i = 0; i < 3; i++) TextBlock.plain(_sentence(random, 6)),
      ],
    ),
  ]);

  final pictures = <AssetRef>[
    for (var i = 0; i < math.min(4, size.pictures); i++)
      await store.assets.importBytes(
        picture(640 + i * 80, 420, seed: i),
        mimeType: 'image/png',
        originalName: 'picture-$i.png',
      ),
  ];
  final formulas = await page(MadeUpNotes.formulasTitle);
  await _fill(store, formulas, <NoteElement>[
    // Three across, a picture after every few of them.
    for (var i = 0; i < size.boxes; i++)
      TextElement(
        id: Ulid.generate(),
        frame: Frame(
          x: 40 + (i % 3) * 380.0,
          y: 120 + (i ~/ 3) * 260.0,
          width: 360,
          height: 240,
        ),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          for (var line = 0; line < 4; line++)
            _paragraph(random, formulas: true),
        ],
      ),
    for (var i = 0; i < size.pictures; i++)
      ImageElement(
        id: Ulid.generate(),
        frame: Frame(
          x: 1200 + (i % 2) * 340.0,
          y: 120 + (i ~/ 2) * 240.0,
          width: 320,
          height: 210,
        ),
        createdAt: 0,
        updatedAt: 0,
        assetId: pictures[i % pictures.length].id,
      ),
  ]);
  final blank = await page(MadeUpNotes.blankTitle);

  // The pages like most: a fifth of them in the first section, the rest
  // dealt out among the others; every seventh beneath the one before it.
  const heavy = 5;
  final ordinary = <String>[];
  String? before;
  Section? beforeIn;
  for (var i = 0; i < math.max(size.pages - heavy, 1); i++) {
    final section = i % 5 == 0 || sections.length == 1
        ? busy
        : sections[1 + i % (sections.length - 1)];
    final made = await store.pages.createPage(
      sectionId: section.id,
      title:
          '${_kinds[i % _kinds.length]} ${i ~/ _kinds.length + 1}: '
          '${_subjects[random.nextInt(_subjects.length)]}',
      parentId: i % 7 == 6 && identical(beforeIn, section) ? before : null,
    );
    before = made.id;
    beforeIn = section;
    if (identical(section, busy)) ordinary.add(made.id);
    var document = PageDocument.empty(id: made.id).withElementAdded(
      TextElement(
        id: Ulid.generate(),
        frame: const Frame(x: 40, y: 120, width: 600, height: 300),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          for (var line = 3 + random.nextInt(6); line > 0; line--)
            _paragraph(random, formulas: line % 4 == 0),
        ],
      ),
    );
    // A line of handwriting beneath it, on one page in fifteen.
    if (i % 15 == 7) {
      for (var word = 0; word < 6; word++) {
        document = document.withElementAdded(
          handwriting(random, Offset(60 + word * 130.0, 480), highlight: false),
        );
      }
    }
    await store.pages.saveDocument(made.id, document);
  }

  var strokes = 0;
  for (final element in inkElements) {
    if (element is InkElement) strokes += element.strokes.length;
  }
  return MadeUpNotes(
    notebook: busy.notebookId,
    section: busy.id,
    ordinary: ordinary[ordinary.length ~/ 2],
    ink: ink,
    inkAgain: inkAgain,
    longText: longText,
    formulas: formulas,
    blank: blank,
    holds: <String, int>{
      'notebooks': notebooks.length,
      'sections': sections.length,
      'pages': (await store.pages.listAllPages()).length,
      'pagesInFullestSection': (await store.pages.listPages(busy.id)).length,
      'strokes': strokes,
      'paragraphs': size.paragraphs,
      'boxes': size.boxes,
      'pictures': size.pictures,
      'printout': size.printout,
    },
  );
}

/// A picture [width] by [height], as a PNG: bands of colour with a grain
/// over them, so it is neither one flat colour nor noise — as a photograph
/// of a whiteboard is neither.
Uint8List picture(int width, int height, {int seed = 0}) {
  final random = math.Random(seed);
  final rows = BytesBuilder();
  for (var y = 0; y < height; y++) {
    // Each row unfiltered.
    rows.addByte(0);
    for (var x = 0; x < width; x++) {
      final band = ((x + y * 0.4) ~/ 60 + seed) % 3;
      final grain = random.nextInt(24);
      rows
        ..addByte(180 + band * 20 + grain)
        ..addByte(200 - band * 30 + grain)
        ..addByte(150 + ((y * 80) ~/ height) + grain);
    }
  }
  final out = BytesBuilder()
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = <int>[...ascii.encode(type), ...data];
    out
      ..add(_uint32(data.length))
      ..add(body)
      ..add(_uint32(_crc32(body)));
  }

  chunk('IHDR', <int>[
    ..._uint32(width),
    ..._uint32(height),
    // Eight bits each of red, green and blue.
    8, 2, 0, 0, 0,
  ]);
  chunk('IDAT', zlib.encode(rows.takeBytes()));
  chunk('IEND', const <int>[]);
  return out.takeBytes();
}

List<int> _uint32(int value) => <int>[
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

/// The checksum a PNG keeps of each of its chunks.
int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
