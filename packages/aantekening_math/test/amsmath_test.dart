import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the typesetter reads [latex] without a complaint.
bool _typesets(String latex) {
  try {
    TexParser(latex, const TexParserSettings(displayMode: true)).parse();
    return true;
  } on Object {
    return false;
  }
}

void main() {
  group('the typesetter reads', () {
    const formulas = <String>[
      // amsmath's display environments.
      r'\begin{align} a &= b \\ c &= d \end{align}',
      r'\begin{align*} a &= b \end{align*}',
      r'\begin{gather} a \\ b \end{gather}',
      r'\begin{gather*} a \end{gather*}',
      r'\begin{equation} E = mc^2 \end{equation}',
      r'\begin{equation*} E = mc^2 \end{equation*}',
      r'\begin{split} a &= b \\ &= c \end{split}',
      r'\begin{multline} a + b \\ = c \end{multline}',
      r'\begin{alignat}{2} a &= b & c &= d \end{alignat}',
      r'\begin{flalign*} a &= b \end{flalign*}',
      // mathtools' starred matrices.
      r'\begin{pmatrix*}[r] 1 & -2 \end{pmatrix*}',
      r'\begin{bmatrix*}[l] 1 \end{bmatrix*}',
      // Numbering and labels, of an equation that has none to keep.
      r'x \tag{1}',
      r'x \tag*{a}',
      r'x \notag \nonumber \label{eq:x}',
      r'\eqref{eq:x}',
      // Commands.
      r'\emph{e}',
      r'\iiiint f \idotsint g',
      r'\sideset{}{^\prime}\sum',
      r'\smash{x} \mathclap{x} \mathrlap{x} \mathllap{x}',
      r'\varliminf \varlimsup \injlim \projlim \varinjlim \varprojlim',
      r'\limsup \liminf',
      r'\argmin_x f \argmax_x f',
      r'\dddot{x} \ddddot{x}',
      r'\mspace{18mu}',
      r'\intertext{and} \shoveleft{a} \hdotsfor{3}',
      r'\prescript{a}{b}{X}',
      r'\nicefrac{1}{2} \sfrac{1}{2}',
      r'\uptau \upalpha',
      // Definitions, as a note's preamble makes them.
      r'\DeclareMathOperator{\tr}{tr} \tr A',
      r'\DeclareMathOperator*{\esssup}{ess\,sup} \esssup_x f',
      r'\newcommand{\R}{\mathbb{R}} \R',
      r'\newcommand*{\N}{\mathbb{N}} \N',
      r'\def\Q{\mathbb{Q}} \Q',
      r'\def\pair#1#2{(#1, #2)} \pair{a}{b}',
      // An operator before what takes arguments of its own.
      r'\operatorname{f}\frac12',
      r'\operatorname*{a}\sqrt{2}',
    ];
    for (final formula in formulas) {
      test(formula, () => expect(_typesets(formula), isTrue));
    }

    testWidgets('and lays all of them out', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (final formula in formulas)
                  MathView(
                    source: formula,
                    mode: MathMode.latex,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF000000),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Tooltip), findsNothing, reason: 'no parse error');
    });
  });

  group('Simple syntax passes LaTeX through', () {
    const cases = <String, String>{
      r'\begin{align} a &= b \\ c &= d \end{align}':
          r'\begin{align} a &= b \\ c &= d \end{align}',
      r'x = \begin{cases} 1 & x > 0 \\ 0 & \text{else} \end{cases}':
          r'x = \begin{cases} 1 & x > 0 \\ 0 & \text{else} \end{cases}',
      r'\text{for all } x': r'\text{for all } x',
      r'\mathbb{R}^n': r'\mathbb{R}^n',
      r'\operatorname*{argmax}_x f': r'\operatorname*{argmax}_x f',
      r'\underbrace{a+b}_n': r'\underbrace{a + b}_n',
      r'\overbrace{a/b}^n': r'\overbrace{\frac{a}{b}}^n',
      r'\left( a/b \right)': r'\left( \frac{a}{b} \right)',
      r'\bigl[ x \bigr]': r'\bigl[ x \bigr]',
      r'\boxed{a/b}': r'\boxed{\frac{a}{b}}',
      r'\xleftarrow[a]{b}': r'\xleftarrow[a]{b}',
      r'\dfrac{a}{b}': r'\dfrac{a}{b}',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final translation = LinearMath.translate(entry.key);
        expect(translation.latex, entry.value);
        expect(translation.diagnostics, isEmpty);
      });
    }

    test('and shows it as it was written', () {
      for (final latex in <String>[
        r'\begin{align} a &= b \end{align}',
        r'\dfrac{a}{b}',
        r'\tbinom{n}{k}',
        r'\overbrace{a + b}^n',
      ]) {
        final simple = LinearMath.fromLatex(latex);
        expect(LinearMath.translate(simple).latex, latex, reason: simple);
      }
    });
  });
}
