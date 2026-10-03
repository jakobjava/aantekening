part of 'tikz_picture.dart';

/// Adds the tip [kind] at [point], pointing [direction], to [heads]: the
/// filled shapes of the tips, or for an open tip its strokes as a thin
/// fill. Returns how much of the line it takes the place of.
double _tip(
  List<Path> heads,
  String kind,
  Offset point,
  Offset direction,
  double width,
) {
  if (direction.distance < 1e-9) return 0;
  final d = direction / direction.distance;
  final n = Offset(-d.dy, d.dx);
  final length = 3 + 3 * width;
  if (kind.startsWith('open ')) {
    // An open tip is its outline, the line ending where it begins.
    final closed = <Path>[];
    _tip(closed, kind.substring(5), point, direction, width);
    for (final shape in closed) {
      final ring = Path()..fillType = PathFillType.evenOdd;
      final bounds = shape.getBounds();
      ring
        ..addPath(shape, Offset.zero)
        ..addPath(
          shape.transform(_shrinkAbout(bounds.center, bounds, width)),
          Offset.zero,
        );
      heads.add(ring);
    }
    return _tipLength(kind.substring(5), width);
  }
  if (kind.startsWith('double ')) {
    _tip(heads, kind.substring(7), point, direction, width);
    _tip(
      heads,
      kind.substring(7),
      point - d * (length * 0.6),
      direction,
      width,
    );
    return 0;
  }
  switch (kind) {
    case 'bar':
      final half = 2 + 1.5 * width;
      heads.add(
        _strokeShape(<Offset>[point + n * half, point - n * half], width),
      );
      return 0;
    case 'stealth':
      final half = length * 0.45;
      heads.add(
        Path()..addPolygon(<Offset>[
          point,
          point - d * length + n * half,
          point - d * (length * 0.6),
          point - d * length - n * half,
        ], true),
      );
      return length * 0.6;
    case 'latex':
      final half = length * 0.38;
      heads.add(
        Path()..addPolygon(<Offset>[
          point,
          point - d * length + n * half,
          point - d * length - n * half,
        ], true),
      );
      return length * 0.8;
    case 'dot':
      final radius = _tipLength(kind, width) / 2;
      heads.add(
        Path()..addOval(
          Rect.fromCircle(center: point - d * radius, radius: radius),
        ),
      );
      return radius;
    case 'square':
      final half = _tipLength(kind, width) / 2;
      final centre = point - d * half;
      heads.add(
        Path()..addPolygon(<Offset>[
          centre + d * half + n * half,
          centre - d * half + n * half,
          centre - d * half - n * half,
          centre + d * half - n * half,
        ], true),
      );
      return half;
    case 'kite':
      final half = length * 0.35;
      heads.add(
        Path()..addPolygon(<Offset>[
          point,
          point - d * (length * 0.4) + n * half,
          point - d * length,
          point - d * (length * 0.4) - n * half,
        ], true),
      );
      return length * 0.8;
    case 'bracket':
      final half = 2 + 1.5 * width;
      final serif = 1 + width;
      heads.add(
        _strokeShape(<Offset>[
          point + n * half - d * serif,
          point + n * half,
          point - n * half,
          point - n * half - d * serif,
        ], width),
      );
      return 0;
    default:
      final reach = 1.5 + 2.5 * width;
      heads.add(
        _strokeShape(<Offset>[
          point - d * reach + n * (reach * 0.8),
          point,
          point - d * reach - n * (reach * 0.8),
        ], width),
      );
      return 0;
  }
}

/// How long the tip [kind] is along the line, for a line [width] wide.
double _tipLength(String kind, double width) => switch (kind) {
  'dot' || 'square' => 2.4 + 2 * width,
  _ => 3 + 3 * width,
};

/// What draws a shape with [bounds] smaller by [width] all round, about
/// [centre]: the inside of an open tip's outline.
Float64List _shrinkAbout(Offset centre, Rect bounds, double width) {
  final sx = bounds.width <= 2 * width ? 0.0 : 1 - 2 * width / bounds.width;
  final sy = bounds.height <= 2 * width ? 0.0 : 1 - 2 * width / bounds.height;
  return Float64List.fromList(<double>[
    sx, 0, 0, 0, //
    0, sy, 0, 0, //
    0, 0, 1, 0, //
    centre.dx * (1 - sx), centre.dy * (1 - sy), 0, 1,
  ]);
}

/// The outline of a line through [points], [width] wide, to fill.
Path _strokeShape(List<Offset> points, double width) {
  final shape = Path();
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i];
    final b = points[i + 1];
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * (width / 2);
    shape
      ..addPolygon(<Offset>[a + n, b + n, b - n, a - n], true)
      ..addOval(Rect.fromCircle(center: b, radius: width / 2));
  }
  return shape;
}

/// [path] shortened by [atStart] at its start and [atEnd] at its end.
Path _trimmed(Path path, double atStart, double atEnd) {
  if (atStart == 0 && atEnd == 0) return path;
  final metrics = path.computeMetrics().toList();
  final trimmed = Path();
  for (var i = 0; i < metrics.length; i++) {
    final metric = metrics[i];
    final from = i == 0 ? atStart : 0.0;
    final to = metric.length - (i == metrics.length - 1 ? atEnd : 0.0);
    if (to > from) trimmed.addPath(metric.extractPath(from, to), Offset.zero);
  }
  return trimmed;
}

/// [path] broken into dashes, [pattern] giving the lengths on and off.
Path _dashed(Path path, List<double> pattern) {
  final dashed = Path();
  final total = pattern.fold<double>(0, (sum, length) => sum + length);
  if (total <= 0) return path;
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var i = 0;
    while (distance < metric.length) {
      final length = pattern[i % pattern.length];
      if (i.isEven) {
        dashed.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
      }
      distance += length;
      i++;
    }
  }
  return dashed;
}
