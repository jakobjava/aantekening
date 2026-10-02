/// The source of the formula being edited, drawn over the text of its box
/// rather than laid out in it.
library;

import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'block_paragraph.dart';

/// The formula being edited, as it is drawn over the text: its source, and
/// the caret, selection and highlights in it, in offsets of the source.
@immutable
class FormulaOverlay {
  const FormulaOverlay({
    required this.paragraph,
    required this.place,
    required this.source,
    this.caret,
    this.selection,
    this.composing,
    this.marks = const <({TextRange range, Color color})>[],
  });

  /// Keys the [BlockParagraph] the formula is in.
  final GlobalKey paragraph;

  /// Where the formula's place is in the text laid out there.
  final int place;

  /// The source, in the style it is typed in.
  final TextSpan source;

  /// Where the caret is, when it shows.
  final int? caret;

  /// The part of the source that is selected, if any.
  final TextSelection? selection;

  /// Source the input method is still composing, underlined.
  final TextRange? composing;

  /// What the highlights in the source mark, each drawn on its colour.
  final List<({TextRange range, Color color})> marks;

  @override
  bool operator ==(Object other) =>
      other is FormulaOverlay &&
      other.paragraph == paragraph &&
      other.place == place &&
      other.source == source &&
      other.caret == caret &&
      other.selection == selection &&
      other.composing == composing &&
      listEquals(other.marks, marks);

  @override
  int get hashCode => Object.hash(
    paragraph,
    place,
    source,
    caret,
    selection,
    composing,
    Object.hashAll(marks),
  );
}

/// Tells what draws the source of the formula being edited that it is to be
/// drawn again.
class FormulaChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// The text of a box, laying out the source of the formula being edited to
/// be drawn over it ([FormulaFieldPainter]).
///
/// The source is laid out across the whole box, its padding included, from
/// its first line on the formula's, onto as many lines beneath as it needs.
/// The text keeps the place the formula had, so nothing in it moves as the
/// source is typed.
class FormulaLayer extends SingleChildRenderObjectWidget {
  const FormulaLayer({
    required this.formula,
    required this.paint,
    required this.changes,
    required this.outset,
    required super.child,
    super.key,
  });

  final FormulaOverlay? formula;
  final BlockPaint paint;

  /// Told whenever the source is laid out again, or is to be drawn
  /// differently, for what draws it to draw it again.
  final FormulaChanges changes;

  /// How far the box reaches beyond this layer on either side: its padding,
  /// which the field the source is typed in spans too.
  final EdgeInsets outset;

  @override
  RenderFormulaLayer createRenderObject(BuildContext context) =>
      RenderFormulaLayer(
        formula: formula,
        blockPaint: paint,
        changes: changes,
        outset: outset,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFormulaLayer renderObject,
  ) {
    renderObject
      ..formula = formula
      ..blockPaint = paint
      ..changes = changes
      ..outset = outset;
  }
}

class RenderFormulaLayer extends RenderProxyBox {
  RenderFormulaLayer({
    required this._formula,
    required this._blockPaint,
    required this._changes,
    required this._outset,
  });

  /// The room above and below the source, inside the field round it.
  static const double _padding = 1;

