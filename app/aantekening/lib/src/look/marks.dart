/// The few symbols the interface draws: thin straight lines for what a word
/// would be too long for — closing, adding, opening a row, ticking.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A symbol, drawn in lines on a grid of twelve by twelve.
enum MarkShape {
  close,
  add,
  remove,
  check,
  chevronRight,
  chevronDown,
  chevronUp,
  chevronLeft,
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,

  /// Three dots in a row: more commands.
  more,

  /// A small solid triangle pointing down: a drop-down.
  dropdown,

  /// Two columns of dots: something to take hold of.
  grip,

  /// An empty box, and one ticked.
  box,
  boxTicked,
}

/// [shape], drawn [size] across in the colour of the icons here, or
/// [color].
///
/// It stands in an icon's place, taking its colour from an [IconTheme] —
/// so a button that greys out its icon greys out its mark.
class Mark extends StatelessWidget {
  const Mark(this.shape, {this.size = 12, this.color, super.key});

  final MarkShape shape;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icons = IconTheme.of(context);
    final color =
        this.color ??
        icons.color?.withValues(
          alpha: (icons.color!.a * (icons.opacity ?? 1)).clamp(0, 1),
        ) ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(shape, color)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.shape, this.color);

  final MarkShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 12;
    // Lines stay thin however large the mark, so marks of every size look
    // like one set.
    final weight = math.max(1.0, math.min(1.6, unit * 1.2));
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final fill = Paint()..color = color;
    Offset at(double x, double y) => Offset(x * unit, y * unit);
    void lines(List<List<(double, double)>> runs) {
      for (final run in runs) {
        final path = Path()..moveTo(run.first.$1 * unit, run.first.$2 * unit);
        for (final (x, y) in run.skip(1)) {
          path.lineTo(x * unit, y * unit);
        }
        canvas.drawPath(path, line);
      }
    }

    void dot(double x, double y, double across) => canvas.drawRect(
      Rect.fromCenter(center: at(x, y), width: across, height: across),
      fill,
    );

    switch (shape) {
      case MarkShape.close:
        lines(<List<(double, double)>>[
          <(double, double)>[(3, 3), (9, 9)],
          <(double, double)>[(9, 3), (3, 9)],
        ]);
      case MarkShape.add:
        lines(<List<(double, double)>>[
          <(double, double)>[(6, 2), (6, 10)],
          <(double, double)>[(2, 6), (10, 6)],
        ]);
      case MarkShape.remove:
        lines(<List<(double, double)>>[
          <(double, double)>[(2, 6), (10, 6)],
        ]);
      case MarkShape.check:
        lines(<List<(double, double)>>[
          <(double, double)>[(2.5, 6.5), (5, 9), (9.5, 3.5)],
        ]);
      case MarkShape.chevronRight:
        lines(<List<(double, double)>>[
          <(double, double)>[(4.5, 2.5), (8, 6), (4.5, 9.5)],
        ]);
      case MarkShape.chevronLeft:
        lines(<List<(double, double)>>[
          <(double, double)>[(7.5, 2.5), (4, 6), (7.5, 9.5)],
        ]);
      case MarkShape.chevronDown:
        lines(<List<(double, double)>>[
          <(double, double)>[(2.5, 4.5), (6, 8), (9.5, 4.5)],
        ]);
      case MarkShape.chevronUp:
        lines(<List<(double, double)>>[
          <(double, double)>[(2.5, 7.5), (6, 4), (9.5, 7.5)],
        ]);
      case MarkShape.arrowUp:
        lines(<List<(double, double)>>[
          <(double, double)>[(6, 10), (6, 2)],
          <(double, double)>[(2.5, 5.5), (6, 2), (9.5, 5.5)],
        ]);
      case MarkShape.arrowDown:
        lines(<List<(double, double)>>[
          <(double, double)>[(6, 2), (6, 10)],
          <(double, double)>[(2.5, 6.5), (6, 10), (9.5, 6.5)],
        ]);
      case MarkShape.arrowLeft:
        lines(<List<(double, double)>>[
          <(double, double)>[(10, 6), (2, 6)],
          <(double, double)>[(5.5, 2.5), (2, 6), (5.5, 9.5)],
        ]);
      case MarkShape.arrowRight:
        lines(<List<(double, double)>>[
          <(double, double)>[(2, 6), (10, 6)],
          <(double, double)>[(6.5, 2.5), (10, 6), (6.5, 9.5)],
        ]);
      case MarkShape.more:
        for (final x in <double>[2.5, 6, 9.5]) {
          dot(x, 6, weight * 1.5);
        }
      case MarkShape.dropdown:
        canvas.drawPath(
          Path()
            ..moveTo(3 * unit, 4.5 * unit)
            ..lineTo(9 * unit, 4.5 * unit)
            ..lineTo(6 * unit, 7.5 * unit)
            ..close(),
          fill,
        );
      case MarkShape.grip:
        for (final x in <double>[4.5, 7.5]) {
          for (final y in <double>[3, 6, 9]) {
            dot(x, y, weight * 1.3);
          }
        }
      case MarkShape.box:
        canvas.drawRect(
          Rect.fromLTRB(2 * unit, 2 * unit, 10 * unit, 10 * unit),
          line,
        );
      case MarkShape.boxTicked:
        canvas.drawRect(
          Rect.fromLTRB(2 * unit, 2 * unit, 10 * unit, 10 * unit),
          line,
        );
        lines(<List<(double, double)>>[
          <(double, double)>[(4, 6.2), (5.6, 7.8), (8.2, 4.4)],
        ]);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}
