/// What can be written in the Simple syntax, as a cheat sheet shows it.
library;

import 'package:flutter/foundation.dart';

import 'linear_math.dart';
import 'symbols.dart';

/// Something the Simple syntax writes: what to type, and what it is.
@immutable
class SyntaxExample {
  const SyntaxExample(this.typed, this.meaning);

  /// What is typed, in the Simple syntax.
  final String typed;

  /// What it stands for, in a few words.
  final String meaning;

  /// The LaTeX it is stored as: [typed] translated, so what the guide shows
  /// is always what typing it gives.
  String get latex => LinearMath.toLatex(typed);
}

/// A group of [examples] on one subject.
@immutable
class SyntaxTopic {
  const SyntaxTopic(this.title, this.examples);

  final String title;
  final List<SyntaxExample> examples;
}

/// The Simple syntax, subject by subject.
///
/// Every example is typed as it is written here and must translate without a
/// complaint; the tests hold the guide to that.
abstract final class SimpleSyntaxGuide {
  static final List<SyntaxTopic> topics = List<SyntaxTopic>.unmodifiable(
    <SyntaxTopic>[
      const SyntaxTopic('Arithmetic', <SyntaxExample>[
        SyntaxExample('a + b - c', 'Plus and minus'),
        SyntaxExample('a * b', 'Times, as a dot'),
        SyntaxExample('a times b', 'Times, as a cross'),
        SyntaxExample('a/b', 'Fraction'),
        SyntaxExample('(a + b)/(c + d)', 'Brackets group a fraction'),
        SyntaxExample('2 1/2', 'Mixed number'),
        SyntaxExample('a +- b', 'Plus or minus'),
        SyntaxExample('n!', 'Factorial'),
        SyntaxExample('a mod n', 'Modulo'),
      ]),
      const SyntaxTopic('Powers and indices', <SyntaxExample>[
        SyntaxExample('x^2', 'Superscript'),
        SyntaxExample('x_i', 'Subscript'),
        SyntaxExample('x_i^2', 'Both'),
        SyntaxExample('e^(-x^2)', 'Brackets group a script'),
        SyntaxExample("f'(x) + f''(x)", 'Primes'),
        SyntaxExample('A^dagger', 'Dagger, the adjoint'),
        SyntaxExample('{}^14 C', 'Script before a symbol'),
      ]),
      const SyntaxTopic('Roots and functions', <SyntaxExample>[
        SyntaxExample('sqrt(x)', 'Square root'),
        SyntaxExample('root(3, x)', 'Other roots'),
        SyntaxExample('sin(x) + cos^2 x', 'Trigonometry'),
        SyntaxExample('ln(x) + log_2(x)', 'Logarithms'),
        SyntaxExample('exp(x)', 'Exponential'),
        SyntaxExample('tr(A) = sgn(x)', 'Other named functions'),
        SyntaxExample('binom(n, k)', 'Binomial coefficient'),
      ]),
      const SyntaxTopic('Brackets', <SyntaxExample>[
        SyntaxExample('(a) [b]', 'Round and square, growing to fit'),
        SyntaxExample('set(1, 2, 3)', 'Braces'),
        SyntaxExample('abs(x) = |x|', 'Absolute value'),
        SyntaxExample('norm(v)', 'Norm'),
        SyntaxExample('floor(x) + ceil(x)', 'Floor and ceiling'),
        SyntaxExample('inner(u, v)', 'Angle brackets'),
      ]),
      const SyntaxTopic('Sums, integrals and limits', <SyntaxExample>[
        SyntaxExample('sum_(i=1)^n a_i', 'Sum'),
        SyntaxExample('prod_(k=1)^n k', 'Product'),
        SyntaxExample('int_0^1 f(x) d x', 'Integral'),
        SyntaxExample('iint_D f d A', 'Double integral'),
        SyntaxExample('oint_C F', 'Contour integral'),
        SyntaxExample('lim_(x -> 0) f(x)', 'Limit'),
        SyntaxExample('max_(x in S) f(x)', 'Maximum and minimum'),
        SyntaxExample('bigcup_i A_i', 'Union of many'),
      ]),
      const SyntaxTopic('Quantum mechanics', <SyntaxExample>[
        SyntaxExample('ket(psi)', 'Ket'),
        SyntaxExample('bra(phi)', 'Bra'),
        SyntaxExample('braket(phi, psi)', 'Inner product'),
        SyntaxExample('braket(phi, H, psi)', 'Matrix element'),
        SyntaxExample('braket(A)', 'Expectation value'),
        SyntaxExample('ket(psi) bra(phi)', 'Outer product'),
        SyntaxExample('hat(H) ket(psi) = E ket(psi)', 'Operators'),
        SyntaxExample('ket(0) otimes ket(1)', 'Tensor product'),
        SyntaxExample('i hbar partial_t', 'Reduced Planck constant'),
      ]),
      const SyntaxTopic('Relations', <SyntaxExample>[
        SyntaxExample('a = b != c', 'Equal, not equal'),
        SyntaxExample('a < b <= c', 'Less than, or equal'),
        SyntaxExample('a > b >= c', 'Greater than, or equal'),
        SyntaxExample('a ~~ b', 'Approximately'),
        SyntaxExample('a equiv b', 'Identical'),
        SyntaxExample('a propto b', 'Proportional'),
        SyntaxExample('a sim b', 'Similar'),
        SyntaxExample('a ll b', 'Much less'),
        SyntaxExample('a perp b', 'Perpendicular'),
      ]),
      const SyntaxTopic('Arrows and logic', <SyntaxExample>[
        SyntaxExample('x -> y', 'Tends to, maps to'),
        SyntaxExample('x <- y', 'From'),
        SyntaxExample('x <-> y', 'Both ways'),
        SyntaxExample('p => q', 'Therefore'),
        SyntaxExample('p ==> q', 'Implies'),
        SyntaxExample('p <=> q', 'If and only if'),
        SyntaxExample('x mapsto x^2', 'Maps to'),
        SyntaxExample('forall x exists y', 'For all, there exists'),
        SyntaxExample('neg p wedge q vee r', 'Not, and, or'),
      ]),
      const SyntaxTopic('Sets', <SyntaxExample>[
        SyntaxExample('x in A', 'Element of'),
        SyntaxExample('x notin A', 'Not an element of'),
        SyntaxExample('A subset B subseteq C', 'Subsets'),
        SyntaxExample('A cup B cap C', 'Union, intersection'),
        SyntaxExample('A setminus B', 'Difference'),
        SyntaxExample('emptyset', 'Empty set'),
        SyntaxExample('NN ZZ QQ RR CC', 'Number sets'),
      ]),
      const SyntaxTopic('Accents and styles', <SyntaxExample>[
        SyntaxExample('vec(v)', 'Vector'),
        SyntaxExample('hat(x) + bar(x)', 'Hat, bar'),
        SyntaxExample('dot(x) + ddot(x)', 'Time derivatives'),
        SyntaxExample('tilde(x)', 'Tilde'),
        SyntaxExample('overline(AB)', 'Line over'),
        SyntaxExample('boldsymbol(F)', 'Bold'),
        SyntaxExample('mathcal(L)', 'Script'),
        SyntaxExample('mathbb(E)', 'Blackboard bold'),
      ]),
      const SyntaxTopic('Matrices and cases', <SyntaxExample>[
        SyntaxExample('mat(1, 2; 3, 4)', 'Matrix: `,` between, `;` down'),
        SyntaxExample('bmat(a, b; c, d)', 'In square brackets'),
        SyntaxExample('vmat(a, b; c, d)', 'Determinant'),
        SyntaxExample('vec(x, y, z)', 'Column vector'),
        SyntaxExample('cases(x, x >= 0; -x, x < 0)', 'Cases'),
      ]),
      SyntaxTopic('Greek letters', <SyntaxExample>[
        for (final letter in greekLetters.keys)
          if (greekLetters[letter]!.startsWith(r'\'))
            SyntaxExample(letter, letter),
      ]),
      const SyntaxTopic('Other symbols', <SyntaxExample>[
        SyntaxExample('infty', 'Infinity, or oo'),
        SyntaxExample('partial', 'Partial derivative'),
        SyntaxExample('nabla', 'Nabla'),
        SyntaxExample('ell', 'Script l'),
        SyntaxExample('ldots + cdots', 'Dots'),
        SyntaxExample('90 deg', 'Degrees'),
        SyntaxExample('angle', 'Angle'),
        SyntaxExample('therefore', 'Therefore'),
      ]),
      const SyntaxTopic('Words and LaTeX', <SyntaxExample>[
        SyntaxExample('x "if " x > 0', 'Words, in quotes'),
        SyntaxExample(r'\mathscr{L}', 'Any LaTeX command'),
        SyntaxExample(r'`\overset{!}{=}`', 'Any LaTeX, in backticks'),
      ]),
    ],
  );
}
