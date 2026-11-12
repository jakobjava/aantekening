/// What the page's commands act on, for the keys and the guide that run
/// them.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';

import 'text/math_templates.dart';
import 'text/text_box_controller.dart';

/// What the page's commands act on: the page, the text being edited, and
/// the page editor's own commands.
@immutable
class PageCommands {
  const PageCommands({
    required this.canvas,
    required this.text,
    required this.lastInkTool,
    required this.onToolSelected,
    required this.onFormula,
    required this.onInsertTextBox,
    required this.onInsertImage,
    required this.onInsertPdf,
    required this.onInsertLatex,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitPage,
    required this.onActualSize,
    required this.onMathInsert,
  });

  final CanvasController canvas;
  final TextBoxEditorController text;

  /// The pen or the highlighter, whichever was used last: the one colours
  /// and widths are set for while neither is in hand.
  final ValueGetter<CanvasTool> lastInkTool;

  final ValueChanged<CanvasTool> onToolSelected;
  final VoidCallback onFormula;
  final VoidCallback onInsertTextBox;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertPdf;

  /// Asks for LaTeX, and puts it into the text being edited, or onto the
  /// page.
  final VoidCallback onInsertLatex;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitPage;
  final VoidCallback onActualSize;

  /// Puts a structure or symbol into the formula being edited, or into a
  /// new one.
  final ValueChanged<MathTemplate> onMathInsert;

  /// Pen widths offered, in page units.
  static const List<double> penWidths = <double>[1, 1.6, 2.2, 3.5, 5, 8];

  /// Highlighter nib heights offered, in page units.
  static const List<double> highlighterWidths = <double>[12, 18, 22, 30, 40];

  /// The pen or the highlighter colours and widths are set for: the one in
  /// hand, or else the one used last.
  PenSettings get ink => lastInkTool() == CanvasTool.highlighter
      ? canvas.highlighterSettings
      : canvas.penSettings;

  /// The widths offered for [ink].
  List<double> get inkWidths =>
      ink.tool == InkTool.highlighter ? highlighterWidths : penWidths;

  /// Changes the pen or highlighter and takes it up, as picking a pen
  /// colour in OneNote does — unless the shape tool, which draws in the
  /// pen's ink, is in hand.
  void changeInk(PenSettings settings) {
    canvas.setPen(settings);
    if (canvas.tool == CanvasTool.shape &&
        settings.tool != InkTool.highlighter) {
      return;
    }
    onToolSelected(
      settings.tool == InkTool.highlighter
          ? CanvasTool.highlighter
          : CanvasTool.pen,
    );
  }

  /// Makes the ink [by] steps thicker, or thinner for a negative [by],
  /// among the widths offered.
  void stepInkWidth(int by) {
    final settings = ink;
    changeInk(
      settings.copyWith(width: _stepped(inkWidths, settings.width, by)),
    );
  }

  /// The width [by] steps on from [width] among [widths], or back for a
  /// negative [by].
  static double _stepped(List<double> widths, double width, int by) {
    var at = widths.indexWhere((each) => each >= width);
    if (at < 0) at = widths.length - 1;
    return widths[(at + by).clamp(0, widths.length - 1)];
  }

  /// The pen's line drawn the next way of [InkLine.values]: whole, in
  /// dashes, in dots, and whole again.
  void stepInkLine() {
    final pen = canvas.penSettings;
    changeInk(pen.copyWith(line: _next(pen.line)));
  }

  static InkLine _next(InkLine line) =>
      InkLine.values[(line.index + 1) % InkLine.values.length];

  /// How strong a fill is that has not been given a strength: one that
  /// colours a shape and still lets the text it is drawn round be read.
  static const int _usualFillAlpha = 0x80;

  /// [color] as a fill as strong as [like] is, or as fills usually are.
  static int _fillOf(int color, int? like) =>
      (color & 0x00FFFFFF) | ((like ?? (_usualFillAlpha << 24)) & 0xFF000000);

  /// How strong the fill [fill] is, named: the nearest strength offered.
  static String fillStrengthOf(int fill) {
    final alpha = fill >>> 24;
    var nearest = PenSettings.fillStrengths.first;
    for (final each in PenSettings.fillStrengths) {
      if ((each.alpha - alpha).abs() < (nearest.alpha - alpha).abs()) {
        nearest = each;
      }
    }
    return nearest.label;
  }

