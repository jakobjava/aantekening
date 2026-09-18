/// The painted layers of the canvas: paper, ink, wet ink and selection.
library;

import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import 'canvas_viewport.dart';
import 'stroke_geometry.dart';

/// Draws the paper and its ruling.
///
/// Lines are generated for the visible region only and drawn in screen space,
/// so the cost of the background is bounded by the window size rather than by
/// how far the user has panned.
class BackgroundPainter extends CustomPainter {
  const BackgroundPainter({
    required this.background,
    required this.viewport,
    this.paperWidth,
  });

  final PageBackground background;
  final CanvasViewport viewport;

  /// Optional page-width guide, in page units.
  final double? paperWidth;

  /// Below this on-screen spacing the ruling reads as a grey wash, so it is
  /// dropped rather than drawn.
  static const double minimumScreenSpacing = 6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(background.paperColor),
    );

    final spacing = background.spacing * viewport.zoom;
    if (background.kind != PageBackgroundKind.blank &&
        spacing >= minimumScreenSpacing) {
      final paint = Paint()
        ..color = Color(background.lineColor)
        ..strokeWidth = 1
        ..isAntiAlias = false;

      switch (background.kind) {
        case PageBackgroundKind.grid:
          _drawVerticals(canvas, size, spacing, paint);
          _drawHorizontals(canvas, size, spacing, paint);
        case PageBackgroundKind.ruled:
          _drawHorizontals(canvas, size, spacing, paint);
        case PageBackgroundKind.dotted:
          _drawDots(canvas, size, spacing, paint);
        case PageBackgroundKind.blank:
          break;
      }
    }

    _drawPaperGuide(canvas, size);
  }

  void _drawVerticals(Canvas canvas, Size size, double spacing, Paint paint) {
    final first = _firstLine(viewport.origin.dx, background.spacing);
    for (
      var x = viewport.toScreen(Offset(first, 0)).dx;
      x < size.width;
      x += spacing
    ) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawHorizontals(Canvas canvas, Size size, double spacing, Paint paint) {
    final first = _firstLine(viewport.origin.dy, background.spacing);
    for (
      var y = viewport.toScreen(Offset(0, first)).dy;
      y < size.height;
      y += spacing
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDots(Canvas canvas, Size size, double spacing, Paint paint) {
    final dot = Paint()
      ..color = Color(background.lineColor)
      ..style = PaintingStyle.fill;
    final radius = (viewport.zoom).clamp(0.6, 1.6);

    final firstX = _firstLine(viewport.origin.dx, background.spacing);
    final firstY = _firstLine(viewport.origin.dy, background.spacing);
    final startX = viewport.toScreen(Offset(firstX, 0)).dx;
    final startY = viewport.toScreen(Offset(0, firstY)).dy;

    for (var y = startY; y < size.height; y += spacing) {
      for (var x = startX; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dot);
      }
    }
  }

  /// Draws the optional right-hand margin that marks the printable width.
  void _drawPaperGuide(Canvas canvas, Size size) {
    final width = paperWidth;
    if (width == null) return;
    final x = viewport.toScreen(Offset(width, 0)).dx;
    if (x < 0 || x > size.width) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Color(background.lineColor)
        ..strokeWidth = 1,
    );
  }

  /// The first ruling position at or before the visible edge.
  static double _firstLine(double originInPageSpace, double spacing) =>
      (originInPageSpace / spacing).floor() * spacing;

  @override
  bool shouldRepaint(BackgroundPainter old) =>
      old.viewport != viewport ||
      old.paperWidth != paperWidth ||
      old.background.kind != background.kind ||
      old.background.spacing != background.spacing ||
      old.background.lineColor != background.lineColor ||
      old.background.paperColor != background.paperColor;
}

/// Draws committed ink strokes.
///
/// Ink is split into two layers around the widget-based elements: highlighter
/// under them, pen over them. That reproduces what the tools mean physically —
/// a highlighter goes beneath writing, a pen on top — while keeping the text
/// and formula elements as real widgets that can be edited and selected.
class InkPainter extends CustomPainter {
  InkPainter({
    required this.elements,
    required this.viewport,
    required this.layer,
    super.repaint,
  });

  final List<InkElement> elements;
  final CanvasViewport viewport;
  final InkLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    if (elements.isEmpty) return;

