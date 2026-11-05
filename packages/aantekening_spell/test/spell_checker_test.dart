import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:test/test.dart';

List<String> _words(String text) => <String>[
  for (final span in WordSplitter.wordsOf(text))
    text.substring(span.start, span.end),
];

void main() {
  group('splitting text into words', () {
    test('keeps apostrophes, hyphens and full stops between letters', () {
      expect(_words("It's a well-known fact, e.g. in 'quotes'."), <String>[
        "It's",
        'well-known',
        'fact',
        'e.g',
        'in',
        'quotes',
      ]);
    });

    test('leaves out words with digits, capitals and single letters', () {
      expect(_words('A mp3 of the BBC in 3D, x'), <String>['of', 'the', 'in']);
    });

    test('leaves out web and e-mail addresses', () {
      expect(
        _words('see https://example.org/some-page or me@mail.nl now'),
        <String>['see', 'or', 'now'],
      );
    });

    test('reads letters beyond ASCII', () {
      expect(_words('Straße, café en ĳs'), <String>[
        'Straße',
        'café',
        'en',
        'ĳs',
      ]);
    });
  });

  group('checking text', () {
    final english = HunspellDictionary.parse(
      'SET UTF-8\nTRY esianrtolcdugmphbyfvkwz\nSFX S Y 1\nSFX S 0 s .\n',
      '4\ncat/S\ndog/S\nthe\netc.\n',
    );
    final dutch = HunspellDictionary.parse(
      'SET UTF-8\nTRY enrtaioslkdgumvhbpjcfwzyxq\n',
      '2\nkat\nhond\n',
    );
    // Words made of any number of others, so that ruling out a long word
    // not among them takes longer than a check is given.
    final endless = HunspellDictionary.parse(
      'SET UTF-8\nCOMPOUNDFLAG X\nCOMPOUNDMIN 1\n',
      '4\na/X\naa/X\naaa/X\naaaa/X\n',
    );

    List<String> misspelt(SpellChecker checker, String text) => <String>[
      for (final span in SpellChecker.misspellingsWith(text, checker.isCorrect))
        text.substring(span.start, span.end),
    ];

    test('finds the words no language has', () {
      final checker = SpellChecker(<HunspellDictionary>[english, dutch]);
      expect(misspelt(checker, 'the cat and the kat, hond en dogs'), <String>[
        'and',
        'en',
      ]);
    });

    test('takes an abbreviation with its full stop', () {
      final checker = SpellChecker(<HunspellDictionary>[english]);
      expect(misspelt(checker, 'the etc. cat'), isEmpty);
      expect(misspelt(checker, 'the etc cat'), hasLength(1));
    });

    test('is unsure of a word a language ran out of time on, each time it '
        'is asked', () {
      final checker = SpellChecker(<HunspellDictionary>[english, endless]);
      final word = 'a' * 40 + 'b';
      expect(checker.verdictOn(word), Verdict.unsure);
      expect(checker.isCorrect(word), isFalse);
      expect(checker.verdictOn(word), Verdict.unsure, reason: 'not kept');
      expect(checker.verdictOn('cat'), Verdict.right);
      expect(checker.verdictOn('dgo'), Verdict.wrong);
    });

    test('takes words added to it, capitalised as a word may be', () {
      final checker = SpellChecker(
        <HunspellDictionary>[english],
        personalWords: <String>['aantekening'],
      );
      expect(checker.isCorrect('aantekening'), isTrue);
      expect(checker.isCorrect('Aantekening'), isTrue);
      expect(checker.isCorrect('AANTEKENING'), isTrue);
      expect(checker.isCorrect('aanteken'), isFalse);

      checker.addWord('Utrecht');
      expect(checker.isCorrect('Utrecht'), isTrue);
      expect(checker.isCorrect('UTRECHT'), isTrue);
      expect(checker.isCorrect('utrecht'), isFalse);
    });

    test('suggests from every language, best first', () {
      final checker = SpellChecker(<HunspellDictionary>[
        HunspellDictionary.parse('SET UTF-8\nTRY aiu\n', '2\ncat\ncut\n'),
        HunspellDictionary.parse('SET UTF-8\nTRY aiu\n', '2\nkat\nkit\n'),
      ]);
      // Each language's best, then the next best: a key beside the one
      // pressed comes before any other letter, as in Hunspell.
      expect(checker.suggest('kut'), <String>['cut', 'kit', 'kat']);
      expect(checker.suggest('kut', limit: 2), <String>['cut', 'kit']);
    });
  });
}
