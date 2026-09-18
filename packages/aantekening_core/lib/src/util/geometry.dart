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

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  /// The four corners after rotation, clockwise from the top-left.
  List<Vec2> get corners {
    final toPage = localToPage;
    return <Vec2>[
      toPage.apply(0, 0),
      toPage.apply(width, 0),
      toPage.apply(width, height),
      toPage.apply(0, height),
    ];
  }

  /// Maps the frame's own coordinates — (0, 0) at its unrotated top-left
  /// corner — to page coordinates.
  Affine2D get localToPage =>
      Affine2D.translation(centerX, centerY) *
      Affine2D.rotation(rotation) *
      Affine2D.translation(-width / 2, -height / 2);

  /// Maps a page point to the frame's own coordinates, (0, 0) at its
  /// unrotated top-left corner: the inverse of [localToPage].
  Vec2 pageToLocal(double px, double py) {
    final dx = px - centerX;
    final dy = py - centerY;
    if (rotation == 0) return Vec2(dx + width / 2, dy + height / 2);
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return Vec2(
      dx * cos + dy * sin + width / 2,
      -dx * sin + dy * cos + height / 2,
    );
  }

  /// This frame at [newWidth] × [newHeight], with its top-left corner — where
  /// its content starts — where it was, turned or not.
  ///
  /// Changing the size of a turned frame through [copyWith] keeps [x] and [y],
  /// the corner of the frame before it is turned; turned about the new centre,
  /// that moves the whole frame.
  Frame resizedFromTopLeft(double newWidth, double newHeight) {
    if (rotation == 0) return copyWith(width: newWidth, height: newHeight);
    final corner = localToPage.apply(0, 0);
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final cx = corner.x + newWidth / 2 * cos - newHeight / 2 * sin;
    final cy = corner.y + newWidth / 2 * sin + newHeight / 2 * cos;
    return Frame(
      x: cx - newWidth / 2,
      y: cy - newHeight / 2,
      width: newWidth,
      height: newHeight,
      rotation: rotation,
    );
  }

  /// Whether the page point ([px], [py]) lies inside the rotated frame, or
  /// within [slop] of it.
  bool containsPoint(double px, double py, {double slop = 0}) {
    var lx = px - centerX;
    var ly = py - centerY;
    if (rotation != 0) {
      final cos = math.cos(-rotation);
      final sin = math.sin(-rotation);
      final rx = lx * cos - ly * sin;
      final ry = lx * sin + ly * cos;
      lx = rx;
      ly = ry;
    }
    return lx.abs() <= width / 2 + slop && ly.abs() <= height / 2 + slop;
  }

  /// A frame of the same size whose centre is at ([cx], [cy]).
  Frame centeredAt(double cx, double cy) =>
      copyWith(x: cx - width / 2, y: cy - height / 2);

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

/// A 2-D affine transform: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`.
///
/// Used to move, scale and rotate content whose geometry is absolute, such as
/// ink, where a transform has to be baked into the samples rather than applied
/// when painting.
class Affine2D {
  const Affine2D(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const Affine2D identity = Affine2D(1, 0, 0, 1, 0, 0);

  factory Affine2D.translation(double dx, double dy) =>
      Affine2D(1, 0, 0, 1, dx, dy);

  factory Affine2D.scaling(double sx, double sy) =>
      Affine2D(sx, 0, 0, sy, 0, 0);

  /// A clockwise rotation by [radians] about the origin, in screen
  /// orientation where y points down.
  factory Affine2D.rotation(double radians) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Affine2D(cos, sin, -sin, cos, 0, 0);
  }

  /// Scaling by ([sx], [sy]) that keeps ([px], [py]) fixed.
  factory Affine2D.scalingAbout(double sx, double sy, double px, double py) =>
      Affine2D.translation(px, py) *
      Affine2D.scaling(sx, sy) *
      Affine2D.translation(-px, -py);

  /// Rotation by [radians] about ([px], [py]).
  factory Affine2D.rotationAbout(double radians, double px, double py) =>
      Affine2D.translation(px, py) *
      Affine2D.rotation(radians) *
      Affine2D.translation(-px, -py);

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  Vec2 apply(double x, double y) =>
      Vec2(a * x + c * y + tx, b * x + d * y + ty);

  /// How much the transform scales lengths, on average over directions.
  double get meanScale => math.sqrt((a * d - b * c).abs());

  /// The transform that applies [other] first, then this one.
  Affine2D operator *(Affine2D other) => Affine2D(
    a * other.a + c * other.b,
    b * other.a + d * other.b,
    a * other.c + c * other.d,
    b * other.c + d * other.d,
    a * other.tx + c * other.ty + tx,
    b * other.tx + d * other.ty + ty,
  );

  @override
  bool operator ==(Object other) =>
      other is Affine2D &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Affine2D($a, $b, $c, $d, $tx, $ty)';
}
