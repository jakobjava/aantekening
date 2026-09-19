import 'dart:convert';

import 'package:aantekening_spell/aantekening_spell.dart';
import 'package:test/test.dart';

// Small dictionaries exercising what real ones use. Every verdict expected
// here is what Hunspell 1.7.3 itself gives for the same files.

const String _englishAffixes = '''
SET UTF-8
TRY esianrtolcdugmphbyfvkwzESIANRTOLCDUGMPHBYFVKWZ'
ICONV 1
ICONV ’ '
REP 2
REP f ph
REP ph f
KEEPCASE K
FORBIDDENWORD !
NEEDAFFIX N
PFX U Y 1
PFX U 0 un .
SFX S Y 3
SFX S y ies [^aeiou]y
SFX S 0 s [aeiou]y
SFX S 0 s [^y]
SFX D Y 2
SFX D 0 ed [^e]
SFX D 0 d e
SFX M N 1
SFX M 0 's .
''';

const String _englishWords = '''
14
happy/U
colour/SDM
cat/SM
city/SM
hope/D
lock/UD
London/M
NASA/K
iPhone/S
recieve/!
tele/N
phone/SM
etc.
a lot
''';

const String _germanAffixes = '''
SET UTF-8
TRY esijanrtolcdugmphbyfvkwqxzäüößáéêàâñESIJANRTOLCDUGMPHBYFVKWQXZÄÜÖÉ-.
COMPOUNDBEGIN x
COMPOUNDMIDDLE y
COMPOUNDEND z
ONLYINCOMPOUND o
COMPOUNDPERMITFLAG c
COMPOUNDMIN 2
CHECKSHARPS
KEEPCASE w
BREAK 2
BREAK -
BREAK .
SFX s Y 1
SFX s 0 s/xyco .
SFX n Y 1
SFX n 0 n .
''';

const String _germanWords = '''
10
haus/xyzs
tür/xyzn
schlüssel/xyz
groß
Straße/w
dampf/xyzs
schiff/xyz
fahrt/xyz
kapitän/xyz
nur/o
''';

void _expectVerdicts(HunspellDictionary dictionary, Map<String, bool> words) {
  for (final MapEntry(key: word, value: correct) in words.entries) {
    expect(dictionary.check(word), correct, reason: word);
  }
}

