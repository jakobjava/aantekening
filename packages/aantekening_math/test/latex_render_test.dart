import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every expression the simple mode accepts must produce LaTeX the renderer
/// can actually typeset.
///
/// Translating to a plausible-looking string is not enough: a stray brace or a
/// command the engine does not know would leave the user staring at an error
/// box on their own page.
void main() {
  const expressions = <String>[
    '1/2',
    '(a+b)/(c+d)',
    'x^2 + y^2 = z^2',
    'sum_(i=1)^n i^2',
    'int_0^1 x^2 dx',
    'lim_(x->0) sin(x)/x',
    'sqrt(x+1)',
    'root(3,x)',
    'e^(-x^2/2)',
    'alpha beta gamma Delta Omega',
    'abs(x) + norm(v)',
    '|x-y| <= |x| + |y|',
    'vec(F) = m vec(a)',
    'binom(n,k)',
    'frac(partial f, partial x)',
    'A cup B subseteq C',
    'x in RR',
    'f(x, y) = x^2 y^3',
    'hat(x) bar(y) tilde(z)',
    '2 1/2',
    'sin^2 x + cos^2 x = 1',
    'oo',
    '"for all" x > 0',
    'a != b',
    'p => q',
    'floor(x) + ceil(y)',
    'x_1 + x_2 + ldots + x_n',
    'lim_(n->oo) (1+1/n)^n',
  ];

  group('generated LaTeX parses', () {
    for (final expression in expressions) {
      test('"$expression"', () {
        final latex = LinearMath.toLatex(expression);
        expect(
          () => TexParser(latex, const TexParserSettings()).parse(),
          returnsNormally,
          reason: 'produced: $latex',
        );
      });
    }
  });

  test('a recovered fragment still parses', () {
    // What is on screen halfway through typing must also be renderable.
    for (final partial in <String>['x^', '(a+b', 'sqrt(', '1/', 'sum_']) {
      final latex = LinearMath.toLatex(partial);
      expect(
        () => TexParser(latex, const TexParserSettings()).parse(),
        returnsNormally,
        reason: '"$partial" produced: $latex',
      );
    }
  });
}
