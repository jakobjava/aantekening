import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  group('a group', () {
    test('closes past its escaped braces', () {
      expect(LatexSource.closedBrace(r'{a\}b} c', 0), 6);
      expect(LatexSource.closingBrace(r'{a\}b} c', 0), 6);
    });

    test('left open closes nowhere, or at the end', () {
      expect(LatexSource.closedBrace(r'{a\}', 0), isNull);
      expect(LatexSource.closingBrace(r'{a\}', 0), 4);
      expect(LatexSource.inside('{a{b}', 0, 5), 'a{b}');
    });
  });

  group('options', () {
    test('close past the groups and escaped brackets in them', () {
      expect(LatexSource.closedBracket('[a{]}b] c', 0), 7);
      expect(LatexSource.closedBracket(r'[a\]b] c', 0), 6);
      expect(LatexSource.inside(r'[a\]b] c', 0, 6), r'a\]b');
    });

    test('left open close nowhere', () {
      expect(LatexSource.closedBracket('[a{]', 0), isNull);
      expect(LatexSource.closingBracket('[a{]', 0), 4);
    });
  });

  group('an environment', () {
    const source =
        r'\begin{array}{c} \begin{array}{c} x \end{array} \end{array} y';
    final from = r'\begin{array}'.length;

    test('ends at its own end, those within it counted', () {
      expect(
        LatexSource.environmentEnd(source, from, 'array'),
        source.length - 2,
      );
    });

    test('never ended ends nowhere', () {
      expect(
        LatexSource.environmentEnd(
          r'\begin{array} x \end{matrix}',
          from,
          'array',
        ),
        isNull,
      );
    });
  });
}
