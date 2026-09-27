/// Turning sampled ink into paintable geometry.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/rendering.dart';

/// Builds paths and widths from raw stroke samples.
abstract final class StrokeGeometry {
  /// Pressure readings closer together than this are treated as constant.
  static const double pressureEpsilon = 0.08;

  /// How much pressure is allowed to change a stroke's nominal width.
  ///
  /// A light touch thins the line to 40% and a firm one thickens it to 140%,
  /// which is enough to read as handwriting without the stroke breaking up.
  static const double minPressureScale = 0.4;
  static const double maxPressureScale = 1.4;

  /// Builds a smoothed path through a stroke's samples.
  ///
  /// Consecutive samples are joined with quadratic segments that pass through
  /// their midpoints. Raw pointer samples are noisy and unevenly spaced, and
  /// drawing them as straight segments shows every jitter; this costs one
  /// quadratic per sample and removes almost all of it.
  static Path smoothPath(InkStroke stroke) {
    final path = Path();
    final count = stroke.pointCount;
    if (count == 0) return path;

    if (count == 1) {
      // A tap still leaves a mark.
      final radius = stroke.width / 2;
      path.addOval(
        Rect.fromCircle(
          center: Offset(stroke.xAt(0), stroke.yAt(0)),
          radius: radius <= 0 ? 0.5 : radius,
        ),
      );
      return path;
    }

    path.moveTo(stroke.xAt(0), stroke.yAt(0));
    if (count == 2) {
      path.lineTo(stroke.xAt(1), stroke.yAt(1));
      return path;
    }

    for (var i = 1; i < count - 1; i++) {
      final midX = (stroke.xAt(i) + stroke.xAt(i + 1)) / 2;
      final midY = (stroke.yAt(i) + stroke.yAt(i + 1)) / 2;
      path.quadraticBezierTo(stroke.xAt(i), stroke.yAt(i), midX, midY);
    }
    path.lineTo(stroke.xAt(count - 1), stroke.yAt(count - 1));
    return path;
  }

  /// Whether the stroke's pressure varies enough to be worth drawing
  /// segment by segment rather than as one constant-width path.
  static bool hasPressureVariation(InkStroke stroke) {
    final count = stroke.pointCount;
    if (count < 2) return false;

    var minimum = stroke.pressureAt(0);
    var maximum = minimum;
    for (var i = 1; i < count; i++) {
      final pressure = stroke.pressureAt(i);
      if (pressure < minimum) minimum = pressure;
      if (pressure > maximum) maximum = pressure;
      if (maximum - minimum > pressureEpsilon) return true;
    }
    return false;
  }

  /// The sharpest turn, as the cosine of its angle, a run of a
  /// [pressurePath] goes round; a sharper one ends the run there, and the
  /// round ends of the two runs make the corner round.
  static const double _sharpestTurn = 0.866;

  /// How near to the sample before, as a share of the stroke's half-width
  /// there, a sample is taken as the same one: it would change nothing that
  /// can be seen, and add to what is drawn every frame.
  static const double _sameSample = 0.3;

  /// The area a stroke whose width follows its pressure covers, as one
  /// filled path.
  ///
  /// Drawn as a line of its own width between each two samples, a page of
  /// handwriting took tens of thousands of draws, every frame. Here each side
  /// is offset by half the width at every sample, with round ends. A sharp
  /// turn ends one run and starts the next, so the sides never cross there,
  /// and the round ends meeting make the corner round. Every run is wound the
  /// same way, so where runs overlap the fill is their union.
  static Path pressurePath(InkStroke stroke) {
    final path = Path();
    final count = stroke.pointCount;
    if (count == 0) return path;

    final xs = <double>[];
    final ys = <double>[];
    final radii = <double>[];
    for (var i = 0; i < count; i++) {
      final x = stroke.xAt(i);
      final y = stroke.yAt(i);
      final radius = math.max(widthAt(stroke, i) / 2, 0.25);
      final near = math.max(radius * _sameSample, 0.01);
      if (xs.isNotEmpty &&
          (x - xs.last).abs() < near &&
          (y - ys.last).abs() < near) {
        radii.last = math.max(radii.last, radius);
        continue;
      }
      xs.add(x);
      ys.add(y);
      radii.add(radius);
    }
    if (xs.length == 1) {
      return path..addOval(
        Rect.fromCircle(center: Offset(xs[0], ys[0]), radius: radii[0]),
      );
    }

    // The unit direction of each step, from sample i to i + 1.
    final steps = xs.length - 1;
    final dxs = Float64List(steps);
    final dys = Float64List(steps);
    for (var i = 0; i < steps; i++) {
      final dx = xs[i + 1] - xs[i];
      final dy = ys[i + 1] - ys[i];
      final length = math.sqrt(dx * dx + dy * dy);
      dxs[i] = dx / length;
      dys[i] = dy / length;
    }

    void run(int first, int last) {
      final left = <Offset>[];
      final right = <Offset>[];
      for (var i = first; i <= last; i++) {
        // The left of the direction of travel, bisecting the turn at a
        // sample within the run and lengthened so the sides stay a width
        // apart round it.
        var nx = 0.0;
        var ny = 0.0;
        if (i > first) {
          nx += dys[i - 1];
          ny -= dxs[i - 1];
        }
        if (i < last) {
          nx += dys[i];
          ny -= dxs[i];
        }
        final length = math.sqrt(nx * nx + ny * ny);
        final inner = i > first && i < last;
        final reach = radii[i] * (inner ? 2 / (length * length) : 1 / length);
        left.add(Offset(xs[i] + nx * reach, ys[i] + ny * reach));
        right.add(Offset(xs[i] - nx * reach, ys[i] - ny * reach));
      }
      path.moveTo(left.first.dx, left.first.dy);
      for (var i = 1; i < left.length; i++) {
        path.lineTo(left[i].dx, left[i].dy);
      }
      _roundEnd(
        path,
        left.last,
        right.last,
        dxs[last - 1],
        dys[last - 1],
        radii[last],
      );
      for (var i = right.length - 2; i >= 0; i--) {
        path.lineTo(right[i].dx, right[i].dy);
      }
      _roundEnd(
        path,
        right.first,
        left.first,
        -dxs[first],
        -dys[first],
        radii[first],
      );
      path.close();
    }

    var first = 0;
    for (var i = 1; i < steps; i++) {
      final turn = dxs[i - 1] * dxs[i] + dys[i - 1] * dys[i];
      if (turn < _sharpestTurn) {
        run(first, i);
        first = i;
      }
    }
    run(first, steps);
    return path;
  }

