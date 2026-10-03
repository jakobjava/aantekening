part of 'tikz_picture.dart';

/// A path being worked out: where it is and what it has drawn.
class _Path {
  _Path(this.style);

  final _Style style;

  /// What is drawn, in points with y running downwards.
  final Path drawn = Path();

  /// The current point, with y upwards, and the node it is, if it is one.
  Offset? current;
  _Node? currentNode;

  /// What `+` coordinates are taken from: the last point not given with a
  /// single `+`.
  Offset? reference;

  /// Where the pen is, if it has drawn since it last moved.
  Offset? pen;

  /// Where the path starts and where it ends, and the directions it leaves
  /// and arrives in, for the tips.
  Offset? firstPoint;
  Offset? firstToward;
  Offset? lastPoint;
  Offset? lastFrom;
  bool closedAtEnd = false;
  bool get hasDrawn => firstPoint != null;

  /// How the last connection was drawn — `--`, `-|`, `|-`, `..` — if one
  /// is waiting for its coordinate.
  String? connector;

  /// Nodes written between a connection and its coordinate, placed on it.
  final List<_NodeSpec> pending = <_NodeSpec>[];

  /// The last stretch drawn, from 0 at its start to 1 at its end, for nodes
  /// placed along it.
  Offset Function(double t)? lastStretch;

  /// What is drawn above the path: its nodes.
  final List<TikzMark> above = <TikzMark>[];

  /// The straight line last drawn to, with rounded corners: it is drawn
  /// once what follows says how its end is rounded.
  ({Offset from, Offset to})? corner;
}

/// Drawing the parts of a path: lines, curves and shapes.
extension _Shapes on _Painter {
  void _moveTo(_Path path, ({Offset point, _Node? node}) target) {
    _flushCorner(path);
    path
      ..current = target.point
      ..currentNode = target.node
      ..pen = null;
    path.reference ??= target.point;
  }

  /// Starts drawing at the current point, heading for [toward]: on the
  /// border of the node it is, if it is one, and moving there if the pen is
  /// elsewhere.
  Offset _begin(_Path path, Offset toward) {
    _flushCorner(path);
    final current = path.current;
    if (current == null) {
      throw const FormatException('A path needs a point to start from');
    }
    final node = path.currentNode;
    final start = node == null ? current : node.towards(toward);
    if (path.pen != start) {
      path.drawn.moveTo(start.dx, -start.dy);
      if (!path.hasDrawn) {
        path
          ..firstPoint = start
          ..firstToward = toward;
      }
    }
    return start;
  }

  /// Notes that a stretch has been drawn to [end], arriving from [from],
  /// and places the nodes written along it.
  void _drawn(
    _Path path, {
    required Offset end,
    required Offset from,
    required Offset Function(double t) stretch,
    required ({Offset point, _Node? node}) target,
  }) {
    path
      ..pen = end
      ..lastPoint = end
      ..lastFrom = from
      ..closedAtEnd = false
      ..lastStretch = stretch
      ..current = target.point
      ..currentNode = target.node
      ..connector = null;
    for (final spec in path.pending) {
      _node(spec, path, stretch: stretch, along: 0.5);
    }
    path.pending.clear();
  }

  void _connect(_Path path, ({Offset point, _Node? node}) target) {
    final connector = path.connector!;
    if (connector == '--') {
      _line(path, target);
      return;
    }
    final from = path.current!;
    final corner = connector == '-|'
        ? Offset(target.point.dx, from.dy)
        : Offset(from.dx, target.point.dy);
    final start = _begin(path, corner);
    final end = target.node?.towards(corner) ?? target.point;
    path.drawn
      ..lineTo(corner.dx, -corner.dy)
      ..lineTo(end.dx, -end.dy);
    _drawn(
      path,
      end: end,
      from: corner,
      stretch: (t) => t < 0.5
          ? Offset.lerp(start, corner, t * 2)!
          : Offset.lerp(corner, end, t * 2 - 1)!,
      target: target,
    );
  }

  void _line(_Path path, ({Offset point, _Node? node}) target) {
    final radius = path.style.rounded;
    if (radius != null) _turn(path, target.point, radius);
    final start = _begin(path, target.point);
    final end = target.node?.towards(start) ?? target.point;
    if (radius == null) {
      path.drawn.lineTo(end.dx, -end.dy);
    } else {
      path.corner = (from: start, to: end);
    }
    _drawn(
      path,
      end: end,
      from: start,
      stretch: (t) => Offset.lerp(start, end, t)!,
      target: target,
    );
  }

