import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening/src/editor/text/block_paragraph.dart';
import 'package:aantekening/src/spelling/dictionaries.dart';
import 'package:aantekening/src/spelling/proofreader.dart';
import 'package:aantekening/src/spelling/spelling.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'editor_harness.dart';

/// A little English dictionary, written to [directory].
DictionaryFiles writeDictionary(Directory directory) {
  final affixFile = File('${directory.path}/en.aff')
    ..writeAsStringSync('SET UTF-8\nTRY esianrtolcdugmphbyfvkwz\n');
  final wordList = File('${directory.path}/en.dic')
    ..writeAsStringSync('6\nthe\ncat\nsat\non\nmat\nnote\n');
  return (affixFile: affixFile.path, wordList: wordList.path);
}

/// Completes the next time [notifier] notifies its listeners.
Future<void> notified(ChangeNotifier notifier) {
  final heard = Completer<void>();
  void listener() {
    notifier.removeListener(listener);
    heard.complete();
  }

  notifier.addListener(listener);
  return heard.future;
}

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('spelling_'));
  tearDown(() => directory.deleteSync(recursive: true));

  group('the dictionary folder', () {
    const files = <String, String>{
      'index.aff': 'SET UTF-8\n',
      'index.dic': '1\nkat\n',
      'license': 'Free to use.',
    };
    String hash(String text) => sha256.convert(utf8.encode(text)).toString();
    final test = CatalogDictionary(
      'xx',
      'Test',
      affixHash: hash(files['index.aff']!),
      wordListHash: hash(files['index.dic']!),
      licenseHash: hash(files['license']!),
    );
    DictionaryFolder folder() =>
        DictionaryFolder(Directory('${directory.path}/dictionaries'));

    testWidgets('installs a download only if each file is the one expected', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final server = MockClient(
          (request) async =>
              http.Response(files[request.url.pathSegments.last]!, 200),
        );
        final installed = await folder().download(test, server);
        expect(installed.name, 'Test');
        expect(File(installed.files.wordList).readAsStringSync(), '1\nkat\n');

        final tampered = MockClient(
          (request) async => http.Response('something else', 200),
        );
        await expectLater(
          folder().download(
            CatalogDictionary(
              'yy',
              'Other',
              affixHash: test.affixHash,
              wordListHash: test.wordListHash,
              licenseHash: test.licenseHash,
            ),
            tampered,
          ),
          throwsA(isA<DictionaryException>()),
        );
        final missing = MockClient(
          (request) async => http.Response('Not found', 404),
        );
        await expectLater(
          folder().download(test, missing),
          throwsA(isA<DictionaryException>()),
        );
        expect(
          (await folder().list()).map((dictionary) => dictionary.code),
          <String>['xx'],
          reason: 'a failed download leaves what was there',
        );
      });
    });

    testWidgets('adds a dictionary from its files, and removes it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final files = writeDictionary(directory);
        final added = await folder().import(files.affixFile, files.wordList);
        expect(added.name, 'en');
        expect(
          (await folder().list()).map((dictionary) => dictionary.name),
          <String>['en'],
        );

        File(files.wordList).writeAsStringSync('not a word list');
        await expectLater(
          folder().import(files.affixFile, files.wordList),
          throwsA(isA<DictionaryException>()),
        );

        await folder().remove(added.code);
        expect(await folder().list(), isEmpty);
      });
    });
  });

  group('a proofreader', () {
    late BackgroundSpellChecker checker;
    late Proofreader proofreader;
    late List<String> added;

    setUp(() async {
      checker = await BackgroundSpellChecker.spawn();
      added = <String>[];
      proofreader = Proofreader(checker, <DictionaryFiles>[
        writeDictionary(directory),
      ], onWordAdded: added.add);
    });

    tearDown(() {
      proofreader.dispose();
      checker.close();
    });

    List<String> wrongIn(String text, {int? caret}) => <String>[
      for (final word in proofreader.misspellingsIn(text, caret: caret))
        text.substring(word.start, word.end),
    ];

    test('marks words once the checker has said', () async {
      const text = 'the cat sat on teh mat';
      expect(wrongIn(text), isEmpty, reason: 'nothing is known yet');
      await notified(proofreader);
      expect(wrongIn(text), <String>['teh']);
      expect(
        wrongIn(text, caret: 18),
        isEmpty,
        reason: 'the word being typed is left alone',
      );
      expect(await proofreader.suggest('teh'), contains('the'));
    });

    test('unmarks a word added to the dictionary, or ignored', () async {
      const text = 'aantekening on the mat, Lorem';
      wrongIn(text);
      await notified(proofreader);
      expect(wrongIn(text), <String>['aantekening', 'Lorem']);

      proofreader.ignore('Lorem');
      expect(wrongIn(text), <String>['aantekening']);

      await proofreader.addWord('aantekening');
      expect(added, <String>['aantekening']);
      expect(wrongIn(text), isEmpty);
      expect(wrongIn('Aantekening'), isEmpty, reason: 'capitalised, too');
    });

    test('marks a word the checker ran out of time on, asks again, and '
        'stops asking', () async {
      // Words made of any number of others, so that ruling out a long word
      // not among them takes longer than a check is given.
      final affixFile = File('${directory.path}/endless.aff')
        ..writeAsStringSync('SET UTF-8\nCOMPOUNDFLAG X\nCOMPOUNDMIN 1\n');
      final wordList = File('${directory.path}/endless.dic')
        ..writeAsStringSync('4\na/X\naa/X\naaa/X\naaaa/X\n');
      final hard = Proofreader(
        checker,
        <DictionaryFiles>[
          writeDictionary(directory),
          (affixFile: affixFile.path, wordList: wordList.path),
        ],
        onWordAdded: added.add,
        askAgainAfter: const Duration(milliseconds: 10),
      );
      addTearDown(hard.dispose);
      var answers = 0;
      hard.addListener(() => answers++);
      final text = 'the ${'a' * 40}b sat';
      List<String> wrong() => <String>[
        for (final word in hard.misspellingsIn(text))
          text.substring(word.start, word.end),
      ];

      wrong();
      while (answers < Proofreader.tries) {
        await notified(hard);
        expect(wrong(), <String>['${'a' * 40}b'], reason: 'as it says');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(answers, Proofreader.tries, reason: 'asked no more');
      expect(wrong(), <String>['${'a' * 40}b']);
    });

    test('unmarks a word the checker ran out of time on once it is sure of '
        'it', () async {
      final hesitant = _Hesitant();
      final unsure = Proofreader(
        hesitant,
        const <DictionaryFiles>[],
        onWordAdded: added.add,
        askAgainAfter: const Duration(milliseconds: 10),
      );
      addTearDown(unsure.dispose);
      List<String> wrong(String text) => <String>[
        for (final word in unsure.misspellingsIn(text))
          text.substring(word.start, word.end),
      ];

      expect(wrong('Donaudampfschifffahrt'), isEmpty);
      await notified(unsure);
      expect(wrong('Donaudampfschifffahrt'), <String>['Donaudampfschifffahrt']);
      await notified(unsure);
      expect(wrong('Donaudampfschifffahrt'), isEmpty);
      expect(hesitant.asked, <List<String>>[
        <String>['Donaudampfschifffahrt'],
        <String>['Donaudampfschifffahrt'],
      ]);
      wrong('Donaudampfschifffahrt');
      await pumpEventQueue();
      expect(hesitant.asked, hasLength(2), reason: 'sure, it is kept');
    });

    test('keeps the verdicts it remembers, the newest', () async {
      final sure = _Hesitant(hesitating: false);
      final reader = Proofreader(
        sure,
        const <DictionaryFiles>[],
        onWordAdded: added.add,
      );
      addTearDown(reader.dispose);
      // Words of letters alone, as many as are remembered, and one more.
      String word(int n) => String.fromCharCodes(<int>[
        for (var i = 0; i < 4; i++) 0x61 + n ~/ math.pow(26, i) % 26,
      ]);
      reader.misspellingsIn(
        <String>[for (var n = 0; n <= Proofreader.remembered; n++) word(n)]
            .join(' '),
      );
      await notified(reader);
      sure.asked.clear();

      reader.misspellingsIn(word(Proofreader.remembered));
      await pumpEventQueue();
      expect(sure.asked, isEmpty, reason: 'the newest are kept');
      reader.misspellingsIn(word(0));
      await pumpEventQueue();
      expect(sure.asked, <List<String>>[
        <String>[word(0)],
      ], reason: 'the oldest are asked about again');
    });
  });

  group('in a text box', () {
    late AantekeningStore store;
    late String pageId;
    late BackgroundSpellChecker checker;
    late Proofreader proofreader;

    setUp(() async {
      final assets = Directory('${directory.path}/assets')..createSync();
      store = AantekeningStore.inMemory(assetDirectory: assets);
      final notebook = await store.library.createNotebook(title: 'Notes');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Section',
      );
      pageId = (await store.pages.createPage(sectionId: section.id)).id;
      checker = await BackgroundSpellChecker.spawn();
      proofreader = Proofreader(checker, <DictionaryFiles>[
        writeDictionary(directory),
      ], onWordAdded: (_) {});
    });

    tearDown(() async {
      proofreader.dispose();
      checker.close();
      await store.close();
    });

    /// Opens the page, checking spelling with [proofreader].
    Future<void> open(WidgetTester tester) => openEditor(
      tester,
      store,
      pageId,
      overrides: [proofreaderProvider.overrideWithValue(proofreader)],
    );

    // The checker answers from another isolate, in real time, and what it
    // says is taken in as the test's frames are pumped.
    Future<void> letCheckerAnswer(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    RenderBlockParagraph paragraphOf(WidgetTester tester) => tester
        .renderObject<RenderBlockParagraph>(find.byType(BlockParagraph).first);

    /// Right-clicks the laid-out characters [start]..[end] and picks
    /// [choice] from the menu.
    Future<void> correct(
      WidgetTester tester,
      int start,
      int end,
      String choice,
    ) async {
      final paragraph = paragraphOf(tester);
      await tester.tapAt(
        paragraph.localToGlobal(paragraph.rangeRects(start, end).single.center),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await letCheckerAnswer(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
    }

    testWidgets('a word spelled wrongly is underlined and corrected', (
      tester,
    ) async {
      await open(tester);
      await startTextBox(tester);
      await type(tester, 'teh cat sat ');
      await letCheckerAnswer(tester);

      expect(paragraphOf(tester).decoration.misspellings, <TextRange>[
        const TextRange(start: 0, end: 3),
      ]);
      await correct(tester, 0, 3, 'the');
      expect(textOf(tester), 'the cat sat ');
    });

    testWidgets('correcting a word finishes the formula being written', (
      tester,
    ) async {
      await open(tester);
      await startTextBox(tester);
      // The source is typed over the formula's own line: the word is on
      // the line above, where it can be right-clicked.
      await type(tester, 'teh cat');
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'x^2');
      await letCheckerAnswer(tester);

      await correct(tester, 0, 3, 'the');
      final blocks = blocksOf(tester);
      expect(blocks.first.plainText, 'the cat');
      expect(
        blocks.last.runs.single,
        const TextRun.math('x^2', MathMode.latex),
      );
      expect(inFormula(tester), isFalse);
    });
  });
}

/// A checker that runs out of time on each word the first time it is asked,
/// if [hesitating], and is sure of it the next: it is right.
class _Hesitant implements BackgroundSpellChecker {
  _Hesitant({this.hesitating = true});

  final bool hesitating;
  final List<List<String>> asked = <List<String>>[];
  final Set<String> _seen = <String>{};

  @override
  Future<void> use(
    List<DictionaryFiles> dictionaries, {
    Iterable<String> personalWords = const <String>[],
  }) async {}

  @override
  Future<List<Verdict>> check(List<String> words) async {
    asked.add(words);
    return <Verdict>[
      for (final word in words)
        _seen.add(word) && hesitating ? Verdict.unsure : Verdict.right,
    ];
  }

  @override
  Future<List<String>> suggest(String word, {int limit = 8}) async =>
      const <String>[];

  @override
  Future<void> addWord(String word) async {}

  @override
  void close() {}
}
