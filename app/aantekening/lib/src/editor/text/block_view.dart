/// How one block's text is laid out on screen.
library;

import 'dart:collection';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'formula_overlay.dart' show FormulaOverlay;
import 'shrink_to_width.dart';
import 'text_styles.dart';

/// The character a typeset formula occupies in laid-out text.
///
/// The framework represents every inline widget by this one code point, so a
/// formula whose source is `x^2` is three characters in the model but one on
/// screen. [BlockView] maps between the two.
const String objectReplacementCharacter = '\uFFFC';

/// Where one run sits in the model's offsets and in the laid-out text.
class RunLayout {
  const RunLayout({
    required this.index,
    required this.modelStart,
    required this.modelEnd,
    required this.viewStart,
    required this.viewEnd,
    required this.collapsed,
    this.open = false,
  });

  /// The run's index in its block.
  final int index;
  final int modelStart;
  final int modelEnd;

  /// Where the run's own text is laid out.
  final int viewStart;
  final int viewEnd;

  /// Whether this run is a formula, standing in the laid-out text as a
  /// single [objectReplacementCharacter].
  final bool collapsed;

  /// Whether this is the formula being edited: its place in the text is
  /// kept, and its source drawn over it ([FormulaOverlay]).
  final bool open;
}

/// A block as it is laid out: which formula (if any) is open for editing, the
/// text the layout and the input method see, and the offset mapping between
/// that text and the model.
///
/// Every formula stands in the text as one character, the one being edited
/// too: its place is kept as it was while its source is typed over it, so
/// nothing around it moves.
class BlockView {
  BlockView(this.block, {this.openRun}) {
    final buffer = StringBuffer();
    var model = 0;
    var view = 0;
    for (var i = 0; i < block.runs.length; i++) {
      final run = block.runs[i];
      final length = run.text.length;
      final collapsed = run.isMath;
      final viewLength = collapsed ? 1 : length;
      runs.add(
        RunLayout(
          index: i,
          modelStart: model,
          modelEnd: model + length,
          viewStart: view,
          viewEnd: view + viewLength,
          collapsed: collapsed,
          open: i == openRun,
        ),
      );
      buffer.write(collapsed ? objectReplacementCharacter : run.text);
      model += length;
      view += viewLength;
    }
    text = buffer.toString();
  }

  final TextBlock block;

  /// The index of the formula run being edited, shown as its source.
  final int? openRun;

  final List<RunLayout> runs = <RunLayout>[];

  /// The text as laid out and as the input method sees it.
  late final String text;

  /// Whether this block is a formula alone on its line, which is typeset in
  /// display style, as OneNote does with such equations. It sits where its
  /// paragraph is aligned: centred only if that is centred.
  bool get isDisplayFormula =>
      block.runs.length == 1 && block.runs.single.isMath;

  /// Maps a model offset to the laid-out text. An offset inside a formula
  /// snaps to its start.
  int toView(int model) {
    for (final run in runs) {
      if (model <= run.modelStart) return run.viewStart;
      if (model < run.modelEnd) {
        return run.collapsed
            ? run.viewStart
            : run.viewStart + model - run.modelStart;
      }
    }
    final last = runs.isEmpty ? null : runs.last;
    return last == null ? model : last.viewEnd + model - last.modelEnd;
  }

  /// Maps an offset in the laid-out text back to the model.
  int toModel(int view) {
    for (final run in runs) {
      if (view <= run.viewStart) return run.modelStart;
      if (view < run.viewEnd) {
        return run.collapsed
            ? run.modelStart
            : run.modelStart + view - run.viewStart;
      }
    }
    final last = runs.isEmpty ? null : runs.last;
    return last == null ? view : last.modelEnd + view - last.viewEnd;
  }

  /// The typeset formula occupying laid-out offset [view], if any: not the
  /// one being edited.
  RunLayout? collapsedAt(int view) {
    for (final run in runs) {
      if (run.collapsed && !run.open && run.viewStart == view) return run;
    }
    return null;
  }

  /// The run with index [index].
  RunLayout runAt(int index) => runs[index];

