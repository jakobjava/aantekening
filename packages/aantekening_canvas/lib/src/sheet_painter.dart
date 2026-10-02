/// Sheets of paper on a desk, each printed with its template.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

import 'canvas_viewport.dart';

/// Draws the desk, and on it the sheets in view, each printed with its
/// template, as [viewport] sees them.
///
/// A template's lines are worked out once for a size of sheet, in page
/// units, and drawn in a single call for each sheet in view, as thin as a
/// device pixel at any zoom.
void paintSheets(
  Canvas canvas,
  Size size,
  CanvasViewport viewport,
  Sheets sheets, {
  required Color desk,
  required Color paper,
}) {
  final fold = viewport.fold;
  if (fold == null) return;
  canvas.drawRect(Offset.zero & size, Paint()..color = desk);

  final zoom = viewport.zoom;
  final top = viewport.origin.dy;
  final first = math.max(0, ((top - fold.gap) / fold.pitch).floor());
  final last = math.min(
    fold.count - 1,
    ((top + size.height / zoom) / fold.pitch).floor(),
  );
  final dark = paper.computeLuminance() < 0.4;
  final shadow = Paint()..color = const Color(0x1F000000);
  final edge = Paint()
    ..color = const Color(0x24000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0;
  final sheetPaint = Paint()..color = paper;
  for (var index = first; index <= last; index++) {
    final inView = fold.sheetInView(index);
    final rect = Rect.fromLTRB(
      (inView.left - viewport.origin.dx) * zoom,
      (inView.top - top) * zoom,
      (inView.right - viewport.origin.dx) * zoom,
      (inView.bottom - top) * zoom,
    );
    canvas
      ..drawRect(rect.shift(const Offset(0, 1.5)).inflate(0.5), shadow)
      ..drawRect(rect, sheetPaint);
    final template = index < sheets.templates.length
        ? sheets.templates[index]
        : sheets.templates.last;
    if (template != SheetTemplate.blank) {
      final printed = _Printed.of(template, sheets.width, sheets.height);
      printed.paint(
        canvas,
        rect,
        zoom,
        dark: dark,
        strength: printed.strengthAt(zoom),
      );
    }
    canvas.drawRect(rect, edge);
  }
}

/// What a template prints on a sheet of one size: lines, from end to end,
/// and dots, in page units from the sheet's corner.
class _Printed {
  _Printed({required this.spacing, this.lines, this.margins, this.dots});

  /// The template of [template] for sheets [width] by [height], worked
  /// out once.
  factory _Printed.of(SheetTemplate template, double width, double height) =>
      _made[(template, width, height)] ??= _make(template, width, height);

  static final Map<(SheetTemplate, double, double), _Printed> _made =
      <(SheetTemplate, double, double), _Printed>{};

  /// The least gap between two of its lines or dots, in page units.
  final double spacing;

  /// The ends of each line, two points to a line.
  final Float32List? lines;

  /// The ends of each margin line, drawn in the margin's colour.
  final Float32List? margins;

  /// The dots.
  final Float32List? dots;

  /// Rule and grid lines, a light blue-grey on white paper, as printed
  /// paper is; a faint white on dark paper.
  static const Color _rule = Color(0x707C9CC0);
  static const Color _ruleOnDark = Color(0x40FFFFFF);
  static const Color _margin = Color(0x80E06C75);

  /// How far apart, on screen, a template's lines have to be to be drawn
  /// as strong as they are; closer, they are drawn fainter, down to
  /// [_faintest], so that a sheet seen small shows its pattern without
  /// turning grey.
  static const double _clear = 8;
  static const double _faintest = 0.35;

  /// How strongly the template is drawn at [zoom], from [_faintest] to 1.
  double strengthAt(double zoom) =>
      (spacing * zoom / _clear).clamp(_faintest, 1.0);

  /// The lines of a lined sheet, and its Cornell sheet's notes.
  static const double _lined = 32;

  /// The squares and dots of a squared or dotted sheet.
  static const double _square = 20;

  /// The lines of a staff, and from one staff to the next.
  static const double _staffLine = 8;
  static const double _staffPitch = 84;

  /// Draws the template over [sheet], [zoom] pixels to a page unit, as
  /// strong as [strength] has it.
  void paint(
    Canvas canvas,
    Rect sheet,
    double zoom, {
    required bool dark,
    double strength = 1,
  }) {
    canvas
      ..save()
      ..clipRect(sheet)
      ..translate(sheet.left, sheet.top)
      ..scale(zoom);
    Color faded(Color color) => color.withValues(alpha: color.a * strength);
    final rule = faded(dark ? _ruleOnDark : _rule);
    if (lines case final lines?) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        lines,
        Paint()
          ..color = rule
          ..strokeWidth = 0,
      );
    }
    if (margins case final margins?) {
      canvas.drawRawPoints(
        ui.PointMode.lines,
        margins,
        Paint()
          ..color = faded(_margin)
          ..strokeWidth = 0,
      );
    }
    if (dots case final dots?) {
      canvas.drawRawPoints(
        ui.PointMode.points,
        dots,
        Paint()
          ..color = rule.withValues(alpha: math.min(1, rule.a * 1.6))
          // Two pixels across at least, but never so large, drawn small,
          // that the dots run together.
          ..strokeWidth = math.min(math.max(1.6, 2.2 / zoom), _square / 3)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  static _Printed _make(SheetTemplate template, double width, double height) {
    final lines = <double>[];
    final margins = <double>[];
    void across(double y, {double from = 0, double? to}) =>
        lines.addAll(<double>[from, y, to ?? width, y]);
    void down(List<double> into, double x, double from, double to) =>
        into.addAll(<double>[x, from, x, to]);
    switch (template) {
      case SheetTemplate.blank:
        return _Printed(spacing: double.infinity);
      case SheetTemplate.lined:
        // Room for a heading above the first line, and a margin down the
        // left.
        for (var y = 3 * _lined; y < height - _lined / 2; y += _lined) {
          across(y);
        }
        down(margins, 2.5 * _lined, 0, height);
        return _Printed(
          spacing: _lined,
          lines: Float32List.fromList(lines),
          margins: Float32List.fromList(margins),
        );
      case SheetTemplate.grid:
        final (left, top) = (_inset(width), _inset(height));
        for (var x = left; x <= width; x += _square) {
          down(lines, x, 0, height);
        }
        for (var y = top; y <= height; y += _square) {
          across(y);
        }
        return _Printed(spacing: _square, lines: Float32List.fromList(lines));
      case SheetTemplate.dotted:
        final (left, top) = (_inset(width), _inset(height));
        return _Printed(
          spacing: _square,
          dots: Float32List.fromList(<double>[
            for (var y = top; y <= height; y += _square)
              for (var x = left; x <= width; x += _square) ...<double>[x, y],
          ]),
        );
      case SheetTemplate.music:
        // As many staves as fit between the margins, the space left over
        // shared above and below.
        final side = 0.07 * width;
        final usable = height - 2 * 0.07 * height;
        final staves = math.max(1, (usable / _staffPitch).floor());
        final start =
            (height - staves * _staffPitch) / 2 +
            (_staffPitch - 4 * _staffLine) / 2;
        for (var staff = 0; staff < staves; staff++) {
          final y = start + staff * _staffPitch;
          for (var line = 0; line < 5; line++) {
            across(y + line * _staffLine, from: side, to: width - side);
          }
          // The bar lines at either end.
          down(lines, side, y, y + 4 * _staffLine);
          down(lines, width - side, y, y + 4 * _staffLine);
        }
        return _Printed(
          spacing: _staffLine,
          lines: Float32List.fromList(lines),
        );
      case SheetTemplate.cornell:
        // A heading across the top, cues down the left, notes on lines to
        // the right of them, and a summary across the foot.
        final heading = 3 * _lined;
        final summary = (0.78 * height / _lined).round() * _lined;
        final cues = 0.3 * width;
        across(heading);
        across(summary);
        down(lines, cues, heading, summary);
        for (var y = heading + _lined; y < summary; y += _lined) {
          across(y, from: cues);
        }
        return _Printed(spacing: _lined, lines: Float32List.fromList(lines));
    }
  }

  /// Where a sheet's squares start along a side [length] long: the part of a
  /// square left over shared at both ends, so the squares lie in its middle.
  static double _inset(double length) => (length % _square) / 2;
}

/// A sheet printed with [template], drawn whole, [width] across: to choose
/// a template by.
class SheetThumbnail extends StatelessWidget {
  const SheetThumbnail({
    required this.template,
    this.width = 54,
    this.size = SheetSize.a4,
    super.key,
  });

  final SheetTemplate template;
  final double width;
  final SheetSize size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * size.height / size.width),
    painter: _ThumbnailPainter(template, size),
  );
}

class _ThumbnailPainter extends CustomPainter {
  const _ThumbnailPainter(this.template, this.sheet);

  final SheetTemplate template;
  final SheetSize sheet;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    if (template != SheetTemplate.blank) {
      // Drawn however close its lines come: small, they read as the
      // template's pattern.
      _Printed.of(
        template,
        sheet.width,
        sheet.height,
      ).paint(canvas, rect, size.width / sheet.width, dark: false);
    }
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = const Color(0x40000000)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.template != template || old.sheet != sheet;
}
