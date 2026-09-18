/// A paragraph that draws its own caret, selection, formula highlight and
/// search matches.
library;

import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// What to draw over and under one block's text, in laid-out offsets.
@immutable
class BlockDecoration {
  const BlockDecoration({
    this.selection,
    this.caret,
    this.caretAffinity = TextAffinity.downstream,
    this.composing,
    this.formula,
    this.matches = const <TextRange>[],
  });

  static const BlockDecoration none = BlockDecoration();

  /// The part of this block that is selected, if any.
  final TextSelection? selection;

  /// Where the caret is, when it is in this block.
  final int? caret;

  /// Which side of a line break the caret belongs to.
  final TextAffinity caretAffinity;

  /// Text the input method is still composing, underlined.
  final TextRange? composing;

  /// The formula being edited, its source and the room either side of it,
  /// drawn in a tinted, outlined box.
  final TextRange? formula;

  /// Words a search found, marked behind the text.
  final List<TextRange> matches;

  @override
  bool operator ==(Object other) =>
      other is BlockDecoration &&
      other.selection == selection &&
      other.caret == caret &&
      other.caretAffinity == caretAffinity &&
      other.composing == composing &&
      other.formula == formula &&
      listEquals(other.matches, matches);

  @override
  int get hashCode => Object.hash(
    selection,
    caret,
    caretAffinity,
    composing,
    formula,
    Object.hashAll(matches),
  );
}

/// Colours and sizes for [BlockParagraph].
@immutable
class BlockPaint {
  const BlockPaint({
    required this.caretColor,
    required this.selectionColor,
    required this.formulaColor,
    required this.composingColor,
    required this.matchColor,
    this.formulaOutline,
    this.caretWidth = 1.6,
  });

  final Color caretColor;
  final Color selectionColor;
  final Color formulaColor;

  /// Behind the words a search found.
  final Color matchColor;

  /// The line drawn around the formula being edited, if any.
  final Color? formulaOutline;
  final Color composingColor;

  /// Caret width in screen pixels. It is converted to the paragraph's own
  /// units when painted, so the caret stays a crisp line at any zoom without
  /// the text box having to rebuild whenever the zoom changes.
  final double caretWidth;

  @override
  bool operator ==(Object other) =>
      other is BlockPaint &&
      other.caretColor == caretColor &&
      other.selectionColor == selectionColor &&
      other.formulaColor == formulaColor &&
      other.formulaOutline == formulaOutline &&
      other.composingColor == composingColor &&
      other.matchColor == matchColor &&
      other.caretWidth == caretWidth;

  @override
  int get hashCode => Object.hash(
    caretColor,
    selectionColor,
    formulaColor,
    formulaOutline,
    composingColor,
    matchColor,
    caretWidth,
  );
}

/// Wraps a [RichText] and paints the editing decorations around it.
///
/// Drawing these here rather than in an overlay keeps them in the paragraph's
/// own coordinate space, so they move, wrap and scale with the text for free.
class BlockParagraph extends SingleChildRenderObjectWidget {
  const BlockParagraph({
    required this.decoration,
    required this.paint,
    required this.caretVisible,
    required RichText super.child,
    super.key,
  });

  final BlockDecoration decoration;
  final BlockPaint paint;

  /// Toggled by the editor to blink the caret without rebuilding anything.
  final ValueListenable<bool> caretVisible;

  @override
  RenderBlockParagraph createRenderObject(BuildContext context) =>
      RenderBlockParagraph(
        decoration: decoration,
        blockPaint: paint,
        caretVisible: caretVisible,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBlockParagraph renderObject,
  ) {
    renderObject
      ..decoration = decoration
      ..blockPaint = paint
      ..caretVisible = caretVisible;
  }
}

class RenderBlockParagraph extends RenderProxyBox {
  RenderBlockParagraph({
    required this._decoration,
    required this._blockPaint,
    required this._caretVisible,
  });

  /// The laid-out text; offsets in [BlockDecoration] refer to it.
  RenderParagraph get paragraph => child! as RenderParagraph;

  BlockDecoration get decoration => _decoration;
  BlockDecoration _decoration;
  set decoration(BlockDecoration value) {
    if (value == _decoration) return;
    _decoration = value;
    markNeedsPaint();
  }

  BlockPaint get blockPaint => _blockPaint;
  BlockPaint _blockPaint;
  set blockPaint(BlockPaint value) {
    if (value == _blockPaint) return;
    _blockPaint = value;
    markNeedsPaint();
  }

  ValueListenable<bool> get caretVisible => _caretVisible;
  ValueListenable<bool> _caretVisible;
  set caretVisible(ValueListenable<bool> value) {
    if (identical(value, _caretVisible)) return;
    if (attached) _caretVisible.removeListener(_onBlink);
    _caretVisible = value;
    if (attached) _caretVisible.addListener(_onBlink);
    markNeedsPaint();
  }

  void _onBlink() {
    if (_decoration.caret != null) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _caretVisible.addListener(_onBlink);
  }

  @override
  void detach() {
    _caretVisible.removeListener(_onBlink);
    super.detach();
  }

  @override
  void performLayout() {
    final text = paragraph..layout(constraints, parentUsesSize: true);
    // Spaces at the end of the text take no room in the framework's measure
    // of a line, yet the caret goes after them; the paragraph widens to
    // hold them, so a box sizing itself to its text widens as a space is
    // typed, as it does for a letter.
    final spaces = _trailingSpaces();
    size = constraints.constrain(
      Size(
        spaces == null ? text.size.width : math.max(text.size.width, spaces),
        text.size.height,
      ),
    );
  }

