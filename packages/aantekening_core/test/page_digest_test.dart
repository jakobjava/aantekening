import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

TextElement box(String id, List<TextBlock> blocks, {double y = 0}) =>
    TextElement(
      id: id,
      frame: Frame(x: 0, y: y, width: 300, height: 100),
      createdAt: 0,
      updatedAt: 0,
      blocks: blocks,
    );

InkElement ink(String id, double x, double y, {InkTool tool = InkTool.pen}) =>
    InkElement(
      id: id,
      frame: Frame(x: x, y: y, width: 40, height: 20),
      createdAt: 0,
      updatedAt: 0,
      strokes: <InkStroke>[
        InkStroke(
          tool: tool,
          color: 0xFF000000,
          width: 2,
          points: Float32List.fromList(<double>[
            x,
            y,
            1,
            0,
            x + 40,
            y + 20,
            1,
            0,
          ]),
        ),
      ],
    );

PdfElement pdf(String id, {double y = 400}) => PdfElement(
  id: id,
  frame: Frame(x: 0, y: y, width: 600, height: 800),
  createdAt: 0,
  updatedAt: 0,
  assetId: 'lecture.pdf',
  pageIndex: 2,
  extractedText: 'A ball is thrown upwards.',
);

PageDigest digest(List<NoteElement> elements) => PageDigest.of(
  PageDocument(id: 'page', elements: elements),
  title: 'Kinematics',
);

