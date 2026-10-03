import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  test('a formula brought in stays one, through JSON and changes', () {
    const run = TextRun.imported(r'\ce{H2O}', TextMarks(color: 0xFFFF0000));
    final read = TextRun.fromJson(run.toJson());
    expect(read, run);
    expect(read.imported, isTrue);
    expect(run.copyWith(text: 'x', math: MathMode.linear).imported, isTrue);
    expect(const TextRun.math('x', MathMode.latex).imported, isFalse);
    expect(
      const TextRun.math('x', MathMode.latex),
      isNot(const TextRun.imported('x')),
    );
    expect(const TextRun('x').toJson().containsKey('imported'), isFalse);
  });

  group('a preamble', () {
    test('writes the commands it defines into a formula', () {
      final preamble = LatexPreamble.read(r'''
\newcommand{\Rn}{\mathbb{R}^n}
\newcommand{\pair}[2]{(#1, #2)}
\DeclareMathOperator{\sgn}{sgn}
\def\half{\frac12}''');
      expect(preamble.leftOver, isEmpty);
      expect(preamble.apply(r'x \in \Rn'), r'x \in {\mathbb{R}^n}');
      expect(preamble.apply(r'\pair{a}{b}'), '(a, b)');
      expect(preamble.apply(r'\sgn x'), r'\operatorname{sgn}x');
      expect(preamble.apply(r'\half'), r'{\frac12}');
    });

    test('fills in an optional first argument, or its default', () {
      final preamble = LatexPreamble.read(
        r'\newcommand{\ball}[2][black]{\fill[#1] (#2) circle (1);}',
      );
      expect(preamble.apply(r'\ball[red]{a}'), r'\fill[red] (a) circle (1);');
      expect(preamble.apply(r'\ball{a}'), r'\fill[black] (a) circle (1);');
      expect(
        preamble.apply(r'\ball[{x[1]}]{a}'),
        r'\fill[{x[1]}] (a) circle (1);',
      );
    });

    test('gives TikZ pictures its styles, before their own options', () {
      final preamble = LatexPreamble.read(
        r'\tikzset{dot/.style={fill}} \tikzstyle{axis}=[->]',
      );
      expect(preamble.tikzStyles, 'dot/.style={fill}, axis/.style={->}');
      expect(
        preamble.apply(
          r'\begin{tikzpicture}[scale=2] \draw; \end{tikzpicture}',
        ),
        r'\begin{tikzpicture}[dot/.style={fill}, axis/.style={->}, scale=2]'
        r' \draw; \end{tikzpicture}',
      );
      expect(
        preamble.apply(r'\tikz \draw;'),
        r'\tikz[dot/.style={fill}, axis/.style={->}]\draw;',
      );
      expect(preamble.apply(r'\frac{a}{b}'), r'\frac{a}{b}');
    });

    test('says what in it is neither a command nor a style', () {
      expect(LatexPreamble.read(r'\newcommand{\a}{1} hello').leftOver, 'hello');
    });
  });
}