  void _cubic(
    _Path path,
    Offset c1,
    Offset c2,
    ({Offset point, _Node? node}) target,
  ) {
    final start = _begin(path, c1);
    final end = target.node?.towards(c2) ?? target.point;
    path.drawn.cubicTo(c1.dx, -c1.dy, c2.dx, -c2.dy, end.dx, -end.dy);
    _drawn(
      path,
      end: end,
      from: c2,
      stretch: (t) => _bezier(start, c1, c2, end, t),
      target: target,
    );
  }

  static Offset _bezier(Offset a, Offset b, Offset c, Offset d, double t) {
    final u = 1 - t;
    return a * (u * u * u) +
        b * (3 * u * u * t) +
        c * (3 * u * t * t) +
        d * (t * t * t);
  }

  /// `.. controls (c1) and (c2) .. (target)`.
  void _curve(TikzScanner scanner, _Path path) {
    if (!scanner.takeWord('controls')) {
      throw const FormatException('".." is followed by "controls"');
    }
    final first = _controlText(scanner);
    final second = scanner.takeWord('and') ? _controlText(scanner) : first;
    if (!scanner.take('..')) {
      throw const FormatException('Missing ".." after the controls');
    }
    final start = path.current;
    if (start == null) {
      throw const FormatException('A curve needs a point to start from');
    }
    final target = _coordinate(scanner, path);
    Offset control(({String text, bool relative}) spec, Offset from) {
      final point = _point(spec.text, path, relative: 0).point;
      return spec.relative
          ? from + (point - path.style.transform.apply(Offset.zero))
          : point;
    }

    _cubic(
      path,
      control(first, start),
      // A relative second control is taken from where the curve ends.
      control(second, target.point),
      target,
    );
  }

  ({String text, bool relative}) _controlText(TikzScanner scanner) {
    final relative = scanner.take('++') || scanner.take('+');
    return (text: scanner.group('(', ')'), relative: relative);
  }

  void _close(_Path path) {
    _flushCorner(path);
    path.drawn.close();
    path
      ..closedAtEnd = true
      ..connector = null
      ..pen = null;
  }

  /// `to [options] (target)`, or an `edge`, drawn as a path of its own.
  void _to(TikzScanner scanner, _Path path, {required bool edge}) {
    final options = scanner.optional('[', ']');
    final nodes = <_NodeSpec>[];
    while (scanner.takeWord('node')) {
      nodes.add(_nodeSpec(scanner));
    }
    final style = path.style.copy()
      ..bend = null
      ..outAngle = null
      ..inAngle = null
      ..quotes = const <String>[];
    if (edge) {
      style
        ..draws = true
        ..fills = false
        ..shading = null;
    }
    if (options != null) {
      style.apply(TikzSource.options(options), onPath: true);
    }
    // A quoted label sits on the line, halfway along.
    for (final quote in style.quotes) {
      final (:text, :options) = _Nodes._quoted(quote);
      nodes.add((options: options, name: null, at: null, text: text));
    }
    final into = edge
        ? (_Path(style)
            ..reference = path.reference
            ..current = path.current
            ..currentNode = path.currentNode)
        : path;
    into.pending.addAll(nodes);
    final reference = path.reference;
    final target = _coordinate(scanner, path);
    if (edge) path.reference = reference;
    final from = into.current;
    if (from == null) {
      throw const FormatException('"to" needs a point to start from');
    }
    if (style.bend == null && style.outAngle == null && style.inAngle == null) {
      _line(into, target);
    } else {
      final d = target.point - from;
      final angle = d.direction * 180 / math.pi;
      final out = style.outAngle ?? angle + (style.bend ?? 0);
      final inward = style.inAngle ?? angle + 180 - (style.bend ?? 0);
      final reach = 0.3915 * d.distance * style.looseness;
      Offset heading(double degrees) =>
          Offset.fromDirection(degrees * math.pi / 180, reach);
      _cubic(into, from + heading(out), target.point + heading(inward), target);
    }
    if (edge) {
      _finish(into);
    }
  }

