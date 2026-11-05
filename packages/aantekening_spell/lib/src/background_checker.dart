/// Spell checking in an isolate of its own, away from the interface.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dictionary.dart';
import 'spell_checker.dart';

/// Where a Hunspell dictionary's two files are.
typedef DictionaryFiles = ({String affixFile, String wordList});

/// A [SpellChecker] in a background isolate, so that reading a dictionary —
/// a second or so for a large one — and checking and suggesting never hold
/// up the interface.
///
/// Requests are carried out one at a time, in the order they are made, so a
/// check made straight after [use] is answered with the new dictionaries.
///
/// An interface as well, for what uses it to be tried with a checker that
/// says what it is told to.
interface class BackgroundSpellChecker {
  BackgroundSpellChecker._(this._responses) {
    _responses.listen(_onResponse);
  }

  /// Starts the isolate. It checks nothing until it is given dictionaries
  /// with [use].
  static Future<BackgroundSpellChecker> spawn() async {
    final checker = BackgroundSpellChecker._(
      ReceivePort('spell checker responses'),
    );
    try {
      checker._isolate = await Isolate.spawn(
        _serve,
        checker._responses.sendPort,
        onExit: checker._responses.sendPort,
        debugName: 'spell checker',
      );
      await checker._started.future;
    } on Object {
      checker.close();
      rethrow;
    }
    return checker;
  }

  final ReceivePort _responses;
  Isolate? _isolate;
  late SendPort _requests;
  final Completer<void> _started = Completer<void>();
  final Map<int, Completer<Object?>> _waiting = <int, Completer<Object?>>{};
  int _next = 0;
  bool _closed = false;

  /// Checks against [dictionaries] from now on — a word is right if any of
  /// them has it — and against [personalWords]. Each dictionary is read
  /// once and kept while it is in use, and the last of those used before
  /// too, so going back to it is quick; one whose files have changed is
  /// read again.
  Future<void> use(
    List<DictionaryFiles> dictionaries, {
    Iterable<String> personalWords = const <String>[],
  }) => _ask(_Use(dictionaries, personalWords.toList()));

  /// What the dictionaries say of each of [words]: right, wrong, or
  /// unsure — wrong as far as one could tell in the time it had.
  Future<List<Verdict>> check(List<String> words) async => <Verdict>[
    for (final index in (await _ask(_Check(words)))! as List<int>)
      Verdict.values[index],
  ];

  /// Likely spellings of [word], at most [limit], best first.
  Future<List<String>> suggest(String word, {int limit = 8}) async =>
      (await _ask(_Suggest(word, limit)))! as List<String>;

  /// Counts [word] as right from now on.
  Future<void> addWord(String word) => _ask(_AddWord(word));

  /// Stops the isolate. Requests still waiting fail.
  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill();
    _responses.close();
    if (!_started.isCompleted) {
      // Waited for only once the isolate is running: an isolate that could
      // not be started fails [spawn] with its own error, not this one.
      _started.future.ignore();
      _started.completeError(StateError('The spell checker stopped.'));
    }
    for (final waiting in _waiting.values) {
      waiting.completeError(StateError('The spell checker stopped.'));
    }
    _waiting.clear();
  }

  Future<Object?> _ask(_Request request) {
    if (_closed) {
      return Future<Object?>.error(StateError('The spell checker is closed.'));
    }
    final id = _next++;
    final answer = _waiting[id] = Completer<Object?>();
    _requests.send((id, request));
    return answer.future;
  }

  void _onResponse(Object? message) {
    if (message is SendPort) {
      _requests = message;
      _started.complete();
      return;
    }
    // The isolate has ended, which it does only when something has gone
    // badly wrong in it.
    if (message == null) return close();
    if (message is! (int, Object?)) return;
    final (id, result) = message;
    final waiting = _waiting.remove(id);
    if (waiting == null) return;
    if (result is _Failure) {
      waiting.completeError(Exception(result.error));
    } else {
      waiting.complete(result);
    }
  }

  static void _serve(SendPort responses) {
    final requests = ReceivePort('spell checker requests');
    responses.send(requests.sendPort);
    final worker = _Worker();
    requests.listen((message) {
      final (id, request) = message as (int, _Request);
      Object? result;
      try {
        result = worker.handle(request);
      } on Object catch (error) {
        result = _Failure('$error');
      }
      responses.send((id, result));
    });
  }
}

sealed class _Request {
  const _Request();
}

final class _Use extends _Request {
  const _Use(this.dictionaries, this.personalWords);

  final List<DictionaryFiles> dictionaries;
  final List<String> personalWords;
}

final class _Check extends _Request {
  const _Check(this.words);

  final List<String> words;
}

final class _Suggest extends _Request {
  const _Suggest(this.word, this.limit);

  final String word;
  final int limit;
}

final class _AddWord extends _Request {
  const _AddWord(this.word);

  final String word;
}

/// What went wrong carrying out a request, sent back in place of its answer.
final class _Failure {
  const _Failure(this.error);

  final String error;
}

/// The isolate's side: the dictionaries read, and the checker made of
/// those in use.
final class _Worker {
  /// The dictionaries read, each with when its files were changed, the one
  /// used last at the end: those in use, and the one used before them.
  final Map<DictionaryFiles, _Read> _read = <DictionaryFiles, _Read>{};
  SpellChecker _checker = SpellChecker(const <HunspellDictionary>[]);

  Object? handle(_Request request) {
    switch (request) {
      case _Use(:final dictionaries, :final personalWords):
        _checker = SpellChecker(<HunspellDictionary>[
          for (final files in dictionaries) _dictionary(files),
        ], personalWords: personalWords);
        _forget(keep: dictionaries.toSet());
        return null;
      case _Check(:final words):
        // By index, which is the same in either isolate.
        return Uint8List.fromList(<int>[
          for (final word in words) _checker.verdictOn(word).index,
        ]);
      case _Suggest(:final word, :final limit):
        return _checker.suggest(word, limit: limit);
      case _AddWord(:final word):
        _checker.addWord(word);
        return null;
    }
  }

  /// The dictionary in [files], read afresh if they have changed since.
  HunspellDictionary _dictionary(DictionaryFiles files) {
    final affixFile = File(files.affixFile);
    final wordList = File(files.wordList);
    final changed = (affixFile.lastModifiedSync(), wordList.lastModifiedSync());
    final read = _read.remove(files);
    final dictionary = read != null && read.changed == changed
        ? read.dictionary
        : HunspellDictionary.fromBytes(
            affixFile.readAsBytesSync(),
            wordList.readAsBytesSync(),
          );
    _read[files] = (changed: changed, dictionary: dictionary);
    return dictionary;
  }

  /// Lets go of the dictionaries read that are not in [keep], all but the
  /// last of them used, so that going back to it is quick: a large one
  /// takes tens of megabytes.
  void _forget({required Set<DictionaryFiles> keep}) {
    final others = <DictionaryFiles>[
      for (final files in _read.keys)
        if (!keep.contains(files)) files,
    ];
    if (others.isNotEmpty) others.removeLast();
    others.forEach(_read.remove);
  }
}

/// A dictionary read, and when its two files had last been changed.
typedef _Read = ({(DateTime, DateTime) changed, HunspellDictionary dictionary});
