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
///
/// The verdicts are kept here alone, the [remembered] newest of them. A
/// word the checker ran out of time on is marked, as it says, but not kept
/// so: it is asked about again a little later, up to [tries] times in all,
/// and kept as wrong only then.
class Proofreader extends ChangeNotifier {
  /// Checks against [dictionaries] and [personalWords] with [checker], and
  /// tells [onWordAdded] of each word added, to be remembered.
  Proofreader(
    this._checker,
    List<DictionaryFiles> dictionaries, {
    Iterable<String> personalWords = const <String>[],
    required this.onWordAdded,
    @visibleForTesting this.askAgainAfter = const Duration(seconds: 1),
  }) {
    // Awaited before each request; failing, it is reported to each.
    _ready = _checker.use(dictionaries, personalWords: personalWords)..ignore();
  }

  /// How many verdicts are kept, the oldest let go first: far more words
  /// than a screen shows, and a megabyte or two.
  static const int remembered = 20000;

  /// How many times a word is asked about before the checker running out
  /// of time on it is taken as its verdict.
  static const int tries = 3;

  final BackgroundSpellChecker _checker;
  final ValueChanged<String> onWordAdded;
  late final Future<void> _ready;

  /// How long after the checker was unsure of a word it is asked again: a
  /// check runs out of time when the isolate is busy, as well as on a word
  /// that is hard to rule out.
  final Duration askAgainAfter;

  /// Whether each word asked about is right, in the order they came.
  final Map<String, bool> _verdicts = <String, bool>{};

  /// Words the checker ran out of time on, and how often it has.
  final Map<String, int> _unsure = <String, int>{};
  final List<String> _again = <String>[];
  Timer? _askingAgain;

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
      ..._unsure.keys,
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
    // Wrong, as the checker said, until it has said again.
    if (_unsure.containsKey(word)) return false;
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
    final List<Verdict> verdicts;
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
      final word = words[i];
      if (verdicts[i] == Verdict.unsure) {
        final times = _unsure[word] = (_unsure[word] ?? 0) + 1;
        if (times < tries) {
          _askAgain(word);
          continue;
        }
      }
      _unsure.remove(word);
      _asked.remove(word);
      _verdicts[word] = verdicts[i].isRight;
    }
    if (_verdicts.length > remembered) _forgetOldest();
    notifyListeners();
  }

  /// Lets go of the oldest quarter of the verdicts, a word of which is
  /// asked about again when it is next drawn.
  void _forgetOldest() {
    final oldest = _verdicts.keys.take(remembered ~/ 4).toList();
    oldest.forEach(_verdicts.remove);
  }

  /// Asks about [word] again in a while, with any others by then.
  void _askAgain(String word) {
    if (!_again.contains(word)) _again.add(word);
    _askingAgain ??= Timer(askAgainAfter, () {
      _askingAgain = null;
      final words = List<String>.of(_again);
      _again.clear();
      unawaited(_check(words));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _askingAgain?.cancel();
    super.dispose();
  }
}
