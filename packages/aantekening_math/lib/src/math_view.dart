/// Widgets that typeset a formula from either authoring mode.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart' show TexParser;

import 'linear_math.dart';
import 'renderer_latex.dart';

/// Renders a formula written in [mode].
///
/// Typesetting happens natively through flutter_math_fork rather than in a web
/// view: it keeps formulas as fast to paint as any other element on the canvas,
/// and it works identically on Linux, Windows and Android.
class MathView extends StatelessWidget {
  const MathView({
    required this.source,
    required this.mode,
    super.key,
    this.displayStyle = true,
    this.textStyle,
  });

  /// Renders the formula held by [element].
  factory MathView.element(MathElement element, {Key? key, TextStyle? style}) =>
      MathView(
        key: key,
        source: element.source,
        mode: element.mode,
        displayStyle: element.displayStyle,
        textStyle: style,
      );

  /// The formula, in whichever syntax [mode] names.
  final String source;

  final MathMode mode;

  /// Display style centres the formula and uses full-size operators; inline
  /// style keeps it on the text baseline.
  final bool displayStyle;

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) {
      return _Placeholder(style: textStyle);
    }

    final latex = RendererLatex.of(LinearMath.latexFor(mode, source));
    SyntaxTree? tree;
    ParseException? error;
    try {
      tree = SyntaxTree(
        greenRoot: typesetHighlights(
          TexParser(latex, const TexParserSettings()).parse(),
        ),
      );
    } on ParseException catch (e) {
      error = e;
    } on Object catch (e) {
      // The typesetter's own parser can fail in ways it does not describe.
      error = ParseException('$e');
    }
    return Math(
      ast: tree,
      parseError: error,
      mathStyle: displayStyle ? MathStyle.display : MathStyle.text,
      textStyle: textStyle ?? DefaultTextStyle.of(context).style,
      // A formula that TeX itself rejects still has to show something, or the
      // page would appear to lose content while it is being edited.
      onErrorFallback: (error) => _MathError(
        message: error.messageWithType,
        source: source,
        style: textStyle,
      ),
    );
  }

  /// [node] with each highlight typeset as it should be: its colour painted,
  /// and what it marks at the size it would have without it.
  ///
  /// A highlight is stored as `\colorbox{…}{$…$}`. The typesetter paints a
  /// box's colour only where the box has a border, so each is given one in
  /// its own colour. And TeX typesets the `$…$` in text style whatever
  /// surrounds it: a highlighted fraction on a line of its own shrank, and a
  /// highlighted exponent grew. Leaving that style out lets the marked part
  /// keep its size.
  @visibleForTesting
  static T typesetHighlights<T extends GreenNode>(T node) {
    final children = node.children;
    // A copy of the node's own list, so it takes only children of the kind
    // the node holds.
    final kept = children.toList();
    var changed = false;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child == null) continue;
      final typeset = typesetHighlights(child);
      if (!identical(typeset, child)) {
        kept[i] = typeset;
        changed = true;
      }
    }
    final updated = changed ? node.updateChildren(kept) as T : node;
    if (updated is! EnclosureNode ||
        updated.backgroundcolor == null ||
        updated.hasBorder) {
      return updated;
    }
    final base = updated.base;
    final only = base.children.length == 1 ? base.children.single : null;
    // The maths `$…$` sets in text style, to be set in the style around it
    // instead.
    final marked =
        only is StyleNode &&
            only.optionsDiff.style == MathStyle.text &&
            only.optionsDiff.size == null &&
            only.optionsDiff.color == null &&
            only.optionsDiff.textFontOptions == null &&
            only.optionsDiff.mathFontOptions == null
        ? only.children
        : null;
    return EnclosureNode(
          base: marked == null ? base : base.updateChildren(marked),
          hasBorder: true,
          bordercolor: updated.backgroundcolor,
          backgroundcolor: updated.backgroundcolor,
          notation: updated.notation,
          horizontalPadding: updated.horizontalPadding,
          verticalPadding: updated.verticalPadding,
        )
        as T;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Text(
      '□',
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        color: color,
      ),
    );
  }
}

class _MathError extends StatelessWidget {
  const _MathError({required this.message, required this.source, this.style});

  final String message;
  final String source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            source,
            style: (style ?? DefaultTextStyle.of(context).style).copyWith(
              fontFamily: 'monospace',
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}
