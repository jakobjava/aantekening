import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The typesetter's own fonts: a bracket is as tall as their measure has
/// it, not as tall as the test font's square letters.
Future<void> _loadTypesetterFonts() async {
  final fonts = Directory(
    '../../third_party/flutter_math_fork/lib/katex_fonts/fonts',
  );
  final byFamily = <String, List<File>>{};
  for (final file in fonts.listSync().whereType<File>()) {
    final family = file.uri.pathSegments.last.split('-').first;
    (byFamily['packages/flutter_math_fork/$family'] ??= <File>[]).add(file);
  }
  for (final MapEntry(key: family, value: files) in byFamily.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadTypesetterFonts);

  // Brackets as tall as what they hold, in a script, a fraction or a root
  // as well as on the line: the bracket chosen is drawn as large as it was
  // measured, and lays out within what it was asked to fill.
  final formulas = <String>[
    for (final (open, close) in <(String, String)>[
      ('(', ')'),
      ('|', '|'),
      (r'\{', r'\}'),
      (r'\langle', r'\rangle'),
    ])
      for (final inner in <String>['x^2', r'\frac{1}{2}', r'\sqrt{x}'])
        for (final around in <String>[
          '#',
          '#^{2}_{i}',
          'e^{#}',
          'x_{#}',
          r'\frac{#}{2}',
          r'\sqrt{#}',
        ])
          around.replaceFirst('#', '\\left$open $inner \\right$close'),
    r'\left\langle \psi \middle| H \middle| \psi \right\rangle',
    r'\left\langle \frac{\frac{a}{b}}{\frac{c}{d}} \right\rangle^2',
    r'\left\langle \sum_{i=1}^{n} \frac{\int_0^1 x}{\frac{a}{b^{\frac{1}{2}}}} '
        r'\right\rangle_{i}',
  ];
  testWidgets('a bracket round something short is as tall as one typed '
      'alone, in text and in a script', (tester) async {
    Future<double> height(String latex) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MathView(
              source: latex,
              mode: MathMode.latex,
              displayStyle: false,
              textStyle: const TextStyle(fontSize: 32),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(MathView)).height;
    }

    expect(
      await height(r'f\left( x \right)'),
      closeTo(await height('f(x)'), 0.5),
    );
    expect(
      await height(r'e^{\left( x \right)}'),
      closeTo(await height('e^{(x)}'), 0.5),
    );
  });

  for (final latex in formulas) {
    testWidgets('$latex lays out within its constraints', (tester) async {
      for (final size in <double>[9, 11.5, 13.3, 16, 18.7, 21.3, 26.7, 32]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MathView(
                  source: latex,
                  mode: MathMode.latex,
                  displayStyle: false,
                  textStyle: TextStyle(fontSize: size),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'at $size');
      }
    });
  }
}
