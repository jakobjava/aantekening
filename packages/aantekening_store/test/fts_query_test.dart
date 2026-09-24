import 'package:aantekening_store/aantekening_store.dart';
import 'package:test/test.dart';

void main() {
  group('FtsQuery', () {
    test('quotes and ANDs the typed words', () {
      expect(
        FtsQuery.build('fourier transform', prefixLastTerm: false),
        '"fourier" AND "transform"',
      );
    });

    test('ORs the words of a question asked', () {
      expect(
        FtsQuery.build('newton laws', prefixLastTerm: false, matchAny: true),
        '"newton" OR "laws"',
      );
    });

    test('makes the last word a prefix so results narrow while typing', () {
      expect(FtsQuery.build('four'), '"four"*');
      expect(FtsQuery.build('fourier tra'), '"fourier" AND "tra"*');
    });

    test('keeps a closed quoted run together as an exact phrase', () {
      expect(FtsQuery.build('"chain rule"'), '"chain rule"');
    });

    test('neutralises FTS5 operators typed as ordinary text', () {
      // Without escaping these would parse as syntax and raise mid-keystroke.
      expect(FtsQuery.build('a AND', prefixLastTerm: false), '"a" AND "AND"');
      expect(
        FtsQuery.build('rate-limit', prefixLastTerm: false),
        '"rate" AND "limit"',
      );
      expect(
        FtsQuery.build('col:value', prefixLastTerm: false),
        '"col" AND "value"',
      );
      expect(FtsQuery.build('(x)', prefixLastTerm: false), '"x"');
      expect(FtsQuery.build('-NOT', prefixLastTerm: false), '"NOT"');
    });

    test('escapes embedded quotes by doubling them', () {
      expect(
        FtsQuery.build('say "hi', prefixLastTerm: false),
        '"say" AND "hi"',
      );
    });

    test('returns null when there is nothing to search for', () {
      expect(FtsQuery.build(''), isNull);
      expect(FtsQuery.build('   '), isNull);
      expect(FtsQuery.build('()*'), isNull);
    });
  });
}
