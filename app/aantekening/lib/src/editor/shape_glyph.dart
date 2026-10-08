/// A shape drawn small, as it is drawn on the page, to be picked.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import '../look/tones.dart';

/// [kind] drawn [size] across in thin lines of the text's colour, from the
/// very lines it is drawn with on the page.
class ShapeGlyph extends StatelessWidget {
  const ShapeGlyph(this.kind, {this.size = 24, super.key});

  final ShapeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ShapeGlyphPainter(kind, context.tones.text)),
  );
}

class _ShapeGlyphPainter extends CustomPainter {
  _ShapeGlyphPainter(this.kind, this.color);

  final ShapeKind kind;
  final Color color;

  /// How thick the lines are, in pixels.
  static const double _stroke = 1.2;

  /// How wide the shape is drawn before it is made small: four squares of
  /// the grid, so its ticks and lines are few enough to tell apart.
  static const double _across = 4 * InkShape.unit;

  /// The shape; a line slanted, to be told from a dash.
  InkShape get _shape {
    if (!kind.throughPoints || kind == ShapeKind.numberLine) {
      return InkShape.placed(kind, const Vec2.zero(), width: _across);
    }
    final begun = InkShape.begin(kind, const Vec2(0, _across * 2 / 3));
    return begun.withHandle(begun.draggedHandle, const Vec2(_across, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _shape;
    final corners = shape.handles;
    final xs = corners.map((point) => point.x);
    final ys = corners.map((point) => point.y);
    final left = xs.reduce(math.min);
    final top = ys.reduce(math.min);
    final width = xs.reduce(math.max) - left;
    final height = ys.reduce(math.max) - top;
    final scale = (size.shortestSide - 2 * _stroke) / math.max(width, height);
    // The lines are made for a pen as thick, on the page, as the glyph's
    // lines are once drawn this small: its arrowheads and dashes to match.
    final lines = shape.lines(_stroke / scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..translate(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      )
      ..scale(scale)
      ..translate(-left, -top);
    for (final line in lines) {
      canvas.drawPath(
        Path()..addPolygon(<Offset>[
          for (final point in line) Offset(point.x, point.y),
        ], false),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapeGlyphPainter old) =>
      old.kind != kind || old.color != color;
}