  /// Half a circle of [radius] from [from] to [to], bulging along [dx],
  /// [dy]: two quarters, each a conic, which is a circle exactly and cheaper
  /// to draw than an arc.
  static void _roundEnd(
    Path path,
    Offset from,
    Offset to,
    double dx,
    double dy,
    double radius,
  ) {
    final bulge = Offset(dx * radius, dy * radius);
    final tip = (from + to) / 2 + bulge;
    final corner = from + bulge;
    final other = to + bulge;
    path
      ..conicTo(corner.dx, corner.dy, tip.dx, tip.dy, math.sqrt1_2)
      ..conicTo(other.dx, other.dy, to.dx, to.dy, math.sqrt1_2);
  }

  /// The drawn width at sample [index].
  static double widthAt(InkStroke stroke, int index) {
    final pressure = stroke.pressureAt(index).clamp(0.0, 1.0);
    final scale =
        minPressureScale + (maxPressureScale - minPressureScale) * pressure;
    return stroke.width * scale;
  }

  /// How thick a chisel nib is, relative to its height.
  static const double chiselThicknessRatio = 0.16;

  /// The area a chisel nib sweeps along a stroke: a thin upright line, the
  /// way a highlighter marker's flat tip is held.
  ///
  /// A horizontal stroke is as tall as the nib and a vertical one as thin as
  /// its edge. Each step between samples adds the convex hull of the nib at
  /// both ends, all wound the same way, so the filled path is their union and
  /// a stroke never darkens where it crosses itself.
  static Path chiselPath(InkStroke stroke) {
    final path = Path()..fillType = PathFillType.nonZero;
    final count = stroke.pointCount;
    if (count == 0) return path;

    final halfHeight = stroke.width / 2;
    final halfThickness = math.max(
      0.75,
      stroke.width * chiselThicknessRatio / 2,
    );

    if (count == 1) {
      path.addRect(
        Rect.fromCenter(
          center: Offset(stroke.xAt(0), stroke.yAt(0)),
          width: halfThickness * 2,
          height: halfHeight * 2,
        ),
      );
      return path;
    }

    final corners = List<Offset>.filled(8, Offset.zero);
    // Samples nearer together than the nib is thick are passed over: the
    // nib's sweep between those either side covers them.
    var x0 = stroke.xAt(0);
    var y0 = stroke.yAt(0);
    for (var i = 1; i < count; i++) {
      final x1 = stroke.xAt(i);
      final y1 = stroke.yAt(i);
      if (i < count - 1 &&
          (x1 - x0).abs() < halfThickness &&
          (y1 - y0).abs() < halfThickness) {
        continue;
      }
      corners[0] = Offset(x0 - halfThickness, y0 - halfHeight);
      corners[1] = Offset(x0 + halfThickness, y0 - halfHeight);
      corners[2] = Offset(x0 + halfThickness, y0 + halfHeight);
      corners[3] = Offset(x0 - halfThickness, y0 + halfHeight);
      corners[4] = Offset(x1 - halfThickness, y1 - halfHeight);
      corners[5] = Offset(x1 + halfThickness, y1 - halfHeight);
      corners[6] = Offset(x1 + halfThickness, y1 + halfHeight);
      corners[7] = Offset(x1 - halfThickness, y1 + halfHeight);
      path.addPolygon(_convexHull(corners), true);
      x0 = x1;
      y0 = y1;
    }
    return path;
  }

  /// The convex hull of [points], counter-clockwise (Andrew's monotone chain).
  static List<Offset> _convexHull(List<Offset> points) {
    final sorted = List<Offset>.of(points)
      ..sort(
        (a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy),
      );
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <Offset>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    return <Offset>[
      ...lower.sublist(0, lower.length - 1),
      ...upper.sublist(0, upper.length - 1),
    ];
  }
}
