part of 'tikz_picture.dart';

/// A node, or a named coordinate, where it ended up.
class _Node {
  _Node(
    this.centre,
    this.halfWidth,
    this.halfHeight,
    this.shape,
    this.outer, {
    this.outline,
    this.corners = const <String, int>{},
  });

  /// Where a bare coordinate is.
  _Node.point(this.centre)
    : halfWidth = 0,
      halfHeight = 0,
      shape = 'coordinate',
      outer = 0,
      outline = null,
      corners = const <String, int>{};

  final Offset centre;
  final double halfWidth;
  final double halfHeight;
  final double outer;
  final String shape;

  /// The corners of a shape with straight sides other than a rectangle,
  /// from its centre, with y upwards.
  final List<Offset>? outline;

  /// Which of [outline]'s corners each named anchor is: `corner 1`,
  /// `outer point 2`, `apex`.
  final Map<String, int> corners;

  double get _w => halfWidth + outer;
  double get _h => halfHeight + outer;

  /// The point on the border in the direction [angle], in degrees.
  Offset border(double angle) {
    if (shape == 'coordinate') return centre;
    final r = angle * math.pi / 180;
    final dx = math.cos(r);
    final dy = math.sin(r);
    final outline = this.outline;
    final double t;
    if (outline != null) {
      t = _rayOut(outline, Offset(dx, dy)) + outer;
    } else if (shape == 'circle' || shape == 'ellipse') {
      t = 1 / math.sqrt(math.pow(dx / _w, 2) + math.pow(dy / _h, 2));
    } else {
      t = math.min(
        dx.abs() < 1e-9 ? double.infinity : _w / dx.abs(),
        dy.abs() < 1e-9 ? double.infinity : _h / dy.abs(),
      );
    }
    return centre + Offset(dx, dy) * t;
  }

  /// How far from the centre a ray heading [d] leaves the polygon
  /// [outline].
  static double _rayOut(List<Offset> outline, Offset d) {
    var nearest = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final e = outline[(i + 1) % outline.length] - p;
      final det = d.dx * -e.dy - d.dy * -e.dx;
      if (det.abs() < 1e-12) continue;
      final t = (p.dx * -e.dy - p.dy * -e.dx) / det;
      final u = (d.dx * p.dy - d.dy * p.dx) / det;
      if (t > 0 && u >= -1e-9 && u <= 1 + 1e-9 && t > nearest) nearest = t;
    }
    return nearest;
  }

  /// The point on the border facing [point].
  Offset towards(Offset point) {
    final d = point - centre;
    return d.distance < 1e-9 ? centre : border(d.direction * 180 / math.pi);
  }

  static const Map<String, double> _compass = <String, double>{
    'east': 0,
    'north east': 45,
    'north': 90,
    'north west': 135,
    'west': 180,
    'south west': 225,
    'south': 270,
    'south east': 315,
  };

  /// Where the anchor [name] is: a side or corner, a centre, or an angle.
  Offset anchor(String name) {
    final trimmed = name.trim();
    if (trimmed == 'center' || trimmed == 'centre' || trimmed == 'mid') {
      return centre;
    }
    if (trimmed == 'base') return anchor('south');
    final corner = corners[trimmed];
    if (corner != null) return centre + outline![corner];
    final angle = _compass[trimmed];
    if (angle != null) {
      // A rectangle's corners are its corners, not where 45° meets it.
      if (shape == 'rectangle' && angle % 90 != 0) {
        final r = angle * math.pi / 180;
        return centre + Offset(_w * math.cos(r).sign, _h * math.sin(r).sign);
      }
      return border(angle);
    }
    final degrees = double.tryParse(trimmed);
    if (degrees == null) {
      throw FormatException('A node has no anchor "$trimmed"');
    }
    return border(degrees);
  }

  /// The anchor that faces away from [side]: what is above a node hangs
  /// from its south side.
  static String anchorFacing(String side) => switch (side) {
    'above' => 'south',
    'below' => 'north',
    'left' => 'east',
    'right' => 'west',
    'above left' => 'south east',
    'above right' => 'south west',
    'below left' => 'north east',
    'below right' => 'north west',
    _ => 'center',
  };

  /// The anchor on the [side] of a node.
  static String anchorOn(String side) => anchorFacing(switch (side) {
    'above' => 'below',
    'below' => 'above',
    'left' => 'right',
    'right' => 'left',
    'above left' => 'below right',
    'above right' => 'below left',
    'below left' => 'above right',
    'below right' => 'above left',
    _ => side,
  });
}

/// What is said about a node before it is placed.
typedef _NodeSpec = ({String options, String? name, String? at, String text});

