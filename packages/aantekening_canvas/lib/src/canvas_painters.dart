/// The painted layers of the canvas: paper, ink, wet ink and selection.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import 'canvas_viewport.dart';
import 'selection_handles.dart';
import 'stroke_geometry.dart';
import 'tools.dart';

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
///
/// Each ink element is recorded once into a picture in page space and replayed
/// under the viewport transform. Panning and zooming then cost one picture per
/// element rather than rebuilding every stroke's path on every frame.
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

  static final Expando<ui.Picture> _beneath = Expando<ui.Picture>('beneath');
  static final Expando<ui.Picture> _above = Expando<ui.Picture>('above');

  @override
  void paint(Canvas canvas, Size size) {
    if (elements.isEmpty) return;

    final visible = viewport.visibleBounds(size);
    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);
    for (final element in elements) {
      if (!element.bounds.intersects(visible)) continue;
      final picture = _pictureOf(element);
      if (picture != null) canvas.drawPicture(picture);
    }
    canvas.restore();
  }

  /// The element's strokes on this layer, recorded once. Elements are
  /// immutable, so an edited element is a new object with a new picture.
  ui.Picture? _pictureOf(InkElement element) {
    final cache = layer == InkLayer.beneath ? _beneath : _above;
    final cached = cache[element];
    if (cached != null) return cached;
    if (!element.strokes.any((stroke) => layer.accepts(stroke.tool))) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in element.strokes) {
      if (layer.accepts(stroke.tool)) paintStroke(canvas, stroke);
    }
    return cache[element] = recorder.endRecording();
  }

  /// Paints one stroke in page space.
  static void paintStroke(Canvas canvas, InkStroke stroke) {
    if (stroke.tool == InkTool.highlighter) {
      canvas.drawPath(
        StrokeGeometry.chiselPath(stroke),
        Paint()
          ..color = Color(stroke.color)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          // Multiply keeps a highlighter from covering what it marks, and lets
          // overlapping strokes deepen the way a real marker does.
          ..blendMode = BlendMode.multiply,
      );
      return;
    }

    final paint = Paint()
      ..color = Color(stroke.color)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final pressureVaries =
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
  final PenSettings pen;

  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < InkStroke.stride) return;

    final stroke = InkStroke(
      tool: pen.tool,
      color: pen.strokeColor,
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

/// Draws the selection box, its handles and the marquee.
///
/// Every selected object gets a thin outline of its own; the box that can be
/// dragged, resized and turned goes round the whole selection. Only the handles
/// the selection actually supports are drawn — a text box offers its left
/// and right sides, a picture its corners and all four sides — because a
/// handle that does nothing is worse than none.
class SelectionPainter extends CustomPainter {
  const SelectionPainter({
    required this.selected,
    required this.viewport,
    required this.accent,
    this.marquee,
    this.showHandles = true,
  });

  final List<NoteElement> selected;
  final CanvasViewport viewport;
  final Color accent;

  /// The rubber-band rectangle being dragged, in page space.
  final Aabb? marquee;

  /// Whether to draw the box and its handles, or only the outlines.
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (selected.length > 1) {
      for (final element in selected) {
        final frame = SelectionFrame.around(<NoteElement>[element]);
        if (frame != null) {
          canvas.drawPath(
            _polygon(SelectionHandles.outlineOf(frame, viewport)),
            thin,
          );
        }
      }
    }

    final frame = SelectionFrame.around(selected);
    if (frame != null) {
      canvas.drawPath(
        _polygon(SelectionHandles.outlineOf(frame, viewport)),
        outline,
      );
      if (showHandles) _drawHandles(canvas, frame);
    }

    final band = marquee;
    if (band != null) {
      final rect = Rect.fromPoints(
        viewport.toScreen(Offset(band.left, band.top)),
        viewport.toScreen(Offset(band.right, band.bottom)),
      );
      canvas
        ..drawRect(rect, Paint()..color = accent.withValues(alpha: 0.12))
        ..drawRect(rect, outline);
    }
  }

  void _drawHandles(Canvas canvas, SelectionFrame frame) {
    final fill = Paint()..color = accent;
    final ring = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final positions = SelectionHandles.positionsFor(selected, viewport);

    final knob = positions[SelectionHandle.rotate];
    if (knob != null) {
      final outline = SelectionHandles.outlineOf(frame, viewport);
      canvas
        ..drawLine(
          (outline[0] + outline[1]) / 2,
          knob,
          Paint()
            ..color = accent
            ..strokeWidth = 1.2,
        )
        ..drawRect(
          Rect.fromCircle(center: knob, radius: SelectionHandles.size * 0.6),
          fill,
        )
        ..drawRect(
          Rect.fromCircle(center: knob, radius: SelectionHandles.size * 0.6),
          ring,
        );
    }

    for (final entry in positions.entries) {
      if (entry.key == SelectionHandle.rotate) continue;
      final isSide = entry.key.isSide;
      final upright =
          entry.key == SelectionHandle.left ||
          entry.key == SelectionHandle.right;
      // Handles turn with the box, so a side's bar always lies along it.
      canvas
        ..save()
        ..translate(entry.value.dx, entry.value.dy)
        ..rotate(frame.rotation);
      const size = SelectionHandles.size;
      final handle = Rect.fromCenter(
        center: Offset.zero,
        width: isSide && !upright ? size * 2.5 : size,
        height: upright ? size * 2.5 : size,
      );
      canvas
        ..drawRect(handle, fill)
        ..drawRect(handle, ring)
        ..restore();
    }
  }

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.viewport != viewport ||
      old.marquee != marquee ||
      old.accent != accent ||
      old.showHandles != showHandles ||
      !_sameElements(old.selected, selected);

  static bool _sameElements(List<NoteElement> a, List<NoteElement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