  final TextPainter _painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    textWidthBasis: TextWidthBasis.longestLine,
  );

  /// The field the source is typed in, in this layer's units, once placed.
  Rect? _box;

  FormulaOverlay? _formula;
  set formula(FormulaOverlay? value) {
    if (value == _formula) return;
    _formula = value;
    markNeedsLayout();
  }

  BlockPaint _blockPaint;
  set blockPaint(BlockPaint value) {
    if (value == _blockPaint) return;
    _blockPaint = value;
    _changes.changed();
  }

  FormulaChanges _changes;
  set changes(FormulaChanges value) {
    if (identical(value, _changes)) return;
    _changes = value;
    markNeedsLayout();
  }

  EdgeInsets _outset;
  set outset(EdgeInsets value) {
    if (value == _outset) return;
    _outset = value;
    markNeedsLayout();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  /// The field the source of the formula being edited is typed in, in this
  /// layer's units.
  Rect? get formulaBox => _box;

  Offset get _textOrigin => _box!.topLeft + Offset(_outset.left, _padding);

  /// The offset in the source nearest [local], a point in this layer's units
  /// on or right beside the field; null for one elsewhere.
  int? sourceOffsetAt(Offset local) {
    final box = _box;
    if (box == null || !box.inflate(2).contains(local)) return null;
    return _painter.getPositionForOffset(local - _textOrigin).offset;
  }

  /// The caret at [offset] in the source, in this layer's units.
  Rect? sourceCaretRect(int offset) {
    if (_box == null) return null;
    final position = TextPosition(offset: offset);
    final top = _painter.getOffsetForCaret(position, Rect.zero);
    final height = _painter.getFullHeightForCaret(position, Rect.zero);
    final width = _blockPaint.caretWidth * screenPixelIn(this);
    return Rect.fromLTWH(top.dx, top.dy, width, height).shift(_textOrigin);
  }

  @override
  void performLayout() {
    super.performLayout();
    _box = null;
    _changes.changed();
    final formula = _formula;
    final paragraph = formula?.paragraph.currentContext?.findRenderObject();
    if (formula == null ||
        paragraph is! RenderBlockParagraph ||
        !paragraph.hasSize) {
      return;
    }
    final boxes = paragraph.paragraph.getBoxesForSelection(
      TextSelection(baseOffset: formula.place, extentOffset: formula.place + 1),
    );
    if (boxes.isEmpty) return;
    final place = MatrixUtils.transformRect(
      paragraph.getTransformTo(this),
      boxes.first.toRect(),
    );

    final across = size.width;
    _painter
      ..text = formula.source
      ..layout(minWidth: across, maxWidth: across);
    final lines = _painter.computeLineMetrics();
    final firstLine = lines.isEmpty
        ? _painter.preferredLineHeight
        : lines.first.height;
    // Its first line on the formula's, as the text was typed there.
    _box = Rect.fromLTWH(
      -_outset.left,
      place.center.dy - firstLine / 2 - _padding,
      across + _outset.horizontal,
      _painter.height + 2 * _padding,
    );
  }

  /// Draws the field the source is typed in, with the caret in it if
  /// [caretShows], onto [canvas] in this layer's units.
  void paintField(Canvas canvas, {required bool caretShows}) {
    final formula = _formula;
    final box = _box;
    if (formula == null || box == null || !attached) return;
    final text = _textOrigin;
    List<Rect> rangeRects(int start, int end) => <Rect>[
      for (final rect in _painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
        boxHeightStyle: BoxHeightStyle.max,
      ))
        rect.toRect().shift(text),
    ];

    canvas.drawRect(box, Paint()..color = _blockPaint.formulaColor);
    for (final mark in formula.marks) {
      final paint = Paint()..color = mark.color;
      for (final rect in rangeRects(mark.range.start, mark.range.end)) {
        canvas.drawRect(rect, paint);
      }
    }
    _painter.paint(canvas, text);

    final selection = formula.selection;
    if (selection != null && !selection.isCollapsed) {
      final paint = Paint()..color = _blockPaint.selectionColor;
      for (final rect in rangeRects(selection.start, selection.end)) {
        canvas.drawRect(rect, paint);
      }
    }
    final composing = formula.composing;
    if (composing != null && composing.isValid && !composing.isCollapsed) {
      final paint = Paint()
        ..color = _blockPaint.composingColor
        ..strokeWidth = screenPixelIn(this);
      for (final rect in rangeRects(composing.start, composing.end)) {
        canvas.drawLine(
          rect.bottomLeft.translate(0, -1),
          rect.bottomRight.translate(0, -1),
          paint,
        );
      }
    }

    final outline = _blockPaint.formulaOutline;
    if (outline != null) {
      canvas.drawRect(
        box,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = _blockPaint.caretWidth * 0.7 * screenPixelIn(this),
      );
    }

    final caret = formula.caret;
    if (caret != null && caretShows) {
      final rect = sourceCaretRect(caret);
      if (rect != null) {
        canvas.drawRect(rect, Paint()..color = _blockPaint.caretColor);
      }
    }
  }
}

/// Draws the field laid out by the [FormulaLayer] [layer] keys, in that
/// layer's units: put where the layer is ([CompositedTransformFollower]) over
/// everything else on the page, the frame and handles round the box
/// included. It takes the presses that land on it.
class FormulaFieldPainter extends CustomPainter {
  FormulaFieldPainter({
    required this.layer,
    required this.caretVisible,
    required Listenable changes,
  }) : super(repaint: Listenable.merge(<Listenable>[changes, caretVisible]));

  final GlobalKey layer;

  /// Toggled by the editor to blink the caret without rebuilding anything.
  final ValueListenable<bool> caretVisible;

  RenderFormulaLayer? get _layer {
    final object = layer.currentContext?.findRenderObject();
    return object is RenderFormulaLayer ? object : null;
  }

  @override
  void paint(Canvas canvas, Size size) =>
      _layer?.paintField(canvas, caretShows: caretVisible.value);

  @override
  bool hitTest(Offset position) =>
      _layer?.formulaBox?.inflate(2).contains(position) ?? false;

  @override
  bool shouldRepaint(FormulaFieldPainter oldDelegate) =>
      oldDelegate.layer != layer || oldDelegate.caretVisible != caretVisible;
}
