import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
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
    'highlight(x^2) + highlight(#A8E6B0, 1/2)',
  ];

  group('every example the cheat sheet shows parses', () {
    for (final topic in SimpleSyntaxGuide.topics) {
      for (final example in topic.examples) {
        test('${topic.title}: "${example.typed}"', () {
          final translation = LinearMath.translate(example.typed);
          expect(translation.diagnostics, isEmpty);
          expect(
            () => TexParser(
              RendererLatex.of(example.latex),
              const TexParserSettings(),
            ).parse(),
            returnsNormally,
            reason: 'produced: ${example.latex}',
          );
        });
      }
    }
  });

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

  test('named operators parse before anything that follows them', () {
    for (final latex in <String>[
      r'\operatorname{tr} \left( A \right)',
      r'\operatorname{tr}^2 \sqrt{x}',
      r'\operatorname{tr}_{i}^{2} \frac{a}{b}',
      r'\operatorname*{arg\,max}_{x} f(x)',
      r'\operatorname{sgn}{x} + \operatorname{sgn}',
    ]) {
      expect(
        () => TexParser(
          RendererLatex.of(latex),
          const TexParserSettings(),
        ).parse(),
        returnsNormally,
        reason: RendererLatex.of(latex),
      );
    }
    expect(
      RendererLatex.of(r'\operatorname{tr}^2 \left( A \right)'),
      r'\operatorname{tr}^2{} \left( A \right)',
    );
    expect(RendererLatex.of(r'\sin x'), r'\sin x');
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

  testWidgets('a highlight is painted in its colour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MathView(
            source: r'a + \colorbox{#FFEF9D}{$b^2$}',
            mode: MathMode.latex,
          ),
        ),
      ),
    );
    final painted = tester
        .widgetList<Container>(find.byType(Container))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color);
    expect(painted, contains(const Color(0xFFFFEF9D)));
  });

  group('a highlighted part keeps its size', () {
    Future<Size> sizeOf(
      WidgetTester tester,
      String latex, {
      required bool display,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MathView(
              source: latex,
              mode: MathMode.latex,
              displayStyle: display,
              textStyle: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(MathView));
    }

    testWidgets('a fraction on a line of its own', (tester) async {
      final plain = await sizeOf(tester, r'\frac{a}{b}', display: true);
      final marked = await sizeOf(
        tester,
        r'\colorbox{#FFEF9D}{$\frac{a}{b}$}',
        display: true,
      );
      // As tall, and a little room either side for the highlight.
      expect(marked.height, greaterThanOrEqualTo(plain.height));
      expect(marked.width, greaterThan(plain.width));
    });

    testWidgets('an exponent', (tester) async {
      final plain = await sizeOf(tester, 'x^{2}', display: false);
      final marked = await sizeOf(
        tester,
        r'x^{\colorbox{#FFEF9D}{$2$}}',
        display: false,
      );
      final full = await sizeOf(
        tester,
        r'x \colorbox{#FFEF9D}{$2$}',
        display: false,
      );
      expect(
        marked.height,
        lessThan(full.height),
        reason: 'set as small as an exponent, not at full size',
      );
      expect(marked.width, lessThan(full.width));
      expect(plain.width, lessThan(marked.width));
    });
  });
}
