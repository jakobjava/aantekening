/// Shapes drawn in ink: a stroke held still until it turns into the shape
/// it was drawn as, or a shape chosen on the Draw tab and dragged out.
///
/// A shape is a shape only while it is being drawn, and reshaped by the
/// pointer still down. Once the pen lifts it is ink, strokes like any other,
/// as OneNote keeps its shapes: moved, resized, turned and erased as
/// handwriting is.
library;

import 'dart:math' as math;

import '../util/geometry.dart';
import 'ink.dart';

/// Where a shape is offered on the Draw tab.
enum ShapeFamily {
  lines('Lines'),
  outlines('Shapes'),
  graphs('Graphs'),
  solids('Solids');

  const ShapeFamily(this.label);

  final String label;
}

/// A kind of shape, and how it is drawn.
enum ShapeKind {
  line('Line', ShapeFamily.lines),
  arrow('Arrow', ShapeFamily.lines),
  doubleArrow('Double arrow', ShapeFamily.lines),
  rectangle('Rectangle', ShapeFamily.outlines, aspect: 0.625),
  square('Square', ShapeFamily.outlines, keepsSquare: true),
  ellipse('Ellipse', ShapeFamily.outlines, aspect: 0.625),
  circle('Circle', ShapeFamily.outlines, keepsSquare: true),
  triangle('Triangle', ShapeFamily.outlines),
  rightTriangle('Right triangle', ShapeFamily.outlines, mirrors: true),
  diamond('Diamond', ShapeFamily.outlines),
  parallelogram('Parallelogram', ShapeFamily.outlines, aspect: 0.5),
  trapezoid('Trapezoid', ShapeFamily.outlines, aspect: 0.5),
  pentagon('Pentagon', ShapeFamily.outlines),
  hexagon('Hexagon', ShapeFamily.outlines, aspect: 0.875),
  axes('Axes', ShapeFamily.graphs),
  crossAxes('Axes, four quadrants', ShapeFamily.graphs),
  axes3d('Axes in 3D', ShapeFamily.graphs),
  numberLine('Number line', ShapeFamily.graphs),
  grid('Grid', ShapeFamily.graphs),
  cube('Cube', ShapeFamily.solids, keepsSquare: true),
  cuboid('Cuboid', ShapeFamily.solids, aspect: 0.625),
  cylinder('Cylinder', ShapeFamily.solids, aspect: 1.25),
  cone('Cone', ShapeFamily.solids, aspect: 1.25),
  pyramid('Pyramid', ShapeFamily.solids),
  sphere('Sphere', ShapeFamily.solids, keepsSquare: true),

  /// Straight lines joined at corners, as drawn: recognised, not offered.
  polyline('Lines', null),

  /// A closed outline of straight sides, as drawn: recognised, not offered.
  polygon('Polygon', null);

  const ShapeKind(
    this.label,
    this.family, {
    this.keepsSquare = false,
    this.aspect = 1,
    this.mirrors = false,
  });

  final String label;

  /// Where it is offered, or null for a shape only recognised.
  final ShapeFamily? family;

  /// Whether it is as high as it is wide, however it is dragged out.
  final bool keepsSquare;

  /// How high it is for its width, put down with a click.
  final double aspect;

  /// Whether dragged out leftwards or upwards it is drawn mirrored: the
  /// right angle of a right triangle is where the drag began.
  final bool mirrors;

  /// Whether it is drawn through points, rather than in a box.
  bool get throughPoints => switch (this) {
    line || arrow || doubleArrow || numberLine || polyline || polygon => true,
    _ => false,
  };

  /// The shapes offered in [family], in order.
  static List<ShapeKind> of(ShapeFamily family) => <ShapeKind>[
    for (final kind in values)
      if (kind.family == family) kind,
  ];
}

/// A shape being drawn: where it is, how it is reshaped, and the lines it
/// is drawn with.
sealed class InkShape {
  const InkShape(this.kind);

