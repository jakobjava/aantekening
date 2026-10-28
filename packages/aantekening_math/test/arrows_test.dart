import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the equilibria lying one way are drawn as such: each its '
      'own arrows, and neither the equilibrium lying neither way', (
    tester,
  ) async {
    Future<Uint8List> drawn(String typed) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: 240,
                  height: 80,
                  child: Center(
                    child: MathView(
                      source: LinearMath.toLatex(typed),
                      mode: MathMode.latex,
                      textStyle: const TextStyle(
                        fontSize: 32,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return (await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData();
        return data!.buffer.asUint8List();
      }))!;
    }

    final even = await drawn('ce(A <=> B)');
    final right = await drawn('ce(A <=>> B)');
    final left = await drawn('ce(A <<=> B)');
    expect(right, isNot(equals(even)), reason: 'lying right');
    expect(left, isNot(equals(even)), reason: 'lying left');
    expect(left, isNot(equals(right)));
    // Typed outside ce() too.
    expect(await drawn('A <=>> B'), isNot(equals(await drawn('A <<=> B'))));
  });

  test('the equilibria lying one way are written back as themselves', () {
    for (final latex in <String>[
      r'A \xrightequilibrium{} B',
      r'A \xleftequilibrium{} B',
    ]) {
      expect(LinearMath.toLatex(LinearMath.fromLatex(latex)), latex);
    }
  });
}
