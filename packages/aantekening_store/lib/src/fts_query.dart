/// Translation of user-typed search text into FTS5 MATCH expressions.
library;

import 'package:aantekening_core/aantekening_core.dart';

/// Builds FTS5 `MATCH` expressions from raw user input.
///
/// Search text is typed by a human, not written as a query language. Bare
/// input would be read as FTS5 syntax, where a trailing `AND`, a stray `"` or
/// a `-` is a syntax error that surfaces as an exception mid-keystroke, so
/// every term [SearchTerms] reads from the input is quoted.
abstract final class FtsQuery {
  /// Converts [input] into a MATCH expression, or returns null when it
  /// contains nothing searchable.
  ///
  /// Terms are ANDed, or with [matchAny] ORed, for a question asked in
  /// words rather than a search typed as terms: the pages with more of its
  /// words, and rarer ones, rank first. When [prefixLastTerm] is set the
  /// final bare word matches as a prefix, so results narrow as the user
  /// types rather than appearing only once a word is finished.
  static String? build(
    String input, {
    bool prefixLastTerm = true,
    bool matchAny = false,
  }) {
    final terms = SearchTerms.parse(input, prefixLastTerm: prefixLastTerm);
    if (terms.isEmpty) return null;
    return <String>[
      for (final term in terms.terms)
        '"${term.text.replaceAll('"', '""')}"${term.isPrefix ? '*' : ''}',
    ].join(matchAny ? ' OR ' : ' AND ');
  }
}
