/// Translation of user-typed search text into FTS5 MATCH expressions.
library;

/// Builds FTS5 `MATCH` expressions from raw user input.
///
/// Search text is typed by a human, not written as a query language, so
/// everything the user types is treated as terms to find. Bare input would
/// otherwise be interpreted as FTS5 syntax, where a trailing `AND`, a stray
/// `"` or a `-` is a syntax error that surfaces as an exception mid-keystroke.
abstract final class FtsQuery {
  /// Converts [input] into a MATCH expression, or returns null when it
  /// contains nothing searchable.
  ///
  /// Terms are ANDed. Double-quoted runs in [input] are kept together as
  /// phrases. When [prefixLastTerm] is set the final term matches as a prefix,
  /// so results narrow as the user types rather than appearing only once a word
  /// is finished.
  static String? build(String input, {bool prefixLastTerm = true}) {
    final tokens = _tokenize(input);
    if (tokens.isEmpty) return null;

    final parts = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final quoted = '"${token.text.replaceAll('"', '""')}"';
      final isLast = i == tokens.length - 1;
      // A phrase the user closed with a quote is deliberate and exact; only a
      // bare trailing word is treated as still being typed.
      final prefix = isLast && prefixLastTerm && !token.isPhrase;
      parts.add(prefix ? '$quoted*' : quoted);
    }
    return parts.join(' AND ');
  }

  /// Splits [input] into terms, honouring double-quoted phrases.
  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    void flush({required bool isPhrase}) {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.isEmpty) return;
      tokens.add(_Token(text, isPhrase));
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        flush(isPhrase: inQuotes);
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && _isSeparator(char)) {
        flush(isPhrase: false);
        continue;
      }
      buffer.write(char);
    }
    // An unterminated quote is a phrase the user is still typing.
    flush(isPhrase: false);

    return tokens;
  }

  /// Characters that end a term.
  ///
  /// FTS5's own operators are included so that typing `a-b` or `x:y` searches
  /// for the words rather than parsing as a column filter or a negation.
  static bool _isSeparator(String char) {
    if (char.trim().isEmpty) return true;
    return const <String>{
      '(',
      ')',
      '*',
      ':',
      '^',
      '-',
      '+',
      ',',
      ';',
      '~',
    }.contains(char);
  }
}

class _Token {
  const _Token(this.text, this.isPhrase);

  final String text;
  final bool isPhrase;
}
