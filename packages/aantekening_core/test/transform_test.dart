import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

Matcher near(Vec2 expected) => predicate<Vec2>(
  (v) => (v.x - expected.x).abs() < 1e-9 && (v.y - expected.y).abs() < 1e-9,
  'near $expected',
);

InkStroke line(double x0, double y0, double x1, double y1) =>
    InkStroke.fromPoints(
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 2,
      xs: <double>[x0, x1],
      ys: <double>[y0, y1],
    );

void main() {
  group('Affine2D', () {
    test('rotates clockwise in screen orientation', () {
      final quarter = Affine2D.rotation(math.pi / 2);
      expect(quarter.apply(1, 0), near(const Vec2(0, 1)));
    });

    test('composes right to left', () {
      final moveThenDouble =
          Affine2D.scaling(2, 2) * Affine2D.translation(1, 0);
      expect(moveThenDouble.apply(0, 0), near(const Vec2(2, 0)));
    });

    test('scaling about a point keeps that point fixed', () {
      final scale = Affine2D.scalingAbout(3, 3, 10, 20);
      expect(scale.apply(10, 20), near(const Vec2(10, 20)));
      expect(scale.apply(11, 20), near(const Vec2(13, 20)));
      expect(scale.meanScale, closeTo(3, 1e-9));
    });
  });

  group('rotated frames', () {
    const frame = Frame(
      x: 0,
      y: 0,
      width: 100,
      height: 20,
      rotation: math.pi / 2,
    );

    test('contain points of the rotated shape only', () {
      // Standing upright about its centre (50, 10): 20 wide, 100 tall.
      expect(frame.containsPoint(50, -30), isTrue);
      expect(frame.containsPoint(90, 10), isFalse);
    });

    test('report their rotated corners', () {
      expect(frame.corners.first, near(const Vec2(60, -40)));
    });

    test('map page points back to their own coordinates', () {
      expect(frame.pageToLocal(60, -40), near(const Vec2(0, 0)));
      // 5 along its top edge, 3 in from it.
      final page = frame.localToPage.apply(5, 3);
      expect(frame.pageToLocal(page.x, page.y), near(const Vec2(5, 3)));
    });

    test('grow from their top-left corner, wherever it has turned to', () {
      for (final rotation in <double>[0, 0.4, math.pi / 2, -2.5]) {
        final turned = frame.copyWith(rotation: rotation);
        final grown = turned.resizedFromTopLeft(140, 55);
        expect(grown.width, 140);
        expect(grown.height, 55);
        expect(grown.rotation, rotation);
        expect(grown.corners.first, near(turned.corners.first));
      }
    });
  });

  group('InkElement', () {
    test('its frame follows its strokes', () {
      final element = InkElement(
        id: 'i',
        frame: const Frame(x: 0, y: 0, width: 1, height: 1),
        createdAt: 0,
        updatedAt: 0,
      ).withStrokes(<InkStroke>[line(10, 10, 50, 10)]);

      expect(element.frame.x, closeTo(8, 1e-9));
      expect(element.frame.width, closeTo(44, 1e-9));
    });

    test('bakes a rotation into its samples', () {
      final element = InkElement(
        id: 'i',
        frame: const Frame(x: 0, y: 0, width: 1, height: 1),
        createdAt: 0,
        updatedAt: 0,
        strokes: <InkStroke>[line(0, 0, 10, 0)],
      );

      final turned = element.transformed(Affine2D.rotation(math.pi / 2));

      final stroke = turned.strokes.single;
      expect(stroke.xAt(1), closeTo(0, 1e-5));
      expect(stroke.yAt(1), closeTo(10, 1e-5));
    });

    test('is hit only near its strokes', () {
      final element = InkElement(
        id: 'i',
        frame: const Frame(x: 0, y: 0, width: 1, height: 1),
        createdAt: 0,
        updatedAt: 0,
        strokes: <InkStroke>[line(0, 0, 100, 0), line(0, 100, 100, 100)],
      );

      expect(element.hitsStroke(50, 1, 3), isTrue);
      expect(element.hitsStroke(50, 50, 3), isFalse, reason: 'empty middle');
    });
  });

  group('TextElement width', () {
    const box = TextElement(
      id: 't',
      frame: Frame(x: 0, y: 0, width: 200, height: 40),
      createdAt: 0,
      updatedAt: 0,
      autoWidth: true,
    );

    test('moving keeps it growing with its text', () {
      expect(box.withFrame(box.frame.translate(5, 5)).autoWidth, isTrue);
    });

    test('resizing by hand fixes its width', () {
      expect(box.withFrame(box.frame.copyWith(width: 300)).autoWidth, isFalse);
    });

    test('round-trips through JSON', () {
      expect(TextElement.fromJson(box.toJson()).autoWidth, isTrue);
    });
  });

  group('TextMarks', () {
    test('size and colours round-trip and can be cleared', () {
      const marks = TextMarks(size: 18, color: 0xFFFF0000, highlight: 1);
      final decoded = TextMarks.fromJson(marks.toJson());
      expect(decoded, marks);
      expect(decoded.withHighlight(null).highlight, isNull);
      expect(decoded.withSize(null).isEmpty, isFalse);
      expect(decoded.withSize(null).size, isNull);
    });

    test('a formula keeps only colour and size', () {
      final blocks = RichTextEditing.applyMarks(
        const <TextBlock>[
          TextBlock(runs: <TextRun>[TextRun.math('x', MathMode.linear)]),
        ],
        const RichSelection(RichPosition(0, 0), RichPosition(0, 1)),
        (marks) => marks
            .copyWith(bold: true, color: 0xFF0000FF, size: 20)
            .withHighlight(0x66FFD60A),
      );

      final formula = blocks.single.runs.single;
      expect(formula.marks, const TextMarks(color: 0xFF0000FF, size: 20));
      expect(TextRun.fromJson(formula.toJson()), formula);
    });
  });
}
