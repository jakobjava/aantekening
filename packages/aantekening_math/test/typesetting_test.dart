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
}