  /// Rounds the corner the line last drawn turns at to head for [next],
  /// [radius] round, or as round as the lines either side leave room for.
  static void _turn(_Path path, Offset next, double radius) {
    final corner = path.corner;
    if (corner == null || corner.to != path.current) return;
    final into = corner.to - corner.from;
    final out = next - corner.to;
    final r = math.min(radius, math.min(into.distance, out.distance) / 2);
    if (r <= 0) return;
    final before = corner.to - into / into.distance * r;
    final after = corner.to + out / out.distance * r;
    path.drawn
      ..lineTo(before.dx, -before.dy)
      ..quadraticBezierTo(corner.to.dx, -corner.to.dy, after.dx, -after.dy);
    path.corner = null;
  }

  /// Draws the line waiting for its corner to be rounded, sharp.
  static void _flushCorner(_Path path) {
    final corner = path.corner;
    if (corner == null) return;
    path.drawn.lineTo(corner.to.dx, -corner.to.dy);
    path.corner = null;
  }

  /// `sin (target)` and `cos (target)`: a quarter of a sine wave from the
  /// current point, rising from it, or levelling off from it.
  void _wave(
    _Path path,
    ({Offset point, _Node? node}) target, {
    required bool sine,
  }) {
    final from = path.current;
    if (from == null) {
      throw const FormatException('A wave needs a point to start from');
    }
    final d = target.point - from;
    const steep = math.pi / 6;
    _cubic(
      path,
      from + Offset(d.dx / 3, sine ? d.dy * steep : 0),
      from + Offset(d.dx * 2 / 3, sine ? d.dy : d.dy * (1 - steep)),
      target,
    );
  }

  /// `rectangle (corner)`, from the current point.
  void _rectangle(_Path path, ({Offset point, _Node? node}) corner) {
    _flushCorner(path);
    final from = path.current;
    if (from == null) {
      throw const FormatException('A rectangle needs a corner to start at');
    }
    final transform = path.style.transform;
    final a = transform.inverse.apply(from);
    final b = transform.inverse.apply(corner.point);
    final corners = <Offset>[
      a,
      Offset(b.dx, a.dy),
      b,
      Offset(a.dx, b.dy),
    ].map(transform.apply).toList();
    _polygon(path.drawn, corners, rounded: path.style.rounded);
    path
      ..current = corner.point
      ..currentNode = null
      ..pen = null
      ..connector = null;
    _drawnShape(path, corners.first);
  }

  /// The closed polygon through [corners], each corner [rounded] that far
  /// round if it is, or as round as its sides leave room for.
  static void _polygon(Path drawn, List<Offset> corners, {double? rounded}) {
    if (rounded == null || rounded <= 0) {
      drawn.moveTo(corners.first.dx, -corners.first.dy);
      for (final corner in corners.skip(1)) {
        drawn.lineTo(corner.dx, -corner.dy);
      }
      drawn.close();
      return;
    }
    final n = corners.length;
    for (var i = 0; i <= n; i++) {
      final corner = corners[i % n];
      final before = corners[(i + n - 1) % n] - corner;
      final after = corners[(i + 1) % n] - corner;
      final r = math.min(
        rounded,
        math.min(before.distance, after.distance) / 2,
      );
      final into = corner + before / math.max(before.distance, 1e-9) * r;
      final out = corner + after / math.max(after.distance, 1e-9) * r;
      if (i == 0) {
        drawn.moveTo(out.dx, -out.dy);
        continue;
      }
      drawn
        ..lineTo(into.dx, -into.dy)
        ..quadraticBezierTo(corner.dx, -corner.dy, out.dx, -out.dy);
    }
    drawn.close();
  }

  /// A closed shape drawn at [at] counts as drawing, without tips.
  static void _drawnShape(_Path path, Offset at) {
    if (!path.hasDrawn) {
      path
        ..firstPoint = at
        ..firstToward = at;
    }
    path.closedAtEnd = true;
  }

