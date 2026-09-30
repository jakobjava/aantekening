import 'dart:io';

import 'package:aantekening/src/editor/text/block_view.dart';
import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The typesetter's own fonts, from the copy of it the workspace uses: the
/// room it gives a formula is the fonts' measure, so what is drawn is
/// checked in them.
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

const TextStyle _style = TextStyle(fontSize: 60, color: Color(0xFF000000));

/// A line of text holding [latex] typeset, as a text box lays one out.
Widget _line(String latex) => Text.rich(
  TextSpan(
    style: _style,
    children: <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: TypesetFormulas.of(latex, MathMode.latex, true, _style),
      ),
    ],
  ),
);

/// How many bands of ink, one below the other with paper between them,
/// [lines] are drawn in.
Future<int> _bandsOfInk(WidgetTester tester, List<Widget> lines) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: page,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
        ),
      ),
    ),
  );
  final render =
      page.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await render.toImage();
    final pixels = (await image.toByteData())!;
    bool inked(int y) {
      for (var x = 0; x < image.width; x++) {
        if (pixels.getUint8((y * image.width + x) * 4) < 128) return true;
      }
      return false;
    }

    var bands = 0;
    var before = false;
    for (var y = 0; y < image.height; y++) {
      final now = inked(y);
      if (now && !before) bands++;
      before = now;
    }
    return bands;
  }))!;
}

void main() {
  setUpAll(_loadTypesetterFonts);

  // A fraction is three bands: its numerator, its bar and its denominator.
  testWidgets('fractions on lines one below the other do not touch', (
    tester,
  ) async {
    final bands = await _bandsOfInk(tester, <Widget>[
      _line(r'\frac{1}{2}'),
      _line(r'\frac{1}{2}'),
    ]);
    expect(bands, 6);
  });

  testWidgets('the rows of a matrix of fractions do not touch', (tester) async {
    final bands = await _bandsOfInk(tester, <Widget>[
      // Fractions set large, taller than a row: set as they are, rows of
      // them meet, as in TeX.
      _line(r'\begin{matrix}\dfrac{1}{2} \\ \dfrac{1}{2}\end{matrix}'),
    ]);
    expect(bands, 6);
  });
}
