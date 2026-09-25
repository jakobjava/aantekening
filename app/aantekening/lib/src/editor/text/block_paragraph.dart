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
    this.typingStyle,
    this.composing,
    this.formula,
    this.formulaMarks = const <({TextRange range, Color color})>[],
    this.matches = const <TextRange>[],
    this.misspellings = const <TextRange>[],
  });

  static const BlockDecoration none = BlockDecoration();

  /// The part of this block that is selected, if any.
  final TextSelection? selection;

  /// Where the caret is, when it is in this block.
  final int? caret;

  /// Which side of a line break the caret belongs to.
  final TextAffinity caretAffinity;

  /// The style what is typed next will have, when it differs from the text
  /// at the caret: a font size chosen with nothing selected. The caret is
  /// drawn at its size, as it will be once something is typed.
  final TextStyle? typingStyle;

  /// Text the input method is still composing, underlined.
  final TextRange? composing;

  /// The formula being edited, its source and the room either side of it,
  /// drawn in a tinted, outlined box.
  final TextRange? formula;

  /// What the highlights in the source of the formula being edited mark,
  /// each drawn on its colour inside the formula's box.
  final List<({TextRange range, Color color})> formulaMarks;

  /// Words a search found, marked behind the text.
  final List<TextRange> matches;

  /// Words spelled wrongly, underlined with a wavy line.
  final List<TextRange> misspellings;

  @override
  bool operator ==(Object other) =>
      other is BlockDecoration &&
      other.selection == selection &&
      other.caret == caret &&
      other.caretAffinity == caretAffinity &&
      other.typingStyle == typingStyle &&
      other.composing == composing &&
      other.formula == formula &&
      listEquals(other.formulaMarks, formulaMarks) &&
      listEquals(other.matches, matches) &&
      listEquals(other.misspellings, misspellings);

  @override
  int get hashCode => Object.hash(
    selection,
    caret,
    caretAffinity,
    typingStyle,
    composing,
    formula,
    Object.hashAll(formulaMarks),
    Object.hashAll(matches),
    Object.hashAll(misspellings),
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
    required this.misspellingColor,
    this.formulaOutline,
    this.caretWidth = 1.6,
  });

  final Color caretColor;
  final Color selectionColor;
  final Color formulaColor;

  /// Behind the words a search found.
  final Color matchColor;

  /// The wavy line beneath a word spelled wrongly.
  final Color misspellingColor;

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
      other.misspellingColor == misspellingColor &&
      other.caretWidth == caretWidth;

  @override
  int get hashCode => Object.hash(
    caretColor,
    selectionColor,
    formulaColor,
    formulaOutline,
    composingColor,
    matchColor,
    misspellingColor,
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

  /// The caret's rectangle for laid-out offset [offset], in local
  /// coordinates: as tall as the text beside it on its line, or as text in
  /// [typingStyle] would be there.
  ///
  /// The height is measured from a character beside the caret rather than
  /// taken from the framework's caret metrics, which at the end of the text
  /// size and place the caret by the paragraph's base style: in a line of
  /// large text the caret was small and hung below it.
  Rect caretRect(
    int offset, [
    TextAffinity affinity = TextAffinity.downstream,
    TextStyle? typingStyle,
  ]) {
    final width = _caretWidth;
    final position = TextPosition(offset: offset, affinity: affinity);
    var x = paragraph
        .getOffsetForCaret(position, Rect.fromLTWH(0, 0, width, 0))
        .dx;

    final (box, boxOffset) = _caretNeighbour(offset, affinity);
    double top;
    double bottom;
    if (box == null) {
      // No character on the line: an empty paragraph.
      top = paragraph.getOffsetForCaret(position, Rect.zero).dy;
      bottom = top + paragraph.getFullHeightForCaret(position);
    } else {
      top = box.top;
      bottom = box.bottom;
      // After a space at the end of a line the framework puts the caret
      // against the last letter, as if the space were not there. The space
      // is measured instead, so typing one moves the caret on.
      if (boxOffset == offset - 1 && _isSpaceAt(boxOffset)) x = box.right;
    }

    final style = typingStyle;
    if (style != null) {
      // Placed on the line's baseline, found from the character beside it.
      final line = box == null ? null : _styleAt(boxOffset);
      final baseline = box == null
          ? top + _StyleMetrics.of(paragraph.text.style!).lineBaseline
          : line == null
          ? bottom - _StyleMetrics.of(paragraph.text.style!).descent
          : top + _StyleMetrics.of(line).ascent;
      final typing = _StyleMetrics.of(style);
      top = baseline - typing.ascent;
      bottom = baseline + typing.descent;
    }

    return Rect.fromLTRB(
      x.clamp(0, math.max(0, size.width - width / 2)),
      top,
      x.clamp(0, math.max(0, size.width - width / 2)) + width,
      bottom > top ? bottom : top + _lineHeight,
    );
  }

  /// The box of the character the caret at [offset] takes its height from,
  /// and that character's offset: the one before it on its line, or the one
  /// after where none is before; a letter rather than an object in the
  /// text, a formula, where there is one.
  (Rect?, int) _caretNeighbour(int offset, TextAffinity affinity) {
    final length = paragraph.text
        .toPlainText(includeSemanticsLabels: false)
        .length;
    Rect? boxOf(int at) {
      if (at < 0 || at >= length) return null;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: at, extentOffset: at + 1),
      );
      return boxes.isEmpty ? null : boxes.first.toRect();
    }

    var before = boxOf(offset - 1);
    var after = boxOf(offset);
    // At a wrap, the caret is on one line or the other.
    if (before != null && after != null && before.bottom <= after.top + 0.5) {
      if (affinity == TextAffinity.downstream) {
        before = null;
      } else {
        after = null;
      }
    }
    final candidates = <(Rect, int)>[
      if (before != null) (before, offset - 1),
      if (after != null) (after, offset),
    ];
    if (candidates.isEmpty) return (null, -1);
    for (final candidate in candidates) {
      if (!_isObjectAt(candidate.$2)) return candidate;
    }
    return candidates.first;
  }

  bool _isObjectAt(int index) => paragraph.text.codeUnitAt(index) == 0xFFFC;

  /// The style the character at laid-out [offset] is drawn in, or null for
  /// an object in the text.
  TextStyle? _styleAt(int offset) {
    TextStyle? found;
    var position = 0;
    bool visit(InlineSpan span, TextStyle? inherited) {
      final own = span.style;
      final style = own == null ? inherited : (inherited?.merge(own) ?? own);
      if (span is TextSpan) {
        final text = span.text;
        if (text != null) {
          if (offset < position + text.length) {
            found = style;
            return false;
          }
          position += text.length;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          if (!visit(child, style)) return false;
        }
        return true;
      }
      if (offset == position) return false;
      position++;
      return true;
    }

    visit(paragraph.text, null);
    return found;
  }

  /// [BlockPaint.caretWidth] converted from screen pixels to local units.
  double get _caretWidth => _blockPaint.caretWidth * _pixel;

  double get _pixel => screenPixelIn(this);

  /// Draws a wavy line beneath each word spelled wrongly, the same size on
  /// screen at any zoom, as word processors draw it.
  void _paintMisspellings(Canvas canvas, Offset offset) {
    final pixel = _pixel;
    final amplitude = 1.2 * pixel;
    final wavelength = 4 * pixel;
    final paint = Paint()
      ..color = _blockPaint.misspellingColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = pixel;
    for (final word in _decoration.misspellings) {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      )) {
        final rect = box.toRect().shift(offset);
        final y = rect.bottom - amplitude;
        final path = Path()..moveTo(rect.left, y);
        var up = true;
        for (var x = rect.left; x < rect.right; x += wavelength / 2) {
          final end = math.min(x + wavelength / 2, rect.right);
          path.quadraticBezierTo(
            (x + end) / 2,
            y + (up ? -amplitude : amplitude) * 2,
            end,
            y,
          );
          up = !up;
        }
        canvas.drawPath(path, paint);
      }
    }
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

  /// The box drawn round the formula laid out over [start]..[end] — the room
  /// either side of its source included — one rectangle for each line it is
  /// on.
  ///
  /// The layout reports a separate rectangle for each stretch of the line
  /// laid out in one style, which drawn as they are would be a row of boxes.
  /// The room at one end may wrap onto a line of its own in a narrow box;
  /// that line is left out, rather than drawn as a sliver of box beside text
  /// the formula is not on.
  List<Rect> formulaRects(int start, int end) {
    final source = _lines(rangeRects(start + 1, end - 1));
    // An empty formula is nothing but the room to type in.
    final lines = source.isEmpty ? _lines(rangeRects(start, end)) : source;
    if (source.isNotEmpty) {
      for (final room in <Rect>[
        ...rangeRects(start, start + 1),
        ...rangeRects(end - 1, end),
      ]) {
        final line = _lineOf(lines, room);
        if (line >= 0) lines[line] = lines[line].expandToInclude(room);
      }
    }
    return <Rect>[
      for (final rect in lines)
        Rect.fromLTRB(rect.left, rect.top + 1, rect.right, rect.bottom - 1),
    ];
  }

  /// [rects] gathered into one rectangle for each line they lie on.
  static List<Rect> _lines(List<Rect> rects) {
    final lines = <Rect>[];
    for (final rect in rects) {
      final line = _lineOf(lines, rect);
      if (line < 0) {
        lines.add(rect);
      } else {
        lines[line] = lines[line].expandToInclude(rect);
      }
    }
    return lines;
  }

  /// Which of [lines] [rect] lies on — the one it overlaps by more than half
  /// its height — or -1 for none of them.
  static int _lineOf(List<Rect> lines, Rect rect) => lines.indexWhere(
    (other) =>
        math.min(other.bottom, rect.bottom) - math.max(other.top, rect.top) >
        math.min(other.height, rect.height) / 2,
  );

  /// Where the caret is drawn, or null where none is: [caretRect] for the
  /// caret the decoration names, kept within the box round the formula being
  /// edited while it stands in that.
  Rect? get drawnCaret {
    final caret = _decoration.caret;
    if (caret == null) return null;
    final rect = caretRect(
      caret,
      _decoration.caretAffinity,
      _decoration.typingStyle,
    );
    final formula = _decoration.formula;
    if (formula == null || caret < formula.start || caret > formula.end) {
      return rect;
    }
    return _inside(formulaRects(formula.start, formula.end), rect);
  }

  /// The rectangles covering laid-out range [start]..[end], those in the
  /// formula being edited kept within the box round it, as the caret is.
  List<Rect> _rectsIn(int start, int end) {
    final formula = _decoration.formula;
    if (formula == null || end <= formula.start || start >= formula.end) {
      return rangeRects(start, end);
    }
    final boxes = formulaRects(formula.start, formula.end);
    final from = math.max(start, formula.start);
    final to = math.min(end, formula.end);
    return <Rect>[
      if (start < from) ...rangeRects(start, from),
      for (final rect in rangeRects(from, to)) _inside(boxes, rect),
      if (to < end) ...rangeRects(to, end),
    ];
  }

  /// [caret] kept within whichever of [boxes] it stands on, so the caret in a
  /// formula never reaches past the box drawn round it.
  static Rect _inside(List<Rect> boxes, Rect caret) {
    for (final box in boxes) {
      if (caret.bottom <= box.top || caret.top >= box.bottom) continue;
      return Rect.fromLTRB(
        caret.left,
        math.max(caret.top, box.top),
        caret.right,
        math.min(caret.bottom, box.bottom),
      );
    }
    return caret;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final formula = _decoration.formula;
    final boxes = formula == null
        ? const <Rect>[]
        : <Rect>[
            for (final rect in formulaRects(formula.start, formula.end))
              rect.shift(offset),
          ];
    if (formula != null) {
      final fill = Paint()..color = _blockPaint.formulaColor;
      for (final box in boxes) {
        canvas.drawRect(box, fill);
      }
      for (final mark in _decoration.formulaMarks) {
        final paint = Paint()..color = mark.color;
        for (final rect in _rectsIn(mark.range.start, mark.range.end)) {
          canvas.drawRect(rect.shift(offset), paint);
        }
      }
      final outline = _blockPaint.formulaOutline;
      if (outline != null) {
        final stroke = Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = _caretWidth * 0.7;
        for (final box in boxes) {
          canvas.drawRect(box, stroke);
        }
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

    super.paint(context, offset);

    // Over the text, translucent, so it shows on highlighted text too.
    final selection = _decoration.selection;
    if (selection != null && !selection.isCollapsed) {
      final paint = Paint()..color = _blockPaint.selectionColor;
      for (final rect in _rectsIn(selection.start, selection.end)) {
        canvas.drawRect(rect.shift(offset), paint);
      }
    }

    if (_decoration.misspellings.isNotEmpty) {
      _paintMisspellings(canvas, offset);
    }

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

    final caret = drawnCaret;
    if (caret != null && _caretVisible.value) {
      canvas.drawRect(
        caret.shift(offset),
        Paint()..color = _blockPaint.caretColor,
      );
    }
  }
}

/// A screen pixel in [object]'s own units, which differ from pixels as the
/// page is zoomed.
///
/// What is drawn on the paper to work with rather than to keep — a caret, the
/// handles round a picture — is sized in screen pixels through this, so it
/// stays the same size however far the page is zoomed.
double screenPixelIn(RenderObject object) {
  if (!object.attached) return 1;
  final scale = object.getTransformTo(null).getMaxScaleOnAxis();
  return scale > 0 ? 1 / scale : 1;
}

/// How far text in a style reaches above and below its baseline, as the
/// layout measures a character's box, and where the baseline is in a line
/// of it.
final class _StyleMetrics {
  const _StyleMetrics(this.ascent, this.descent, this.lineBaseline);

  static final Map<TextStyle, _StyleMetrics> _cache =
      <TextStyle, _StyleMetrics>{};

  static _StyleMetrics of(TextStyle style) {
    final cached = _cache[style];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final box = painter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .first;
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    if (_cache.length > 64) _cache.clear();
    return _cache[style] = _StyleMetrics(
      baseline - box.top,
      box.bottom - baseline,
      baseline,
    );
  }

  final double ascent;
  final double descent;

  /// How far below the top of a line the baseline is.
  final double lineBaseline;
}