  /// A shape of [kind] begun at [at], as small as it can be, to be dragged
  /// out by its [draggedHandle].
  factory InkShape.begin(ShapeKind kind, Vec2 at) => kind.throughPoints
      ? PathShape(kind, <Vec2>[at, at])
      : BoxShape(kind, origin: at, size: const Vec2.zero());

  /// A shape of [kind] [width] across, from [at] — at its usual size, what
  /// a click puts down without dragging one out. A number line is longer,
  /// for its ticks.
  factory InkShape.placed(
    ShapeKind kind,
    Vec2 at, {
    double width = usualWidth,
  }) {
    final begun = InkShape.begin(kind, at);
    final across = kind == ShapeKind.numberLine ? width * 5 / 3 : width;
    return begun.withHandle(
      begun.draggedHandle,
      at + Vec2(across, kind.throughPoints ? 0 : across * kind.aspect),
    );
  }

  /// How wide a shape is put down with a click, in page units: six squares
  /// of the page's grid.
  static const double usualWidth = 144;

  /// The spacing of the ticks on axes and number lines, and of a grid's
  /// lines: a square of the page's grid.
  static const double unit = 24;

  final ShapeKind kind;

  /// The points it can be taken hold of by while it is drawn.
  List<Vec2> get handles;

  /// The handle a shape just begun is dragged out by.
  int get draggedHandle;

  /// A copy with handle [index] moved to [to]. With [constrain] — Shift
  /// held — a box stays square and a line keeps to steps of 15°.
  InkShape withHandle(int index, Vec2 to, {bool constrain = false});

  /// How far it reaches: too little to be seen below a page unit or two.
  double get extent {
    final points = handles;
    final xs = points.map((point) => point.x);
    final ys = points.map((point) => point.y);
    return Vec2(
      xs.reduce(math.max) - xs.reduce(math.min),
      ys.reduce(math.max) - ys.reduce(math.min),
    ).length;
  }

  /// The lines it is drawn with, each through its points, for a pen
  /// [width] wide: arrowheads, ticks and dashes are sized to the pen.
  List<List<Vec2>> lines(double width);

  /// The strokes it is drawn with, in [tool], [color] and [width].
  ///
  /// Every sample is pressed alike, so it is drawn at the pen's width all
  /// along. Its corners are kept corners by how ink is drawn, which goes
  /// straight to a sharp turn between long sides rather than round it.
  List<InkStroke> strokes({
    required InkTool tool,
    required int color,
    required double width,
  }) => <InkStroke>[
    for (final line in lines(width))
      if (line.length > 1)
        InkStroke.fromPoints(
          tool: tool,
          color: color,
          width: width,
          xs: <double>[for (final point in line) point.x],
          ys: <double>[for (final point in line) point.y],
        ),
  ];
}

/// A shape through points: a line, an arrow, a number line, or the lines
/// and outlines recognised in what was drawn.
final class PathShape extends InkShape {
  const PathShape(super.kind, this.points);

  final List<Vec2> points;

  /// Within how far of a step of 45° a line is put on it, in radians: a
  /// line meant to be level is.
  static const double _pull = 3 * math.pi / 180;

  @override
  List<Vec2> get handles => points;

  @override
  int get draggedHandle => points.length - 1;

  @override
  PathShape withHandle(int index, Vec2 to, {bool constrain = false}) {
    final moved = List<Vec2>.of(points);
    moved[index] = points.length == 2
        ? _aligned(points[1 - index], to, constrain: constrain)
        : to;
    return PathShape(kind, moved);
  }

  /// [to] turned about [from] onto a step of 15° with [constrain], or onto
  /// a step of 45° it is near.
  static Vec2 _aligned(Vec2 from, Vec2 to, {bool constrain = false}) {
    final along = to - from;
    if (along.length == 0) return to;
    final step = (constrain ? 15 : 45) * math.pi / 180;
    final nearest = (along.angle / step).roundToDouble() * step;
    if (!constrain && (along.angle - nearest).abs() > _pull) return to;
    return from + Vec2(along.length, 0).rotated(nearest);
  }