/// Placing nodes and their labels.
extension _Nodes on _Painter {
  /// What follows `node`: options, a name and where it is, in any order,
  /// then its text, unless it is a coordinate, which has none.
  _NodeSpec _nodeSpec(TikzScanner scanner, {bool text = true}) {
    final options = StringBuffer();
    String? name;
    String? at;
    while (true) {
      if (scanner.sees('[')) {
        options
          ..write(scanner.group('[', ']'))
          ..write(',');
      } else if (scanner.sees('(')) {
        name = scanner.group('(', ')').trim();
      } else if (scanner.takeWord('at')) {
        at = scanner.group('(', ')');
      } else {
        break;
      }
    }
    return (
      options: options.toString(),
      name: name,
      at: at,
      text: text ? scanner.group('{', '}') : '',
    );
  }

  /// Places the node [spec] says: where it is said to be, or on [stretch]
  /// as far along as it says (or [along]), or at the current point.
  void _node(
    _NodeSpec spec,
    _Path path, {
    required Offset Function(double t)? stretch,
    required double? along,
  }) {
    final style = path.style.forNode();
    final every = style.styles['every node'];
    if (every != null) style.apply(every, onPath: true);
    style
      ..apply(style.nodeOptions, onPath: true)
      ..apply(TikzSource.options(spec.options), onPath: true);
    final shift =
        style.transform.apply(Offset.zero) -
        path.style.transform.apply(Offset.zero);
    final Offset position;
    if (spec.at != null) {
      position = _point(spec.at!, path, relative: 0).point;
    } else if (stretch != null && (style.pos ?? along) != null) {
      position = stretch(style.pos ?? along!);
    } else if (path.current != null) {
      position = path.current!;
    } else if (style.placement?.of != null || style.fit != null) {
      // Placed beside another node, or round others, which say where.
      position = Offset.zero;
    } else {
      throw const FormatException('A node needs a place: "at (x,y)"');
    }
    final node = _place(spec.text, style, position + shift, into: path.above);
    if (spec.name != null) _nodes[spec.name!] = node;

    for (final quote in style.quotes) {
      final (:text, :options) = _quoted(quote);
      final words = TikzSource.options(options);
      final side = words
          .where((o) => o.value == null && _Style._sides.contains(o.key))
          .lastOrNull
          ?.key;
      final rest = words
          .where((o) => o.key != side)
          .map((o) => o.value == null ? o.key : '${o.key}={${o.value}}')
          .join(',');
      style.labels = <String>[
        ...style.labels,
        '[$rest]${side ?? 'above'}:$text',
      ];
    }
    for (final label in style.labels) {
      final open = label.trim().startsWith('[')
          ? TikzScanner.matching(label.trim(), 0, '[', ']')
          : -1;
      final options = open < 0 ? '' : label.trim().substring(1, open);
      final rest = open < 0 ? label : label.trim().substring(open + 1);
      final colon = TikzSource.topLevel(rest, ':');
      final side = colon < 0 ? 'above' : rest.substring(0, colon).trim();
      final text = colon < 0 ? rest : rest.substring(colon + 1);
      final angle = double.tryParse(side);
      final labelStyle = path.style.forNode()
        ..apply(TikzSource.options(options), onPath: true);
      labelStyle.anchor = angle == null
          ? _Node.anchorFacing(side)
          : '${angle + 180}';
      _place(
        text,
        labelStyle,
        angle == null ? node.anchor(_Node.anchorOn(side)) : node.border(angle),
        into: path.above,
      );
    }
  }

  /// How far a rectangular node in [style] reaches from its centre, round
  /// the label [index] and its inner sep, or as large as it must be.
  Size _halfSize(int index, _Style style) {
    final size = _labelSize(index);
    return Size(
      math.max(size.width / 2 + style.innerSep, style.minWidth / 2),
      math.max(size.height / 2 + style.innerSep, style.minHeight / 2),
    );
  }

  /// [quote], a label of the `quotes` library — `"$\alpha$" below` — as
  /// its text and the options after it.
  static ({String text, String options}) _quoted(String quote) {
    final end = quote.indexOf('"', 1);
    if (end < 0) throw FormatException('Missing the closing quote in $quote');
    return (
      text: quote.substring(1, end),
      options: quote.substring(end + 1).replaceAll("'", ''),
    );
  }

