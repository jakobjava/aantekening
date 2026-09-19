/// Which words of the text on screen are spelled wrongly.
library;

import 'dart:async';

import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:flutter/foundation.dart';

/// Finds the words spelled wrongly in text as it is drawn, going by the
/// verdicts of a [BackgroundSpellChecker].
///
/// The text is drawn at once; a word not yet checked counts as right until
/// the checker has said, asked about together with the other words drawn in
/// the same frame. Listeners hear when verdicts come back, and draw again.
class Proofreader extends ChangeNotifier {
  /// Checks against [dictionaries] and [personalWords] with [checker], and
  /// tells [onWordAdded] of each word added, to be remembered.
  Proofreader(
    this._checker,
    List<DictionaryFiles> dictionaries, {
    Iterable<String> personalWords = const <String>[],
    required this.onWordAdded,
  }) {
    // Awaited before each request; failing, it is reported to each.
    _ready = _checker.use(dictionaries, personalWords: personalWords)..ignore();
  }

  final BackgroundSpellChecker _checker;
  final ValueChanged<String> onWordAdded;
  late final Future<void> _ready;

  final Map<String, bool> _verdicts = <String, bool>{};

  /// Words being asked about, or which could not be.
  final Set<String> _asked = <String>{};
  final List<String> _waiting = <String>[];

  /// Words to leave unmarked for as long as the app runs.
  final Set<String> _ignored = <String>{};
  bool _disposed = false;

  /// The words of [text] spelled wrongly, as far as is known yet: all but
  /// the one the caret at [caret] is in or at the end of, which is still
  /// being typed.
  List<WordSpan> misspellingsIn(String text, {int? caret}) => <WordSpan>[
    for (final span in SpellChecker.misspellingsWith(text, _isCorrect))
      if (caret == null || caret < span.start || caret > span.end) span,
  ];

  /// Likely spellings of [word], best first; none if the checker cannot
  /// say.
  Future<List<String>> suggest(String word) async {
    try {
      await _ready;
      return await _checker.suggest(word, limit: 6);
    } on Object {
      return const <String>[];
    }
  }

  /// Counts [word] as right from now on, here and wherever the person
  /// writes.
  Future<void> addWord(String word) async {
    onWordAdded(word);
    try {
      await _ready;
      await _checker.addWord(word);
    } on Object {
      // It is remembered, and counts from the next time the checker starts.
      return;
    }
    // Only a word spelled wrongly can be right now. Those stay marked until
    // the checker has said again.
    final wrong = <String>[
      for (final MapEntry(key: word, value: right) in _verdicts.entries)
        if (!right) word,
    ];
    await _check(wrong);
  }

  /// Leaves [word] unmarked for as long as the app runs.
  void ignore(String word) {
    if (_ignored.add(word) && !_disposed) notifyListeners();
  }

  bool _isCorrect(String word) {
    if (_ignored.contains(word)) return true;
    final verdict = _verdicts[word];
    if (verdict != null) return verdict;
    if (_asked.add(word)) {
      _waiting.add(word);
      if (_waiting.length == 1) scheduleMicrotask(_askWaiting);
    }
    return true;
  }

  Future<void> _askWaiting() {
    final words = List<String>.of(_waiting);
    _waiting.clear();
    return _check(words);
  }

  Future<void> _check(List<String> words) async {
    if (words.isEmpty) return;
    final List<bool> verdicts;
    try {
      await _ready;
      verdicts = await _checker.check(words);
    } on Object {
      // The dictionaries could not be read, or the checker has stopped:
      // nothing is marked, and the words are not asked about again.
      return;
    }
    if (_disposed) return;
    for (var i = 0; i < words.length; i++) {
      _verdicts[words[i]] = verdicts[i];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