  @override
  List<List<Vec2>> lines(double width) {
    final first = points.first;
    final last = points.last;
    return switch (kind) {
      ShapeKind.arrow => <List<Vec2>>[points, _arrowHead(first, last, width)],
      ShapeKind.doubleArrow => <List<Vec2>>[
        points,
        _arrowHead(first, last, width),
        _arrowHead(last, first, width),
      ],
      ShapeKind.numberLine => <List<Vec2>>[
        points,
        _arrowHead(first, last, width),
        ..._ticks(first, last, width, first: InkShape.unit / 2),
      ],
      ShapeKind.polygon => <List<Vec2>>[_closed(points)],
      _ => <List<Vec2>>[points],
    };
  }
}

/// A shape drawn in a box: an outline, a graph or a solid.
///
/// The box has axes of its own, turned by [angle], and reaches [size]
/// along them from [origin]: the corner a drag began at, so a size is
/// negative where the box was dragged out leftwards or upwards.
final class BoxShape extends InkShape {
  const BoxShape(
    super.kind, {
    required this.origin,
    required this.size,
    this.angle = 0,
  });

  final Vec2 origin;
  final Vec2 size;

  /// How far the box's axes are turned, clockwise in radians.
  final double angle;

  /// The corners of the box, as fractions of its size along its axes, in
  /// the order of [handles].
  static const List<(double, double)> _corners = <(double, double)>[
    (0, 0),
    (1, 0),
    (1, 1),
    (0, 1),
  ];

  Vec2 _at(double across, double down) =>
      origin + Vec2(size.x * across, size.y * down).rotated(angle);

  @override
  List<Vec2> get handles => <Vec2>[
    for (final (across, down) in _corners) _at(across, down),
  ];

  @override
  int get draggedHandle => 2;

  /// Moves one corner, keeping the one across from it where it is.
  @override
  BoxShape withHandle(int index, Vec2 to, {bool constrain = false}) {
    final (across, down) = _corners[index];
    final kept = _at(1 - across, 1 - down);
    final reach = (to - kept).rotated(-angle);
    var width = across == 1 ? reach.x : -reach.x;
    var height = down == 1 ? reach.y : -reach.y;
    if (constrain || kind.keepsSquare) {
      final side = math.max(width.abs(), height.abs());
      width = width < 0 ? -side : side;
      height = height < 0 ? -side : side;
    }
    return BoxShape(
      kind,
      origin:
          kept - Vec2(width * (1 - across), height * (1 - down)).rotated(angle),
      size: Vec2(width, height),
      angle: angle,
    );
  }

  @override
  List<List<Vec2>> lines(double width) {
    final box = _Box.of(this);
    return switch (kind) {
      ShapeKind.rectangle || ShapeKind.square => <List<Vec2>>[
        _closed(<Vec2>[box(0, 0), box(1, 0), box(1, 1), box(0, 1)]),
      ],
      ShapeKind.ellipse || ShapeKind.circle => <List<Vec2>>[
        box.ellipse(box(0.5, 0.5), box.width / 2, box.height / 2),
      ],
      ShapeKind.triangle => <List<Vec2>>[
        _closed(<Vec2>[box(0.5, 0), box(1, 1), box(0, 1)]),
      ],
      ShapeKind.rightTriangle => <List<Vec2>>[
        _closed(<Vec2>[box(0, 0), box(1, 0), box(0, 1)]),
      ],
      ShapeKind.diamond => <List<Vec2>>[
        _closed(<Vec2>[box(0.5, 0), box(1, 0.5), box(0.5, 1), box(0, 0.5)]),
      ],
      ShapeKind.parallelogram => <List<Vec2>>[
        _closed(<Vec2>[box(0.25, 0), box(1, 0), box(0.75, 1), box(0, 1)]),
      ],
      ShapeKind.trapezoid => <List<Vec2>>[
        _closed(<Vec2>[box(0.25, 0), box(0.75, 0), box(1, 1), box(0, 1)]),
      ],
      ShapeKind.pentagon => <List<Vec2>>[box.regular(5, -math.pi / 2)],
      ShapeKind.hexagon => <List<Vec2>>[box.regular(6, 0)],
      ShapeKind.axes => _axes(box, width),
      ShapeKind.crossAxes => _crossAxes(box, width),
      ShapeKind.axes3d => _axes3d(box, width),
      ShapeKind.grid => _grid(box),
      ShapeKind.cube || ShapeKind.cuboid => _cuboid(box, width),
      ShapeKind.cylinder => _cylinder(box, width),
      ShapeKind.cone => _cone(box, width),
      ShapeKind.pyramid => _pyramid(box, width),
      ShapeKind.sphere => _sphere(box, width),
      ShapeKind.line ||
      ShapeKind.arrow ||
      ShapeKind.doubleArrow ||
      ShapeKind.numberLine ||
      ShapeKind.polyline ||
      ShapeKind.polygon => const <List<Vec2>>[],
    };
  }

