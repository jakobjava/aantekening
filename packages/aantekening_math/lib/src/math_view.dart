/// Widgets that typeset a formula from either authoring mode.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart' show TexParser;

import 'linear_math.dart';
import 'packages/latex_packages.dart';
import 'renderer_latex.dart';
import 'tikz/tikz_picture.dart';
import 'tikz/tikz_view.dart';

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
    this.packages = false,
  });

  /// Renders the formula held by [element].
  /// The formula, in whichever syntax [mode] names.
  final String source;

  final MathMode mode;

  /// Display style centres the formula and uses full-size operators; inline
  /// style keeps it on the text baseline.
  final bool displayStyle;

  final TextStyle? textStyle;

  /// Whether the packages LaTeX documents use for physics, chemistry and
  /// units — physics, mhchem, siunitx — are read: in a formula brought in
  /// as LaTeX ([LatexPackages]).
  final bool packages;

  /// [latex] as the typesetter is given it: with the commands it defines
  /// itself and what [preamble] sets written into it, and the packages'
  /// commands written out if it may use them, [packages].
  static String prepared(
    String latex, {
    LatexPreamble? preamble,
    bool packages = false,
  }) {
    // What the formula defines itself — a picture's `\newcommand`s and
    // `\def`s, before it uses them — is written out as a preamble's is.
    final own = LatexPreamble();
    final written = own.apply(own.takeFrom(latex));
    final applied = preamble == null ? written : preamble.apply(written);
    return packages ? LatexPackages.expand(applied) : applied;
  }

  /// What keeps [latex] from being typeset, or null where nothing does;
  /// [preamble] and [packages] as for [prepared].
  static String? problemIn(
    String latex, {
    LatexPreamble? preamble,
    bool packages = false,
  }) {
    final ready = prepared(latex, preamble: preamble, packages: packages);
    if (TikzPicture.holds(ready)) return TikzPicture.problemIn(ready);
    return switch (_parse(ready)) {
      (_, final error?) => error.message,
      _ => null,
    };
  }

  /// [latex] read by the typesetter, or why it cannot be.
  static (SyntaxTree?, ParseException?) _parse(String latex) {
    try {
      return (
        SyntaxTree(
          greenRoot: typesetHighlights(
            TexParser(
              RendererLatex.of(latex),
              const TexParserSettings(),
            ).parse(),
          ),
        ),
        null,
      );
    } on ParseException catch (e) {
      return (null, e);
    } on Object catch (e) {
      // The typesetter's own parser can fail in ways it does not describe.
      return (null, ParseException('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) {
      return _Placeholder(style: textStyle);
    }
    final latex = prepared(
      LinearMath.latexFor(mode, source),
      preamble: MathPreamble.of(context),
      packages: packages,
    );
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    if (TikzPicture.holds(latex)) {
      try {
        return TikzView(picture: TikzPicture.read(latex), style: style);
      } on FormatException catch (e) {
        return _MathError(message: e.message, source: source, style: style);
      }
    }
    final (tree, error) = _parse(latex);
    return Math(
      ast: tree,
      parseError: error,
      mathStyle: displayStyle ? MathStyle.display : MathStyle.text,
      textStyle: style,
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

/// What every formula beneath it is typeset with: the commands and TikZ
/// styles the person has set ([LatexPreamble]).
class MathPreamble extends InheritedWidget {
  const MathPreamble({required this.preamble, required super.child, super.key});

  final LatexPreamble preamble;

  /// The preamble the formulas at [context] are typeset with, if any.
  static LatexPreamble? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MathPreamble>()?.preamble;

  /// [of], outside a build: nothing is built again when it changes.
  static LatexPreamble? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MathPreamble>()?.preamble;

  @override
  bool updateShouldNotify(MathPreamble oldWidget) =>
      !identical(oldWidget.preamble, preamble);
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
