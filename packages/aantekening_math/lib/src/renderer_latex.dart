/// LaTeX as the typesetter needs it.
library;

/// Adjusts standard LaTeX for flutter_math_fork where it reads a command
/// differently from TeX, without changing what the formula is.
///
/// Formulas are stored as the LaTeX every other tool reads; this is applied
/// only on the way to the screen.
abstract final class RendererLatex {
  static final RegExp _operatorName = RegExp(r'\\operatorname\*?\s*\{[^{}]*\}');

  /// [latex] as flutter_math_fork typesets it the way TeX would.
  ///
  /// flutter_math_fork reads `\operatorname{tr}` as taking the group after
  /// it, and its scripts, as its argument, and fails when that begins with a
  /// command of its own, as `\operatorname{tr} \left( A \right)` does. TeX
  /// takes the name alone. An empty group after the name and its scripts
  /// gives the typesetter its argument and leaves what follows alone.
  static String of(String latex) {
    if (!latex.contains(r'\operatorname')) return latex;
    final out = StringBuffer();
    var at = 0;
    for (final match in _operatorName.allMatches(latex)) {
      if (match.start < at) continue;
      final end = _afterScripts(latex, match.end);
      out.write(latex.substring(at, end));
      final next = _skipSpace(latex, end);
      if (next >= latex.length || latex[next] != '{') out.write('{}');
      at = end;
    }
    out.write(latex.substring(at));
    return out.toString();
  }

  /// Where the subscripts and superscripts starting at [index] end.
  static int _afterScripts(String latex, int index) {
    var at = index;
    while (true) {
      final script = _skipSpace(latex, at);
      if (script >= latex.length ||
          (latex[script] != '^' && latex[script] != '_')) {
        return at;
      }
      at = _afterArgument(latex, _skipSpace(latex, script + 1));
    }
  }

  /// Where the argument starting at [index] ends: a braced group, a
  /// command, or one character.
  static int _afterArgument(String latex, int index) {
    if (index >= latex.length) return index;
    switch (latex[index]) {
      case '{':
        var depth = 0;
        for (var i = index; i < latex.length; i++) {
          if (latex[i] == r'\') {
            i++;
          } else if (latex[i] == '{') {
            depth++;
          } else if (latex[i] == '}' && --depth == 0) {
            return i + 1;
          }
        }
        return latex.length;
      case r'\':
        var i = index + 1;
        if (i < latex.length && !_isLetter(latex.codeUnitAt(i))) return i + 1;
        while (i < latex.length && _isLetter(latex.codeUnitAt(i))) {
          i++;
        }
        return i;
      default:
        return index + 1;
    }
  }

  static int _skipSpace(String latex, int index) {
    var i = index;
    while (i < latex.length && latex[i] == ' ') {
      i++;
    }
    return i;
  }

  static bool _isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
}
