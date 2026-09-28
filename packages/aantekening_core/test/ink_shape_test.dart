import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

/// A stroke through [corners], sampled every [step] units, each sample
/// moved up to [wobble] from where it should be, as a hand draws.
List<Vec2> _drawn(
  List<Vec2> corners, {
  double step = 3,
  double wobble = 1.5,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final points = <Vec2>[];
  for (var i = 0; i + 1 < corners.length; i++) {
    final from = corners[i];
    final to = corners[i + 1];
    final count = math.max(1, (from.distanceTo(to) / step).round());
    for (var j = 0; j < count; j++) {
      final at = from + (to - from) * (j / count);
      points.add(
        at +
            Vec2(
              (random.nextDouble() * 2 - 1) * wobble,
              (random.nextDouble() * 2 - 1) * wobble,
            ),
      );
    }
  }
  return points..add(corners.last);
}

/// A stroke round an ellipse about [centre], from [start] radians round
/// through [turn] radians.
List<Vec2> _round(
  Vec2 centre,
  double rx,
  double ry, {
  double angle = 0,
  double start = 0,
  double turn = 2 * math.pi,
  double wobble = 1.5,
}) {
  final count = (turn.abs() * math.max(rx, ry) / 3).round();
  return _drawn(
    <Vec2>[
      for (var i = 0; i <= count; i++)
        centre +
            Vec2(
              rx * math.cos(start + turn * i / count),
              ry * math.sin(start + turn * i / count),
            ).rotated(angle),
    ],
    step: 1000,
    wobble: wobble,
  );
}

void main() {
  group('ShapeRecognizer', () {
    test('reads a wobbly straight stroke as a line, level if nearly', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[Vec2(10, 100), Vec2(210, 104)]),
      );
      expect(shape, isA<PathShape>());
      shape as PathShape;
      expect(shape.kind, ShapeKind.line);
      expect(shape.points.first.distanceTo(const Vec2(10, 100)), lessThan(3));
      expect(shape.points.last.y, closeTo(shape.points.first.y, 1e-9));
    });

    test('leaves a slanted line slanted', () {
      final shape =
          ShapeRecognizer.recognize(
                _drawn(const <Vec2>[Vec2(0, 0), Vec2(200, 70)]),
              )!
              as PathShape;
      expect(shape.kind, ShapeKind.line);
      expect(shape.points.last.distanceTo(const Vec2(200, 70)), lessThan(3));
    });

    test('reads a shaft with a head drawn on as an arrow', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(0, 0),
          Vec2(200, 0),
          Vec2(180, -15),
          Vec2(200, 0),
          Vec2(180, 15),
        ]),
      );
      expect(shape?.kind, ShapeKind.arrow);
      final points = (shape! as PathShape).points;
      expect(points.last.distanceTo(const Vec2(200, 0)), lessThan(4));
    });

    test('reads lines joined at corners as a polyline', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[Vec2(0, 0), Vec2(0, 150), Vec2(200, 150)]),
      );
      expect(shape?.kind, ShapeKind.polyline);
      final points = (shape! as PathShape).points;
      expect(points, hasLength(3));
      // Its sides were nearly upright and level, and are made so.
      expect(points[0].x, points[1].x);
      expect(points[1].y, points[2].y);
    });

    test('reads a closed stroke of four right angles as a rectangle', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(50, 50),
          Vec2(250, 52),
          Vec2(251, 150),
          Vec2(49, 149),
          Vec2(52, 55),
        ]),
      );
      expect(shape?.kind, ShapeKind.rectangle);
      shape as BoxShape;
      expect(shape.angle, 0);
      expect(shape.size.x, closeTo(200, 6));
      expect(shape.size.y, closeTo(98, 6));
    });

    test('reads a rectangle started mid-side and drawn past its start', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(150, 50),
          Vec2(250, 50),
          Vec2(250, 150),
          Vec2(50, 150),
          Vec2(50, 50),
          Vec2(170, 50),
        ]),
      );
      expect(shape?.kind, ShapeKind.rectangle);
    });

    test('reads a rectangle with nearly equal sides as a square', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(0, 0),
          Vec2(100, 0),
          Vec2(100, 106),
          Vec2(0, 104),
          Vec2(0, 0),
        ]),
      );
      expect(shape?.kind, ShapeKind.square);
      shape as BoxShape;
      expect(shape.size.x, shape.size.y);
    });

    test('keeps a rectangle drawn turned, turned', () {
      final turn = 30 * math.pi / 180;
      Vec2 at(double x, double y) => Vec2(x, y).rotated(turn);
      final shape = ShapeRecognizer.recognize(
        _drawn(<Vec2>[
          at(0, 0),
          at(200, 0),
          at(200, 100),
          at(0, 100),
          at(0, 0),
        ]),
      );
      expect(shape?.kind, ShapeKind.rectangle);
      expect((shape! as BoxShape).angle, closeTo(turn, 0.05));
    });

    test('reads three straight sides as a triangle', () {
      final shape = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(100, 0),
          Vec2(200, 170),
          Vec2(0, 172),
          Vec2(100, 0),
        ]),
      );
      expect(shape?.kind, ShapeKind.polygon);
      final points = (shape! as PathShape).points;
      expect(points, hasLength(3));
      // The base was nearly level, and is made so.
      final base = points.where((point) => point.y > 100).toList();
      expect(base[0].y, base[1].y);
    });

    test('reads a round stroke as a circle, and an oval as an ellipse', () {
      final circle = ShapeRecognizer.recognize(
        _round(const Vec2(200, 200), 80, 76),
      );
      expect(circle?.kind, ShapeKind.circle);
      circle as BoxShape;
      expect(circle.size.x, closeTo(156, 8));
      expect(circle.origin.distanceTo(const Vec2(122, 122)), lessThan(8));

      final ellipse = ShapeRecognizer.recognize(
        _round(const Vec2(200, 200), 120, 60, start: 1),
      );
      expect(ellipse?.kind, ShapeKind.ellipse);
      ellipse as BoxShape;
      expect(ellipse.angle, 0);
      expect(ellipse.size.x, closeTo(240, 12));
      expect(ellipse.size.y, closeTo(120, 12));
    });

    test('keeps an upright oval upright, and a turned one turned', () {
      final upright =
          ShapeRecognizer.recognize(_round(const Vec2(0, 0), 50, 110))!
              as BoxShape;
      expect(upright.kind, ShapeKind.ellipse);
      expect(upright.angle, 0);
      expect(upright.size.x, closeTo(100, 10));
      expect(upright.size.y, closeTo(220, 10));

      final turned =
          ShapeRecognizer.recognize(
                _round(const Vec2(0, 0), 120, 50, angle: 0.6),
              )!
              as BoxShape;
      expect(turned.kind, ShapeKind.ellipse);
      expect(turned.angle, closeTo(0.6, 0.08));
    });

    test('reads outlines drawn with sides of their own', () {
      Vec2 round(int i, int sides, double start) => Vec2(
        80 * math.cos(start + i * 2 * math.pi / sides),
        80 * math.sin(start + i * 2 * math.pi / sides),
      );
      final hexagon = ShapeRecognizer.recognize(
        _drawn(<Vec2>[for (var i = 0; i <= 6; i++) round(i, 6, 0)]),
      );
      expect(hexagon?.kind, ShapeKind.polygon);
      expect((hexagon! as PathShape).points, hasLength(6));

      // Its sides all alike, but its corners are not right angles.
      final diamond = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(0, -80),
          Vec2(60, 0),
          Vec2(0, 80),
          Vec2(-60, 0),
          Vec2(0, -80),
        ]),
      );
      expect(diamond?.kind, ShapeKind.polygon);
    });

    test('reads an arrow with a closed head, and a jittery line', () {
      final arrow = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[
          Vec2(0, 0),
          Vec2(250, 40),
          Vec2(228, 24),
          Vec2(222, 52),
          Vec2(250, 40),
        ]),
      );
      expect(arrow?.kind, ShapeKind.arrow);
      final line = ShapeRecognizer.recognize(
        _drawn(const <Vec2>[Vec2(0, 0), Vec2(300, 0)], wobble: 3),
      );
      expect(line?.kind, ShapeKind.line);
    });

    test('leaves writing as it was written', () {
      // An S, a spiral, a zigzag of many strokes and a wavy line.
      final s = <Vec2>[
        ..._round(const Vec2(50, 30), 30, 30, start: 0, turn: -1.5 * math.pi),
        ..._round(
          const Vec2(50, 90),
          30,
          30,
          start: -math.pi / 2,
          turn: 1.5 * math.pi,
        ),
      ];
      final spiral = <Vec2>[
        for (var i = 0; i < 300; i++)
          Vec2(
            (20 + i * 0.3) * math.cos(i * 0.06),
            (20 + i * 0.3) * math.sin(i * 0.06),
          ),
      ];
      final zigzag = _drawn(<Vec2>[
        for (var i = 0; i < 9; i++) Vec2(i * 20.0, i.isEven ? 0 : 30),
      ]);
      final wave = <Vec2>[
        for (var x = 0.0; x <= 300; x += 3) Vec2(x, 20 * math.sin(x / 30)),
      ];
      for (final stroke in <List<Vec2>>[s, spiral, zigzag, wave]) {
        final shape = ShapeRecognizer.recognize(stroke);
        expect(shape, isNull, reason: "${shape?.kind} ${shape?.handles}");
      }
    });

    test('leaves a dot, and makes a highlighter only straight', () {
      expect(
        ShapeRecognizer.recognize(const <Vec2>[Vec2(0, 0), Vec2(2, 1)]),
        isNull,
      );
      final square = _drawn(const <Vec2>[
        Vec2(0, 0),
        Vec2(100, 0),
        Vec2(100, 100),
        Vec2(0, 100),
        Vec2(0, 0),
      ]);
      expect(ShapeRecognizer.recognize(square, linesOnly: true), isNull);
      expect(
        ShapeRecognizer.recognize(
          _drawn(const <Vec2>[Vec2(0, 0), Vec2(300, 2)]),
          linesOnly: true,
        )?.kind,
        ShapeKind.line,
      );
    });
  });

  group('InkShape', () {
    test('a line keeps one end while the other is moved', () {
      const line = PathShape(ShapeKind.line, <Vec2>[Vec2(0, 0), Vec2(100, 0)]);
      final moved = line.withHandle(1, const Vec2(60, 80));
      expect(moved.points, <Vec2>[const Vec2(0, 0), const Vec2(60, 80)]);
      // Near level, it is put level; with Shift, on a step of 15°.
      expect(line.withHandle(1, const Vec2(100, 3)).points.last.y, 0);
      final stepped = line.withHandle(1, const Vec2(100, 40), constrain: true);
      expect(
        (stepped.points.last - stepped.points.first).angle,
        closeTo(15 * math.pi / 180, 1e-9),
      );
    });

    test('a box keeps the corner across from the one moved', () {
      final box = InkShape.begin(
        ShapeKind.rectangle,
        const Vec2(10, 10),
      ).withHandle(2, const Vec2(110, 60));
      expect(box.handles.first, const Vec2(10, 10));
      expect(box.handles[2], const Vec2(110, 60));
      final moved = box.withHandle(0, const Vec2(-10, 0));
      expect(moved.handles[2], const Vec2(110, 60));
      expect(moved.handles[0], const Vec2(-10, 0));
      // A square stays square, whichever way it is pulled.
      final square =
          InkShape.begin(
                ShapeKind.square,
                const Vec2(0, 0),
              ).withHandle(2, const Vec2(40, 90))
              as BoxShape;
      expect(square.size, const Vec2(90, 90));
    });

    test('a turned box is resized along its own sides', () {
      const box = BoxShape(
        ShapeKind.rectangle,
        origin: Vec2(0, 0),
        size: Vec2(100, 50),
        angle: math.pi / 2,
      );
      final corners = box.handles;
      expect(corners[1].x, closeTo(0, 1e-9));
      expect(corners[1].y, closeTo(100, 1e-9));
      final wider = box.withHandle(2, corners[2] + const Vec2(0, 20));
      expect(wider.size.x, closeTo(120, 1e-9));
      expect(wider.size.y, closeTo(50, 1e-9));
      expect(wider.handles[0].distanceTo(corners[0]), lessThan(1e-9));
    });

    test('a click puts a shape down at its usual size', () {
      final placed = InkShape.placed(ShapeKind.cylinder, const Vec2(0, 0));
      expect(placed.handles[2], const Vec2(144, 180));
      final line = InkShape.placed(ShapeKind.arrow, const Vec2(5, 5));
      expect(line.handles.last, const Vec2(149, 5));
    });

    test('draws each shape in strokes of the pen, its corners kept', () {
      for (final kind in ShapeKind.values) {
        final shape = InkShape.placed(kind, const Vec2(24, 24));
        final strokes = shape.strokes(
          tool: InkTool.pen,
          color: 0xFF000000,
          width: 2,
        );
        if (kind == ShapeKind.polyline || kind == ShapeKind.polygon) continue;
        expect(strokes, isNotEmpty, reason: kind.name);
        for (final stroke in strokes) {
          expect(stroke.width, 2);
          expect(stroke.pressureAt(0), 1);
        }
      }
      final square = InkShape.placed(
        ShapeKind.square,
        const Vec2(0, 0),
      ).strokes(tool: InkTool.pen, color: 0xFF000000, width: 2).single;
      // Five corners, the three inside sampled twice.
      expect(square.pointCount, 8);
    });

    test('draws the edges out of sight dashed', () {
      final cube = InkShape.placed(ShapeKind.cube, const Vec2(0, 0));
      final strokes = cube.lines(2);
      final dashes = strokes.where((line) => line.length == 2).length;
      expect(dashes, greaterThan(10));
    });

    test('ticks axes every square of the grid', () {
      final axes = InkShape.begin(
        ShapeKind.axes,
        const Vec2(0, 0),
      ).withHandle(2, const Vec2(240, 240));
      // Two axes, two heads, and nine ticks on each: the tenth would be
      // under the head.
      expect(axes.lines(2), hasLength(2 + 2 + 2 * 9));
    });
  });
}