  /// `circle (r)`, `circle [radius=r]`, `ellipse (rx and ry)`: round the
  /// current point.
  void _ellipse(TikzScanner scanner, _Path path) {
    _flushCorner(path);
    final style = path.style.copy();
    final options = scanner.optional('[', ']');
    if (options != null) style.apply(TikzSource.options(options), onPath: true);
    final size = scanner.optional('(', ')');
    final radii = size?.split(RegExp(r'\s+and\s+'));
    final x = radii?.first ?? style.xRadius ?? style.radius;
    final y = radii?.last ?? style.yRadius ?? style.radius;
    if (x == null || y == null) {
      throw const FormatException('A circle needs a radius');
    }
    final centre = path.current;
    if (centre == null) {
      throw const FormatException('A circle needs a centre');
    }
    final rx = style.radiusOf(x, vertical: false);
    final ry = style.radiusOf(y, vertical: true);
    final user = style.transform.inverse.apply(centre);
    final start = style.transform.apply(user + Offset(rx, 0));
    path.drawn.moveTo(start.dx, -start.dy);
    _arcPieces(path.drawn, style.transform, user, rx, ry, 0, 360);
    path.drawn.close();
    path
      ..pen = null
      ..connector = null;
    _drawnShape(path, start);
  }

  /// Draws the arc of the ellipse round [centre] (before [transform]) from
  /// [from] to [to] degrees, in cubic pieces of at most a right angle.
  static Offset _arcPieces(
    Path drawn,
    _Affine transform,
    Offset centre,
    double rx,
    double ry,
    double from,
    double to,
  ) {
    final pieces = math.max(1, ((to - from).abs() / 90).ceil());
    final step = (to - from) / pieces * math.pi / 180;
    final k = 4 / 3 * math.tan(step / 4);
    var a = from * math.pi / 180;
    Offset at(double r) => centre + Offset(rx * math.cos(r), ry * math.sin(r));
    Offset tangent(double r) => Offset(-rx * math.sin(r), ry * math.cos(r)) * k;
    var end = transform.apply(at(a));
    for (var i = 0; i < pieces; i++) {
      final b = a + step;
      final c1 = transform.apply(at(a) + tangent(a));
      final c2 = transform.apply(at(b) - tangent(b));
      end = transform.apply(at(b));
      drawn.cubicTo(c1.dx, -c1.dy, c2.dx, -c2.dy, end.dx, -end.dy);
      a = b;
    }
    return end;
  }

  /// `arc (start:end:radius)` or `arc [start angle=…, …]`, from the current
  /// point.
  void _arc(TikzScanner scanner, _Path path) {
    final style = path.style.copy();
    final options = scanner.optional('[', ']');
    if (options != null) style.apply(TikzSource.options(options), onPath: true);
    final spec = scanner.optional('(', ')');
    double from;
    double to;
    String? x;
    String? y;
    if (spec != null) {
      final parts = TikzSource.split(spec, ':');
      if (parts.length != 3) {
        throw FormatException('An arc is "(start:end:radius)", not "$spec"');
      }
      from = TikzExpression.evaluate(parts[0], _variables).value;
      to = TikzExpression.evaluate(parts[1], _variables).value;
      final radii = parts[2].split(RegExp(r'\s+and\s+'));
      x = radii.first;
      y = radii.last;
    } else {
      from = style.startAngle ?? 0;
      to =
          style.endAngle ??
          from +
              (style.deltaAngle ??
                  (throw const FormatException('An arc needs its end angle')));
      x = style.xRadius ?? style.radius;
      y = style.yRadius ?? style.radius;
    }
    if (x == null || y == null) {
      throw const FormatException('An arc needs a radius');
    }
    final rx = style.radiusOf(x, vertical: false);
    final ry = style.radiusOf(y, vertical: true);
    final start = path.current;
    if (start == null) {
      throw const FormatException('An arc needs a point to start from');
    }
    final user = style.transform.inverse.apply(start);
    final r = from * math.pi / 180;
    final centre = user - Offset(rx * math.cos(r), ry * math.sin(r));
    // Which way the arc runs at an angle, for the tips at its ends.
    Offset heading(double degrees) {
      final a = degrees * math.pi / 180;
      return style.transform.linear(
        Offset(-rx * math.sin(a), ry * math.cos(a)) * (to >= from ? 1 : -1),
      );
    }

    _begin(path, start + heading(from));
    final end = _arcPieces(
      path.drawn,
      style.transform,
      centre,
      rx,
      ry,
      from,
      to,
    );
    _drawn(
      path,
      end: end,
      from: end - heading(to),
      stretch: (t) => style.transform.apply(
        centre +
            Offset(
              rx * math.cos((from + (to - from) * t) * math.pi / 180),
              ry * math.sin((from + (to - from) * t) * math.pi / 180),
            ),
      ),
      target: (point: end, node: null),
    );
  }

