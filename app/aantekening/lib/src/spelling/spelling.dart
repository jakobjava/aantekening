/// Spell checking as it is set up on this machine: whether it is on, the
/// languages checked, and the words the person has added.
library;

import 'dart:io';

import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../preferences.dart';
import 'dictionaries.dart';
import 'proofreader.dart';

@immutable
class SpellingSettings {
  const SpellingSettings({
    this.enabled = true,
    this.languages = const <String>[],
    this.personalWords = const <String>[],
  });

  /// Whether words spelled wrongly are marked.
  final bool enabled;

  /// The codes of the dictionaries checked against: a word is right if any
  /// of them has it.
  final List<String> languages;

  /// Words the person has added, which are always right.
  final List<String> personalWords;

  SpellingSettings copyWith({
    bool? enabled,
    List<String>? languages,
    List<String>? personalWords,
  }) => SpellingSettings(
    enabled: enabled ?? this.enabled,
    languages: languages ?? this.languages,
    personalWords: personalWords ?? this.personalWords,
  );
}

/// Spelling's settings, remembered between sessions.
class SpellingController extends Notifier<SpellingSettings> {
  static const String _enabledKey = 'spelling.enabled';
  static const String _languagesKey = 'spelling.languages';
  static const String _wordsKey = 'spelling.words';

  @override
  SpellingSettings build() {
    List<String> strings(Object? saved) => List<String>.unmodifiable(
      saved is List ? saved.whereType<String>() : const <String>[],
    );
    return SpellingSettings(
      enabled: ref.preference(_enabledKey) != false,
      languages: strings(ref.preference(_languagesKey)),
      personalWords: strings(ref.preference(_wordsKey)),
    );
  }

  void setEnabled(bool enabled) {
    if (enabled == state.enabled) return;
    state = state.copyWith(enabled: enabled);
    ref.savePreference(_enabledKey, enabled ? null : false);
  }

  /// Checks against [code]'s dictionary too, or no longer, as [used] says.
  void useLanguage(String code, {required bool used}) {
    if (state.languages.contains(code) == used) return;
    final languages = List<String>.unmodifiable(<String>[
      for (final language in state.languages)
        if (language != code) language,
      if (used) code,
    ]);
    state = state.copyWith(languages: languages);
    ref.savePreference(_languagesKey, languages.isEmpty ? null : languages);
  }

  void addWord(String word) {
    if (state.personalWords.contains(word)) return;
    _setWords(<String>[...state.personalWords, word]);
  }

  /// Takes [word] out of the person's words, so it is checked again.
  void removeWord(String word) {
    if (!state.personalWords.contains(word)) return;
    _setWords(<String>[
      for (final kept in state.personalWords)
        if (kept != word) kept,
    ]);
    // The checker was given the words it started with, and learns only
    // those added since; it starts again without this one.
    ref.invalidate(proofreaderProvider);
  }

  void _setWords(List<String> words) {
    state = state.copyWith(personalWords: List<String>.unmodifiable(words));
    ref.savePreference(_wordsKey, words.isEmpty ? null : words);
  }
}

final spellingProvider = NotifierProvider<SpellingController, SpellingSettings>(
  SpellingController.new,
);

/// Where the dictionaries are kept: beside the preferences, as they belong
/// to this machine rather than to the notes.
final dictionaryFolderProvider = FutureProvider<DictionaryFolder>((ref) async {
  final support = await getApplicationSupportDirectory();
  return DictionaryFolder(Directory(p.join(support.path, 'dictionaries')));
});

/// What dictionaries are downloaded with.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// The dictionaries installed, by name. Refreshed by invalidating it.
final installedDictionariesProvider = FutureProvider<List<InstalledDictionary>>(
  (ref) async => (await ref.watch(dictionaryFolderProvider.future)).list(),
);

/// The isolate words are checked in, started the first time it is needed.
final spellCheckerProvider = FutureProvider<BackgroundSpellChecker>((
  ref,
) async {
  final checker = await BackgroundSpellChecker.spawn();
  ref.onDispose(checker.close);
  return checker;
});

/// What marks the words spelled wrongly, or null while spelling is off or
/// there is no dictionary to check against.
final proofreaderProvider = Provider<Proofreader?>((ref) {
  final enabled = ref.watch(spellingProvider.select((s) => s.enabled));
  final languages = ref.watch(spellingProvider.select((s) => s.languages));
  final installed = ref.watch(installedDictionariesProvider).value;
  if (!enabled || installed == null) return null;
  final dictionaries = <DictionaryFiles>[
    for (final dictionary in installed)
      if (languages.contains(dictionary.code)) dictionary.files,
  ];
  if (dictionaries.isEmpty) return null;
  final checker = ref.watch(spellCheckerProvider).value;
  if (checker == null) return null;

  final spelling = ref.read(spellingProvider.notifier);
  final proofreader = Proofreader(
    checker,
    dictionaries,
    personalWords: ref.read(spellingProvider).personalWords,
    onWordAdded: spelling.addWord,
  );
  ref.onDispose(proofreader.dispose);
  return proofreader;
});

/// Installs and removes dictionaries. Its state is the codes of those being
/// downloaded.
class DictionariesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Downloads [dictionary] and checks spelling in its language too.
  /// Failing, it throws a [DictionaryException] saying why.
  Future<void> download(CatalogDictionary dictionary) async {
    final code = dictionary.code;
    if (state.contains(code)) return;
    state = <String>{...state, code};
    try {
      final folder = await ref.read(dictionaryFolderProvider.future);
      await folder.download(dictionary, ref.read(httpClientProvider));
      _installed(code);
    } finally {
      state = state.difference(<String>{code});
    }
  }

  /// Installs the dictionary in [affixFile] and [wordList] and checks
  /// spelling in its language too. Failing, it throws a
  /// [DictionaryException] saying why.
  Future<void> import(String affixFile, String wordList) async {
    final folder = await ref.read(dictionaryFolderProvider.future);
    final dictionary = await folder.import(affixFile, wordList);
    _installed(dictionary.code);
  }

  /// Removes the dictionary filed under [code].
  Future<void> remove(String code) async {
    ref.read(spellingProvider.notifier).useLanguage(code, used: false);
    final folder = await ref.read(dictionaryFolderProvider.future);
    await folder.remove(code);
    ref.invalidate(installedDictionariesProvider);
  }

  void _installed(String code) {
    ref.invalidate(installedDictionariesProvider);
    ref.read(spellingProvider.notifier).useLanguage(code, used: true);
  }
}

final dictionariesProvider =
    NotifierProvider<DictionariesController, Set<String>>(
      DictionariesController.new,
    );
