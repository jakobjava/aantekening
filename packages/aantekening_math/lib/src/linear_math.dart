/// The public entry point for translating linear math input into LaTeX.
library;

import 'package:aantekening_core/aantekening_core.dart';

import 'ast.dart';
import 'latex_reader.dart';
import 'lexer.dart';
import 'linear_writer.dart';
import 'math_storage.dart';
import 'parser.dart';

/// The result of translating a linear expression.
class MathTranslation {
  const MathTranslation({
    required this.latex,
    required this.tree,
    this.diagnostics = const <MathDiagnostic>[],
  });

  /// The LaTeX to render. Always present, even when [diagnostics] is not empty,
  /// so a partially typed formula still previews.
  final String latex;

  /// The parsed expression, for callers that want to inspect or transform it.
  final MathNode tree;

  /// Problems found in the input, each pointing at an offset the editor can
  /// underline.
  final List<MathDiagnostic> diagnostics;

  bool get isComplete => diagnostics.isEmpty;
}

/// Translates OneNote-style linear input into LaTeX.
///
/// The simple mode exists because most notes are taken under time pressure:
/// `1/2` and `sqrt(x)` are faster to type than `\frac{1}{2}` and `\sqrt{x}`,
/// and they read back as mathematics rather than as markup. Formulas are
/// stored as LaTeX either way ([MathStorage]); [fromLatex] writes one back in
/// the linear syntax for editing.
abstract final class LinearMath {
  /// Translates [input], never throwing.
  static MathTranslation translate(String input) {
    final lexer = MathLexer(input);
    final tokens = lexer.tokenize();
    final diagnostics = List<MathDiagnostic>.of(lexer.diagnostics);
    final tree = MathParser(tokens, diagnostics).parse();
    return MathTranslation(
      latex: tree.toLatex(),
      tree: tree,
      diagnostics: diagnostics,
    );
  }

  /// Translates [input] and returns only its LaTeX.
  static String toLatex(String input) => translate(input).latex;

  /// Writes [latex] in the linear syntax: what a formula stored as LaTeX
  /// looks like when it is edited in Simple mode. [toLatex] of the result
  /// renders the same as [latex].
  static String fromLatex(String latex) =>
      LinearWriter.write(LatexReader(latex).read());

  /// The LaTeX for a formula written in [mode]: [source] itself, or its
  /// translation.
  static String latexFor(MathMode mode, String source) => switch (mode) {
    MathMode.latex => source,
    MathMode.linear => toLatex(source),
  };
}
