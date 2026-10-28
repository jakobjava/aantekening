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
  static int closingBrace(String source, int open) {
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
    return source.length;
  }

  /// Just past the bracket closing the options that open at [open], groups
  /// inside skipped whole; the end of [source] if it never closes.
  static int closingBracket(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final char = source[i];
      if (char == '{') {
        i = closingBrace(source, i) - 1;
      } else if (char == '[') {
        depth++;
      } else if (char == ']' && --depth == 0) {
        return i + 1;
      }
    }
    return source.length;
  }

  /// What is inside the group or options opening at [open] in [source],
  /// [close] just past their end as [closingBrace] or [closingBracket] found
  /// it: all that follows the opening, if it never closes — as it does not
  /// while it is being typed.
  static String inside(String source, int open, int close) {
    final closer = source[open] == '[' ? ']' : '}';
    // Closed, a closing added after it changes nothing.
    final closed =
        (closer == ']'
            ? closingBracket('$source]', open)
            : closingBrace('$source}', open)) ==
        close;
    return source.substring(open + 1, closed ? close - 1 : source.length);
  }

  static bool isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

  static bool isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
}
