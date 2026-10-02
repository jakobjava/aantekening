/// The interface's icons: each a few thin lines, drawn by the app so they
/// look the same everywhere and match its marks.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An icon, drawn in lines on a grid of sixteen by sixteen.
enum AppIcon {
  undo,
  redo,
  select,
  lasso,
  eraser,
  pen,
  highlighter,
  textBox,
  picture,
  pdf,
  formula,
  cheatSheet,
  spelling,
  languages,
  zoomIn,
  zoomOut,
  fitPage,
  pagePreview,
  reset,
  bullets,
  numbers,
  todo,
  indent,
  outdent,
  notebooks,
  search,
  graph,
  ai,
  settings,
  bin,
  appearance,
  layout,
  keyboard,
  folder,
  about,
  cut,
  copy,
  paste,
  link,
  page,
  export,
  sheets,
  addSheet,
  paper,
  sheetUp,
  sheetDown,
}

/// The colour of the icons here: the [IconTheme]'s, greyed out as it is,
/// or else the text's.
Color iconColorOf(BuildContext context) {
  final icons = IconTheme.of(context);
  return icons.color?.withValues(
        alpha: (icons.color!.a * (icons.opacity ?? 1)).clamp(0, 1),
      ) ??
      DefaultTextStyle.of(context).style.color ??
      const Color(0xFF000000);
}

/// [icon], [size] across, in the colour of the icons here — which follows
/// the text's, greyed out with it — or [color].
class AppIconView extends StatelessWidget {
  const AppIconView(this.icon, {this.size = 16, this.color, super.key});

