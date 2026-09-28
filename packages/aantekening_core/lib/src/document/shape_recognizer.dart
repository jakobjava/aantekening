/// Seeing which shape a stroke was drawn as.
library;

import 'dart:math' as math;

import '../util/geometry.dart';
import 'ink_shape.dart';

/// Reads a stroke as the shape it was meant to be: a line, an arrow, lines
/// joined at corners, a triangle or other outline of straight sides, a
/// rectangle or square, or an ellipse or circle.
///
/// It is strict: a stroke that is none of these clearly is left as it was
/// written, since the pen held still at the end of a word must not turn the
/// word into a shape.
abstract final class ShapeRecognizer {
  /// The shape [points] were drawn as, or null. With [linesOnly], a straight
  /// line or nothing: a highlighter's stroke is straightened, not outlined.
  static InkShape? recognize(List<Vec2> points, {bool linesOnly = false}) {
    final path = <Vec2>[];
    for (final point in points) {
      if (path.isEmpty || path.last != point) path.add(point);
    }
    if (path.length < 2) return null;
    final size = _Stroke(path).size;
    if (size < _smallest) return null;
    final line = _line(path);
    if (line != null || linesOnly) return line;
    final gap = path.first.distanceTo(path.last);
    return gap < _closing * size ? _closedShape(path, size) : _openShape(path);
  }

  /// Below this across, in page units, a stroke is a dot or a tick.
  static const double _smallest = 8;

  /// How near its start, for its size, a stroke has to end to be closed.
  static const double _closing = 0.22;

  /// How far a side may bow from straight, for its length: an outline's
  /// sides are told from an ellipse's arcs, which bow twice as far, and
  /// lines left open from writing, which is rarely as straight.
  static const double _outlineBow = 0.1;
  static const double _lineBow = 0.06;

  /// How little a corner may turn, in radians, to be a corner.
  static const double _slightest = 22 * math.pi / 180;

  /// Within how far of level or upright a side is made so, in radians.
  static const double _level = 6 * math.pi / 180;

  /// A straight line: no further from the line between its ends, anywhere,
  /// than a sixteenth of its length, and not going on past either end.
  static PathShape? _line(List<Vec2> path) {
    final start = path.first;
    final end = path.last;
    final chord = end - start;
    final length = chord.length;
    if (length == 0) return null;
    for (final point in path) {
      final along = (point - start).dot(chord) / (length * length);
      if (along < -0.1 || along > 1.1) return null;
    }
    final bow = _farthestFrom(path, 0, path.length - 1).distance;
    if (bow > math.max(length / 16, 2)) return null;
    return _straight(ShapeKind.line, start, end);
  }

  /// A line of [kind] from [start] to [end], put level or upright if it
  /// nearly is.
  static PathShape _straight(ShapeKind kind, Vec2 start, Vec2 end) =>
      PathShape(kind, <Vec2>[start, end]).withHandle(1, end);

  /// An arrow, or straight lines joined at corners.
  static PathShape? _openShape(List<Vec2> path) {
    final stroke = _Stroke(path);
    final corners = _cornersOf(path, 0, path.length - 1, stroke.size);
    return _arrow(path, corners) ?? _polyline(path, corners, stroke);
  }

  /// A straight shaft, and a head drawn at its end without lifting the pen:
  /// every stroke after the shaft near its tip and behind it.
  static PathShape? _arrow(List<Vec2> path, List<int> corners) {
    if (corners.length < 3) return null;
    final tail = path[corners[0]];
    final tip = path[corners[1]];
    final shaft = tip - tail;
    final length = shaft.length;
    if (_farthestFrom(path, corners[0], corners[1]).distance > length / 12) {
      return null;
    }
    final direction = shaft / length;
    var reach = 0.0;
    for (var i = corners[1]; i < path.length; i++) {
      final offset = path[i] - tip;
      if (offset.length > length / 2 || offset.dot(direction) > length / 8) {
        return null;
      }
      reach = math.max(reach, offset.length);
    }
    if (reach < length / 12) return null;
    return _straight(ShapeKind.arrow, tail, tip);
  }

  /// Two to four straight lines, end to end.
  static PathShape? _polyline(
    List<Vec2> path,
    List<int> corners,
    _Stroke stroke,
  ) {
    if (corners.length < 3 || corners.length > 5) return null;
    if (!_straightSides(path, corners, stroke, bow: _lineBow)) return null;
    return PathShape(
      ShapeKind.polyline,
      _levelled(<Vec2>[for (final corner in corners) path[corner]]),
    );
  }