  /// `grid (corner)`: lines a step apart across the rectangle.
  void _grid(_Path path, _Style style, ({Offset point, _Node? node}) corner) {
    _flushCorner(path);
    final from = path.current;
    if (from == null) {
      throw const FormatException('A grid needs a corner to start at');
    }
    final inverse = style.transform.inverse;
    final a = inverse.apply(from);
    final b = inverse.apply(corner.point);
    final stepX = style.radiusOf(style.step, vertical: false);
    final stepY = style.radiusOf(style.step, vertical: true);
    if (stepX <= 0 || stepY <= 0) {
      throw const FormatException('A grid needs a step');
    }
    final left = math.min(a.dx, b.dx);
    final right = math.max(a.dx, b.dx);
    final bottom = math.min(a.dy, b.dy);
    final top = math.max(a.dy, b.dy);
    if ((right - left) / stepX + (top - bottom) / stepY > 2000) {
      throw const FormatException('The grid has too many lines');
    }
    void line(Offset p, Offset q) {
      final s = style.transform.apply(p);
      final e = style.transform.apply(q);
      path.drawn
        ..moveTo(s.dx, -s.dy)
        ..lineTo(e.dx, -e.dy);
    }

    for (var x = (left / stepX).ceil() * stepX; x <= right + 1e-6; x += stepX) {
      line(Offset(x, bottom), Offset(x, top));
    }
    for (var y = (bottom / stepY).ceil() * stepY; y <= top + 1e-6; y += stepY) {
      line(Offset(left, y), Offset(right, y));
    }
    path
      ..current = corner.point
      ..currentNode = null
      ..pen = null
      ..connector = null;
    _drawnShape(path, from);
  }

  /// `parabola (end)` or `parabola bend (vertex) (end)`.
  void _parabola(TikzScanner scanner, _Path path) {
    scanner.optional('[', ']');
    final transform = path.style.transform;
    final start = path.current;
    if (start == null) {
      throw const FormatException('A parabola needs a point to start from');
    }
    Offset user(Offset p) => transform.inverse.apply(p);
    void half(Offset from, Offset to, {required bool vertexAtStart}) {
      final a = user(from);
      final b = user(to);
      final control = vertexAtStart
          ? Offset((a.dx + b.dx) / 2, a.dy)
          : Offset((a.dx + b.dx) / 2, b.dy);
      final c = transform.apply(control);
      final c1 = from + (c - from) * (2 / 3);
      final c2 = to + (c - to) * (2 / 3);
      _cubic(path, c1, c2, (point: to, node: null));
    }

    if (scanner.takeWord('bend')) {
      final vertex = _coordinate(scanner, path).point;
      final end = _coordinate(scanner, path).point;
      half(start, vertex, vertexAtStart: false);
      half(vertex, end, vertexAtStart: true);
    } else {
      half(start, _coordinate(scanner, path).point, vertexAtStart: true);
    }
  }

  /// `plot coordinates {…}` or `plot (\x, {f(\x)})`, from the current
  /// point if it is joined on with `--`.
  void _plot(TikzScanner scanner, _Path path) {
    final style = path.style.copy();
    final options = scanner.optional('[', ']');
    if (options != null) style.apply(TikzSource.options(options), onPath: true);
    final points = <Offset>[];
    if (scanner.takeWord('coordinates')) {
      final list = TikzScanner(scanner.group('{', '}'));
      while (!list.done) {
        points.add(_point(list.group('(', ')'), path, relative: 0).point);
      }
    } else {
      final inner = scanner.group('(', ')');
      final (:from, :to) = style.domain;
      for (var i = 0; i < style.samples; i++) {
        _variables[style.variable] =
            from + (to - from) * i / (style.samples - 1);
        points.add(style.transform.apply(style.vector(inner, _variables)));
      }
      _variables.remove(style.variable);
    }
    if (points.isEmpty) return;
    if (path.connector == null || path.current == null) {
      _moveTo(path, (point: points.first, node: null));
    } else {
      _line(path, (point: points.first, node: null));
    }
    for (var i = 1; i < points.length; i++) {
      final target = (point: points[i], node: null);
      if (!style.smooth) {
        _line(path, target);
        continue;
      }
      final before = points[math.max(0, i - 2)];
      final after = points[math.min(points.length - 1, i + 1)];
      final from = points[i - 1];
      _cubic(
        path,
        from + (points[i] - before) / 6,
        points[i] - (after - from) / 6,
        target,
      );
    }
    path.reference = points.last;
  }
}