  /// The first quadrant: the axes from the bottom-left corner, along the
  /// bottom and up the left side.
  static List<List<Vec2>> _axes(_Box box, double width) {
    final origin = box(0, 1);
    return <List<Vec2>>[
      ..._axis(origin, box(1, 1), width),
      ..._axis(origin, box(0, 0), width),
    ];
  }

  /// All four quadrants: the axes crossing in the middle.
  static List<List<Vec2>> _crossAxes(_Box box, double width) {
    final origin = box(0.5, 0.5);
    return <List<Vec2>>[
      ..._axis(origin, box(1, 0.5), width, back: box(0, 0.5)),
      ..._axis(origin, box(0.5, 0), width, back: box(0.5, 1)),
    ];
  }

  /// x coming out of the page, down to the left; y to the right; z up —
  /// the x axis ticked at half the square's diagonal, as a drawing in
  /// oblique projection has it.
  static List<List<Vec2>> _axes3d(_Box box, double width) {
    final origin = box(0.4, 0.6);
    return <List<Vec2>>[
      ..._axis(origin, box(0, 1), width, unit: InkShape.unit * math.sqrt1_2),
      ..._axis(origin, box(1, 0.6), width),
      ..._axis(origin, box(0.4, 0), width),
    ];
  }

  static List<List<Vec2>> _grid(_Box box) => <List<Vec2>>[
    _closed(<Vec2>[box(0, 0), box(1, 0), box(1, 1), box(0, 1)]),
    for (var x = InkShape.unit; x < box.width - 1; x += InkShape.unit)
      <Vec2>[box.point(x, 0), box.point(x, box.height)],
    for (var y = InkShape.unit; y < box.height - 1; y += InkShape.unit)
      <Vec2>[box.point(0, y), box.point(box.width, y)],
  ];

  /// A box seen from the front, a little from above and the right: the
  /// edges behind it dashed.
  static List<List<Vec2>> _cuboid(_Box box, double width) {
    final w = box.width;
    final h = box.height;
    final depth = 0.26 * math.min(w, h);
    final frontTop = <Vec2>[box.point(0, depth), box.point(w - depth, depth)];
    final frontBottom = <Vec2>[box.point(w - depth, h), box.point(0, h)];
    final backLeft = box.point(depth, 0);
    final backRight = box.point(w, 0);
    final backBottomRight = box.point(w, h - depth);
    final hidden = box.point(depth, h - depth);
    return <List<Vec2>>[
      _closed(<Vec2>[...frontTop, ...frontBottom]),
      <Vec2>[frontTop.first, backLeft, backRight, backBottomRight],
      <Vec2>[frontTop.last, backRight],
      <Vec2>[frontBottom.first, backBottomRight],
      ..._dashed(<Vec2>[backLeft, hidden, backBottomRight], width),
      ..._dashed(<Vec2>[hidden, frontBottom.last], width),
    ];
  }