  /// Puts a node with [text] at [position] as [style] places it, drawing it
  /// [into] the marks if it says so.
  _Node _place(
    String text,
    _Style style,
    Offset position, {
    required List<TikzMark> into,
  }) {
    final half = _halfSize(_labels.length, style);
    var halfWidth = half.width;
    var halfHeight = half.height;
    var at = position;
    // A node fitted round others is as large as they are, where they are.
    if (style.fit case final fit?) {
      final box = _fitted(fit);
      at = box.center;
      halfWidth = math.max(halfWidth, box.width / 2 + style.innerSep);
      halfHeight = math.max(halfHeight, box.height / 2 + style.innerSep);
    }
    var shape = style.shape;
    ({List<Offset> outline, Map<String, int> corners})? made;
    if (style.through case final through?) {
      shape = 'circle';
      halfWidth = halfHeight =
          (_point(through, null, relative: 0).point - at).distance;
    } else if (shape == 'circle') {
      final r = math.max(
        math.sqrt(halfWidth * halfWidth + halfHeight * halfHeight),
        math.max(style.minWidth, style.minHeight) / 2,
      );
      halfWidth = halfHeight = r;
    } else if (shape == 'ellipse') {
      halfWidth *= math.sqrt2;
      halfHeight *= math.sqrt2;
    } else if (shape != 'coordinate') {
      made = _NodeShapes.outline(shape, style, halfWidth, halfHeight);
      if (made == null) {
        shape = 'rectangle';
      } else {
        final bounds = _boundsOf(made.outline);
        halfWidth = bounds.width / 2;
        halfHeight = bounds.height / 2;
      }
    }
    final outer = style.outerSep ?? style.lineWidth / 2;
    _Node nodeAt(Offset centre) => _Node(
      centre,
      halfWidth,
      halfHeight,
      shape,
      outer,
      outline: made?.outline,
      corners: made?.corners ?? const <String, int>{},
    );

    var anchor = style.anchor ?? 'center';
    final placement = style.placement;
    if (placement != null) {
      anchor = _Node.anchorFacing(placement.side);
      final of = placement.of;
      if (of != null) {
        final other = _nodes[of];
        if (other == null) {
          throw FormatException('Nothing in the picture is called "$of"');
        }
        at = other.anchor(_Node.anchorOn(placement.side));
      }
      at += _sideways(placement.side) * placement.distance;
    }
    final node = nodeAt(at - nodeAt(Offset.zero).anchor(anchor));
    final centre = node.centre;

    if (shape != 'coordinate' && (style.draws || style.fills)) {
      final outline = Path();
      if (shape == 'circle' || shape == 'ellipse') {
        outline.addOval(
          Rect.fromCenter(
            center: _out(centre),
            width: halfWidth * 2,
            height: halfHeight * 2,
          ),
        );
      } else {
        _Shapes._polygon(outline, <Offset>[
          for (final corner
              in made?.outline ??
                  <Offset>[
                    Offset(-halfWidth, -halfHeight),
                    Offset(halfWidth, -halfHeight),
                    Offset(halfWidth, halfHeight),
                    Offset(-halfWidth, halfHeight),
                  ])
            centre + corner,
        ], rounded: style.rounded);
      }
      _emit(outline, style, closed: true, into: into, tips: false);
    }
    _labels.add(
      TikzLabel(
        latex: _latexOf(text, style),
        colour: style.text,
        scale: style.fontScale,
        centre: _out(centre),
      ),
    );
    return node;
  }

  static Rect _boundsOf(List<Offset> points) {
    var bounds = Rect.fromPoints(points.first, points.first);
    for (final point in points.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    return bounds;
  }

  /// The box round what [fit] lists: nodes, whole, and points.
  Rect _fitted(String fit) {
    final scanner = TikzScanner(fit);
    Rect? box;
    while (!scanner.done) {
      final found = _point(scanner.group('(', ')'), null, relative: 0);
      final node = found.node;
      final rect = node == null
          ? Rect.fromPoints(found.point, found.point)
          : Rect.fromCenter(
              center: node.centre,
              width: node._w * 2,
              height: node._h * 2,
            );
      box = box?.expandToInclude(rect) ?? rect;
    }
    if (box == null) throw const FormatException('"fit" names nothing');
    return box;
  }

  /// Which way [side] lies, a unit long (or along both axes for a corner).
  static Offset _sideways(String side) => Offset(
    side.contains('left')
        ? -1
        : side.contains('right')
        ? 1
        : 0,
    side.contains('above')
        ? 1
        : side.contains('below')
        ? -1
        : 0,
  );

  /// A node's [text] as LaTeX to typeset: text, with maths in `$…$`, lines
  /// broken at `\\`.
  static String _latexOf(String text, _Style style) {
    final lines = <String>[
      for (final line in TikzSource.split(text, r'\\'))
        if (line.trim().isNotEmpty) _lineLatex(line.trim(), style),
    ];
    if (lines.isEmpty) return '';
    if (lines.length == 1) return lines.single;
    final column = switch (style.align) {
      'left' => 'l',
      'right' => 'r',
      _ => 'c',
    };
    return '\\begin{array}{$column}${lines.join(r' \\ ')}\\end{array}';
  }

  static String _lineLatex(String line, _Style style) {
    final maths = RegExp(r'^\$([^$]*)\$$').firstMatch(line);
    if (maths != null) {
      final inner = maths.group(1)!;
      return style.bold ? '\\boldsymbol{$inner}' : inner;
    }
    var text = line;
    if (style.bold) text = '\\textbf{$text}';
    if (style.italic) text = '\\textit{$text}';
    return '\\text{$text}';
  }
}
