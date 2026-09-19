import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

const int _now = 1758000000000;

TextElement _text(String id, String body, {double x = 0, double y = 0}) =>
    TextElement(
      id: id,
      frame: Frame(x: x, y: y, width: 200, height: 40),
      createdAt: _now,
      updatedAt: _now,
      blocks: <TextBlock>[TextBlock.plain(body)],
    );

void main() {
  group('PageDocument serialization', () {
    test('round-trips every element type', () {
      final document = PageDocument(
        id: 'PAGE01',
        revision: 7,
        canvas: const CanvasSettings(
          background: PageBackground(
            kind: PageBackgroundKind.grid,
            spacing: 32,
          ),
          paperWidth: 816,
        ),
        elements: <NoteElement>[
          TextElement(
            id: 'el_text',
            frame: const Frame(x: 10, y: 20, width: 300, height: 120),
            createdAt: _now,
            updatedAt: _now,
            blocks: <TextBlock>[
              const TextBlock(
                kind: TextBlockKind.heading1,
                runs: <TextRun>[TextRun('Chapter', TextMarks(bold: true))],
              ),
              const TextBlock(
                kind: TextBlockKind.todo,
                checked: true,
                indent: 1,
                runs: <TextRun>[TextRun('review proofs')],
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
          ImageElement(
            id: 'el_image',
            frame: const Frame(x: 0, y: 200, width: 400, height: 300),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'asset_a',
            fit: MediaFit.cover,
            altText: 'a diagram',
          ),
          PdfElement(
            id: 'el_pdf',
            frame: const Frame(x: 500, y: 0, width: 612, height: 792),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'asset_b',
            pageIndex: 3,
            extractedText: 'lecture notes',
          ),
          MathElement(
            id: 'el_math',
            frame: const Frame(x: 0, y: 600, width: 200, height: 60),
            createdAt: _now,
            updatedAt: _now,
            source: r'\frac{a}{b}',
            mode: MathMode.latex,
          ),
          TableElement(
            id: 'el_table',
            frame: const Frame(x: 0, y: 700, width: 300, height: 100),
            createdAt: _now,
            updatedAt: _now,
            headerRow: true,
            columnWidths: const <double>[150, 150],
            rows: <List<TextBlock>>[
              <TextBlock>[TextBlock.plain('n'), TextBlock.plain('f(n)')],
              <TextBlock>[TextBlock.plain('1'), TextBlock.plain('1')],
            ],
          ),
          GroupElement(
            id: 'el_group',
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            childIds: const <String>['el_text', 'el_math'],
            label: 'proof',
          ),
        ],
      );

      final restored = PageDocument.decode(document.encode());

      expect(restored.id, document.id);
      expect(restored.revision, 7);
      expect(restored.canvas.paperWidth, 816);
      expect(restored.canvas.background.kind, PageBackgroundKind.grid);
      expect(restored.elements.map((e) => e.type).toList(), <String>[
        'text',
        'ink',
        'image',
        'pdf',
        'math',
        'table',
        'group',
      ]);

      final text = restored.elementById('el_text')! as TextElement;
      expect(text.blocks.first.runs.first.marks.bold, isTrue);
      expect(text.blocks[1].kind, TextBlockKind.todo);
      expect(text.blocks[1].checked, isTrue);
      expect(text.blocks[1].indent, 1);

      final ink = restored.elementById('el_ink')! as InkElement;
      expect(ink.strokes.single.pointCount, 3);
      expect(ink.strokes.single.tool, InkTool.highlighter);
      expect(ink.strokes.single.pressureAt(1), closeTo(0.9, 1e-6));

      final math = restored.elementById('el_math')! as MathElement;
      expect(math.source, r'\frac{a}{b}');
      expect(math.mode, MathMode.latex);

      final table = restored.elementById('el_table')! as TableElement;
      expect(table.rowCount, 2);
      expect(table.columnCount, 2);
      expect(table.rows[1][1].plainText, '1');
    });

    test('skips unknown element types instead of failing the whole page', () {
      final json = <String, Object?>{
        'formatVersion': 99,
        'id': 'PAGE02',
        'revision': 1,
        'canvas': const CanvasSettings().toJson(),
        'elements': <Object?>[
          _text('el_keep', 'kept').toJson(),
          <String, Object?>{'id': 'el_future', 'type': 'hologram'},
        ],
      };

      final restored = PageDocument.fromJson(json);

      expect(restored.elements.map((e) => e.id), <String>['el_keep']);
    });

    test('reports malformed JSON as a page format error', () {
      expect(
        () => PageDocument.decode('not json'),
        throwsA(isA<PageFormatException>()),
      );
      expect(
        () => PageDocument.decode('[1,2,3]'),
        throwsA(isA<PageFormatException>()),
      );
    });

    test('tolerates a truncated ink sample tuple', () {
      final stroke = InkStroke.fromJson(<String, Object?>{
        'tool': 'pen',
        'color': 0xFF000000,
        'width': 2.0,
        // Seven values: one complete tuple plus a torn second one.
        'points': <double>[0, 0, 1, 0, 5, 5, 1],
      });
      expect(stroke.pointCount, 1);
    });
  });

  group('PageDocument editing', () {
    test('adding an element puts it on top and bumps the revision', () {
      final page = PageDocument.empty(id: 'PAGE03')
          .withElementAdded(_text('a', 'first'))
          .withElementAdded(_text('b', 'second'));

      expect(page.revision, 2);
      expect(page.elements.last.z, page.topZ);
      expect(page.elements.first.z, lessThan(page.elements.last.z));
    });

    test('replacing an absent element is a no-op', () {
      final page = PageDocument.empty(
        id: 'PAGE04',
      ).withElementAdded(_text('a', 'first'));
      final same = page.withElementReplaced(_text('ghost', 'nope'));

      expect(identical(same, page), isTrue);
      expect(same.revision, page.revision);
    });

    test('removing elements drops them and bumps the revision once', () {
      final page = PageDocument.empty(id: 'PAGE05')
          .withElementAdded(_text('a', 'first'))
          .withElementAdded(_text('b', 'second'));

      final trimmed = page.withElementsRemoved(<String>{'a', 'missing'});

      expect(trimmed.elements.map((e) => e.id), <String>['b']);
      expect(trimmed.revision, page.revision + 1);
      expect(
        identical(page.withElementsRemoved(const <String>{}), page),
        isTrue,
      );
    });

    test('content beyond the top or left edge moves onto the page', () {
      final page = PageDocument.empty(id: 'PAGE07')
          .withElementAdded(_text('left', 'a', x: -30, y: 50))
          .withElementAdded(_text('high', 'b', x: 40, y: -10));

      final moved = page.withContentOnPage();

      expect(moved.contentBounds.left, 0);
      expect(moved.contentBounds.top, 0);
      // Moved together, so the content keeps its layout.
      expect(moved.elementById('high')!.frame.x, 70);
      expect(moved.elementById('left')!.frame.y, 60);
    });

    test('a page whose content is on it is left as it is', () {
      final page = PageDocument.empty(
        id: 'PAGE08',
      ).withElementAdded(_text('a', 'first', x: 0, y: 12));

      expect(identical(page.withContentOnPage(), page), isTrue);
    });
  });

  group('PageDocument indexing', () {
    test('extracts text from every element that carries any', () {
      final page = PageDocument(
        id: 'PAGE07',
        elements: <NoteElement>[
          _text('t', 'integral of x'),
          MathElement(
            id: 'm',
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            source: r'\int x \, dx',
          ),
          PdfElement(
            id: 'p',
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'asset',
            pageIndex: 0,
            extractedText: 'fundamental theorem',
          ),
        ],
      );

      final text = page.extractSearchText();

      expect(text, contains('integral of x'));
      expect(text, contains(r'\int x'));
      expect(text, contains('fundamental theorem'));
    });

    test('collects every referenced asset for garbage collection', () {
      final page = PageDocument(
        id: 'PAGE08',
        elements: <NoteElement>[
          ImageElement(
            id: 'i',
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'shared',
          ),
          PdfElement(
            id: 'p',
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'shared',
            pageIndex: 1,
          ),
        ],
      );

      expect(page.referencedAssetIds, <String>{'shared'});
    });

    test('content bounds cover every element', () {
      final page = PageDocument(
        id: 'PAGE09',
        elements: <NoteElement>[
          _text('a', 'x', x: 0, y: 0),
          _text('b', 'y', x: 500, y: 300),
        ],
      );

      final bounds = page.contentBounds;
      expect(bounds.left, 0);
      expect(bounds.right, 700);
      expect(bounds.bottom, 340);
    });
  });

  group('InkElement', () {
    test('bounds track the strokes, not the declared frame', () {
      final element = InkElement(
        id: 'ink',
        frame: const Frame(x: 0, y: 0, width: 1000, height: 1000),
        createdAt: _now,
        updatedAt: _now,
        strokes: <InkStroke>[
          InkStroke(
            tool: InkTool.pen,
            color: 0xFF000000,
            width: 2,
            points: Float32List.fromList(<double>[0, 0, 1, 0, 10, 10, 1, 0]),
          ),
        ],
      );

      expect(element.bounds.right, lessThan(20));
    });

    test('moving the frame translates the underlying samples', () {
      final element = InkElement(
        id: 'ink',
        frame: const Frame(x: 0, y: 0, width: 10, height: 10),
        createdAt: _now,
        updatedAt: _now,
        strokes: <InkStroke>[
          InkStroke.fromPoints(
            tool: InkTool.pen,
            color: 0xFF000000,
            width: 2,
            xs: <double>[0, 10],
            ys: <double>[0, 10],
          ),
        ],
      );

      final moved = element.withFrame(element.frame.translate(100, 50));

      expect(moved.strokes.single.xAt(0), closeTo(100, 1e-6));
      expect(moved.strokes.single.yAt(1), closeTo(60, 1e-6));
    });

    test('stroke hit testing respects the eraser radius', () {
      final stroke = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        xs: <double>[0, 50],
        ys: <double>[0, 0],
      );

      expect(stroke.hitTest(50, 2, 4), isTrue);
      expect(
        stroke.hitTest(25, 1, 4),
        isTrue,
        reason: 'the line between two distant samples is still drawn ink',
      );
      expect(stroke.hitTest(25, 40, 4), isFalse);
    });
  });
}
