import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('equations gathered are set one above the other', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MathView(
          source: r'\begin{gathered}x=1 \\ y=2\end{gathered}',
          mode: MathMode.latex,
          textStyle: TextStyle(fontSize: 16, color: Color(0xFF000000)),
        ),
      ),
    );
    expect(find.byType(Tooltip), findsNothing, reason: 'no parse error');
  });

  group('a formula is read once', () {
    const style = TextStyle(fontSize: 16, color: Color(0xFF000000));
    Widget shown(String source, {int times = 1}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (var i = 0; i < times; i++)
            MathView(source: source, mode: MathMode.linear, textStyle: style),
        ],
      ),
    );

    testWidgets('however often it is built again', (tester) async {
      final before = MathView.reads;
      for (var word = 0; word < 5; word++) {
        // As an answer being written builds every formula above it.
        await tester.pumpWidget(shown('x^2 + 1/2'));
      }
      expect(MathView.reads - before, 1);
      await tester.pumpWidget(shown('x^3 + 1/2'));
      expect(MathView.reads - before, 2);
    });

    testWidgets('when it was asked whether it typesets', (tester) async {
      final latex = LinearMath.toLatex('sqrt(a + b)');
      final before = MathView.reads;
      expect(MathView.problemIn(latex), isNull);
      await tester.pumpWidget(shown('sqrt(a + b)'));
      expect(MathView.reads - before, 1);
    });

    testWidgets('by each view that shows it', (tester) async {
      final before = MathView.reads;
      await tester.pumpWidget(shown('a/b', times: 2));
      expect(tester.takeException(), isNull);
      expect(MathView.reads - before, 2);
    });
  });
}