void main() {
  group('an English dictionary', () {
    final english = HunspellDictionary.parse(_englishAffixes, _englishWords);

    test('takes its words, with the affixes they allow', () {
      _expectVerdicts(english, <String, bool>{
        'happy': true,
        'unhappy': true,
        'colours': true,
        'coloured': true,
        "colour's": true,
        'cities': true,
        'citys': false,
        'hoped': true,
        'hopeed': false,
        'unlocked': true,
        'color': false,
        'hapy': false,
      });
    });

    test('takes capitals as Hunspell does', () {
      _expectVerdicts(english, <String, bool>{
        'Happy': true,
        'HAPPY': true,
        'London': true,
        "London's": true,
        'london': false,
        'NASA': true,
        'Nasa': false,
        'nasa': false,
        'iPhone': true,
        'iPhones': true,
        'IPHONE': true,
        'Iphone': false,
      });
    });

    test('forbids forbidden words, and roots that need an affix', () {
      _expectVerdicts(english, <String, bool>{
        'recieve': false,
        'tele': false,
        'telephone': false,
      });
    });

    test('reads a typographic apostrophe as the dictionary writes it', () {
      expect(english.check('colour’s'), isTrue);
    });

    test('takes abbreviations with their full stop, and numbers', () {
      _expectVerdicts(english, <String, bool>{
        'etc': false,
        'etc.': true,
        '1,000': true,
        '3.14': true,
        '2-3': true,
      });
    });

    test('suggests corrections', () {
      expect(english.suggest('hapy'), <String>['happy']);
      expect(english.suggest('coolour'), <String>['colour']);
      expect(english.suggest('colur'), <String>['colour']);
      expect(english.suggest('fone'), <String>['phone']);
      expect(english.suggest('Londn'), <String>['London']);
      // A pair of words the dictionary lists is the best suggestion there
      // is; a forbidden word is never suggested.
      expect(english.suggest('alot'), <String>['a lot']);
      expect(english.suggest('recieve'), isEmpty);
    });
  });

  group('a German dictionary', () {
    final german = HunspellDictionary.parse(_germanAffixes, _germanWords);

    test('joins words into compounds', () {
      _expectVerdicts(german, <String, bool>{
        'Haus': true,
        'Haustür': true,
        'Haustürschlüssel': true,
        'Hausschlüssel': true,
        'Türhaus': true,
        'Dampfschiff': true,
        'Dampfschifffahrt': true,
        'Dampfsschiff': true,
        'haustürn': true,
        'Hausfoo': false,
        'häuser': false,
      });
    });

    test('keeps a word only allowed in compounds out of them alone', () {
      _expectVerdicts(german, <String, bool>{
        'nur': false,
        'nurhaus': false,
        'hausnur': false,
      });
    });

    test('writes ß as SS in capitals, and keeps its case otherwise', () {
      _expectVerdicts(german, <String, bool>{
        'groß': true,
        'GROSS': true,
        'Straße': true,
        'STRASSE': true,
        'Strasse': false,
      });
    });

    test('checks words broken at a break point on both sides', () {
      _expectVerdicts(german, <String, bool>{
        'Haus-Tür': true,
        'Kapitän-Schlüssel': true,
        'haus.tür': true,
        'foo-Haus': false,
      });
    });

    test('suggests compounds', () {
      expect(german.suggest('Haustr'), <String>['Haustür']);
    });
  });

  group('flags', () {
    test('two characters long', () {
      final dictionary = HunspellDictionary.parse(
        'SET UTF-8\nFLAG long\nCOMPOUNDFLAG Cx\nSFX Aa Y 1\nSFX Aa 0 en .\n',
        '2\nboek/AaCx\nkast/Cx\n',
      );
      _expectVerdicts(dictionary, <String, bool>{
        'boeken': true,
        'boekkast': true,
        'kastboeken': true,
        'kasten': false,
      });
    });

    test('numbered, through aliases, with compound rules', () {
      final dictionary = HunspellDictionary.parse(
        'SET UTF-8\nFLAG num\nAF 2\nAF 101,7\nAF 7\n'
            'SFX 101 Y 1\nSFX 101 0 s .\nCOMPOUNDRULE 1\nCOMPOUNDRULE 7*\n',
        '2\ncat/1\ndog/2\n',
      );
      _expectVerdicts(dictionary, <String, bool>{
        'cats': true,
        'dogs': false,
        'catdog': false,
      });
    });

    test('compound rules with quantifiers', () {
      final dictionary = HunspellDictionary.parse(
        'SET UTF-8\nCOMPOUNDMIN 1\nONLYINCOMPOUND c\n'
            'COMPOUNDRULE 2\nCOMPOUNDRULE n*1t\nCOMPOUNDRULE n*mp\n',
        '8\n0/nm\n1/n1\n2/nm\n3/nm\n1st/p\nst/tc\nnd/pc\n2nd/p\n',
      );
      _expectVerdicts(dictionary, <String, bool>{
        '1st': true,
        '21st': true,
        '101st': true,
        '22nd': true,
        '3rd': false,
      });
    });
  });

  test('reads a dictionary in the encoding its affix file names', () {
    final dictionary = HunspellDictionary.fromBytes(
      latin1.encode('SET ISO8859-1\nSFX A Y 1\nSFX A 0 s .\n'),
      latin1.encode('1\ncafé/A\n'),
    );
    _expectVerdicts(dictionary, <String, bool>{
      'café': true,
      'cafés': true,
      'cafe': false,
    });
  });

  test('ignores comments and blank lines inside tables', () {
    final dictionary = HunspellDictionary.parse(
      'SET UTF-8\n# a comment\nSFX S Y 2\n\nSFX S 0 s .  # plural\n'
          '# between\nSFX S 0 es s\nBREAK 1\nBREAK -\n',
      '2\ncat/S\nbus/S\n',
    );
    _expectVerdicts(dictionary, <String, bool>{
      'cats': true,
      'buses': true,
      'cat-bus': true,
    });
  });
}