  /// Where the spaces the text ends with end, if it ends with any.
  double? _trailingSpaces() {
    final length = paragraph.text.toPlainText().length;
    if (length == 0 || !_isSpaceAt(length - 1)) return null;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: length - 1, extentOffset: length),
    );
    return boxes.isEmpty ? null : boxes.last.right;
  }

  bool _isSpaceAt(int index) {
    final unit = paragraph.text.codeUnitAt(index);
    return unit != null &&
        (unit == 0x20 ||
            unit == 0x09 ||
            unit == 0x1680 ||
            (unit >= 0x2000 && unit <= 0x200A) ||
            unit == 0x205F ||
            unit == 0x3000);
  }

  /// The caret's rectangle for laid-out offset [offset], in local coordinates.
  Rect caretRect(
    int offset, [
    TextAffinity affinity = TextAffinity.downstream,
  ]) {
    final width = _caretWidth;
    final position = TextPosition(offset: offset, affinity: affinity);
    final prototype = Rect.fromLTWH(0, 0, width, _lineHeight);
    var origin = paragraph.getOffsetForCaret(position, prototype);
    var height = paragraph.getFullHeightForCaret(position);
    // After a space at the end of a line the framework puts the caret
    // against the last letter, as short as a glyph, as if the space were not
    // there. The space is measured instead, so typing one moves the caret on.
    if (offset > 0 && _isSpaceAt(offset - 1)) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset - 1, extentOffset: offset),
        boxHeightStyle: BoxHeightStyle.strut,
      );
      // At the start of a wrapped line the caret belongs there, not after
      // the space ending the line above.
      if (boxes.isNotEmpty && (boxes.last.top - origin.dy).abs() < 1) {
        origin = Offset(boxes.last.right, boxes.last.top);
        height = boxes.last.bottom - boxes.last.top;
      }
    }
    return Rect.fromLTWH(
      origin.dx.clamp(0, math.max(0, size.width - width / 2)),
      origin.dy,
      width,
      height > 0 ? height : _lineHeight,
    );
  }

  /// [BlockPaint.caretWidth] converted from screen pixels to local units.
  double get _caretWidth {
    final screen = _blockPaint.caretWidth;
    if (!attached) return screen;
    final scale = getTransformTo(null).getMaxScaleOnAxis();
    return scale > 0 ? screen / scale : screen;
  }

  double get _lineHeight {
    final style = paragraph.text.style;
    final fontSize = style?.fontSize ?? 15;
    return fontSize * (style?.height ?? 1.3);
  }

  /// The rectangles covering laid-out range [start]..[end].
  List<Rect> rangeRects(int start, int end) => <Rect>[
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: BoxHeightStyle.max,
    ))
      box.toRect(),
  ];

  /// The box drawn round the formula laid out over [start]..[end], one
  /// rectangle for each line it is on.
  ///
  /// The layout reports a separate rectangle for each stretch of the line
  /// laid out in one style, which drawn as they are would be a row of boxes.
  List<Rect> formulaRects(int start, int end) {
    final lines = <Rect>[];
    for (final rect in rangeRects(start, end)) {
      final line = lines.indexWhere(
        (other) =>
            math.min(other.bottom, rect.bottom) -
                math.max(other.top, rect.top) >
            math.min(other.height, rect.height) / 2,
      );
      if (line < 0) {
        lines.add(rect);
      } else {
        lines[line] = lines[line].expandToInclude(rect);
      }
    }
    return <Rect>[
      for (final rect in lines)
        Rect.fromLTRB(rect.left, rect.top + 1, rect.right, rect.bottom - 1),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final formula = _decoration.formula;
    if (formula != null) {
      final fill = Paint()..color = _blockPaint.formulaColor;
      final outline = _blockPaint.formulaOutline;
      final stroke = outline == null
          ? null
          : (Paint()
              ..color = outline
              ..style = PaintingStyle.stroke
              ..strokeWidth = _caretWidth * 0.7);
      for (final rect in formulaRects(formula.start, formula.end)) {
        final box = RRect.fromRectAndRadius(
          rect.shift(offset),
          const Radius.circular(3),
        );
        canvas.drawRRect(box, fill);
        if (stroke != null) canvas.drawRRect(box, stroke);
      }
    }

    if (_decoration.matches.isNotEmpty) {
      final paint = Paint()..color = _blockPaint.matchColor;
      for (final match in _decoration.matches) {
        for (final rect in rangeRects(match.start, match.end)) {
          canvas.drawRect(rect.shift(offset), paint);
        }
      }
    }

    final selection = _decoration.selection;
    if (selection != null && !selection.isCollapsed) {
      final paint = Paint()..color = _blockPaint.selectionColor;
      for (final rect in rangeRects(selection.start, selection.end)) {
        canvas.drawRect(rect.shift(offset), paint);
      }
    }

    super.paint(context, offset);

    final composing = _decoration.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      final paint = Paint()
        ..color = _blockPaint.composingColor
        ..strokeWidth = 1;
      for (final rect in rangeRects(composing.start, composing.end)) {
        final y = offset.dy + rect.bottom - 1;
        canvas.drawLine(
          Offset(offset.dx + rect.left, y),
          Offset(offset.dx + rect.right, y),
          paint,
        );
      }
    }

    final caret = _decoration.caret;
    if (caret != null && _caretVisible.value) {
      canvas.drawRect(
        caretRect(caret, _decoration.caretAffinity).shift(offset),
        Paint()..color = _blockPaint.caretColor,
      );
    }
  }
}
