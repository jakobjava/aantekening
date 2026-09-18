/// How one block's text is laid out on screen.
library;

import 'dart:collection';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

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
    this.padded = false,
  });

  /// The run's index in its block.
  final int index;
  final int modelStart;
  final int modelEnd;

  /// Where the run's own text is laid out.
  final int viewStart;
  final int viewEnd;

  /// Whether this run is a typeset formula, standing in the laid-out text as a
  /// single [objectReplacementCharacter].
  final bool collapsed;

  /// Whether this is the formula being edited, laid out with a space of its
  /// own either side of its source: an [objectReplacementCharacter] that is
  /// in the laid-out text but not in the model.
  final bool padded;

  /// Where the run starts and ends in the laid-out text, the space either
  /// side of the formula being edited included.
  int get outerStart => padded ? viewStart - 1 : viewStart;
  int get outerEnd => padded ? viewEnd + 1 : viewEnd;
}

/// A block as it is laid out: which formula (if any) is open for editing, the
/// text the layout and the input method see, and the offset mapping between
/// that text and the model.
///
/// Every formula is typeset except the one being edited, which is shown as
/// its source, so the caret moves through it like any other text. That one
/// has a little room of its own either side, so the box drawn round it sits
/// clear of the text beside it.
class BlockView {
  BlockView(this.block, {this.openRun}) {
    final buffer = StringBuffer();
    var model = 0;
    var view = 0;
    for (var i = 0; i < block.runs.length; i++) {
      final run = block.runs[i];
      final length = run.text.length;
      final collapsed = run.isMath && i != openRun;
      final padded = run.isMath && i == openRun;
      final lead = padded ? 1 : 0;
      final viewLength = collapsed ? 1 : length;
      runs.add(
        RunLayout(
          index: i,
          modelStart: model,
          modelEnd: model + length,
          viewStart: view + lead,
          viewEnd: view + lead + viewLength,
          collapsed: collapsed,
          padded: padded,
        ),
      );
      if (padded) {
        buffer
          ..write(objectReplacementCharacter)
          ..write(run.text)
          ..write(objectReplacementCharacter);
      } else {
        buffer.write(collapsed ? objectReplacementCharacter : run.text);
      }
      model += length;
      view += viewLength + 2 * lead;
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
  /// display style and centred, as OneNote does with such equations.
  bool get isDisplayFormula =>
      block.runs.length == 1 && block.runs.single.isMath && openRun == null;

  /// Maps a model offset to the laid-out text. An offset inside a typeset
  /// formula snaps to its start; the ends of the formula being edited map
  /// inside the room either side of it, where its source starts and ends.
  int toView(int model) {
    for (final run in runs) {
      if (run.padded && model >= run.modelStart && model <= run.modelEnd) {
        return run.viewStart + model - run.modelStart;
      }
      if (model <= run.modelStart) return run.outerStart;
      if (model < run.modelEnd) {
        return run.collapsed
            ? run.viewStart
            : run.viewStart + model - run.modelStart;
      }
    }
    final last = runs.isEmpty ? null : runs.last;
    return last == null ? model : last.outerEnd + model - last.modelEnd;
  }

  /// Maps an offset in the laid-out text back to the model. The room either
  /// side of the formula being edited belongs to its nearer end.
  int toModel(int view) {
    for (final run in runs) {
      if (view <= run.viewStart) return run.modelStart;
      if (view < run.viewEnd) {
        return run.collapsed
            ? run.modelStart
            : run.modelStart + view - run.viewStart;
      }
      if (view <= run.outerEnd) return run.modelEnd;
    }
    final last = runs.isEmpty ? null : runs.last;
    return last == null ? view : last.modelEnd + view - last.outerEnd;
  }

  /// The typeset formula occupying laid-out offset [view], if any.
  RunLayout? collapsedAt(int view) {
    for (final run in runs) {
      if (run.collapsed && run.viewStart == view) return run;
    }
    return null;
  }

  /// The run with index [index].
  RunLayout runAt(int index) => runs[index];

  /// Builds the span the layout draws.
  InlineSpan span({required TextStyle base}) {
    final blockStyle = RichTextStyles.blockStyle(block.kind, base);
    final display = isDisplayFormula;

    return TextSpan(
      style: blockStyle,
      children: <InlineSpan>[
        for (var i = 0; i < block.runs.length; i++)
          _runSpan(block.runs[i], i, blockStyle, display),
      ],
    );
  }

  InlineSpan _runSpan(
    TextRun run,
    int index,
    TextStyle blockStyle,
    bool display,
  ) {
    if (!run.isMath) {
      return TextSpan(
        text: run.text,
        style: RichTextStyles.runStyle(run.marks),
      );
    }
    if (index == openRun) {
      final source = RichTextStyles.formulaSource(blockStyle, run.marks);
      const padding = RichTextStyles.formulaPadding;
      return TextSpan(
        children: <InlineSpan>[
          _room(padding, source),
          TextSpan(text: run.text, style: source),
          _room(
            run.text.isEmpty
                ? RichTextStyles.emptyFormulaWidth - padding
                : padding,
            source,
          ),
        ],
      );
    }
    final marks = RichTextStyles.runStyle(run.marks);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: TypesetFormulas.of(
        run.text,
        run.math!,
        display,
        marks == null ? blockStyle : blockStyle.merge(marks),
      ),
    );
  }
}

/// A blank [width] wide, as tall as a line in [style] and on its baseline,
/// so the caret beside it is as tall as it is beside the letters.
InlineSpan _room(double width, TextStyle style) => WidgetSpan(
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  child: SizedBox(
    width: width,
    child: Text(
      '\u200B',
      style: style,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    ),
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

  static final LinkedHashMap<(String, MathMode, bool, TextStyle), Widget>
  _cache = LinkedHashMap<(String, MathMode, bool, TextStyle), Widget>();

  /// The widget for [source], typeset in display style when [display] is set.
  static Widget of(
    String source,
    MathMode mode,
    bool display,
    TextStyle style,
  ) {
    final key = (source, mode, display, style);
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;

    final widget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: MathView(
        source: source,
        mode: mode,
        displayStyle: display,
        textStyle: style,
      ),
    );
    _cache[key] = widget;
    if (_cache.length > _capacity) _cache.remove(_cache.keys.first);
    return widget;
  }
}
