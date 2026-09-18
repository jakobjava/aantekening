/// The digital-ink model: pressure-sensitive strokes captured from a stylus,
/// mouse or finger.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../util/geometry.dart';
import '../util/json_read.dart';

/// The drawing instrument a stroke was made with.
///
/// The tool determines how the stroke is painted (opacity, blend mode, width
/// response to pressure) but not its geometry, so changing a stroke's tool
/// after the fact never resamples its points.
enum InkTool {
  /// Opaque, pressure-sensitive line.
  pen,

  /// Translucent, constant-width line drawn beneath other ink.
  highlighter,

  /// Textured line whose opacity follows pressure.
  pencil,

  /// Opaque, constant-width line.
  marker,
}

/// A single continuous stroke.
///
/// Points are held in one [Float32List] rather than a list of objects: a long
/// handwritten page can hold hundreds of thousands of samples, and a flat
/// buffer keeps them in contiguous memory, avoids per-point allocation, and can
/// be handed to the renderer without a copy.
class InkStroke {
  InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  /// Builds a stroke from separate coordinate lists, padding the optional
  /// channels when the input device does not report them.
  factory InkStroke.fromPoints({
    required InkTool tool,
    required int color,
    required double width,
    required List<double> xs,
    required List<double> ys,
    List<double>? pressures,
    List<double>? tilts,
  }) {
    final count = math.min(xs.length, ys.length);
    final buffer = Float32List(count * stride);
    for (var i = 0; i < count; i++) {
      final base = i * stride;
      buffer[base] = xs[i];
      buffer[base + 1] = ys[i];
      buffer[base + 2] = (pressures != null && i < pressures.length)
          ? pressures[i]
          : 1.0;
      buffer[base + 3] = (tilts != null && i < tilts.length) ? tilts[i] : 0.0;
    }
    return InkStroke(tool: tool, color: color, width: width, points: buffer);
  }

  /// Number of floats per sample: x, y, pressure, tilt.
  static const int stride = 4;

  final InkTool tool;

  /// Stroke colour as a 32-bit ARGB value.
  final int color;

  /// Nominal stroke width in page-space pixels, before pressure is applied.
  final double width;

  /// Flat sample buffer of `[x, y, pressure, tilt]` tuples.
  final Float32List points;

  Aabb? _bounds;

  /// Number of samples in the stroke.
  int get pointCount => points.length ~/ stride;

  double xAt(int index) => points[index * stride];
  double yAt(int index) => points[index * stride + 1];
  double pressureAt(int index) => points[index * stride + 2];
  double tiltAt(int index) => points[index * stride + 3];

  /// The stroke's bounding box, inflated by half the maximum drawn width.
  ///
  /// Computed once and cached; the canvas queries this on every frame for
  /// culling.
  Aabb get bounds {
    final cached = _bounds;
    if (cached != null) return cached;

    if (pointCount == 0) {
      return _bounds = Aabb.empty;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (var i = 0; i < points.length; i += stride) {
      final x = points[i];
      final y = points[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final pad = width / 2 + 1;
    return _bounds = Aabb(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  /// Returns a copy translated by ([dx], [dy]).
  InkStroke translate(double dx, double dy) {
    final moved = Float32List.fromList(points);
    for (var i = 0; i < moved.length; i += stride) {
      moved[i] += dx;
      moved[i + 1] += dy;
    }
    return InkStroke(tool: tool, color: color, width: width, points: moved);
  }

  /// Returns a copy scaled about ([originX], [originY]).
  ///
  /// Width scales with the average of the two axes so that a stroke stays
  /// visually proportional under non-uniform scaling.
  InkStroke scale(
    double scaleX,
    double scaleY, {
    double originX = 0,
    double originY = 0,
  }) {
    final scaled = Float32List.fromList(points);
    for (var i = 0; i < scaled.length; i += stride) {
      scaled[i] = originX + (scaled[i] - originX) * scaleX;
      scaled[i + 1] = originY + (scaled[i + 1] - originY) * scaleY;
    }
    return InkStroke(
      tool: tool,
      color: color,
      width: width * (scaleX.abs() + scaleY.abs()) / 2,
      points: scaled,
    );
  }

  /// Whether the drawn line passes within [radius] of ([x], [y]).
  ///
  /// Used by the stroke eraser, which deletes whole strokes rather than
  /// splitting them.
  ///
  /// Distance is measured to the segments between samples, not just to the
  /// samples themselves. A line drawn quickly can leave its samples tens of
  /// pixels apart, and testing only those would let the eraser pass straight
  /// through the middle of a visible stroke.
  bool hitTest(double x, double y, double radius) {
    if (!bounds.inflate(radius).containsPoint(x, y)) return false;

    final threshold = radius + width / 2;
    final thresholdSquared = threshold * threshold;
    final count = pointCount;
    if (count == 0) return false;

    if (count == 1) {
      final dx = xAt(0) - x;
      final dy = yAt(0) - y;
      return dx * dx + dy * dy <= thresholdSquared;
    }

    for (var i = 0; i < count - 1; i++) {
      final distanceSquared = _distanceSquaredToSegment(
        x,
        y,
        xAt(i),
        yAt(i),
        xAt(i + 1),
        yAt(i + 1),
      );
      if (distanceSquared <= thresholdSquared) return true;
    }
    return false;
  }

  /// Squared distance from ([px], [py]) to the segment ([ax], [ay])-([bx], [by]).
  static double _distanceSquaredToSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abX = bx - ax;
    final abY = by - ay;
    final lengthSquared = abX * abX + abY * abY;

    // Projection parameter, clamped so the nearest point stays on the segment.
    final t = lengthSquared == 0
        ? 0.0
        : (((px - ax) * abX + (py - ay) * abY) / lengthSquared).clamp(0.0, 1.0);

    final dx = px - (ax + abX * t);
    final dy = py - (ay + abY * t);
    return dx * dx + dy * dy;
  }

  /// Serialises the stroke, rounding coordinates to two decimals.
  ///
  /// Sub-hundredth-of-a-pixel precision is not perceivable but costs roughly a
  /// third of the file size on ink-heavy pages.
  Map<String, Object?> toJson() {
    final flat = List<double>.filled(points.length, 0);
    for (var i = 0; i < points.length; i++) {
      flat[i] = _round2(points[i]);
    }
    return <String, Object?>{
      'tool': tool.name,
      'color': color,
      'width': width,
      'points': flat,
    };
  }

  static InkStroke fromJson(Map<String, Object?> json) {
    final flat = readDoubleList(json, 'points');
    // Tolerate a truncated final tuple rather than dropping the whole stroke.
    final usable = flat.length - (flat.length % stride);
    final buffer = Float32List(usable);
    for (var i = 0; i < usable; i++) {
      buffer[i] = flat[i];
    }
    return InkStroke(
      tool: readEnum(json, 'tool', InkTool.values, InkTool.pen),
      color: readInt(json, 'color', 0xFF000000),
      width: readDouble(json, 'width', 2),
      points: buffer,
    );
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;
}
