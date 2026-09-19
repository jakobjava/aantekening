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

    test('finds the words no language has', () {
      final checker = SpellChecker(<HunspellDictionary>[english, dutch]);
      const text = 'the cat and the kat, hond en dogs';
      expect(
        <String>[
          for (final span in checker.misspellingsIn(text))
            text.substring(span.start, span.end),
        ],
        <String>['and', 'en'],
      );
    });

    test('takes an abbreviation with its full stop', () {
      final checker = SpellChecker(<HunspellDictionary>[english]);
      expect(checker.misspellingsIn('the etc. cat'), isEmpty);
      expect(checker.misspellingsIn('the etc cat'), hasLength(1));
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
      checker.removeWord('Utrecht');
      expect(checker.isCorrect('Utrecht'), isFalse);
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
