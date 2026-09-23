import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simple input covering the linear syntax, for round trips.
const List<String> _simpleExamples = <String>[
  'x^2 + y^2 = r^2',
  '(a + b)/c',
  'x^2/3',
  '2 1/2',
  'sum_(i = 1)^n i^2 = (n(n + 1)(2n + 1))/6',
  'int_0^infty e^(-x^2) d x = sqrt(pi)/2',
  'lim_(x -> 0) sin(x)/x = 1',
  'f(x) = a x^2 + b x + c',
  'alpha + beta <= gamma',
  'a != b, c ~~ d',
  'x in RR ==> x^2 >= 0',
  'vec(v) * vec(w) = |v||w| cos theta',
  'hat(x) + bar(y) + dot(z)',
  'root(3, x + 1)',
  'binom(n, k) = n!/(k!(n - k)!)',
  'norm(x) = sqrt(inner(x, x))',
  'floor(x) <= x <= ceil(x)',
  'mathbb(R)^n',
  'e^(i pi) + 1 = 0',
  'a_(i j) b_(j k)',
  '-x + -y',
  'mat(1, 2; 3, 4)',
  'bmat(a, b; c, d) vec(x, y) = vec(e, f)',
  'vmat(a, b; c, d) = a d - b c',
  'cases(x, x >= 0; -x, x < 0)',
  'set(1, 2, 3) cup set(4)',
  "f'(x) + g''(x)",
  r'\mathcal{A} subset \mathcal{B}',
  '`a^*` + b',
  '"if " x > 0',
  'x = 1, 2, 3',
  'ket(psi) = alpha ket(0) + beta ket(1)',
  'braket(phi, psi) = braket(psi, phi)^*',
  'braket(phi, hat(H), psi)',
  'ket(psi) bra(psi)',
  'U^dagger U = mathbb(1)',
  'tr(rho) = 1',
  'a mod n <-> b',
  'E = highlight(m c^2)',
  'highlight(#A8E6B0, 1/2) x^highlight(2)',
];

