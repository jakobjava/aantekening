/// Widgets that typeset a formula from either authoring mode.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart' show TexParser;

import 'linear_math.dart';
import 'packages/latex_packages.dart';
import 'tikz/tikz_picture.dart';
import 'tikz/tikz_view.dart';

/// Renders a formula written in [mode].
///
/// Typesetting happens natively through flutter_math_fork rather than in a web
/// view: it keeps formulas as fast to paint as any other element on the canvas,
/// and it works identically on Linux, Windows and Android.
class MathView extends StatefulWidget {
  const MathView({
    required this.source,
    required this.mode,
    super.key,
    this.displayStyle = true,
    this.textStyle,
    this.packages = false,
  });

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
    return LatexPackages.expand(applied, chemistryOnly: !packages);
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
    final read = _parse(ready);
    // Asked as a formula is typed, before the formula is typeset as it now
    // stands: what was read is kept for the view that typesets it next.
    _unshown.remove(ready);
    if (_unshown.length >= _keptUnshown) _unshown.remove(_unshown.keys.first);
    _unshown[ready] = read;
    return read.$2?.message;
  }

  /// Formulas read by [problemIn] and not yet typeset, by their prepared
  /// LaTeX. A tree is given to one view only: the typesetter keeps what it
  /// built from each node in the node, and two views showing one tree at
  /// once would show one widget in two places.
  static final Map<String, (SyntaxTree?, ParseException?)> _unshown =
      <String, (SyntaxTree?, ParseException?)>{};

  /// How many formulas [_unshown] keeps.
  static const int _keptUnshown = 4;

  /// How many formulas have been read by the typesetter.
  @visibleForTesting
  static int get reads => _reads;
  static int _reads = 0;

  /// [latex] read by the typesetter, or why it cannot be.
  static (SyntaxTree?, ParseException?) _parse(String latex) {
    _reads++;
    try {
      return (
        SyntaxTree(
          greenRoot: typesetHighlights(
            TexParser(latex, const TexParserSettings()).parse(),
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
  State<MathView> createState() => _MathViewState();

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
    ) as T;
  }
}

class _MathViewState extends State<MathView> {
  /// The formula as it was last typeset, and what it was typeset from.
  /// Built again from the same, as an answer being written builds every
  /// formula above it with each word, it is not read again.
  _Typeset? _last;

  _Typeset _typeset(LatexPreamble? preamble) {
    final last = _last;
    if (last != null &&
        last.source == widget.source &&
        last.mode == widget.mode &&
        last.packages == widget.packages &&
        identical(last.preamble, preamble)) {
      return last;
    }
    final latex = MathView.prepared(
      LinearMath.latexFor(widget.mode, widget.source),
      preamble: preamble,
      packages: widget.packages,
    );
    final kept = last != null && last.latex == latex ? last.read : null;
    return _last = _Typeset(
      source: widget.source,
      mode: widget.mode,
      packages: widget.packages,
      preamble: preamble,
      latex: latex,
      read: TikzPicture.holds(latex)
          ? null
          : kept ?? MathView._unshown.remove(latex) ?? MathView._parse(latex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final textStyle = widget.textStyle;
    if (source.trim().isEmpty) {
      return _Placeholder(style: textStyle);
    }
    final typeset = _typeset(MathPreamble.of(context));
    final style = textStyle ?? DefaultTextStyle.of(context).style;
    final read = typeset.read;
    if (read == null) {
      try {
        return TikzView(picture: TikzPicture.read(typeset.latex), style: style);
      } on FormatException catch (e) {
        return _MathError(message: e.message, source: source, style: style);
      }
    }
    final (tree, error) = read;
    // One node for a screen reader, its source, rather than one for each
    // of its glyphs: a page of formulas had thousands, worked out again as
    // it scrolled.
    return Semantics(
      label: source,
      excludeSemantics: true,
      child: Math(
        ast: tree,
        parseError: error,
        mathStyle: widget.displayStyle ? MathStyle.display : MathStyle.text,
        textStyle: style,
        // A formula that TeX itself rejects still has to show something, or
        // the page would appear to lose content while it is being edited.
        onErrorFallback: (error) => _MathError(
          message: error.messageWithType,
          source: source,
          style: textStyle,
        ),
      ),
    );
  }
}

/// A formula as a view typeset it: what it was typeset from, the LaTeX
/// that came to, and that LaTeX as the typesetter read it, or null for a
/// TikZ picture.
class _Typeset {
  const _Typeset({
    required this.source,
    required this.mode,
    required this.packages,
    required this.preamble,
    required this.latex,
    required this.read,
  });

  final String source;
  final MathMode mode;
  final bool packages;
  final LatexPreamble? preamble;
  final String latex;
  final (SyntaxTree?, ParseException?)? read;
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