  /// A closed outline: of straight sides if it has them, else an ellipse.
  static InkShape? _closedShape(List<Vec2> drawn, double size) {
    final path = _withoutOvershoot(drawn);
    final stroke = _Stroke(path);
    final corners = _cornersOf(
      <Vec2>[...path, path.first],
      0,
      path.length,
      size,
      closed: true,
    );
    final sides = corners.length;
    if (sides >= 3 && sides <= 8) {
      // Round from its first corner, so each side lies between two.
      final start = corners.first;
      final loop = <Vec2>[
        ...path.sublist(start),
        ...path.sublist(0, start),
        path[start],
      ];
      final shifted = <int>[for (final corner in corners) corner - start];
      if (_straightSides(
        loop,
        shifted,
        stroke,
        bow: _outlineBow,
        closed: true,
      )) {
        final points = <Vec2>[for (final corner in corners) path[corner]];
        return (sides == 4 ? _rectangle(points) : null) ?? _polygon(points);
      }
    }
    return _ellipse(path, stroke);
  }

  /// [path] cut where it comes back nearest its start, so a stroke drawn
  /// round a little past where it began closes where it began.
  static List<Vec2> _withoutOvershoot(List<Vec2> path) {
    final start = path.first;
    var end = path.length - 1;
    for (var i = (path.length * 0.7).floor(); i < path.length; i++) {
      if (path[i].distanceTo(start) < path[end].distanceTo(start)) end = i;
    }
    return path.sublist(0, end + 1);
  }

  static PathShape _polygon(List<Vec2> corners) =>
      PathShape(ShapeKind.polygon, _levelled(corners, closed: true));