  /// [fill] at the next strength offered after its own, the strongest
  /// followed by the lightest.
  static int _nextStrength(int fill) {
    const strengths = PenSettings.fillStrengths;
    final label = fillStrengthOf(fill);
    final at = strengths.indexWhere((each) => each.label == label);
    final next = strengths[(at + 1) % strengths.length];
    return (fill & 0x00FFFFFF) | (next.alpha << 24);
  }

  /// Fills the shapes the pen draws from now on with [color], as strongly
  /// as they were filled before; or with nothing, for null.
  void fillShapesWith(int? color) {
    final pen = canvas.penSettings;
    changeInk(
      color == null
          ? pen.copyWith(unfilled: true)
          : pen.copyWith(fill: _fillOf(color, pen.fill)),
    );
  }

  /// Fills the shapes the pen draws more strongly, or after the strongest
  /// most lightly.
  void stepFillStrength() {
    final pen = canvas.penSettings;
    final fill = pen.fill;
    if (fill != null) changeInk(pen.copyWith(fill: _nextStrength(fill)));
  }

  // ------------------------------------------------------- the ink picked

  /// A stroke of the ink picked, to say how it is drawn now: the pen's
  /// first, or else a highlighter's.
  InkStroke? get pickedStroke {
    InkStroke? found;
    for (final element in canvas.selectedElements) {
      if (element is! InkElement || element.locked) continue;
      for (final stroke in element.strokes) {
        if (stroke.tool != InkTool.highlighter) return stroke;
        found ??= stroke;
      }
    }
    return found;
  }

  /// A filled stroke of the ink picked, if any is filled.
  InkStroke? get pickedFilled {
    for (final element in canvas.selectedElements) {
      if (element is! InkElement || element.locked) continue;
      for (final stroke in element.strokes) {
        if (stroke.fill != null) return stroke;
      }
    }
    return null;
  }

  /// Draws the ink picked in [color]: a highlighter's as translucent as
  /// it was, and never in the inverse of what is beneath, which only a
  /// pen draws in.
  void colourPicked(int color) => canvas.restyleSelection((stroke) {
    if (stroke.tool != InkTool.highlighter) {
      return stroke.color == color ? stroke : stroke.restyled(color: color);
    }
    if (color == NoteColors.inverse) return stroke;
    final kept = (color & 0x00FFFFFF) | (stroke.color & 0xFF000000);
    return stroke.color == kept ? stroke : stroke.restyled(color: kept);
  });

  /// Makes the ink picked [by] steps thicker among the widths offered for
  /// the pen or the highlighter it was drawn with, or thinner for a
  /// negative [by].
  void stepPickedWidth(int by) => canvas.restyleSelection((stroke) {
    final width = _stepped(
      stroke.tool == InkTool.highlighter ? highlighterWidths : penWidths,
      stroke.width,
      by,
    );
    return width == stroke.width ? stroke : stroke.restyled(width: width);
  });

  /// Draws the lines of the ink picked the next way after the first of
  /// them: whole, in dashes, in dots. A highlighter's stays whole.
  void stepPickedLine() {
    final first = pickedStroke;
    if (first == null || first.tool == InkTool.highlighter) return;
    final line = _next(first.line);
    canvas.restyleSelection(
      (stroke) => stroke.tool == InkTool.highlighter || stroke.line == line
          ? stroke
          : stroke.restyled(line: line),
    );
  }

  /// Fills what the ink picked goes round with [color] — each stroke that
  /// ends where it began, a shape's outline or a loop drawn by hand — as
  /// strongly as any of it is filled already; or takes the fill from all
  /// of it, for null.
  void fillPicked(int? color) {
    final fill = color == null ? null : _fillOf(color, pickedFilled?.fill);
    canvas.restyleSelection((stroke) {
      if (fill == null) {
        return stroke.fill == null ? stroke : stroke.restyled(unfilled: true);
      }
      if (stroke.tool == InkTool.highlighter ||
          !stroke.isClosed ||
          stroke.fill == fill) {
        return stroke;
      }
      return stroke.restyled(fill: fill);
    });
  }

  /// Fills what is filled of the ink picked more strongly, or after the
  /// strongest most lightly: all of it as the first of it.
  void stepPickedFillStrength() {
    final first = pickedFilled?.fill;
    if (first == null) return;
    final alpha = _nextStrength(first) & 0xFF000000;
    canvas.restyleSelection((stroke) {
      final fill = stroke.fill;
      if (fill == null) return stroke;
      final next = (fill & 0x00FFFFFF) | alpha;
      return next == fill ? stroke : stroke.restyled(fill: next);
    });
  }
}
