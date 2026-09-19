import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts that [input] translates to [latex] with no diagnostics.
void expectLatex(String input, String latex) {
  final translation = LinearMath.translate(input);
  expect(
    translation.diagnostics,
    isEmpty,
    reason: 'while translating "$input"',
  );
  expect(translation.latex, latex, reason: 'while translating "$input"');
}

void main() {
  group('fractions', () {
    test('builds up a simple fraction', () {
      expectLatex('1/2', r'\frac{1}{2}');
    });

    test('drops brackets the fraction bar already implies', () {
      expectLatex('(a+b)/c', r'\frac{a + b}{c}');
      expectLatex('(a+b)/(c+d)', r'\frac{a + b}{c + d}');
    });

    test('binds tighter than addition', () {
      expectLatex('a+b/c', r'a + \frac{b}{c}');
    });

    test('binds only the nearest factor of an implicit product', () {
      // "two and a half", not "(2 times 1) over 2".
      expectLatex('2 1/2', r'2 \frac{1}{2}');
      expectLatex('a b/c', r'a \frac{b}{c}');
    });

    test('nests left to right', () {
      expectLatex('1/2/3', r'\frac{\frac{1}{2}}{3}');
    });

    test('accepts an explicit frac construct', () {
      expectLatex('frac(a,b)', r'\frac{a}{b}');
    });
  });

  group('scripts', () {
    test('raises and lowers single atoms', () {
      expectLatex('x^2', 'x^2');
      expectLatex('x_i', 'x_i');
    });

    test('applies to one atom, not the rest of the product', () {
      expectLatex('x^2y', 'x^2 y');
    });

    test('takes a bracketed group as a whole exponent', () {
      expectLatex('x^(n+1)', 'x^{n + 1}');
      expectLatex('e^(-x^2)', 'e^{-x^2}');
    });

    test('combines a subscript and a superscript on one base', () {
      expectLatex('x^2_i', 'x_i^2');
      expectLatex('x_i^2', 'x_i^2');
    });

    test('keeps both limits of a big operator separate', () {
      // The subscript must not swallow the following "^n".
      expectLatex('sum_(i=1)^n i^2', r'\sum_{i = 1}^n i^2');
      expectLatex('int_0^1 x', r'\int_0^1 x');
    });

    test('allows a negative exponent', () {
      expectLatex('x^-1', 'x^{-1}');
    });
  });

  group('roots', () {
    test('accepts bracketed and bare arguments', () {
      expectLatex('sqrt(x)', r'\sqrt{x}');
      expectLatex('sqrt x', r'\sqrt{x}');
      expectLatex('sqrt(x+1)', r'\sqrt{x + 1}');
    });

    test('supports an explicit degree', () {
      expectLatex('root(3,x)', r'\sqrt[3]{x}');
      expectLatex('nthroot(3,x+1)', r'\sqrt[3]{x + 1}');
    });
  });

  group('functions and operators', () {
    test('typesets named functions upright', () {
      expectLatex('sin x', r'\sin x');
      expectLatex('ln(x)', r'\ln \left( x \right)');
    });

    test('keeps a function application together under division', () {
      expectLatex(
        'lim_(x->0) sin(x)/x',
        r'\lim_{x \to 0} \frac{\sin \left( x \right)}{x}',
      );
    });

    test('scripts a function name', () {
      expectLatex('sin^2 x', r'\sin^2 x');
    });

    test('translates typed operator shorthands', () {
      expectLatex('x <= y', r'x \leq y');
      expectLatex('a != b', r'a \neq b');
      expectLatex('x >= 0', r'x \geq 0');
      expectLatex('a +- b', r'a \pm b');
      expectLatex('x -> oo', r'x \to \infty');
      expectLatex('p => q', r'p \Rightarrow q');
      expectLatex('a * b', r'a \cdot b');
    });

    test('treats spelled-out operators as operators, not operands', () {
      expectLatex('x in A', r'x \in A');
      expectLatex('A cup B', r'A \cup B');
    });
  });

  group('symbols and grouping', () {
    test('recognises Greek letters by name', () {
      expectLatex('alpha + beta', r'\alpha + \beta');
      expectLatex('Delta x', r'\Delta x');
    });

    test('splits unrecognised letter runs into separate variables', () {
      // "xy" is two variables multiplied, as it would be on paper.
      expectLatex('xy', 'x y');
    });

    test('prefers the longest known word', () {
      expectLatex('varepsilon', r'\varepsilon');
      expectLatex('arcsin x', r'\arcsin x');
    });

    test('fences absolute values written either way', () {
      expectLatex('abs(x)', r'\left\lvert x \right\rvert');
      expectLatex('|x|', r'\left\lvert x \right\rvert');
      expectLatex(
        '|x| + |y|',
        r'\left\lvert x \right\rvert + \left\lvert y \right\rvert',
      );
    });

    test('applies accents', () {
      expectLatex('vec(v)', r'\vec{v}');
      expectLatex('bar(x)', r'\bar{x}');
      expectLatex('hat(x)', r'\hat{x}');
    });

    test('keeps quoted prose as text', () {
      expectLatex('"if" x > 0', r'\text{if} x > 0');
    });

    test('handles commas inside brackets', () {
      expectLatex('f(x, y)', r'f \left( x, y \right)');
      expectLatex('binom(n,k)', r'\binom{n}{k}');
    });

    test('groups an ambiguous derivative when brackets are supplied', () {
      expectLatex('(partial f)/(partial x)', r'\frac{\partial f}{\partial x}');
    });
  });

  group('error recovery', () {
    test('still renders an expression that is mid-keystroke', () {
      final translation = LinearMath.translate('x^');
      expect(translation.latex, isNotEmpty);
      expect(translation.isComplete, isFalse);
      expect(translation.diagnostics.single.offset, 2);
    });

    test('closes an unbalanced bracket and reports where', () {
      final translation = LinearMath.translate('(a+b');
      expect(translation.latex, r'\left( a + b \right)');
      expect(translation.diagnostics, hasLength(1));
    });

    test('skips an unrecognised character and keeps going', () {
      final translation = LinearMath.translate(r'a # b');
      expect(translation.latex, 'a b');
      expect(translation.diagnostics.single.message, contains('#'));
    });

    test('an empty expression is a placeholder, not an error', () {
      final translation = LinearMath.translate('');
      expect(translation.diagnostics, isEmpty);
      expect(translation.latex, r'\square');
    });
  });

  group('Dirac notation', () {
    test('writes bras and kets', () {
      expectLatex('ket(psi)', r'\ket{\psi}');
      expectLatex('bra(phi)', r'\bra{\phi}');
      expectLatex('ket(0) + ket(1)', r'\ket{0} + \ket{1}');
    });

    test('writes a bra-ket of one, two or three parts', () {
      expectLatex('braket(A)', r'\braket{A}');
      expectLatex('braket(phi, psi)', r'\braket{\phi | \psi}');
      expectLatex(
        'braket(phi, hat(H), psi)',
        r'\braket{\phi | \hat{H} | \psi}',
      );
    });

    test('keeps a bra-ket part in brackets whole', () {
      expectLatex('ket((a + b)/2)', r'\ket{\frac{a + b}{2}}');
    });

    test('complains of a bra-ket of more than three parts', () {
      final translation = LinearMath.translate('braket(a, b, c, d)');
      expect(translation.diagnostics.single.message, contains('braket'));
    });

    test('writes a daggered operator', () {
      expectLatex('A^dagger', r'A^\dagger');
    });
  });

  group('more words', () {
    test('writes the number sets', () {
      expectLatex('x in RR', r'x \in \mathbb{R}');
      expectLatex('NN subset ZZ', r'\mathbb{N} \subset \mathbb{Z}');
    });

    test('writes named operators upright', () {
      expectLatex('tr(A B)', r'\operatorname{tr} \left( A B \right)');
      expectLatex('Var(X)', r'\operatorname{Var} \left( X \right)');
    });

    test('writes a double arrow and modulo', () {
      expectLatex('a <-> b', r'a \leftrightarrow b');
      expectLatex('a mod n', r'a \bmod n');
    });
  });

  group('mode handling', () {
    test('passes LaTeX sources through untouched', () {
      const source = r'\oint_C \vec{F} \cdot d\vec{r}';
      expect(LinearMath.latexFor(MathMode.latex, source), source);
    });

    test('translates linear sources', () {
      expect(LinearMath.latexFor(MathMode.linear, '1/2'), r'\frac{1}{2}');
    });
  });
}
