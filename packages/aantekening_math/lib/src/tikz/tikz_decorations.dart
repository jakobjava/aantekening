part of 'tikz_picture.dart';

/// The `decorations` libraries — a path drawn as a zigzag, a snake, a coil,
/// a brace, bumps, saw teeth, random steps, ticks or a border, or with
/// arrows and nodes marked along it — and the `patterns` library's fills.
abstract final class _Decorations {
  /// The decoration [options] name, the last given: an option without a
  /// value, or `name=…`.
  static String nameOf(List<TikzOption> options) {
    for (final (:key, :value) in options.reversed) {
      if (key == 'name' && value != null) return value;
      if (value == null && key != 'mirror') return key;
    }
    return 'zigzag';
  }

  /// [drawn] as the decoration [options] say draws it, in the units it is
  /// in; null for `markings`, which draws the marks alone.
  static Path? morph(Path drawn, List<TikzOption> options) {
    double length(String key, double fallback) {
      for (final (key: k, :value) in options.reversed) {
        if (k == key && value != null) return TikzExpression.length(value);
      }
      return fallback;
    }

    final mirror = options.any((option) => option.key == 'mirror');
    final amplitude = length('amplitude', 2.5) * (mirror ? -1 : 1);
    final segment = math.max(length('segment length', 10), 0.5);
    final name = nameOf(options);
    if (name == 'markings') return null;
    if (name == 'brace') {
      return _brace(drawn, amplitude, length('raise', 0), mirror: mirror);
    }
    if (name == 'ticks' || name == 'border') {
      final angle = name == 'border'
          ? (_valueOf(options, 'angle') ?? 45.0)
          : 90.0;
      return _ticks(drawn, amplitude, segment, angle);
    }
    final wave = switch (name) {
      'zigzag' => _zigzag,
      'saw' => _saw,
      'snake' => _snake,
      'bumps' => _bumps,
      'coil' => _coil,
      'random steps' => _randomSteps,
      _ => throw FormatException('No decoration here is called "$name"'),
    };
    final morphed = Path();
    for (final metric in drawn.computeMetrics()) {
      final points = wave(metric, amplitude, segment);
      if (points.isEmpty) continue;
      morphed.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        morphed.lineTo(point.dx, point.dy);
      }
      if (metric.isClosed) morphed.close();
    }
    return morphed;
  }

  static double? _valueOf(List<TikzOption> options, String key) {
    for (final (key: k, :value) in options.reversed) {
      if (k == key && value != null) {
        return TikzExpression.evaluate(value).value;
      }
    }
    return null;
  }

  /// The point [s] along [metric], moved [across] to its left, as the
  /// path runs.
  static Offset _beside(PathMetric metric, double s, double across) {
    final tangent = metric.getTangentForOffset(s.clamp(0, metric.length))!;
    final d = tangent.vector;
    return tangent.position + Offset(d.dy, -d.dx) * across;
  }

  /// Points along [metric], [step] apart, each moved to its left by what
  /// [offset] says for how far along it is.
  static List<Offset> _sampled(
    PathMetric metric,
    double step,
    double Function(double s) offset,
  ) {
    final count = math.max(1, (metric.length / step).ceil());
    return <Offset>[
      for (var i = 0; i <= count; i++)
        _beside(
          metric,
          metric.length * i / count,
          offset(metric.length * i / count),
        ),
    ];
  }

  static List<Offset> _zigzag(PathMetric metric, double a, double segment) {
    final points = <Offset>[_beside(metric, 0, 0)];
    var s = segment / 4;
    var up = true;
    while (s < metric.length) {
      points.add(_beside(metric, s, up ? a : -a));
      up = !up;
      s += segment / 2;
    }
    return points..add(_beside(metric, metric.length, 0));
  }

  static List<Offset> _saw(PathMetric metric, double a, double segment) {
    final points = <Offset>[];
    for (var s = 0.0; s < metric.length; s += segment) {
      points
        ..add(_beside(metric, s, 0))
        ..add(_beside(metric, math.min(s + segment, metric.length), a));
    }
    return points..add(_beside(metric, metric.length, 0));
  }

  static List<Offset> _snake(PathMetric metric, double a, double segment) =>
      _sampled(
        metric,
        segment / 16,
        (s) => a * math.sin(2 * math.pi * s / segment),
      );

  static List<Offset> _bumps(PathMetric metric, double a, double segment) =>
      _sampled(
        metric,
        segment / 16,
        (s) => a * math.sin(2 * math.pi * s / segment).abs(),
      );

  /// A spring: loops wound along the path, seen from the side.
  static List<Offset> _coil(PathMetric metric, double a, double segment) {
    final count = math.max(1, (metric.length / (segment / 16)).ceil());
    final points = <Offset>[];
    for (var i = 0; i <= count; i++) {
      final s = metric.length * i / count;
      final turn = 2 * math.pi * s / segment;
      final tangent = metric.getTangentForOffset(s)!;
      final d = tangent.vector;
      // Back along the path as the loop turns over, so the loops cross.
      final along = a * 0.7 * (1 - math.cos(turn));
      final across = a * math.sin(turn);
      points.add(tangent.position + d * along + Offset(d.dy, -d.dx) * across);
    }
    return points;
  }

  static List<Offset> _randomSteps(
    PathMetric metric,
    double a,
    double segment,
  ) {
    // The same steps every time the picture is drawn.
    final random = math.Random(metric.length.round());
    final points = <Offset>[_beside(metric, 0, 0)];
    for (var s = segment; s < metric.length; s += segment) {
      final shifted = _beside(metric, s, 0);
      points.add(
        shifted +
            Offset(
              (random.nextDouble() * 2 - 1) * a,
              (random.nextDouble() * 2 - 1) * a,
            ),
      );
    }
    return points..add(_beside(metric, metric.length, 0));
  }

  /// Short lines across the path, [segment] apart and [a] long, at [angle]
  /// degrees to it: ticks, or the hatching of a wall.
  static Path _ticks(Path drawn, double a, double segment, double angle) {
    final ticks = Path();
    final r = angle * math.pi / 180;
    for (final metric in drawn.computeMetrics()) {
      for (var s = 0.0; s <= metric.length + 1e-6; s += segment) {
        final tangent = metric.getTangentForOffset(s)!;
        final d = tangent.vector;
        final left = Offset(d.dy, -d.dx);
        final tip =
            tangent.position + (d * math.cos(r) + left * math.sin(r)) * a;
        ticks
          ..moveTo(tangent.position.dx, tangent.position.dy)
          ..lineTo(tip.dx, tip.dy);
      }
    }
    return ticks;
  }

  /// A curly brace from where [drawn] starts to where it ends, [a] deep, to
  /// the left as it runs (to the right if [mirror]ed), [raise] off it.
  static Path _brace(
    Path drawn,
    double a,
    double raise, {
    required bool mirror,
  }) {
    final metrics = drawn.computeMetrics().toList();
    if (metrics.isEmpty) return drawn;
    final start = metrics.first.getTangentForOffset(0)!.position;
    final end = metrics.last.getTangentForOffset(metrics.last.length)!.position;
    final along = end - start;
    if (along.distance < 1e-9) return drawn;
    final d = along / along.distance;
    final n = Offset(d.dy, -d.dx) * (mirror ? -1.0 : 1.0);
    final depth = a.abs();
    final lift = n * raise;
    final a0 = start + lift;
    final b0 = end + lift;
    final m = (a0 + b0) / 2;
    final half = math.min(depth / 2, along.distance / 4);
    final brace = Path()..moveTo(a0.dx, a0.dy);
    void curve(Offset control, Offset to) =>
        brace.quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    void line(Offset to) => brace.lineTo(to.dx, to.dy);
    curve(a0 + n * (depth / 2), a0 + n * (depth / 2) + d * half);
    line(m - d * half + n * (depth / 2));
    curve(m + n * (depth / 2), m + n * depth);
    curve(m + n * (depth / 2), m + d * half + n * (depth / 2));
    line(b0 - d * half + n * (depth / 2));
    curve(b0 + n * (depth / 2), b0);
    return brace;
  }

  /// The places along [drawn] a `mark` option names: `at position 0.5`,
  /// `at position 1cm`, `at position -2mm` from the end, or `between
  /// positions 0 and 1 step 0.25`; and what is put there.
  static List<({Tangent at, String what})> marks(
    Path drawn,
    List<TikzOption> options,
  ) {
    final metrics = drawn.computeMetrics().toList();
    if (metrics.isEmpty) return const <({Tangent at, String what})>[];
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    Tangent? tangentAt(double s) {
      var left = s.clamp(0.0, total);
      for (final metric in metrics) {
        if (left <= metric.length) return metric.getTangentForOffset(left);
        left -= metric.length;
      }
      return metrics.last.getTangentForOffset(metrics.last.length);
    }

    double distance(String spec) {
      final value = TikzExpression.evaluate(spec);
      final along = value.length ? value.value : value.value * total;
      return along < 0 ? total + along : along;
    }

    final found = <({Tangent at, String what})>[];
    for (final (:key, :value) in options) {
      if (key != 'mark' || value == null) continue;
      final at = RegExp(
        r'^at\s+position\s+(.+?)\s+with\s*(.*)$',
        dotAll: true,
      ).firstMatch(value.trim());
      final between = RegExp(
        r'^between\s+positions\s+(.+?)\s+and\s+(.+?)\s+step\s+(.+?)\s+with\s*(.*)$',
        dotAll: true,
      ).firstMatch(value.trim());
      if (at != null) {
        final tangent = tangentAt(distance(at.group(1)!));
        if (tangent != null) found.add((at: tangent, what: at.group(2)!));
      } else if (between != null) {
        final from = distance(between.group(1)!);
        final to = distance(between.group(2)!);
        final stepValue = TikzExpression.evaluate(between.group(3)!);
        final step = stepValue.length
            ? stepValue.value
            : stepValue.value * total;
        if (step <= 0) throw const FormatException('A mark step must be > 0');
        for (var s = from; s <= to + 1e-6 && found.length < 400; s += step) {
          final tangent = tangentAt(s);
          if (tangent != null) {
            found.add((at: tangent, what: between.group(4)!));
          }
        }
      } else {
        throw FormatException('Cannot read the mark "$value"');
      }
    }
    return found;
  }

  /// The pattern [name] filling [area]: lines, a grid, crosshatching or
  /// dots.
  static Path? pattern(Path area, String name) {
    final bounds = area.getBounds();
    if (bounds.isEmpty) return null;
    const gap = 3.0;
    const half = 0.2;
    final lines = Path();
    void line(Offset a, Offset b) {
      final d = b - a;
      final n = Offset(-d.dy, d.dx) / d.distance * half;
      lines.addPolygon(<Offset>[a + n, b + n, b - n, a - n], true);
    }

    final span = bounds.width + bounds.height;
    void diagonals({required bool rising}) {
      for (var t = -span; t <= span; t += gap * math.sqrt2) {
        final a = rising
            ? bounds.bottomLeft + Offset(t, 0)
            : bounds.topLeft + Offset(t, 0);
        final b = rising ? a + Offset(span, -span) : a + Offset(span, span);
        line(a, b);
      }
    }

    void horizontal() {
      for (var y = bounds.top; y <= bounds.bottom; y += gap) {
        line(Offset(bounds.left, y), Offset(bounds.right, y));
      }
    }

    void vertical() {
      for (var x = bounds.left; x <= bounds.right; x += gap) {
        line(Offset(x, bounds.top), Offset(x, bounds.bottom));
      }
    }

    void dots({required bool shifted}) {
      for (var y = bounds.top; y <= bounds.bottom; y += gap) {
        for (var x = bounds.left; x <= bounds.right; x += gap) {
          lines.addOval(
            Rect.fromCircle(
              center:
                  Offset(x, y) +
                  (shifted ? const Offset(1.5, 1.5) : Offset.zero),
              radius: 0.5,
            ),
          );
        }
      }
    }

    switch (name) {
      case 'north east lines':
        diagonals(rising: true);
      case 'north west lines':
        diagonals(rising: false);
      case 'horizontal lines':
        horizontal();
      case 'vertical lines':
        vertical();
      case 'grid':
        horizontal();
        vertical();
      case 'crosshatch':
        diagonals(rising: true);
        diagonals(rising: false);
      case 'dots':
        dots(shifted: false);
      case 'crosshatch dots':
        dots(shifted: false);
        dots(shifted: true);
      default:
        throw FormatException('No pattern here is called "$name"');
    }
    return Path.combine(PathOperation.intersect, area, lines);
  }
}
