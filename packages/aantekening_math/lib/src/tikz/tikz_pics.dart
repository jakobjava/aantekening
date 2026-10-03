part of 'tikz_picture.dart';

/// The `angles` library's pics: the angle at a corner marked with an arc,
/// or a right angle with a square, labelled as the `quotes` library says.
extension _Pics on _Painter {
  /// Draws the pic [content] says — `angle = a--b--c`, `right angle =
  /// a--b--c` — in [style]: the angle at `b` from `a` round to `c`.
  void _pic(String content, _Style style) {
    final equals = content.indexOf('=');
    final kind = equals < 0 ? content.trim() : content.substring(0, equals);
    final corners = equals < 0
        ? const <String>[]
        : content.substring(equals + 1).split('--');
    if (corners.length != 3 ||
        (kind.trim() != 'angle' && kind.trim() != 'right angle')) {
      throw FormatException('No pic here draws "${content.trim()}"');
    }
    final points = <Offset>[
      for (final corner in corners)
        _point(
          corner.trim().replaceAll(RegExp(r'^\(|\)$'), ''),
          null,
          relative: 0,
        ).point,
    ];
    final vertex = points[1];
    final from = (points[0] - vertex).direction * 180 / math.pi;
    var to = (points[2] - vertex).direction * 180 / math.pi;
    if (to < from) to += 360;
    final radius = style.angleRadius;
    final into = _layerOf(style);
    final Path outline;
    final Path area;
    if (kind.trim() == 'right angle') {
      final side = radius / math.sqrt2;
      final u = Offset.fromDirection(from * math.pi / 180, side);
      final v = Offset.fromDirection(to * math.pi / 180, side);
      final square = <Offset>[vertex + u, vertex + u + v, vertex + v];
      outline = Path()
        ..addPolygon(<Offset>[for (final p in square) _out(p)], false);
      area = Path()
        ..addPolygon(<Offset>[
          _out(vertex),
          for (final p in square) _out(p),
        ], true);
    } else {
      final start = _out(
        vertex + Offset.fromDirection(from * math.pi / 180, radius),
      );
      outline = Path()..moveTo(start.dx, start.dy);
      _Shapes._arcPieces(
        outline,
        _Affine.identity,
        vertex,
        radius,
        radius,
        from,
        to,
      );
      area = Path()
        ..moveTo(_out(vertex).dx, _out(vertex).dy)
        ..lineTo(start.dx, start.dy);
      _Shapes._arcPieces(
        area,
        _Affine.identity,
        vertex,
        radius,
        radius,
        from,
        to,
      );
      area.close();
    }
    if (style.fills || style.pattern != null) {
      _emit(
        area,
        style.copy()..draws = false,
        closed: true,
        into: into,
        tips: false,
      );
    }
    if (style.draws) {
      _emit(
        outline,
        style.copy()
          ..fills = false
          ..pattern = null,
        closed: false,
        into: into,
        tips: false,
      );
    }
    final middle = (from + to) / 2 * math.pi / 180;
    for (final quote in style.quotes) {
      final (:text, :options) = _Nodes._quoted(quote);
      final label = style.forNode()
        ..apply(TikzSource.options(options), onPath: true);
      _place(
        text,
        label,
        vertex + Offset.fromDirection(middle, radius * style.angleEccentricity),
        into: into,
      );
    }
  }
}
