/// Finding what was meant from a few letters of it.
library;

/// How well [query] matches [text], higher being better, or null if it does
/// not: every letter of the query must appear in the text, in order.
///
/// Letters at the start of a word, and letters that follow one another,
/// count for more, so "npg" finds "New page" before "Snapping", and a
/// match at the start of the text for more still. Case does not matter.
int? fuzzyScore(String query, String text) {
  final wanted = query.toLowerCase().replaceAll(' ', '');
  if (wanted.isEmpty) return 0;
  final haystack = text.toLowerCase();
  var score = 0;
  var from = 0;
  var previous = -2;
  for (final letter in wanted.split('')) {
    final at = haystack.indexOf(letter, from);
    if (at < 0) return null;
    final wordStart = at == 0 || !_isLetterOrDigit(haystack[at - 1]);
    score += 1;
    if (wordStart) score += 8;
    if (at == previous + 1) score += 5;
    if (at == 0) score += 6;
    // Letters far apart say less about what was meant.
    score -= (at - from).clamp(0, 6);
    previous = at;
    from = at + 1;
  }
  // Of two that match alike, the shorter is likelier the one meant.
  return score * 100 - haystack.length;
}

bool _isLetterOrDigit(String character) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character);