  static List<List<Vec2>> _cylinder(_Box box, double width) {
    final w = box.width;
    final h = box.height;
    final rim = math.min(0.15 * h, 0.2 * w);
    final bottom = box.point(w / 2, h - rim);
    return <List<Vec2>>[
      box.ellipse(box.point(w / 2, rim), w / 2, rim),
      <Vec2>[box.point(0, rim), box.point(0, h - rim)],
      <Vec2>[box.point(w, rim), box.point(w, h - rim)],
      box.ellipse(bottom, w / 2, rim, to: math.pi),
      ..._dashed(box.ellipse(bottom, w / 2, rim, from: math.pi), width),
    ];
  }

  static List<List<Vec2>> _cone(_Box box, double width) {
    final w = box.width;
    final h = box.height;
    final rim = math.min(0.15 * h, 0.2 * w);
    final base = box.point(w / 2, h - rim);
    return <List<Vec2>>[
      <Vec2>[box.point(0, h - rim), box(0.5, 0), box.point(w, h - rim)],
      box.ellipse(base, w / 2, rim, to: math.pi),
      ..._dashed(box.ellipse(base, w / 2, rim, from: math.pi), width),
    ];
  }

  /// A pyramid on a square base, seen as the cuboid is.
  static List<List<Vec2>> _pyramid(_Box box, double width) {
    final w = box.width;
    final h = box.height;
    final across = 0.3 * w;
    final back = 0.22 * h;
    final apex = box(0.5, 0);
    final frontLeft = box.point(0, h);
    final frontRight = box.point(w - across, h);
    final backRight = box.point(w, h - back);
    final hidden = box.point(across, h - back);
    return <List<Vec2>>[
      <Vec2>[apex, frontLeft, frontRight, backRight, apex, frontRight],
      ..._dashed(<Vec2>[frontLeft, hidden, backRight], width),
      ..._dashed(<Vec2>[hidden, apex], width),
    ];
  }

  static List<List<Vec2>> _sphere(_Box box, double width) {
    final centre = box(0.5, 0.5);
    final radius = box.width / 2;
    final equator = radius * 0.3;
    return <List<Vec2>>[
      box.ellipse(centre, radius, box.height / 2),
      box.ellipse(centre, radius, equator, to: math.pi),
      ..._dashed(box.ellipse(centre, radius, equator, from: math.pi), width),
    ];
  }
}

/// A shape's box as it is drawn in: its corner at (0, 0) the top left,
/// unless the shape [ShapeKind.mirrors] with the way it was dragged.
class _Box {
  _Box(this.corner, this.across, this.down, this.width, this.height);

  factory _Box.of(BoxShape shape) {
    final size = shape.size;
    final across = const Vec2(1, 0).rotated(shape.angle);
    final down = const Vec2(0, 1).rotated(shape.angle);
    if (shape.kind.mirrors) {
      return _Box(
        shape.origin,
        size.x < 0 ? -across : across,
        size.y < 0 ? -down : down,
        size.x.abs(),
        size.y.abs(),
      );
    }
    return _Box(
      shape.origin + across * math.min(0, size.x) + down * math.min(0, size.y),
      across,
      down,
      size.x.abs(),
      size.y.abs(),
    );
  }

  final Vec2 corner;

  /// Which way its sides run, as vectors of one page unit.
  final Vec2 across;
  final Vec2 down;

  final double width;
  final double height;

  /// The point [x] and [y] of the way across and down it.
  Vec2 call(double x, double y) => point(x * width, y * height);

  /// The point [x] and [y] page units across and down it.
  Vec2 point(double x, double y) => corner + across * x + down * y;

  /// The ellipse about [centre] with radii [rx] across and [ry] down, from
  /// angle [from] to [to]: the front half of one seen from above is from 0
  /// to pi.
  List<Vec2> ellipse(
    Vec2 centre,
    double rx,
    double ry, {
    double from = 0,
    double to = 2 * math.pi,
  }) {
    // Short enough sides that no corner shows at any size.
    final reach = (to - from) * math.max(rx, ry);
    final sides = (reach / 6).ceil().clamp(12, 160);
    return <Vec2>[
      for (var i = 0; i <= sides; i++)
        centre +
            across * (rx * math.cos(from + (to - from) * i / sides)) +
            down * (ry * math.sin(from + (to - from) * i / sides)),
    ];
  }