void main() {
  group('note links', () {
    test('are written as URIs and read back', () {
      const link = NoteLink.page('p1', elementId: 'e 2', block: 3);
      expect(link.toString(), 'aantekening://page/p1#element=e%202&block=3');
      expect(NoteLink.tryParse(link.toString()), link);
      expect(
        NoteLink.tryParse('aantekening://section/s9'),
        const NoteLink.section('s9'),
      );
      expect(NoteLink.tryParse('https://example.com'), isNull);
      expect(NoteLink.tryParse('aantekening://shelf/x'), isNull);
    });
  });

  group('sentences', () {
    List<String> split(List<TextRun> runs) {
      final text = runs.map((r) => r.text).join();
      return <String>[
        for (final (from, to) in SentenceSplitter.split(runs))
          text.substring(from, to),
      ];
    }

    test('end after a full stop, but not after an abbreviation, a number '
        'or inside a formula', () {
      expect(
        split(const <TextRun>[
          TextRun('Speed is z. B. 9.81 m/s. It falls! Why? Then '),
          TextRun.math(r'a. b', MathMode.latex),
          TextRun(' holds.\nNext line'),
        ]),
        <String>[
          'Speed is z. B. 9.81 m/s.',
          'It falls!',
          'Why?',
          r'Then a. b holds.',
          'Next line',
        ],
      );
      expect(split(const <TextRun>[TextRun('1. First, e.g. this.')]), <String>[
        '1. First, e.g. this.',
      ]);
    });

    test('of a paragraph are linked to their words, formulas and all', () {
      final page = digest(<NoteElement>[
        box('b', <TextBlock>[
          const TextBlock(
            runs: <TextRun>[
              TextRun('It slows down. At the top '),
              TextRun.math('v = 0', MathMode.latex),
              TextRun('.'),
            ],
          ),
        ]),
      ]);
      final sentences = page.passages.single.sentences;
      expect(sentences.map((s) => s.text), <String>[
        'It slows down.',
        r'At the top $v = 0$.',
      ]);
      expect(sentences.last.link.words, (from: 15, to: 32));
      expect(
        NoteLink.tryParse(sentences.last.link.toString()),
        sentences.last.link,
      );
    });
  });

  group('a page digest', () {
    test('writes text as Markdown passages, each linked to its paragraph', () {
      final page = digest(<NoteElement>[
        box('b', <TextBlock>[
          TextBlock.plain('Motion', kind: TextBlockKind.heading1),
          const TextBlock(
            runs: <TextRun>[
              TextRun('Speed is '),
              TextRun('distance', TextMarks(highlight: 0x66FFD60A)),
              TextRun(' over time: '),
              TextRun.math(r'v = \frac{s}{t}', MathMode.latex),
            ],
          ),
          TextBlock.plain('first', kind: TextBlockKind.numbered),
          TextBlock.plain('second', kind: TextBlockKind.numbered),
        ]),
      ]);
      expect(page.passages.map((p) => p.text), <String>[
        '# Motion',
        r'Speed is ==distance== over time: $v = \frac{s}{t}$',
        '1. first',
        '2. second',
      ]);
      expect(
        page.passages.elementAt(1).link,
        const NoteLink.page('page', elementId: 'b', block: 1),
      );
    });

    test('writes a table in a box as rows under its head', () {
      final page = digest(<NoteElement>[
        box('b', <TextBlock>[
          const TextBlock(
            runs: <TextRun>[TextRun('Name')],
            cell: TableCell(0, 0),
          ),
          const TextBlock(
            runs: <TextRun>[TextRun('Age')],
            cell: TableCell(0, 1),
          ),
          const TextBlock(
            runs: <TextRun>[TextRun('Ann')],
            cell: TableCell(1, 0),
          ),
          const TextBlock(
            runs: <TextRun>[TextRun('30')],
            cell: TableCell(1, 1),
          ),
        ]),
      ]);
      expect(page.passages.map((p) => p.text), <String>[
        '| Name | Age |\n| --- | --- |',
        '| Ann | 30 |',
      ]);
    });

    test('keeps the writing on a PDF page with it, as one visual', () {
      final page = digest(<NoteElement>[
        pdf('slide'),
        ink('arrow', 100, 600),
        ink('aside', 900, 100),
      ]);
      final slide = page.items.firstWhere((item) => item.elementId == 'slide');
      final visual = page.visual(slide.visualIds.single)!;
      expect(visual.annotated, isTrue);
      expect(visual.elementIds, <String>['slide', 'arrow']);
      expect(visual.pdfPageIndex, 2);
      expect(slide.passages.single.text, contains('A ball is thrown upwards'));

      // Writing elsewhere is a drawing of its own.
      final aside = page.items.firstWhere((item) => item.elementId == 'aside');
      expect(aside.kind, DigestKind.drawing);
      expect(page.visual(aside.visualIds.single)!.annotated, isFalse);
    });

    test('keeps a text box typed onto a worksheet with it, as one visual, '
        'its text still to be cited', () {
      final answer = TextElement(
        id: 'answer',
        frame: const Frame(x: 100, y: 500, width: 200, height: 40),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock.plain('v = 12 m/s')],
      );
      final page = digest(<NoteElement>[
        pdf('sheet'),
        answer,
        ink('arrow', 150, 700),
      ]);
      final sheet = page.items.firstWhere((item) => item.elementId == 'sheet');
      final visual = page.visual(sheet.visualIds.single)!;
      expect(visual.elementIds, <String>['sheet', 'answer', 'arrow']);
      expect(visual.annotated, isTrue);
      expect(
        visual.description,
        contains('handwriting or drawing and typed text boxes'),
      );

      final typed = page.items.firstWhere((item) => item.elementId == 'answer');
      expect(typed.passages.single.text, 'v = 12 m/s');
      expect(typed.visualIds, <String>[visual.id]);
      expect(typed.notes.single, contains('typed onto page 3 of a PDF'));
      expect(page.visuals, hasLength(1), reason: 'nothing drawn apart');
    });

    test('keeps writing over a printout in a text box with the box', () {
      final printout = TextElement(
        id: 'printout',
        frame: const Frame(x: 0, y: 0, width: 600, height: 800),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          TextBlock.plain('Worksheet 4'),
          const TextBlock.embedded(
            BlockEmbed(
              kind: EmbedKind.pdfPage,
              assetId: 'sheet.pdf',
              pageIndex: 0,
              width: 580,
              height: 750,
            ),
          ),
        ],
      );
      final page = digest(<NoteElement>[printout, ink('circle', 200, 300)]);
      expect(page.visuals, hasLength(1));
      final visual = page.visuals.single;
      expect(visual.elementIds, <String>['printout', 'circle']);
      expect(visual.bounds, isNotNull, reason: 'drawn where it is');
      expect(
        page.passages.elementAt(1).text,
        startsWith('[PDF page 1, in visual ${visual.id}]'),
      );
    });

    test('shows a printout box lying on a PDF page with the page, and the '
        'writing on either', () {
      final box = TextElement(
        id: 'box',
        frame: const Frame(x: 50, y: 450, width: 300, height: 200),
        createdAt: 0,
        updatedAt: 0,
        z: 1,
        blocks: const <TextBlock>[
          TextBlock.embedded(
            BlockEmbed(
              kind: EmbedKind.image,
              assetId: 'graph.png',
              width: 280,
              height: 180,
            ),
          ),
        ],
      );
      final page = digest(<NoteElement>[
        pdf('sheet'),
        box,
        ink('mark', 60, 460),
      ]);
      expect(page.visuals.single.elementIds, <String>['sheet', 'box', 'mark']);
    });

    test('a small picture is not a sheet for a text box larger than it', () {
      final page = digest(<NoteElement>[
        ImageElement(
          id: 'icon',
          frame: const Frame(x: 10, y: 10, width: 20, height: 20),
          createdAt: 0,
          updatedAt: 0,
          assetId: 'i',
        ),
        box('big', <TextBlock>[TextBlock.plain('text')]),
      ]);
      final big = page.items.firstWhere((item) => item.elementId == 'big');
      expect(big.notes, isEmpty);
      expect(big.visualIds, isEmpty);
    });

    test('gathers writing close together into one drawing', () {
      final page = digest(<NoteElement>[
        ink('a', 0, 0),
        ink('b', 60, 0),
        ink('far', 800, 800),
      ]);
      expect(page.items, hasLength(2));
      expect(
        page.visuals.first.elementIds,
        unorderedEquals(<String>['a', 'b']),
      );
    });

    test('reads down the page, and across things side by side', () {
      final page = digest(<NoteElement>[
        box('low', <TextBlock>[TextBlock.plain('3')], y: 500),
        box('top', <TextBlock>[TextBlock.plain('1')]),
        TextElement(
          id: 'beside',
          frame: const Frame(x: 400, y: 10, width: 100, height: 40),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[TextBlock.plain('2')],
        ),
      ]);
      expect(page.items.map((item) => item.elementId), <String>[
        'top',
        'beside',
        'low',
      ]);
    });

    test('leaves out what says nothing', () {
      expect(
        digest(<NoteElement>[box('empty', const <TextBlock>[])]).isEmpty,
        isTrue,
      );
    });
  });
}
