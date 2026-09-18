/// Turning sampled ink into paintable geometry.
library;

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
}
