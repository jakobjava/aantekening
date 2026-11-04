/// Finding what was meant from a few letters of it.
library;

import 'dart:math' as math;

/// How well [query] matches [text], higher being better, or null if it does
/// not: every letter of the query must appear in the text, in order.
///
/// Letters at the start of a word, and letters that follow one another,
/// count for more, so "npg" finds "New page" before "Snapping", and a
/// match at the start of the text for more still. Case does not matter.
/// Of every way the letters can be found in the text, the best counts:
/// "cal" is found at the start of "calculus" in "Local calculus", not
/// inside "Local".
int? fuzzyScore(String query, String text) {
  final wanted = query.toLowerCase().replaceAll(' ', '');
  if (wanted.isEmpty) return 0;
  final haystack = text.toLowerCase();
  final length = haystack.length;
  // The best score of the letters so far with the last of them at each
  // place in the text, or none if it cannot be there.
  var best = List<int?>.filled(length, null);
  for (var letter = 0; letter < wanted.length; letter++) {
    final next = List<int?>.filled(length, null);
    // The best of the letter before more than [_far] places back, which
    // all lose as much for lying so far apart.
    int? far;
    for (var at = 0; at < length; at++) {
      if (at > _far) far = _better(far, best[at - _far - 1]);
      if (haystack[at] != wanted[letter]) continue;
      var gain = 1;
      if (at == 0 || !_isLetterOrDigit(haystack[at - 1])) gain += 8;
      if (at == 0) gain += 6;
      if (letter == 0) {
        // Letters far apart say less about what was meant.
        next[at] = gain - math.min(at, _far);
        continue;
      }
      int? score = far == null ? null : far + gain - _far;
      for (var before = math.max(0, at - _far); before < at; before++) {
        final so = best[before];
        if (so == null) continue;
        final apart = at - before - 1;
        score = _better(score, so + gain - apart + (apart == 0 ? 5 : 0));
      }
      next[at] = score;
    }
    best = next;
  }
  final top = best.fold<int?>(null, _better);
  // Of two that match alike, the shorter is likelier the one meant.
  return top == null ? null : top * 100 - length;
}

/// How many places apart letters lose the most for it.
const int _far = 6;

int? _better(int? a, int? b) => a == null || (b != null && b > a) ? b : a;

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isLetterOrDigit(String character) => _letterOrDigit.hasMatch(character);
