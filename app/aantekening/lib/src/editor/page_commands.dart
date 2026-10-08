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
    final widths = inkWidths;
    var at = widths.indexWhere((width) => width >= settings.width);
    if (at < 0) at = widths.length - 1;
    final to = (at + by).clamp(0, widths.length - 1);
    changeInk(settings.copyWith(width: widths[to]));
  }
}