void main() {
  group('LaTeX to Simple', () {
    final cases = <String, String>{
      r'\frac{a+b}{c}': '(a + b)/c',
      r'\frac{x^{2}}{3}': 'x^2/3',
      r'\frac{1}{2}x': '1/2 x',
      r'x^{2}': 'x^2',
      r'x^{n+1}': 'x^(n + 1)',
      r'x_{i}': 'x_i',
      r'\sqrt{x}': 'sqrt(x)',
      r'\sqrt[3]{x}': 'root(3, x)',
      r'\sum_{i=1}^{n} i^2': 'sum_(i = 1)^n i^2',
      r'\lim_{x \to 0} \frac{\sin x}{x}': 'lim_(x -> 0) (sin x)/x',
      r'\alpha + \beta = \gamma': 'alpha + beta = gamma',
      r'a \leq b \neq c': 'a <= b != c',
      r'a \cdot b \times c': 'a * b times c',
      r'x \pm y': 'x +- y',
      r'\vec{v}': 'vec(v)',
      r'\mathbb{R}': 'RR',
      r'\mathbb{E}': 'mathbb(E)',
      r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}': 'mat(1, 2; 3, 4)',
      r'\begin{bmatrix} a & b \end{bmatrix}': 'bmat(a, b)',
      r'\begin{pmatrix} x \\ y \\ z \end{pmatrix}': 'vec(x, y, z)',
      r'\begin{cases} x & x \geq 0 \\ -x & x < 0 \end{cases}':
          'cases(x, x >= 0; -x, x < 0)',
      r'\left| x \right|': '|x|',
      r'\lVert v \rVert': 'norm(v)',
      r'\{1, 2\}': 'set(1, 2)',
      r'\text{if } x > 0': '"if " x > 0',
      r"f'(x)": "f'(x)",
      r'\operatorname{sgn}(x)': 'sgn(x)',
      r'\operatorname{Hom}(A, B)': r'\operatorname{Hom}(A, B)',
      r'\ket{\psi}': 'ket(psi)',
      r'\Bra{\phi}': 'bra(phi)',
      r'\braket{\phi|\psi}': 'braket(phi, psi)',
      r'\braket{\phi | \hat{H} | \psi}': 'braket(phi, hat(H), psi)',
      r'\braket{\|x\|}': 'braket(norm(x))',
      r'a + \colorbox{#FFEF9D}{$b^2$}': 'a + highlight(b^2)',
      r'\colorbox{#A8E6B0}{$\frac{1}{2}$}': 'highlight(#A8E6B0, 1/2)',
      r'\colorbox{yellow}{if}': r'`\colorbox{yellow}{if}`',
      r'A^\dagger': 'A^dagger',
      r'a \leftrightarrow b': 'a <-> b',
      r'a^*': 'a^`*`',
      r'[0, 1)': '`[`0, 1`)`',
      r'\begin{aligned} a &= b \end{aligned}':
          r'`\begin{aligned} a &= b \end{aligned}`',
      '': '',
    };
    for (final entry in cases.entries) {
      test(entry.key.isEmpty ? '(empty)' : entry.key, () {
        expect(LinearMath.fromLatex(entry.key), entry.value);
      });
    }
  });

  group('round trips', () {
    for (final simple in _simpleExamples) {
      test('Simple: $simple', () {
        final latex = LinearMath.translate(simple);
        expect(latex.diagnostics, isEmpty, reason: 'a valid example');
        final back = LinearMath.fromLatex(latex.latex);
        final again = LinearMath.translate(back);
        expect(again.diagnostics, isEmpty, reason: back);
        expect(again.latex, latex.latex, reason: back);
      });
    }

    for (final latex in <String>[
      r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
      r'\int_a^b f(x)\,dx = F(b) - F(a)',
      r'\nabla \cdot \vec{E} = \frac{\rho}{\varepsilon_0}',
      r'\det\begin{pmatrix} a & b \\ c & d \end{pmatrix} = ad - bc',
      r'P(A \mid B) = \frac{P(B \mid A) P(A)}{P(B)}',
      r'e^{i\theta} = \cos\theta + i\sin\theta',
      r'\left( \frac{a}{b} \right)^{2}',
      r'\overline{z} \cdot z = |z|^2',
      r'\forall \epsilon > 0 \; \exists \delta > 0',
      r'{}^{14}_{6}\mathrm{C}',
    ]) {
      test('LaTeX: $latex', () {
        final simple = LinearMath.fromLatex(latex);
        final translated = LinearMath.translate(simple);
        expect(translated.diagnostics, isEmpty, reason: simple);
        // Written again from its own translation, it comes out the same.
        expect(LinearMath.fromLatex(translated.latex), simple);
      });
    }
  });

  group('the Simple syntax', () {
    String latex(String input) => LinearMath.toLatex(input);

    test('writes matrices, row by row', () {
      expect(
        latex('mat(1, 2; 3, 4)'),
        r'\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}',
      );
      expect(latex('bmat(a; b)'), r'\begin{bmatrix} a \\ b \end{bmatrix}');
      expect(latex('vmat(a, b; c, d)'), startsWith(r'\begin{vmatrix}'));
    });

    test('writes a vector of several entries as a column', () {
      expect(
        latex('vec(1, 2, 3)'),
        r'\begin{pmatrix} 1 \\ 2 \\ 3 \end{pmatrix}',
      );
      expect(latex('vec(v)'), r'\vec{v}');
      expect(latex('vec v'), r'\vec{v}');
    });

    test('writes cases', () {
      expect(
        latex('cases(1, x > 0; 0, "otherwise")'),
        r'\begin{cases} 1 & x > 0 \\ 0 & \text{otherwise} \end{cases}',
      );
    });

    test('passes LaTeX commands and backticks through', () {
      expect(latex(r'\mathcal{A}'), r'\mathcal{A}');
      expect(latex(r'\frac{a}{b}'), r'\frac{a}{b}');
      expect(latex(r'a \, b'), r'a \, b');
      expect(latex('`\\overset{!}{=}`'), r'\overset{!}{=}');
    });

    test('reads primes and letters beyond ASCII', () {
      expect(latex("f'"), r'f^\prime');
      expect(latex('2π'), '2 π');
    });

    test('keeps going past a stray character', () {
      final result = LinearMath.translate('a + b) + c');
      expect(result.diagnostics, isNotEmpty);
      expect(result.latex, contains('c'));
    });
  });

  test('never throws on broken LaTeX', () {
    for (final broken in <String>[
      r'\frac{',
      '}}}',
      r'\left(',
      r'\right)',
      r'\begin{pmatrix} 1 &',
      r'\end{pmatrix}',
      '^^__',
      r'\sqrt[',
      r'\',
      r'\text{',
      '((((',
      '||x',
      r'\lvert x',
      r'\{ 1',
    ]) {
      final simple = LinearMath.fromLatex(broken);
      expect(() => LinearMath.translate(simple), returnsNormally);
    }
  });
}
