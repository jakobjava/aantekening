/// What a search looks for, read from what someone typed.
library;

import 'dart:math' as math;

/// Where a match lies in a text, as UTF-16 offsets, [end] exclusive.
typedef TextMatch = ({int start, int end});

/// One term of a search: a word, or a phrase typed in double quotes.
class SearchTerm {
  const SearchTerm(this.text, {required this.isPhrase, required this.isPrefix});

  /// The term as typed, without its quotes.
  final String text;

  /// Whether it was typed in double quotes, to be found as written.
  final bool isPhrase;

  /// Whether it also matches words it only begins: the last bare word, which
  /// is taken to be still being typed, so results narrow as it is.
  final bool isPrefix;
}

/// The terms of a search, and where they occur in a text.
///
/// Everything typed is taken as words to find, never as query syntax, so a
/// stray `-`, `:` or quote cannot turn a search into an error. Terms are
/// separated by spaces and punctuation; a double-quoted run stays together as
/// a phrase.
///
/// The store builds its full-text query from these terms, and a page shows
/// where they occur through [matchesIn]. Reading the query in one place keeps
/// the words highlighted on a page the words that made it a result. Matching
/// follows the index's tokenizer: words are runs of letters and digits,
/// compared without regard to case or accents.
class SearchTerms {
  SearchTerms._(this.terms);

  /// Reads [input]. With [prefixLastTerm], a bare last word also matches the
  /// words it begins.
  factory SearchTerms.parse(String input, {bool prefixLastTerm = true}) {
    final tokens = <(String, bool)>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    void flush({required bool isPhrase}) {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.isNotEmpty) tokens.add((text, isPhrase));
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
    // An unterminated quote is a phrase still being typed.
    flush(isPhrase: false);

    return SearchTerms._(<SearchTerm>[
      for (var i = 0; i < tokens.length; i++)
        SearchTerm(
          tokens[i].$1,
          isPhrase: tokens[i].$2,
          // A phrase closed with a quote is deliberate and exact; only a bare
          // last word is still being typed.
          isPrefix: prefixLastTerm && i == tokens.length - 1 && !tokens[i].$2,
        ),
    ]);
  }

  final List<SearchTerm> terms;

  bool get isEmpty => terms.isEmpty;

  /// Where the terms occur in [text], in order, overlapping matches merged.
  ///
  /// A term of several words — a phrase, or a word such as `e.g.` that
  /// punctuation splits — matches those words one after another.
  List<TextMatch> matchesIn(String text) {
    if (terms.isEmpty) return const <TextMatch>[];
    final words = <({int start, int end, String folded})>[
      for (final match in _word.allMatches(text))
        (start: match.start, end: match.end, folded: _fold(match[0]!)),
    ];
    final found = <TextMatch>[];
    for (final term in terms) {
      final wanted = <String>[
        for (final match in _word.allMatches(term.text)) _fold(match[0]!),
      ];
      if (wanted.isEmpty) continue;
      for (var i = 0; i + wanted.length <= words.length; i++) {
        var matched = true;
        for (var j = 0; j < wanted.length && matched; j++) {
          final word = words[i + j].folded;
          final lastPrefix = term.isPrefix && j == wanted.length - 1;
          matched = lastPrefix ? word.startsWith(wanted[j]) : word == wanted[j];
        }
        if (!matched) continue;
        final last = words[i + wanted.length - 1];
        found.add((
          start: words[i].start,
          end: term.isPrefix
              ? last.start + math.min(wanted.last.length, last.end - last.start)
              : last.end,
        ));
      }
    }
    found.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextMatch>[];
    for (final match in found) {
      if (merged.isNotEmpty && match.start < merged.last.end) {
        final last = merged.removeLast();
        merged.add((start: last.start, end: math.max(last.end, match.end)));
      } else {
        merged.add(match);
      }
    }
    return merged;
  }

  /// A word, as the index's tokenizer reads one: letters, digits and
  /// private-use characters.
  static final RegExp _word = RegExp(r'[\p{L}\p{N}\p{Co}]+', unicode: true);

  /// Characters that end a term besides spaces, among them the full-text
  /// query's own operators, so that `a-b` or `x:y` searches for the words.
  static bool _isSeparator(String char) =>
      char.trim().isEmpty ||
      const <String>{
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

  /// [word] without case or accents, as the index compares words.
  static String _fold(String word) => String.fromCharCodes(<int>[
    for (final unit in word.codeUnits) _bases[unit] ?? unit,
  ]).toLowerCase();

  /// The Latin letters with accents that decompose to a plain letter, and
  /// those letters. Letters such as ø and ł have no such decomposition and,
  /// as in the index, stay as they are.
  static const String _accented =
      'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎď'
      'ĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤť'
      'ŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž';
  static const String _plain =
      'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaCcCcCcCcDd'
      'EeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTt'
      'UuUuUuUuUuUuWwYyYZzZzZz';

  static final Map<int, int> _bases = <int, int>{
    for (var i = 0; i < _accented.length; i++)
      _accented.codeUnitAt(i): _plain.codeUnitAt(i),
  };
}
