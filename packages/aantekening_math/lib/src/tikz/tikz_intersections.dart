part of 'tikz_picture.dart';

/// The `intersections` library: where two named paths cross, as
/// coordinates of their own.
extension _Intersections on _Painter {
  /// Names where the paths `name intersections` [spec] lists cross:
  /// `intersection-1`, … in the order the first path meets them, or as
  /// `name=` says, and as `by=` lists.
  void _intersect(String spec) {
    String? of;
    var by = const <String>[];
    var prefix = 'intersection';
    for (final (:key, :value) in TikzSource.options(spec)) {
      switch (key) {
        case 'of' when value != null:
          of = value;
        case 'by' when value != null:
          by = <String>[
            for (final name in TikzSource.split(value, ','))
              if (name.trim().isNotEmpty) name.trim(),
          ];
        case 'name' when value != null:
          prefix = value.trim();
      }
    }
    final names = of?.split(RegExp(r'\s+and\s+'));
    if (names == null || names.length != 2) {
      throw const FormatException('Intersections are "of=a and b"');
    }
    Path named(String name) =>
        _namedPaths[name.trim()] ??
        (throw FormatException('No path is called "${name.trim()}"'));
    final points = _crossings(named(names[0]), named(names[1]));
    for (var i = 0; i < points.length; i++) {
      final node = _Node.point(_out(points[i]));
      _nodes['$prefix-${i + 1}'] = node;
      if (i < by.length) _nodes[by[i]] = node;
    }
  }

  /// Where [a] and [b] cross, in the order [a] meets them.
  static List<Offset> _crossings(Path a, Path b) {
    final across = _polylines(a);
    final along = _polylines(b);
    final found = <Offset>[];
    for (final line in across) {
      for (var i = 0; i + 1 < line.length; i++) {
        final hits = <(double, Offset)>[];
        for (final other in along) {
          for (var j = 0; j + 1 < other.length; j++) {
            final hit = _cross(line[i], line[i + 1], other[j], other[j + 1]);
            if (hit != null) hits.add(hit);
          }
        }
        hits.sort((x, y) => x.$1.compareTo(y.$1));
        for (final (_, point) in hits) {
          if (found.every((seen) => (seen - point).distance > 0.05)) {
            found.add(point);
          }
        }
      }
    }
    return found;
  }

  /// [path] as lines between points close enough to follow its curves.
  static List<List<Offset>> _polylines(Path path) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    final step = math.max(total / 2000, 0.2);
    return <List<Offset>>[
      for (final metric in metrics)
        <Offset>[
          for (var s = 0.0; s < metric.length; s += step)
            metric.getTangentForOffset(s)!.position,
          metric.getTangentForOffset(metric.length)!.position,
        ],
    ];
  }

  /// Where the segments p–q and r–s cross, and how far along p–q, if they
  /// do.
  static (double, Offset)? _cross(Offset p, Offset q, Offset r, Offset s) {
    final d = q - p;
    final e = s - r;
    final det = d.dx * e.dy - d.dy * e.dx;
    if (det.abs() < 1e-12) return null;
    final f = r - p;
    final t = (f.dx * e.dy - f.dy * e.dx) / det;
    final u = (f.dx * d.dy - f.dy * d.dx) / det;
    if (t < 0 || t > 1 || u < 0 || u > 1) return null;
    return (t, p + d * t);
  }
}
