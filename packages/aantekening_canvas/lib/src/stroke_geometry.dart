/// Turning sampled ink into paintable geometry.
library;

import 'dart:math' as math;

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
    for (var i = 0; i < count - 1; i++) {
      final x0 = stroke.xAt(i);
      final y0 = stroke.yAt(i);
      final x1 = stroke.xAt(i + 1);
      final y1 = stroke.yAt(i + 1);
      corners[0] = Offset(x0 - halfThickness, y0 - halfHeight);
      corners[1] = Offset(x0 + halfThickness, y0 - halfHeight);
      corners[2] = Offset(x0 + halfThickness, y0 + halfHeight);
      corners[3] = Offset(x0 - halfThickness, y0 + halfHeight);
      corners[4] = Offset(x1 - halfThickness, y1 - halfHeight);
      corners[5] = Offset(x1 + halfThickness, y1 - halfHeight);
      corners[6] = Offset(x1 + halfThickness, y1 + halfHeight);
      corners[7] = Offset(x1 - halfThickness, y1 + halfHeight);
      path.addPolygon(_convexHull(corners), true);
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
