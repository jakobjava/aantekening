import 'dart:convert';
import 'dart:math' as math;
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
    });

    test('reads a formula, a table or a group on the page by itself, from '
        'before text boxes held them, as what holds them now', () {
      Map<String, Object?> element(
        String type,
        Map<String, Object?> rest,
      ) => <String, Object?>{
        'id': 'el_$type',
        'type': type,
        'frame': const Frame(x: 100, y: 200, width: 300, height: 60).toJson(),
        'createdAt': _now,
        'updatedAt': _now,
        ...rest,
      };
      final document = PageDocument.fromJson(<String, Object?>{
        'id': 'PAGE03',
        'canvas': CanvasSettings.defaults.toJson(),
        'elements': <Object?>[
          element('math', <String, Object?>{
            'source': r'\frac{a}{b}',
            'mode': 'latex',
          }),
          element('table', <String, Object?>{
            'columnWidths': <double>[150, 90],
            'rows': <Object?>[
              <Object?>[
                TextBlock.plain('n').toJson(),
                TextBlock.plain('f').toJson(),
              ],
              <Object?>[
                TextBlock.plain('1').toJson(),
                TextBlock.plain('1').toJson(),
              ],
            ],
          }),
          element('group', <String, Object?>{
            'childIds': <String>['el_math'],
          }),
        ],
      });

      expect(document.elements.map((e) => e.id), <String>[
        'el_math',
        'el_table',
      ], reason: 'a group held nothing of its own');
      final formula = document.elementById('el_math')! as TextElement;
      expect(
        formula.blocks.single.runs.single,
        const TextRun.math(r'\frac{a}{b}', MathMode.latex),
      );
      expect(formula.frame.x, lessThan(100), reason: 'its text where it was');
      final table = document.elementById('el_table')! as TextElement;
      expect(table.blocks.map((b) => b.plainText), <String>[
        'n',
        'f',
        '1',
        '1',
      ]);
      expect(table.blocks[3].cell, const TableCell(1, 1, width: 90));
    });

    test('skips unknown element types instead of failing the whole page', () {
      final json = <String, Object?>{
        'formatVersion': 99,
        'id': 'PAGE02',
        'revision': 1,
        'canvas': CanvasSettings.defaults.toJson(),
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

    test('keeps the width a box that fits its text wraps at', () {
      final document = PageDocument(
        id: 'PAGE01',
        elements: <NoteElement>[
          const TextElement(
            id: 'box',
            frame: Frame(x: 0, y: 0, width: 80, height: 40),
            createdAt: _now,
            updatedAt: _now,
            autoWidth: true,
            widthLimit: 312,
          ),
        ],
      );
      final box =
          PageDocument.decode(document.encode()).elements.single as TextElement;
      expect(box.autoWidth, isTrue);
      expect(box.widthLimit, 312);
    });

    test('renames the assets a page shows, and leaves its handwriting', () {
      final ink = InkElement(
        id: 'ink',
        frame: const Frame(x: 0, y: 0, width: 10, height: 10),
        createdAt: _now,
        updatedAt: _now,
      );
      final document = PageDocument(
        id: 'PAGE01',
        elements: <NoteElement>[
          ink,
          const ImageElement(
            id: 'picture',
            frame: Frame(x: 0, y: 20, width: 40, height: 30),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'old',
          ),
        ],
      );
      final renamed = document.withAssetsRenamed(<String, String>{
        'old': 'new',
      });
      expect(renamed.referencedAssetIds, <String>{'new'});
      expect(renamed.elements.first, same(ink));
    });

    test('writes handwriting as its JSON does, whatever the numbers', () {
      final random = math.Random(7);
      final values = <double>[
        0,
        -0.001,
        0.004,
        0.005,
        0.05,
        0.5,
        1,
        -1,
        12.3,
        -12.34,
        100.1,
        99.995,
        1e-9,
        123456.78,
        -98765.43,
        1e14,
        3.14159,
        0.66,
        4291.91,
        for (var i = 0; i < 2000; i++) (random.nextDouble() - 0.3) * 20000,
      ];
      final stroke = InkStroke(
        tool: InkTool.pencil,
        color: 0xFF112233,
        width: 1.3228347898468258,
        points: Float32List.fromList(values),
      );
      final element = InkElement(
        id: 'ink',
        frame: const Frame(x: 1, y: 2, width: 3, height: 4),
        createdAt: _now,
        updatedAt: _now,
        z: 2,
      ).withStrokes(<InkStroke>[stroke, stroke]);
      expect(element.encode(), jsonEncode(element.toJson()));
    });

    test('encodes as its JSON does, after an edit too', () {
      final document = PageDocument(
        id: 'PAGE01',
        revision: 3,
        elements: <NoteElement>[_text('a', 'one'), _text('b', 'two', y: 60)],
      );
      expect(document.encode(), jsonEncode(document.toJson()));

      final edited = document
          .withElementReplaced(_text('b', 'three', y: 60))
          .withElementAdded(_text('c', 'four', y: 120));
      expect(edited.encode(), jsonEncode(edited.toJson()));
      expect(document.encode(), jsonEncode(document.toJson()));
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
      ).withElementAdded(_text('a', 'first', y: 12));

      expect(identical(page.withContentOnPage(), page), isTrue);
    });
  });

  group('PageDocument indexing', () {
    test('extracts text from every element that carries any', () {
      final page = PageDocument(
        id: 'PAGE07',
        elements: <NoteElement>[
          _text('t', 'integral of x'),
          const TextElement(
            id: 'm',
            frame: Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            blocks: <TextBlock>[
              TextBlock(
                runs: <TextRun>[TextRun.math(r'\int x \, dx', MathMode.latex)],
              ),
            ],
          ),
          const PdfElement(
            id: 'p',
            frame: Frame(x: 0, y: 0, width: 10, height: 10),
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
          const ImageElement(
            id: 'i',
            frame: Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: _now,
            updatedAt: _now,
            assetId: 'shared',
          ),
          const PdfElement(
            id: 'p',
            frame: Frame(x: 0, y: 0, width: 10, height: 10),
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
          _text('a', 'x'),
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

  group('copies to paste', () {
    test('are new things, moved, keeping what they hold', () {
      final original = _text('a', 'hello', x: 10, y: 20);
      final copy =
          NoteElement.copiesOf(
                <NoteElement>[original],
                now: _now + 5,
                offset: const Vec2(24, 24),
              ).single
              as TextElement;

      expect(copy.id, isNot(original.id));
      expect(copy.frame.x, 34);
      expect(copy.frame.y, 44);
      expect(copy.createdAt, _now + 5);
      expect(copy.blocks, original.blocks);
    });
  });
}
