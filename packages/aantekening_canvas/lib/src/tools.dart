/// The tools the canvas can be driven with.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

/// What a pointer press does on the canvas.
enum CanvasTool {
  /// Pick up, move and resize elements.
  select,

  /// Drag the page itself.
  pan,

  /// Draw ink.
  draw,

  /// Remove whole strokes under the pointer.
  eraser,

  /// Place a new text box.
  text,

  /// Place a new formula.
  math,
}

/// The current drawing instrument.
@immutable
class PenSettings {
  const PenSettings({
    this.tool = InkTool.pen,
    this.color = 0xFF1A1A1A,
    this.width = 2.2,
    this.pressureSensitive = true,
  });

  /// A small palette of ready-made instruments for the toolbar.
  static const PenSettings blackPen = PenSettings();
  static const PenSettings bluePen = PenSettings(color: 0xFF1D4ED8);
  static const PenSettings redPen = PenSettings(color: 0xFFDC2626);
  static const PenSettings yellowHighlighter = PenSettings(
    tool: InkTool.highlighter,
    color: 0x66FACC15,
    width: 16,
    pressureSensitive: false,
  );

  final InkTool tool;

  /// Stroke colour as 32-bit ARGB.
  final int color;

  /// Nominal width in page units.
  final double width;

  /// Whether stylus pressure modulates the stroke width.
  final bool pressureSensitive;

  PenSettings copyWith({
    InkTool? tool,
    int? color,
    double? width,
    bool? pressureSensitive,
  }) => PenSettings(
    tool: tool ?? this.tool,
    color: color ?? this.color,
    width: width ?? this.width,
    pressureSensitive: pressureSensitive ?? this.pressureSensitive,
  );

  @override
  bool operator ==(Object other) =>
      other is PenSettings &&
      other.tool == tool &&
      other.color == color &&
      other.width == width &&
      other.pressureSensitive == pressureSensitive;

  @override
  int get hashCode => Object.hash(tool, color, width, pressureSensitive);
}