  /// Builds the span the layout draws, with links drawn in [mark].
  ///
  /// The formula being edited is typeset as it is [open], as LaTeX: as its
  /// source last could be, its source being drawn beneath it; empty while
  /// nothing typesets, as for a new one.
  InlineSpan span({
    required TextStyle base,
    required Color mark,
    String open = '',
  }) {
    final blockStyle = RichTextStyles.blockStyleOf(block, base);
    final display = isDisplayFormula;

    return TextSpan(
      style: blockStyle,
      children: <InlineSpan>[
        for (var i = 0; i < block.runs.length; i++)
          _runSpan(block.runs[i], i, blockStyle, display, mark, open),
      ],
    );
  }

  InlineSpan _runSpan(
    TextRun run,
    int index,
    TextStyle blockStyle,
    bool display,
    Color mark,
    String open,
  ) {
    if (!run.isMath) {
      return TextSpan(
        text: run.text,
        style: RichTextStyles.runStyle(run.marks, link: mark),
      );
    }
    // A formula in the inverse of what is beneath is typeset white, and
    // laid on what is beneath as text in it is.
    final inverted = run.marks.color == NoteColors.inverse;
    final marks = RichTextStyles.runStyle(
      inverted ? run.marks.withColor(null) : run.marks,
      link: mark,
    );
    final style = marks == null ? blockStyle : blockStyle.merge(marks);
    if (index == openRun && open.trim().isEmpty) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _room(
          RichTextStyles.emptyFormulaWidth,
          RichTextStyles.formulaSource(blockStyle, run.marks, accent: mark),
        ),
      );
    }
    final formula = TypesetFormulas.of(
      index == openRun ? open : run.text,
      index == openRun ? MathMode.latex : run.math!,
      display,
      inverted ? style.copyWith(color: RichTextStyles.inverse.color) : style,
      packages: run.imported,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: inverted ? _Inverting(child: formula) : formula,
    );
  }
}

/// Lays its child, drawn white, on what lies beneath it with
/// [RichTextStyles.inverse], so that it shows that inverted.
class _Inverting extends SingleChildRenderObjectWidget {
  const _Inverting({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInverting();
}

class _RenderInverting extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // What paints into a layer of its own cannot be gathered into one
    // here, and is drawn as it is.
    if (child.needsCompositing) {
      context.paintChild(child, offset);
      return;
    }
    context.canvas.saveLayer(offset & size, RichTextStyles.inverse);
    context.paintChild(child, offset);
    context.canvas.restore();
  }
}

/// A blank [width] wide, as tall as a line in [style] and on its baseline,
/// so the caret beside it is as tall as it is beside the letters.
Widget _room(double width, TextStyle style) => SizedBox(
  width: width,
  child: Text(
    '\u200B',
    style: style,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  ),
);

/// Typeset formulas, cached by exactly what they show.
///
/// Every keystroke rebuilds the text boxes on screen. Handing the framework the
/// same widget instance for an unchanged formula lets it skip that subtree, so
/// a page full of formulas is not re-parsed and re-typeset for each letter
/// typed.
abstract final class TypesetFormulas {
  static const int _capacity = 512;

  /// The room a formula keeps above and below it, as a share of its size:
  /// with the same below the formula over it, the room TeX keeps between
  /// lines whose boxes would otherwise meet.
  static const double _clearance = 0.1;

  static final LinkedHashMap<(String, MathMode, bool, TextStyle, bool), Widget>
  _cache = LinkedHashMap<(String, MathMode, bool, TextStyle, bool), Widget>();

  /// The widget for [source], typeset in display style when [display] is set,
  /// reading the packages LaTeX brought in uses if [packages] is.
  static Widget of(
    String source,
    MathMode mode,
    bool display,
    TextStyle style, {
    bool packages = false,
  }) {
    final key = (source, mode, display, style, packages);
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;

    // A formula cannot wrap: one wider than its line is made smaller. It
    // keeps a little room above and below, within the line where it is no
    // taller than the text, so a fraction never touches the one on the
    // line above.
    final clearance = (style.fontSize ?? RichTextStyles.bodySize) * _clearance;
    final widget = ShrinkToWidth(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 1, vertical: clearance),
        child: MathView(
          source: source,
          mode: mode,
          displayStyle: display,
          textStyle: style,
          packages: packages,
        ),
      ),
    );
    _cache[key] = widget;
    if (_cache.length > _capacity) _cache.remove(_cache.keys.first);
    return widget;
  }
}
