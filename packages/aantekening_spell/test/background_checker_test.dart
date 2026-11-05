import 'dart:io';

import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late BackgroundSpellChecker checker;

  DictionaryFiles write(String name, String affixes, String words) {
    final affixFile = File('${directory.path}/$name.aff')
      ..writeAsStringSync(affixes);
    final wordList = File('${directory.path}/$name.dic')
      ..writeAsStringSync(words);
    return (affixFile: affixFile.path, wordList: wordList.path);
  }

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('spell_worker_test_');
    checker = await BackgroundSpellChecker.spawn();
  });

  tearDown(() {
    checker.close();
    directory.deleteSync(recursive: true);
  });

  test('checks nothing as right before it has a dictionary', () async {
    expect(await checker.check(<String>['cat']), <Verdict>[Verdict.wrong]);
  });

  test('checks and suggests with the dictionaries it is given', () async {
    final english = write(
      'en',
      'SET UTF-8\nTRY aeiouct\nSFX S Y 1\nSFX S 0 s .\n',
      '2\ncat/S\ndog/S\n',
    );
    final dutch = write('nl', 'SET UTF-8\nTRY aeiouhnd\n', '1\nhond\n');

    await checker.use(<DictionaryFiles>[english, dutch]);
    expect(
      await checker.check(<String>['cats', 'hond', 'honden', 'dgo']),
      <Verdict>[Verdict.right, Verdict.right, Verdict.wrong, Verdict.wrong],
    );
    expect(await checker.suggest('dgo'), <String>['dog']);

    await checker.use(<DictionaryFiles>[dutch], personalWords: <String>['kat']);
    expect(await checker.check(<String>['cats', 'hond', 'kat']), <Verdict>[
      Verdict.wrong,
      Verdict.right,
      Verdict.right,
    ]);
    await checker.addWord('poes');
    expect(await checker.check(<String>['poes', 'Poes']), <Verdict>[
      Verdict.right,
      Verdict.right,
    ]);
  });

  test('says which words it ran out of time on', () async {
    // Words made of any number of others, so that ruling out a long word
    // not among them takes longer than a check is given.
    final endless = write(
      'endless',
      'SET UTF-8\nCOMPOUNDFLAG X\nCOMPOUNDMIN 1\n',
      '4\na/X\naa/X\naaa/X\naaaa/X\n',
    );
    await checker.use(<DictionaryFiles>[endless]);
    expect(
      await checker.check(<String>['aaaaaa', '${'a' * 40}b', 'b']),
      <Verdict>[Verdict.right, Verdict.unsure, Verdict.wrong],
    );
  });

  test('reads a dictionary again once its files have changed', () async {
    final english = write('en', 'SET UTF-8\n', '1\ncat\n');
    await checker.use(<DictionaryFiles>[english]);
    expect(await checker.check(<String>['dog']), <Verdict>[Verdict.wrong]);

    File(english.wordList)
      ..writeAsStringSync('2\ncat\ndog\n')
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    await checker.use(<DictionaryFiles>[english]);
    expect(await checker.check(<String>['cat', 'dog']), <Verdict>[
      Verdict.right,
      Verdict.right,
    ]);
  });

  test('reports a dictionary it cannot read, and goes on working', () async {
    await expectLater(
      checker.use(<DictionaryFiles>[
        (affixFile: '${directory.path}/none.aff', wordList: 'none.dic'),
      ]),
      throwsException,
    );
    expect(await checker.check(<String>['cat']), <Verdict>[Verdict.wrong]);
  });

  test('fails what is still waiting once it is closed', () async {
    final answer = checker.check(<String>['cat']);
    checker.close();
    await expectLater(answer, throwsStateError);
    await expectLater(checker.check(<String>['cat']), throwsStateError);
  });
}
