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
    expect(await checker.check(<String>['cat']), <bool>[false]);
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
      <bool>[true, true, false, false],
    );
    expect(await checker.suggest('dgo'), <String>['dog']);

    await checker.use(<DictionaryFiles>[dutch], personalWords: <String>['kat']);
    expect(await checker.check(<String>['cats', 'hond', 'kat']), <bool>[
      false,
      true,
      true,
    ]);
    await checker.addWord('poes');
    expect(await checker.check(<String>['poes', 'Poes']), <bool>[true, true]);
  });

  test('reports a dictionary it cannot read, and goes on working', () async {
    await expectLater(
      checker.use(<DictionaryFiles>[
        (affixFile: '${directory.path}/none.aff', wordList: 'none.dic'),
      ]),
      throwsException,
    );
    expect(await checker.check(<String>['cat']), <bool>[false]);
  });

  test('fails what is still waiting once it is closed', () async {
    final answer = checker.check(<String>['cat']);
    checker.close();
    await expectLater(answer, throwsStateError);
    await expectLater(checker.check(<String>['cat']), throwsStateError);
  });
}
