/// The tools the canvas can be driven with.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// What a pointer press does on the canvas.
///
/// There is no separate pan or text tool, as in OneNote: the page scrolls with
/// the wheel, the trackpad, a finger, the middle button or space-drag whatever
/// tool is active, and clicking empty paper with [select] places a caret.
enum CanvasTool {
  /// Type and select: a click on empty paper places a caret, a click in a text
  /// box moves the caret there, and anything on the page can be picked up,
  /// moved, resized and rotated — one object or a marquee's worth.
  select,

  /// Draw ink with a round, pressure-sensitive nib.
  pen,

  /// Highlight with a translucent chisel nib, beneath text and ink.
  highlighter,

  /// Drag out the shape chosen ([CanvasController.shapeKind]) in the pen's
  /// ink.
  shape,

  /// Remove whole strokes under the pointer.
  eraser,

  /// Draw a loop round what to pick out: handwriting stroke by stroke,
  /// anything else whose middle it takes in. What is picked is moved,
  /// resized and turned as with [select]; nothing is typed.
  lasso;

  /// Whether this tool lays down ink.
  bool get draws => this == pen || this == highlighter || this == shape;

  /// Whether what this tool picks stays picked while it is in hand.
  bool get selects => this == select || this == lasso;
}

/// The settings of an inking tool.
@immutable
class PenSettings {
  const PenSettings({
    this.tool = InkTool.pen,
    this.color = 0xFF000000,
    this.width = 2.2,
    this.pressureSensitive = true,
  });

  /// The pen a page starts with.
  static const PenSettings defaultPen = PenSettings();

  /// The highlighter a page starts with: yellow, and tall enough to cover a
  /// line of body text.
  static const PenSettings defaultHighlighter = PenSettings(
    tool: InkTool.highlighter,
    color: 0xFFFFD60A,
    width: 22,
    pressureSensitive: false,
  );

  /// How opaque highlighter ink is. Stored in the stroke's colour, so a page
  /// looks the same in any build.
  static const int highlighterAlpha = 0x70;

  final InkTool tool;

  /// Colour as 32-bit ARGB. A highlighter's is opaque here; its translucency
  /// is applied when the stroke is made, see [strokeColor].
  final int color;

  /// Nominal width in page units: the line's thickness for a pen, the height
  /// of the chisel nib for a highlighter.
  final double width;

  /// Whether stylus pressure modulates the stroke width.
  final bool pressureSensitive;

  /// The colour strokes are stored with. A pen can draw in the inverse of
  /// what is beneath it ([NoteColors.inverse]); a highlighter cannot, and
  /// is made translucent.
  int get strokeColor => tool == InkTool.highlighter
      ? (color & 0x00FFFFFF) | (highlighterAlpha << 24)
      : color;

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

/// What pressing a pen's barrel button does, held as the pen touches the
/// page, whatever tool is in hand.
enum PenButtonAction {
  /// Nothing more than the tip does.
  none('Nothing'),

  /// Erases whole strokes, as the eraser does.
  erase('Eraser'),

  /// Picks, moves and resizes, as the select tool does.
  select('Select'),

  /// Picks what a loop is drawn round, as the lasso does.
  lasso('Lasso select'),

  /// Moves the page.
  scroll('Scroll');

  const PenButtonAction(this.label);

  final String label;
}

/// What a pen's two barrel buttons do, as the platform numbers them: the
/// first is Flutter's [kPrimaryStylusButton], the second its
/// [kSecondaryStylusButton].
@immutable
class PenButtons {
  const PenButtons({
    this.first = PenButtonAction.erase,
    this.second = PenButtonAction.lasso,
  });

  final PenButtonAction first;
  final PenButtonAction second;

  /// What a pen pressed with [buttons] held does, or null for its tip
  /// alone.
  PenButtonAction? actionFor(int buttons) {
    if (buttons & kPrimaryStylusButton != 0) return first;
    if (buttons & kSecondaryStylusButton != 0) return second;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PenButtons && other.first == first && other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}
