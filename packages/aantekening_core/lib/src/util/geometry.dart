/// Framework-free geometry primitives shared by the model and the renderer.
library;

import 'dart:math' as math;

/// An immutable 2-D point or vector, in page-space logical pixels.
class Vec2 {
  const Vec2(this.x, this.y);

  const Vec2.zero() : x = 0, y = 0;

  final double x;
  final double y;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
  Vec2 operator *(double factor) => Vec2(x * factor, y * factor);
  Vec2 operator /(double divisor) => Vec2(x / divisor, y / divisor);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(Vec2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  List<double> toJson() => <double>[x, y];

  static Vec2 fromJson(List<Object?> json) => Vec2(
    (json.isNotEmpty ? json[0] as num : 0).toDouble(),
    (json.length > 1 ? json[1] as num : 0).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';
}

/// An axis-aligned bounding box.
///
/// The canvas uses these for viewport culling and for the spatial index, so the
/// hot methods ([intersects], [contains]) are deliberately branch-light and
/// allocation-free.
class Aabb {
  const Aabb(this.left, this.top, this.right, this.bottom);

  /// An empty box positioned so that [union] with it is the identity.
  static const Aabb empty = Aabb(
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );

  factory Aabb.fromLTWH(double left, double top, double width, double height) =>
      Aabb(left, top, left + width, top + height);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  bool get isEmpty => right <= left || bottom <= top;

  bool intersects(Aabb other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;

  bool containsPoint(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  bool containsBox(Aabb other) =>
      other.left >= left &&
      other.right <= right &&
      other.top >= top &&
      other.bottom <= bottom;

  Aabb union(Aabb other) => Aabb(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  Aabb inflate(double amount) =>
      Aabb(left - amount, top - amount, right + amount, bottom + amount);

  Aabb translate(double dx, double dy) =>
      Aabb(left + dx, top + dy, right + dx, bottom + dy);

  @override
  bool operator ==(Object other) =>
      other is Aabb &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Aabb($left, $top, $right, $bottom)';
}

/// The placement of an element on the infinite canvas.
///
/// Rotation is stored in radians and applied about the frame's centre.
class Frame {
  const Frame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  const Frame.origin(this.width, this.height) : x = 0, y = 0, rotation = 0;

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;

  /// The un-rotated bounding box.
  Aabb get bounds => Aabb(x, y, x + width, y + height);

  /// The bounding box after [rotation] is applied, used for culling.
  Aabb get rotatedBounds {
    if (rotation == 0) return bounds;
    final cx = x + width / 2;
    final cy = y + height / 2;
    final cos = math.cos(rotation).abs();
    final sin = math.sin(rotation).abs();
    final halfW = (width * cos + height * sin) / 2;
    final halfH = (width * sin + height * cos) / 2;
    return Aabb(cx - halfW, cy - halfH, cx + halfW, cy + halfH);
  }

  Frame copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) => Frame(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
  );

  Frame translate(double dx, double dy) => copyWith(x: x + dx, y: y + dy);

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (rotation != 0) 'rotation': rotation,
  };

  static Frame fromJson(Map<String, Object?> json) => Frame(
    x: _num(json['x']),
    y: _num(json['y']),
    width: _num(json['width']),
    height: _num(json['height']),
    rotation: _num(json['rotation']),
  );

  static double _num(Object? value) => value is num ? value.toDouble() : 0;

  @override
  bool operator ==(Object other) =>
      other is Frame &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(x, y, width, height, rotation);

  @override
  String toString() => 'Frame($x, $y, ${width}x$height, rot=$rotation)';
}