  /// Four corners at right angles, near enough, as a rectangle — upright
  /// if it nearly is, a square if its sides nearly match.
  static BoxShape? _rectangle(List<Vec2> corners) {
    final sides = <Vec2>[
      for (var i = 0; i < 4; i++) corners[(i + 1) % 4] - corners[i],
    ];
    for (var i = 0; i < 4; i++) {
      final turn = _turn(sides[i], sides[(i + 1) % 4]);
      if ((turn - math.pi / 2).abs() > 12 * math.pi / 180) return null;
    }
    // The sides' way, as a quarter turn: each side's angle four times over
    // points the same way for all four.
    var sum = const Vec2.zero();
    for (final side in sides) {
      sum += Vec2(1, 0).rotated(4 * side.angle) * side.length;
    }
    var angle = sum.angle / 4;
    if (angle.abs() < 7 * math.pi / 180) angle = 0;
    final centre = corners.reduce((a, b) => a + b) / corners.length.toDouble();
    final local = <Vec2>[
      for (final corner in corners) (corner - centre).rotated(-angle),
    ];
    double meanOf(Iterable<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final xs = local.map((point) => point.x).toList()..sort();
    final ys = local.map((point) => point.y).toList()..sort();
    var left = meanOf(xs.take(2));
    var right = meanOf(xs.skip(2));
    var top = meanOf(ys.take(2));
    var bottom = meanOf(ys.skip(2));
    final width = right - left;
    final height = bottom - top;
    final square = (width - height).abs() <= 0.12 * math.max(width, height);
    if (square) {
      final side = (width + height) / 2;
      final middle = Vec2((left + right) / 2, (top + bottom) / 2);
      left = middle.x - side / 2;
      right = middle.x + side / 2;
      top = middle.y - side / 2;
      bottom = middle.y + side / 2;
    }
    return BoxShape(
      square ? ShapeKind.square : ShapeKind.rectangle,
      origin: centre + Vec2(left, top).rotated(angle),
      size: Vec2(right - left, bottom - top),
      angle: angle,
    );
  }

  /// The ellipse [path] runs round once, near enough — upright if it
  /// nearly is, a circle if it is nearly round.
  static BoxShape? _ellipse(List<Vec2> path, _Stroke stroke) {
    final points = stroke.resampled(64);
    final centre = points.reduce((a, b) => a + b) / points.length.toDouble();
    var xx = 0.0;
    var xy = 0.0;
    var yy = 0.0;
    for (final point in points) {
      final offset = point - centre;
      xx += offset.x * offset.x;
      xy += offset.x * offset.y;
      yy += offset.y * offset.y;
    }
    var angle = 0.5 * math.atan2(2 * xy, xx - yy);
    // The radii that fit best along those axes: the least squares of
    // (u/a)² + (v/b)² = 1, which is linear in 1/a² and 1/b².
    var uuuu = 0.0;
    var uuvv = 0.0;
    var vvvv = 0.0;
    var uu = 0.0;
    var vv = 0.0;
    final local = <Vec2>[
      for (final point in points) (point - centre).rotated(-angle),
    ];
    for (final point in local) {
      final u2 = point.x * point.x;
      final v2 = point.y * point.y;
      uuuu += u2 * u2;
      uuvv += u2 * v2;
      vvvv += v2 * v2;
      uu += u2;
      vv += v2;
    }
    final determinant = uuuu * vvvv - uuvv * uuvv;
    if (determinant <= 0) return null;
    final p = (uu * vvvv - vv * uuvv) / determinant;
    final q = (vv * uuuu - uu * uuvv) / determinant;
    if (p <= 0 || q <= 0) return null;
    var a = 1 / math.sqrt(p);
    var b = 1 / math.sqrt(q);
    var misfit = 0.0;
    for (final point in local) {
      misfit += (math.sqrt(p * point.x * point.x + q * point.y * point.y) - 1)
          .abs();
    }
    if (misfit / local.length > 0.08) return null;
    // Round more than once is a spiral, not an ellipse.
    var swept = 0.0;
    for (var i = 1; i < local.length; i++) {
      swept += _turn(local[i - 1], local[i]);
    }
    if (swept > 2.4 * math.pi) return null;

    final circle = math.min(a, b) / math.max(a, b) >= 0.85;
    if (circle) {
      a = b = (a + b) / 2;
      angle = 0;
    } else {
      final quarter = (angle / (math.pi / 2)).roundToDouble();
      if ((angle - quarter * math.pi / 2).abs() < 10 * math.pi / 180) {
        if (quarter.toInt().isOdd) (a, b) = (b, a);
        angle = 0;
      }
    }
    return BoxShape(
      circle ? ShapeKind.circle : ShapeKind.ellipse,
      origin: centre - Vec2(a, b).rotated(angle),
      size: Vec2(2 * a, 2 * b),
      angle: angle,
    );
  }

  /// The indices of [path]'s corners from [from] to [to], ends included:
  /// where it turns, found by leaving out every point nearer the lines
  /// between those kept than a twentieth of its [size], then every corner
  /// it barely turns at. A [closed] path has no ends, only corners.
  static List<int> _cornersOf(
    List<Vec2> path,
    int from,
    int to,
    double size, {
    bool closed = false,
  }) {
    final tolerance = math.max(size / 20, 2.0);
    final corners = <int>[from];
    if (closed) {
      // A loop splits first at the point farthest from its start.
      var farthest = from;
      for (var i = from; i <= to; i++) {
        if (path[i].distanceTo(path[from]) >
            path[farthest].distanceTo(path[from])) {
          farthest = i;
        }
      }
      _simplify(path, from, farthest, tolerance, corners);
      corners.add(farthest);
      _simplify(path, farthest, to, tolerance, corners);
    } else {
      _simplify(path, from, to, tolerance, corners);
      corners.add(to);
    }
    // Corners it barely turns at, and those crowded together, go, the
    // slightest first; a closed path's start is a corner like any other.
    final perimeter = _Stroke(path).length;
    while (corners.length > (closed ? 3 : 2)) {
      var slightest = -1;
      var least = double.infinity;
      final first = closed ? 0 : 1;
      final last = closed ? corners.length - 1 : corners.length - 2;
      for (var i = first; i <= last; i++) {
        final before = path[corners[(i - 1) % corners.length]];
        final at = path[corners[i]];
        final after = path[corners[(i + 1) % corners.length]];
        final turn = _turn(at - before, after - at);
        final crowded =
            math.min(at.distanceTo(before), at.distanceTo(after)) <
            perimeter / 16;
        final weight = crowded ? turn / 4 : turn;
        if (weight < least) {
          least = weight;
          slightest = i;
        }
      }
      if (least >= _slightest) break;
      corners.removeAt(slightest);
    }
    return corners;
  }

  /// Adds to [out] the indices between [from] and [to] of the points kept
  /// by Douglas and Peucker's simplification with [tolerance].
  static void _simplify(
    List<Vec2> path,
    int from,
    int to,
    double tolerance,
    List<int> out,
  ) {
    final farthest = _farthestFrom(path, from, to);
    if (farthest.distance <= tolerance) return;
    _simplify(path, from, farthest.index, tolerance, out);
    out.add(farthest.index);
    _simplify(path, farthest.index, to, tolerance, out);
  }

  /// Whether the path between each corner and the next is straight: bowed
  /// by no more than [bow] of the side's length, and the side no shorter
  /// than a twentieth of the whole. A [closed] path's last side runs from
  /// its last corner round to its end, where it began.
  static bool _straightSides(
    List<Vec2> path,
    List<int> corners,
    _Stroke stroke, {
    required double bow,
    bool closed = false,
  }) {
    final ends = <int>[...corners, if (closed) path.length - 1];
    for (var i = 0; i + 1 < ends.length; i++) {
      final side = path[ends[i]].distanceTo(path[ends[i + 1]]);
      if (side < stroke.length / 20) return false;
      if (_farthestFrom(path, ends[i], ends[i + 1]).distance > bow * side) {
        return false;
      }
    }
    return true;
  }

  /// [corners] with every side nearly level or upright made so: each such
  /// side's ends meet halfway.
  static List<Vec2> _levelled(List<Vec2> corners, {bool closed = false}) {
    final levelled = List<Vec2>.of(corners);
    final sides = closed ? corners.length : corners.length - 1;
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % corners.length;
      final side = levelled[j] - levelled[i];
      final angle = side.angle.abs();
      if (angle < _level || (math.pi - angle) < _level) {
        final y = (levelled[i].y + levelled[j].y) / 2;
        levelled[i] = Vec2(levelled[i].x, y);
        levelled[j] = Vec2(levelled[j].x, y);
      } else if ((angle - math.pi / 2).abs() < _level) {
        final x = (levelled[i].x + levelled[j].x) / 2;
        levelled[i] = Vec2(x, levelled[i].y);
        levelled[j] = Vec2(x, levelled[j].y);
      }
    }
    return levelled;
  }

