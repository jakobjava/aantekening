/// Reading LaTeX source: its spaces, letters and groups.
library;

abstract final class LatexSource {
  static final RegExp _picture = RegExp(
    r'^(?:\\begin\s*\{tikzpicture\}|\\tikz(?![a-zA-Z]))',
  );

  /// Whether [latex] is a TikZ picture: a `tikzpicture` environment, or a
  /// `\tikz` command.
  static bool isPicture(String latex) => _picture.hasMatch(latex.trimLeft());

  /// The first index from [from] in [source] that is not a space.
  static int skipSpaces(String source, int from) {
    var at = from;
    while (at < source.length && isSpace(source.codeUnitAt(at))) {
      at++;
    }
    return at;
  }

  /// Just past the brace closing the group that opens at [open], escaped
  /// braces skipped; the end of [source] if it never closes.
  static int closingBrace(String source, int open) =>
      closedBrace(source, open) ?? source.length;

  /// Just past the brace closing the group that opens at [open], as
  /// [closingBrace] finds it; null if it never closes.
  static int? closedBrace(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final char = source[i];
      if (char == r'\') {
        i++;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        return i + 1;
      }
    }
    return null;
  }

  /// Just past the bracket closing the options that open at [open], groups
  /// inside skipped whole and escaped brackets skipped; the end of [source]
  /// if it never closes.
  static int closingBracket(String source, int open) =>
      closedBracket(source, open) ?? source.length;

  /// Just past the bracket closing the options that open at [open], as
  /// [closingBracket] finds it; null if it never closes.
  static int? closedBracket(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final char = source[i];
      if (char == r'\') {
        i++;
      } else if (char == '{') {
        final close = closedBrace(source, i);
        if (close == null) return null;
        i = close - 1;
      } else if (char == '[') {
        depth++;
      } else if (char == ']' && --depth == 0) {
        return i + 1;
      }
    }
    return null;
  }

  /// What is inside the group or options opening at [open] in [source],
  /// [close] just past their end as [closingBrace] or [closingBracket] found
  /// it: all that follows the opening, if it never closes — as it does not
  /// while it is being typed.
  static String inside(String source, int open, int close) {
    final closed =
        (source[open] == '['
            ? closedBracket(source, open)
            : closedBrace(source, open)) !=
        null;
    return source.substring(open + 1, closed ? close - 1 : source.length);
  }

  /// Just past the `\end{name}` closing the environment [name] whose
  /// `\begin{name}` ends just before [from], those of the same name within
  /// it counted; null if it is never closed.
  static int? environmentEnd(String source, int from, String name) {
    final begin = '\\begin{$name}';
    final end = '\\end{$name}';
    var depth = 1;
    var at = from;
    while (true) {
      final nextEnd = source.indexOf(end, at);
      if (nextEnd < 0) return null;
      final nextBegin = source.indexOf(begin, at);
      if (nextBegin >= 0 && nextBegin < nextEnd) {
        depth++;
        at = nextBegin + begin.length;
      } else {
        at = nextEnd + end.length;
        if (--depth == 0) return at;
      }
    }
  }

  static bool isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

  static bool isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
}
