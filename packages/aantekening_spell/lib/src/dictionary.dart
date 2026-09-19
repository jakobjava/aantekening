/// A Hunspell dictionary: checking words and suggesting corrections.
library;

import 'affix_index.dart';
import 'affix_rules.dart';
import 'checker.dart';
import 'suggester.dart';
import 'text_encoding.dart';
import 'word_table.dart';

/// A spelling dictionary in Hunspell's format — an affix file and a word
/// list — as LibreOffice, Firefox and most spell checkers use them.
final class HunspellDictionary {
  HunspellDictionary._(this.rules, WordTable words) {
    final affixes = AffixIndex(rules);
    _checker = Checker(rules, words, affixes);
    _suggester = Suggester(_checker, rules, words, affixes);
    _checker.hasSimpleSuggestion = _suggester.hasSimpleSuggestion;
  }

  /// The dictionary [affixFile] and [wordList] describe, as they are stored:
  /// in the encoding the affix file names.
  factory HunspellDictionary.fromBytes(
    List<int> affixFile,
    List<int> wordList,
  ) {
    final encoding = DictionaryEncoding.of(affixFile);
    return HunspellDictionary.parse(
      DictionaryEncoding.decode(affixFile, encoding),
      DictionaryEncoding.decode(wordList, encoding),
    );
  }

  /// The dictionary [affixFile] and [wordList] describe, already decoded.
  factory HunspellDictionary.parse(String affixFile, String wordList) {
    final rules = AffixRules.parse(affixFile);
    final words = WordTable(rules)..read(wordList);
    return HunspellDictionary._(rules, words);
  }

  final AffixRules rules;
  late final Checker _checker;
  late final Suggester _suggester;

  /// Whether [word] is spelled correctly.
  bool check(String word) => _checker.spell(word);

  /// Likely spellings of [word], best first.
  List<String> suggest(String word) => _suggester.suggest(word);

  /// Characters this language counts as part of a word, besides letters.
  String get wordCharacters => rules.wordCharacters;
}