  /// How far, in radians, the way turns from [before] to [after].
  static double _turn(Vec2 before, Vec2 after) {
    if (before.length == 0 || after.length == 0) return 0;
    return math.atan2(before.cross(after).abs(), before.dot(after));
  }

  /// The point of [path] strictly between [from] and [to] farthest from
  /// the line between them, and how far.
  static ({int index, double distance}) _farthestFrom(
    List<Vec2> path,
    int from,
    int to,
  ) {
    var index = from;
    var distance = 0.0;
    for (var i = from + 1; i < to; i++) {
      final away = _distanceToSegment(path[i], path[from], path[to]);
      if (away > distance) {
        distance = away;
        index = i;
      }
    }
    return (index: index, distance: distance);
  }

  static double _distanceToSegment(Vec2 point, Vec2 a, Vec2 b) {
    final along = b - a;
    final lengthSquared = along.dot(along);
    final t = lengthSquared == 0
        ? 0.0
        : ((point - a).dot(along) / lengthSquared).clamp(0.0, 1.0);
    return point.distanceTo(a + along * t);
  }
}

/// A stroke's points, and what is measured of them.
class _Stroke {
  _Stroke(this.points);

  final List<Vec2> points;

  /// How long it is, end to end along it.
  late final double length = () {
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += points[i - 1].distanceTo(points[i]);
    }
    return length;
  }();

  /// How far across its box it is, corner to corner.
  late final double size = () {
    final xs = points.map((point) => point.x);
    final ys = points.map((point) => point.y);
    return Vec2(
      xs.reduce(math.max) - xs.reduce(math.min),
      ys.reduce(math.max) - ys.reduce(math.min),
    ).length;
  }();

  /// [count] points spaced evenly along it, so each part of it counts for
  /// as much as it is long, however fast it was drawn.
  List<Vec2> resampled(int count) {
    final step = length / count;
    if (step == 0) return <Vec2>[points.first];
    final out = <Vec2>[points.first];
    var carried = 0.0;
    for (var i = 1; i < points.length && out.length < count; i++) {
      var from = points[i - 1];
      final to = points[i];
      var remaining = from.distanceTo(to);
      while (carried + remaining >= step && out.length < count) {
        final point = from + (to - from).unit * (step - carried);
        out.add(point);
        remaining -= step - carried;
        from = point;
        carried = 0;
      }
      carried += remaining;
    }
    return out;
  }
}
