/// A loop drawn round what is to be selected.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';

/// The loop a lasso is drawn as, in page space: closed by a straight line
/// from where it ends back to where it began.
@immutable
class Lasso {
  Lasso(Offset start)
    : points = List<Offset>.unmodifiable(<Offset>[start]),
      bounds = Aabb(start.dx, start.dy, start.dx, start.dy);

  const Lasso._(this.points, this.bounds);

  final List<Offset> points;

  /// The box about the loop.
  final Aabb bounds;

  /// The loop drawn on to [point].
  Lasso extendedTo(Offset point) => Lasso._(
    List<Offset>.unmodifiable(<Offset>[...points, point]),
    Aabb(
      math.min(bounds.left, point.dx),
      math.min(bounds.top, point.dy),
      math.max(bounds.right, point.dx),
      math.max(bounds.bottom, point.dy),
    ),
  );

  /// Whether ([x], [y]) lies inside the loop. Where it crosses itself, a
  /// point inside twice over is outside, as a loop drawn round it and back
  /// leaves it.
  bool containsPoint(double x, double y) {
    if (!bounds.containsPoint(x, y)) return false;
    var inside = false;
    var previous = points.last;
    for (final point in points) {
      if ((point.dy > y) != (previous.dy > y) &&
          x <
              (previous.dx - point.dx) *
                      (y - point.dy) /
                      (previous.dy - point.dy) +
                  point.dx) {
        inside = !inside;
      }
      previous = point;
    }
    return inside;
  }
}
