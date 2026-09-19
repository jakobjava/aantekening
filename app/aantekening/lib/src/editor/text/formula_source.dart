/// The formula open for editing: its source, and the LaTeX it is stored as.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';

/// Translates between the source of the formula being edited, in the syntax
/// it is shown in, and the LaTeX it is stored as.
///
/// While the source is as it was when the formula was opened, the stored
/// LaTeX is kept exactly rather than rewritten the way the translation would
/// spell it, so opening and leaving a formula never changes it.
final class FormulaSource {
  /// The syntax the source is shown and typed in.
  MathMode syntax = MathMode.linear;

  String? _openedLatex;
  String _openedSource = '';
  (String, MathTranslation)? _translation;

  /// Records that the formula stored as [latex] is shown as [source]; null
  /// for a new formula.
  void opened(String? latex, String source) {
    _openedLatex = latex;
    _openedSource = source;
  }

  /// Forgets the formula, which is no longer open.
  void closed() => opened(null, '');

  /// [latex] as it is shown: the source it was opened as while it is still
  /// that formula, else written in [syntax].
  String sourceOf(String latex) =>
      latex == _openedLatex ? _openedSource : sourceIn(syntax, latex);

  /// [latex] written in [syntax].
  static String sourceIn(MathMode syntax, String latex) =>
      syntax == MathMode.latex ? latex : LinearMath.fromLatex(latex);

  /// The LaTeX the formula is stored as while its source is [source].
  String latexFor(String source) {
    final opened = _openedLatex;
    if (opened != null && source == _openedSource) return opened;
    if (syntax == MathMode.latex || source.trim().isEmpty) return source;
    return _translate(source).latex;
  }

  /// What is wrong with [source], as far as it can be read.
  List<MathDiagnostic> diagnostics(String source) =>
      syntax == MathMode.linear && source.trim().isNotEmpty
      ? _translate(source).diagnostics
      : const <MathDiagnostic>[];

  /// The last source translated is kept with its translation: storing the
  /// formula and previewing it both need it.
  MathTranslation _translate(String source) {
    final last = _translation;
    if (last != null && last.$1 == source) return last.$2;
    final translation = LinearMath.translate(source);
    _translation = (source, translation);
    return translation;
  }
}
