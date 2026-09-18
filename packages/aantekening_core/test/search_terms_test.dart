import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

/// The parts of [text] that [query] highlights.
List<String> found(String query, String text) => <String>[
  for (final match in SearchTerms.parse(query).matchesIn(text))
    text.substring(match.start, match.end),
];

void main() {
  group('reading a query', () {
    test('splits words at spaces and punctuation', () {
      final terms = SearchTerms.parse('rate-limit  x:y').terms;
      expect(terms.map((term) => term.text), <String>[
        'rate',
        'limit',
        'x',
        'y',
      ]);
    });

    test('keeps a quoted run together as a phrase', () {
      final terms = SearchTerms.parse('"chain rule" proof').terms;
      expect(terms.first.text, 'chain rule');
      expect(terms.first.isPhrase, isTrue);
      expect(terms.last.isPhrase, isFalse);
    });

    test('takes only a bare last word as still being typed', () {
      expect(
        SearchTerms.parse('fourier tra').terms.map((term) => term.isPrefix),
        <bool>[false, true],
      );
      expect(SearchTerms.parse('"chain rule"').terms.single.isPrefix, isFalse);
      expect(
        SearchTerms.parse('tra', prefixLastTerm: false).terms.single.isPrefix,
        isFalse,
      );
    });

    test('finds nothing to search for in punctuation alone', () {
      expect(SearchTerms.parse('  ()* ').isEmpty, isTrue);
    });
  });

  group('matches in a text', () {
    test('ignore case and accents, as the index does', () {
      expect(found('uber', 'Über das Café'), <String>['Über']);
      expect(found('CAFE', 'Über das Café'), <String>['Café']);
    });

    test('take whole words, but only the typed start of the last one', () {
      expect(found('the', 'the theorem'), <String>['the', 'the']);
      expect(found('the resi', 'the residue theorem'), <String>['the', 'resi']);
      expect(
        SearchTerms.parse(
          'the',
          prefixLastTerm: false,
        ).matchesIn('the theorem').length,
        1,
      );
    });

    test('find a phrase only where its words follow one another', () {
      expect(found('"chain rule"', 'the chain rule, a rule chain'), <String>[
        'chain rule',
      ]);
    });

    test('merge where two terms overlap', () {
      expect(found('residue res', 'residue'), <String>['residue']);
    });

    test('are empty for an empty query', () {
      expect(SearchTerms.parse('').matchesIn('anything'), isEmpty);
    });
  });
}