  /// A regular polygon of [sides] stretched to fill the box, its first
  /// corner at [start] radians round from the right.
  List<Vec2> regular(int sides, double start) {
    final corners = <(double, double)>[
      for (var i = 0; i < sides; i++)
        (
          math.cos(start + 2 * math.pi * i / sides),
          math.sin(start + 2 * math.pi * i / sides),
        ),
    ];
    final left = corners.map((c) => c.$1).reduce(math.min);
    final right = corners.map((c) => c.$1).reduce(math.max);
    final top = corners.map((c) => c.$2).reduce(math.min);
    final bottom = corners.map((c) => c.$2).reduce(math.max);
    return _closed(<Vec2>[
      for (final (x, y) in corners)
        this((x - left) / (right - left), (y - top) / (bottom - top)),
    ]);
  }
}

/// [points], back to the first.
List<Vec2> _closed(List<Vec2> points) => <Vec2>[...points, points.first];

/// How long an arrowhead is for a pen [width] wide, on a line [length]
/// long: never more than a third of the line.
double _headLength(double width, double length) =>
    math.min(math.max(9.0, 4 * width + 5), length / 3);

/// An open head at [tip] of the line from [from].
List<Vec2> _arrowHead(Vec2 from, Vec2 tip, double width) {
  final back = from - tip;
  final length = back.length;
  if (length == 0) return const <Vec2>[];
  final barb = back.unit * _headLength(width, length);
  const spread = 26 * math.pi / 180;
  return <Vec2>[tip + barb.rotated(spread), tip, tip + barb.rotated(-spread)];
}

/// An axis from [origin] to an arrowhead at [end], ticked every [unit]
/// until the head; with [back], carried on beyond the origin that way,
/// ticked as well.
List<List<Vec2>> _axis(
  Vec2 origin,
  Vec2 end,
  double width, {
  Vec2? back,
  double unit = InkShape.unit,
}) => <List<Vec2>>[
  <Vec2>[back ?? origin, end],
  _arrowHead(origin, end, width),
  ..._ticks(origin, end, width, unit: unit),
  if (back != null) ..._ticks(origin, back, width, unit: unit, headed: false),
];

/// Ticks across the line from [from] to [to], every [unit] from [first]
/// along it, clear of the arrowhead at [to] if it is [headed].
List<List<Vec2>> _ticks(
  Vec2 from,
  Vec2 to,
  double width, {
  double unit = InkShape.unit,
  double? first,
  bool headed = true,
}) {
  final along = to - from;
  final length = along.length;
  if (length == 0) return const <List<Vec2>>[];
  final direction = along / length;
  final across =
      direction.rotated(math.pi / 2) * math.max(3.0, 1.5 * width + 1.5);
  final end = headed ? length - _headLength(width, length) - 3 : length - 3;
  return <List<Vec2>>[
    for (var at = first ?? unit; at <= end; at += unit)
      <Vec2>[from + direction * at - across, from + direction * at + across],
  ];
}

/// [line] broken into dashes, for an edge out of sight.
List<List<Vec2>> _dashed(List<Vec2> line, double width) {
  final dash = math.max(5.0, 3 * width);
  final gap = math.max(4.0, 2.2 * width);
  final dashes = <List<Vec2>>[];
  var current = <Vec2>[];
  var drawing = true;
  var left = dash;
  for (var i = 0; i + 1 < line.length; i++) {
    var from = line[i];
    final to = line[i + 1];
    if (drawing && current.isEmpty) current.add(from);
    var remaining = from.distanceTo(to);
    while (remaining > left) {
      final point = from + (to - from).unit * left;
      if (drawing) {
        dashes.add(<Vec2>[...current, point]);
        current = <Vec2>[];
      } else {
        current = <Vec2>[point];
      }
      remaining -= left;
      from = point;
      drawing = !drawing;
      left = drawing ? dash : gap;
    }
    left -= remaining;
    if (drawing) current.add(to);
  }
  if (drawing && current.length > 1) dashes.add(current);
  return dashes;
}