  final AppIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? iconColorOf(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IconPainter(icon, color)),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final AppIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 16;
    // Thin however large, as the marks are, so icons and marks are of one
    // set.
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, math.min(1.5, unit * 1.2))
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    Offset at(double x, double y) => Offset(x * unit, y * unit);
    canvas.save();

    /// Straight lines through [points], closed back to the first if
    /// [closed].
    void through(List<(double, double)> points, {bool closed = false}) {
      canvas.drawPath(
        Path()
          ..addPolygon(<Offset>[for (final (x, y) in points) at(x, y)], closed),
        line,
      );
    }

    void box(double left, double top, double right, double bottom) => canvas
        .drawRect(Rect.fromPoints(at(left, top), at(right, bottom)), line);

    void ring(double x, double y, double radius) =>
        canvas.drawCircle(at(x, y), radius * unit, line);

    void dot(double x, double y, double radius) =>
        canvas.drawCircle(at(x, y), radius * unit, fill);

    /// An arc about ([x], [y]) from [start] degrees, clockwise from the
    /// right, through [sweep] degrees.
    void arc(double x, double y, double radius, double start, double sweep) =>
        canvas.drawArc(
          Rect.fromCircle(center: at(x, y), radius: radius * unit),
          start * math.pi / 180,
          sweep * math.pi / 180,
          false,
          line,
        );

    void rows(double from, List<double> ys, {double to = 14}) {
      for (final y in ys) {
        through(<(double, double)>[(from, y), (to, y)]);
      }
    }

    void magnifier() {
      ring(7, 7, 4.5);
      through(<(double, double)>[(10.3, 10.3), (14, 14)]);
    }

    switch (icon) {
      case AppIcon.undo || AppIcon.redo:
        if (icon == AppIcon.redo) {
          canvas
            ..translate(size.width, 0)
            ..scale(-1, 1);
        }
        through(<(double, double)>[(6, 3), (3, 6), (6, 9)]);
        through(<(double, double)>[(3, 6), (10, 6)]);
        arc(10, 9.5, 3.5, -90, 180);
        through(<(double, double)>[(10, 13), (7, 13)]);
      case AppIcon.select:
        through(<(double, double)>[
          (4, 2),
          (4, 13),
          (6.8, 10.4),
          (8.8, 14.2),
          (10.6, 13.3),
          (8.6, 9.5),
          (12.2, 9.2),
        ], closed: true);
      case AppIcon.pen:
        through(<(double, double)>[
          (11, 2.5),
          (13.5, 5),
          (5.5, 13),
          (2.5, 13.5),
          (3, 10.5),
        ], closed: true);
        through(<(double, double)>[(9.3, 4.2), (11.8, 6.7)]);
      case AppIcon.highlighter:
        through(<(double, double)>[
          (9, 2),
          (13, 6),
          (8, 11),
          (4, 7),
        ], closed: true);
        through(<(double, double)>[(4, 7), (2.5, 11), (4, 12.5), (8, 11)]);
        through(<(double, double)>[(2, 14.5), (14, 14.5)]);
      case AppIcon.lasso:
        // A loop, open at the bottom where its tail hangs from.
        canvas.drawPath(
          Path()..addArc(
            Rect.fromCenter(
              center: at(8.5, 6.5),
              width: 11 * unit,
              height: 8 * unit,
            ),
            2,
            5.4,
          ),
          line,
        );
        through(<(double, double)>[(6.2, 10.1), (5, 12.3), (6.5, 14.5)]);
      case AppIcon.eraser:
        through(<(double, double)>[
          (9, 2.5),
          (13.5, 7),
          (8, 12.5),
          (3.5, 8),
        ], closed: true);
        through(<(double, double)>[(6.2, 5.3), (10.7, 9.8)]);
        through(<(double, double)>[(8, 14.5), (14, 14.5)]);
      case AppIcon.sheets:
        // Two sheets, one behind the other.
        through(<(double, double)>[(6, 2.5), (13.5, 2.5), (13.5, 11)]);
        box(2.5, 5, 10.5, 14);
      case AppIcon.addSheet:
        box(3, 2, 11, 14);
        through(<(double, double)>[(12.5, 10), (12.5, 15)]);
        through(<(double, double)>[(10, 12.5), (15, 12.5)]);
      case AppIcon.sheetUp || AppIcon.sheetDown:
        if (icon == AppIcon.sheetDown) {
          canvas
            ..translate(0, size.height)
            ..scale(1, -1);
        }
        // A sheet, and an arrow beside it.
        box(2, 4, 9, 14);
        through(<(double, double)>[(12.5, 13), (12.5, 3)]);
        through(<(double, double)>[(10, 5.5), (12.5, 3), (15, 5.5)]);
      case AppIcon.paper:
        box(3, 2, 13, 14);
        rows(5, <double>[6, 8.5, 11], to: 11);
      case AppIcon.textBox:
        box(2, 3, 14, 13);
        through(<(double, double)>[(5, 6), (11, 6)]);
        through(<(double, double)>[(8, 6), (8, 10.5)]);
      case AppIcon.picture:
        box(2, 3, 14, 13);
        through(<(double, double)>[
          (2, 11),
          (6, 7),
          (9, 10),
          (11, 8),
          (14, 11),
        ]);
        ring(10.5, 5.8, 1.1);
      case AppIcon.pdf:
        through(<(double, double)>[
          (4, 2),
          (10, 2),
          (13, 5),
          (13, 14),
          (4, 14),
        ], closed: true);
        through(<(double, double)>[(10, 2), (10, 5), (13, 5)]);
        rows(6.5, <double>[8.5, 11.2], to: 10.5);
      case AppIcon.formula:
        through(<(double, double)>[
          (2, 9),
          (4, 8),
          (6.5, 13),
          (9.5, 3),
          (14, 3),
        ]);
      case AppIcon.cheatSheet:
        box(3, 2, 13, 14);
        rows(5.5, <double>[5.5, 8, 10.5], to: 10.5);
      case AppIcon.spelling:
        through(<(double, double)>[(2.5, 8.5), (6, 12), (13.5, 4.5)]);
      case AppIcon.languages:
        ring(8, 8, 6);
        canvas.drawOval(
          Rect.fromCenter(
            center: at(8, 8),
            width: 5.6 * unit,
            height: 12 * unit,
          ),
          line,
        );
        through(<(double, double)>[(2, 8), (14, 8)]);
      case AppIcon.zoomIn:
        magnifier();
        through(<(double, double)>[(5, 7), (9, 7)]);
        through(<(double, double)>[(7, 5), (7, 9)]);
      case AppIcon.zoomOut:
        magnifier();
        through(<(double, double)>[(5, 7), (9, 7)]);
      case AppIcon.search:
        magnifier();
      case AppIcon.fitPage:
        for (final corner in <List<(double, double)>>[
          <(double, double)>[(2, 5.5), (2, 2), (5.5, 2)],
          <(double, double)>[(10.5, 2), (14, 2), (14, 5.5)],
          <(double, double)>[(14, 10.5), (14, 14), (10.5, 14)],
          <(double, double)>[(5.5, 14), (2, 14), (2, 10.5)],
        ]) {
          through(corner);
        }
      case AppIcon.pagePreview:
        box(2, 2, 14, 14);
        through(<(double, double)>[(10, 2), (10, 14)]);
        box(11.3, 4, 12.7, 7.5);
      case AppIcon.reset:
        arc(8, 8, 5.5, -40, 290);
        through(<(double, double)>[(12.2, 1.5), (12.3, 4.6), (9.2, 4.8)]);
      case AppIcon.bullets:
        for (final y in <double>[4, 8, 12]) {
          dot(3, y, 1.1);
        }
        rows(6, <double>[4, 8, 12]);
      case AppIcon.numbers:
        // A small one and two before their lines.
        through(<(double, double)>[(2.3, 3.2), (3.5, 2.2), (3.5, 6.2)]);
        through(<(double, double)>[
          (2, 9.8),
          (2.7, 8.8),
          (4.3, 8.9),
          (4.5, 10.2),
          (2, 13.2),
          (4.8, 13.2),
        ]);
        rows(7.5, <double>[4.2, 11.2]);
      case AppIcon.todo:
        box(2, 2.5, 6.5, 7);
        through(<(double, double)>[(3, 4.8), (4.2, 6), (6, 3.6)]);
        box(2, 9.5, 6.5, 14);
        rows(9, <double>[4.8, 11.8]);
      case AppIcon.indent || AppIcon.outdent:
        rows(2, <double>[2.5, 13.5]);
        rows(7.5, <double>[6.3, 9.7]);
        through(
          icon == AppIcon.indent
              ? <(double, double)>[(2, 5.5), (4.8, 8), (2, 10.5)]
              : <(double, double)>[(4.8, 5.5), (2, 8), (4.8, 10.5)],
        );
      case AppIcon.notebooks:
        box(3, 2, 13, 14);
        through(<(double, double)>[(5.5, 2), (5.5, 14)]);
        through(<(double, double)>[(8, 5.5), (11, 5.5)]);
      case AppIcon.graph:
        through(<(double, double)>[(4, 4), (12, 5.5), (7, 12.5), (4, 4)]);
        dot(4, 4, 1.8);
        dot(12, 5.5, 1.8);
        dot(7, 12.5, 1.8);
      case AppIcon.ai:
        through(<(double, double)>[
          (8, 1.5),
          (9.6, 6.4),
          (14.5, 8),
          (9.6, 9.6),
          (8, 14.5),
          (6.4, 9.6),
          (1.5, 8),
          (6.4, 6.4),
        ], closed: true);
      case AppIcon.settings:
        through(<(double, double)>[(2, 5), (8.2, 5)]);
        ring(10, 5, 1.8);
        through(<(double, double)>[(11.8, 5), (14, 5)]);
        through(<(double, double)>[(2, 11), (4.2, 11)]);
        ring(6, 11, 1.8);
        through(<(double, double)>[(7.8, 11), (14, 11)]);
      case AppIcon.bin:
        through(<(double, double)>[(2.5, 4), (13.5, 4)]);
        through(<(double, double)>[(6, 4), (6.5, 2.2), (9.5, 2.2), (10, 4)]);
        through(<(double, double)>[(3.8, 4), (4.8, 14), (11.2, 14), (12.2, 4)]);
        through(<(double, double)>[(6.8, 6.8), (7, 11.5)]);
        through(<(double, double)>[(9.2, 6.8), (9, 11.5)]);
      case AppIcon.appearance:
        ring(8, 8, 6);
        canvas.drawArc(
          Rect.fromCircle(center: at(8, 8), radius: 6 * unit),
          -math.pi / 2,
          math.pi,
          true,
          fill,
        );
      case AppIcon.layout:
        box(2, 2.5, 14, 13.5);
        through(<(double, double)>[(2, 5.5), (14, 5.5)]);
        through(<(double, double)>[(6, 5.5), (6, 13.5)]);
      case AppIcon.keyboard:
        box(1.5, 4, 14.5, 12);
        for (final x in <double>[4, 6.7, 9.3, 12]) {
          dot(x, 6.8, 0.7);
        }
        through(<(double, double)>[(5, 9.6), (11, 9.6)]);
      case AppIcon.folder:
        through(<(double, double)>[
          (2, 3.5),
          (6, 3.5),
          (7.5, 5.5),
          (14, 5.5),
          (14, 13),
          (2, 13),
        ], closed: true);
      case AppIcon.about:
        ring(8, 8, 6);
        dot(8, 5, 0.9);
        through(<(double, double)>[(8, 7.5), (8, 11.5)]);
      case AppIcon.cut:
        ring(4.5, 12, 2.2);
        ring(11.5, 12, 2.2);
        through(<(double, double)>[(5.8, 10.2), (11, 2)]);
        through(<(double, double)>[(10.2, 10.2), (5, 2)]);
      case AppIcon.copy:
        through(<(double, double)>[
          (3.5, 10.5),
          (2, 10.5),
          (2, 2),
          (10.5, 2),
          (10.5, 3.5),
        ]);
        box(5.5, 5.5, 14, 14);
      case AppIcon.paste:
        box(3, 3, 13, 14.5);
        box(6, 1.5, 10, 4.5);
        rows(5.5, <double>[8, 11], to: 10.5);
      case AppIcon.link:
        canvas
          ..translate(8 * unit, 8 * unit)
          ..rotate(-math.pi / 4)
          ..translate(-8 * unit, -8 * unit);
        for (final left in <double>[1.5, 7.5]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                left * unit,
                5.5 * unit,
                (left + 7) * unit,
                10.5 * unit,
              ),
              Radius.circular(2.5 * unit),
            ),
            line,
          );
        }
      case AppIcon.page:
        through(<(double, double)>[
          (4, 2),
          (10, 2),
          (13, 5),
          (13, 14),
          (4, 14),
        ], closed: true);
        through(<(double, double)>[(10, 2), (10, 5), (13, 5)]);
        through(<(double, double)>[(8.5, 7.5), (8.5, 12)]);
        through(<(double, double)>[(6.25, 9.75), (10.75, 9.75)]);
      case AppIcon.export:
        through(<(double, double)>[(2, 9), (2, 14), (14, 14), (14, 9)]);
        through(<(double, double)>[(8, 11), (8, 2)]);
        through(<(double, double)>[(4.8, 5.2), (8, 2), (11.2, 5.2)]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