    final visible = viewport.visibleBounds(size);
    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);

    for (final element in elements) {
      if (!element.bounds.intersects(visible)) continue;
      for (final stroke in element.strokes) {
        if (layer.accepts(stroke.tool) && stroke.bounds.intersects(visible)) {
          paintStroke(canvas, stroke);
        }
      }
    }
    canvas.restore();
  }

  /// Paints one stroke in page space.
  static void paintStroke(Canvas canvas, InkStroke stroke) {
    final paint = Paint()
      ..color = Color(stroke.color)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (stroke.tool == InkTool.highlighter) {
      // Multiply keeps overlapping highlighter strokes from stacking into an
      // opaque block, the way a real marker behaves.
      paint.blendMode = BlendMode.multiply;
    }

    final pressureVaries =
        stroke.tool != InkTool.highlighter &&
        stroke.tool != InkTool.marker &&
        StrokeGeometry.hasPressureVariation(stroke);

    if (!pressureVaries) {
      paint.strokeWidth = stroke.width;
      canvas.drawPath(StrokeGeometry.smoothPath(stroke), paint);
      return;
    }

    // Variable width needs one segment per sample; a single path can only
    // carry one stroke width.
    for (var i = 0; i < stroke.pointCount - 1; i++) {
      paint.strokeWidth =
          (StrokeGeometry.widthAt(stroke, i) +
              StrokeGeometry.widthAt(stroke, i + 1)) /
          2;
      canvas.drawLine(
        Offset(stroke.xAt(i), stroke.yAt(i)),
        Offset(stroke.xAt(i + 1), stroke.yAt(i + 1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      old.viewport != viewport ||
      old.layer != layer ||
      !identical(old.elements, elements);
}

/// Which strokes an [InkPainter] draws.
enum InkLayer {
  /// Highlighter, drawn beneath the element widgets.
  beneath,

  /// Pen, pencil and marker, drawn above them.
  above;

  bool accepts(InkTool tool) => switch (this) {
    InkLayer.beneath => tool == InkTool.highlighter,
    InkLayer.above => tool != InkTool.highlighter,
  };
}

/// Draws the stroke currently under the pointer.
///
/// The in-progress stroke lives in its own layer so that each new sample
/// repaints only this painter, leaving the committed ink and the element
/// widgets untouched. That is what keeps the line under the pen from lagging
/// on a page that already holds a lot of content.
class WetInkPainter extends CustomPainter {
  WetInkPainter({
    required this.points,
    required this.pen,
    required this.viewport,
    super.repaint,
  });

  /// Flat `[x, y, pressure, tilt]` samples in page space.
  final List<double> points;

  /// The instrument the stroke is being drawn with.
  final ({InkTool tool, int color, double width}) pen;

  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < InkStroke.stride * 2) return;

    final stroke = InkStroke(
      tool: pen.tool,
      color: pen.color,
      width: pen.width,
      points: Float32List.fromList(points),
    );

    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);
    InkPainter.paintStroke(canvas, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(WetInkPainter old) =>
      old.points.length != points.length ||
      old.viewport != viewport ||
      old.pen != pen;
}

/// Draws selection outlines and the handles around them.
class SelectionPainter extends CustomPainter {
  const SelectionPainter({
    required this.selected,
    required this.viewport,
    required this.accent,
    this.marquee,
  });

  final List<NoteElement> selected;
  final CanvasViewport viewport;
  final Color accent;

  /// The rubber-band rectangle being dragged, in page space.
  final Aabb? marquee;

  /// Size of a resize handle in screen pixels.
  static const double handleSize = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final element in selected) {
      canvas.drawRect(_toScreenRect(element.bounds).inflate(2), outline);
    }

    if (selected.isNotEmpty) {
      _drawHandles(canvas, _unionOf(selected), outline.color);
    }

    final band = marquee;
    if (band != null) {
      final rect = _toScreenRect(band);
      canvas
        ..drawRect(rect, Paint()..color = accent.withValues(alpha: 0.12))
        ..drawRect(rect, outline);
    }
  }

  void _drawHandles(Canvas canvas, Aabb bounds, Color color) {
    final rect = _toScreenRect(bounds).inflate(2);
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final corner in <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final handle = Rect.fromCenter(
        center: corner,
        width: handleSize,
        height: handleSize,
      );
      canvas
        ..drawRect(handle, fill)
        ..drawRect(handle, ring);
    }
  }

  Rect _toScreenRect(Aabb bounds) {
    final topLeft = viewport.toScreen(Offset(bounds.left, bounds.top));
    final bottomRight = viewport.toScreen(Offset(bounds.right, bounds.bottom));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  static Aabb _unionOf(List<NoteElement> elements) {
    var bounds = elements.first.bounds;
    for (var i = 1; i < elements.length; i++) {
      bounds = bounds.union(elements[i].bounds);
    }
    return bounds;
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.viewport != viewport ||
      old.marquee != marquee ||
      old.accent != accent ||
      !identical(old.selected, selected);
}
