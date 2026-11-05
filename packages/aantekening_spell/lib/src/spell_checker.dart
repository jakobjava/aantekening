/// Checking text in one language or several at once.
library;

import 'casing.dart';
import 'dictionary.dart';
import 'word_splitter.dart';

/// What a checker says of a word.
enum Verdict {
  /// Spelled correctly.
  right,

  /// Spelled wrongly.
  wrong,

  /// Said to be wrong, as Hunspell says, by a dictionary that ran out of
  /// time before it was sure: it may be right, and is worth checking again.
  unsure;

  /// Whether the word counts as spelled correctly.
  bool get isRight => this == right;
}

/// Checks text against any number of dictionaries, and against words the
/// person has added: a word is right if any of them has it.
final class SpellChecker {
  SpellChecker(this.dictionaries, {Iterable<String> personalWords = const []})
    : _personal = personalWords.toSet();

  final List<HunspellDictionary> dictionaries;

  /// Words added by the person, checked as a dictionary word is: `word`
  /// also as `Word` and `WORD`, and `Word` also as `WORD`.
  final Set<String> _personal;

  /// Adds [word] to the words that are right.
  void addWord(String word) => _personal.add(word);

  /// Whether [word] is spelled correctly in any of the languages.
  bool isCorrect(String word) => verdictOn(word).isRight;

  /// What the languages say of [word]: right if any of them has it, and
  /// unsure, rather than wrong, if one that has not ran out of time.
  ///
  /// Nothing is remembered here: who asks keeps the verdicts it wants
  /// kept, and asks again about those it was unsure of.
  Verdict verdictOn(String word) {
    if (_isPersonal(word)) return Verdict.right;
    var verdict = Verdict.wrong;
    for (final dictionary in dictionaries) {
      if (dictionary.check(word)) return Verdict.right;
      if (dictionary.timedOut) verdict = Verdict.unsure;
    }
    return verdict;
  }

  bool _isPersonal(String word) {
    if (_personal.contains(word)) return true;
    final lower = Casing.lower(word);
    return switch (Casing.of(word)) {
      CapType.initial => _personal.contains(lower),
      CapType.all =>
        _personal.contains(lower) ||
            _personal.contains(Casing.initialCapital(lower)),
      _ => false,
    };
  }

  /// The words of [text] that [isCorrect] says are spelled wrongly. A word
  /// followed by a full stop is right if it is an abbreviation written with
  /// one: `etc.`.
  static List<WordSpan> misspellingsWith(
    String text,
    bool Function(String word) isCorrect,
  ) {
    bool isCorrectAt(WordSpan span) {
      final word = text.substring(span.start, span.end);
      if (isCorrect(word)) return true;
      return span.end < text.length &&
          text.codeUnitAt(span.end) == 0x2E &&
          isCorrect('$word.');
    }

    return <WordSpan>[
      for (final span in WordSplitter.wordsOf(text))
        if (!isCorrectAt(span)) span,
    ];
  }

  /// Likely spellings of [word], at most [limit]: each language's best
  /// first, then each one's next best, and so on.
  List<String> suggest(String word, {int limit = 8}) {
    final lists = <List<String>>[
      for (final dictionary in dictionaries) dictionary.suggest(word),
    ];
    final suggestions = <String>[];
    for (var rank = 0; suggestions.length < limit; rank++) {
      var any = false;
      for (final list in lists) {
        if (rank >= list.length) continue;
        any = true;
        if (!suggestions.contains(list[rank])) suggestions.add(list[rank]);
        if (suggestions.length == limit) break;
      }
      if (!any) break;
    }
    return suggestions;
  }
}
