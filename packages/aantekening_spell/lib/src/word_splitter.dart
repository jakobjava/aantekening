/// Finding the words of running text to check.
library;

/// Where a word is in a text.
typedef WordSpan = ({int start, int end});

/// Splits text into the words worth checking.
///
/// A word is a run of letters, and of the digits and marks that go with
/// them, joined perhaps by an apostrophe, a hyphen or a full stop between
/// letters: `don't`, `well-known`, `e.g`. Left out, as word processors leave
/// them out: words with digits in them, words in capitals — acronyms, most
/// often — single letters, and web and e-mail addresses.
abstract final class WordSplitter {
  static final RegExp _word = RegExp(
    r"[\p{L}\p{M}\p{N}]+(?:['’\-.][\p{L}\p{M}\p{N}]+)*",
    unicode: true,
  );
  static final RegExp _digit = RegExp(r'\p{N}', unicode: true);
  static final RegExp _lower = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _address = RegExp(
    r'''(?:[a-z][a-z0-9+.\-]*://|www\.)[^\s]*|[^\s@]+@[^\s@]+\.[^\s@]+''',
    caseSensitive: false,
  );

  /// The words of [text] to check, in order.
  static List<WordSpan> wordsOf(String text) {
    final skipped = <WordSpan>[
      for (final match in _address.allMatches(text))
        (start: match.start, end: match.end),
    ];
    final words = <WordSpan>[];
    for (final match in _word.allMatches(text)) {
      final word = match.group(0)!;
      if (word.length < 2 ||
          word.contains(_digit) ||
          !word.contains(_lower) ||
          skipped.any(
            (span) => match.start < span.end && span.start < match.end,
          )) {
        continue;
      }
      words.add((start: match.start, end: match.end));
    }
    return words;
  }
}
