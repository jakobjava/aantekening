part of 'tikz_picture.dart';

/// The node shapes of the `shapes.geometric` library, each a polygon round
/// its text: a diamond, a regular polygon, a star, an isosceles triangle, a
/// trapezium and a semicircle.
abstract final class _NodeShapes {
  /// The corners of a node of [shape] round text that is [halfWidth] and
  /// [halfHeight] from its centre, its inner sep included, with the anchors
  /// its corners are; null for a shape that is not one of these.
  static ({List<Offset> outline, Map<String, int> corners})? outline(
    String shape,
    _Style style,
    double halfWidth,
    double halfHeight,
  ) {
    final w = halfWidth;
    final h = halfHeight;
    final least = math.max(style.minWidth, style.minHeight) / 2;
    final made = switch (shape) {
      'diamond' => (
        outline: <Offset>[
          Offset(math.max(2 * w, style.minWidth / 2), 0),
          Offset(0, math.max(2 * h, style.minHeight / 2)),
          Offset(-math.max(2 * w, style.minWidth / 2), 0),
          Offset(0, -math.max(2 * h, style.minHeight / 2)),
        ],
        corners: const <String, int>{},
      ),
      'regular polygon' => _regular(style.polygonSides, w, h, least),
      'star' => _star(style.starPoints, style.starRatio, w, h, least),
      'isosceles triangle' => _triangle(style.apexAngle, w, h),
      'trapezium' => (
        outline: <Offset>[
          Offset(-w - 2 * h / math.tan(_rad(style.trapeziumLeft)), -h),
          Offset(w + 2 * h / math.tan(_rad(style.trapeziumRight)), -h),
          Offset(w, h),
          Offset(-w, h),
        ],
        corners: const <String, int>{
          'bottom left corner': 0,
          'bottom right corner': 1,
          'top right corner': 2,
          'top left corner': 3,
        },
      ),
      'semicircle' => _semicircle(w, h, least),
      _ => null,
    };
    if (made == null) return null;
    final turn = style.borderRotate;
    if (turn == 0) return made;
    final rotation = _Affine.rotation(turn);
    return (
      outline: <Offset>[for (final p in made.outline) rotation.apply(p)],
      corners: made.corners,
    );
  }

  static double _rad(double degrees) => degrees * math.pi / 180;

  /// A polygon of [sides] equal sides round the text, a corner at the top
  /// when they are odd, a side when they are even.
  static ({List<Offset> outline, Map<String, int> corners}) _regular(
    int sides,
    double w,
    double h,
    double least,
  ) {
    final n = sides.clamp(3, 64);
    final radius = math.max(
      math.sqrt(w * w + h * h) / math.cos(math.pi / n),
      least,
    );
    final first = n.isOdd ? 90.0 : 90 + 180 / n;
    return (
      outline: <Offset>[
        for (var i = 0; i < n; i++)
          Offset.fromDirection(_rad(first + 360 * i / n), radius),
      ],
      corners: <String, int>{for (var i = 0; i < n; i++) 'corner ${i + 1}': i},
    );
  }

  /// A star of [points] points round the text, its inner points [ratio]
  /// times nearer the centre than its outer ones.
  static ({List<Offset> outline, Map<String, int> corners}) _star(
    int points,
    double ratio,
    double w,
    double h,
    double least,
  ) {
    final n = points.clamp(2, 64);
    final inner = math.sqrt(w * w + h * h);
    final outer = math.max(inner * math.max(ratio, 1.01), least);
    return (
      outline: <Offset>[
        for (var i = 0; i < 2 * n; i++)
          Offset.fromDirection(
            _rad(90 + 180 * i / n),
            i.isEven ? outer : outer / math.max(ratio, 1.01),
          ),
      ],
      corners: <String, int>{
        for (var i = 0; i < n; i++) ...<String, int>{
          'outer point ${i + 1}': 2 * i,
          'inner point ${i + 1}': 2 * i + 1,
        },
      },
    );
  }

  /// A triangle with its apex to the east, its sides [apex] degrees apart,
  /// round the text.
  static ({List<Offset> outline, Map<String, int> corners}) _triangle(
    double apex,
    double w,
    double h,
  ) {
    final slope = math.tan(_rad(apex.clamp(1, 179) / 2));
    final tip = w + h / slope;
    final base = (tip + w) * slope;
    return (
      outline: <Offset>[Offset(tip, 0), Offset(-w, base), Offset(-w, -base)],
      corners: const <String, int>{
        'apex': 0,
        'left corner': 1,
        'right corner': 2,
      },
    );
  }

  /// Half a circle standing on its diameter, round the text.
  static ({List<Offset> outline, Map<String, int> corners}) _semicircle(
    double w,
    double h,
    double least,
  ) {
    final radius = math.max(math.sqrt(w * w + 4 * h * h), least);
    const steps = 24;
    return (
      outline: <Offset>[
        for (var i = 0; i <= steps; i++)
          Offset(0, -h) + Offset.fromDirection(_rad(180 * i / steps), radius),
      ],
      corners: const <String, int>{'arc start': 0, 'arc end': steps},
    );
  }
}
