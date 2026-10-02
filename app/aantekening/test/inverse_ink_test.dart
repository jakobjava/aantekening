import 'dart:typed_data';

import 'package:aantekening/src/editor/text/text_styles.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// [over] drawn on a 200×100 ground, black on its left half and white on
/// its right, and the pixels that makes.
Future<({Uint8List pixels, int width})> _drawnOverHalves(
  WidgetTester tester,
  Widget over,
) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 200,
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: ColoredBox(color: Color(0xFF000000))),
                    Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
                  ],
                ),
                over,
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(render.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  return (pixels: bytes.buffer.asUint8List(), width: image.width);
}

/// The red, green and blue of the pixel at [x], [y].
(int, int, int) _at(({Uint8List pixels, int width}) drawn, int x, int y) {
  final i = (y * drawn.width + x) * 4;
  return (drawn.pixels[i], drawn.pixels[i + 1], drawn.pixels[i + 2]);
}

void main() {
  testWidgets('text in the inverse colour is white on black, black on white', (
    tester,
  ) async {
    final style = RichTextStyles.runStyle(
      const TextMarks(color: NoteColors.inverse),
    )!;
    // The test font draws every letter as a square filling its box.
    final drawn = await _drawnOverHalves(
      tester,
      Text(
        'MMMMM',
        style: style.merge(const TextStyle(fontSize: 40, height: 1)),
      ),
    );

    expect(_at(drawn, 20, 20), (255, 255, 255));
    expect(_at(drawn, 180, 20), (0, 0, 0));
    // Beneath the text, the ground is as it was.
    expect(_at(drawn, 20, 80), (0, 0, 0));
    expect(_at(drawn, 180, 80), (255, 255, 255));
  });

  for (final pixelsPerUnit in <double?>[null, 1]) {
    testWidgets('ink in the inverse colour is too, crossings inverted once, '
        '${pixelsPerUnit == null ? 'drawn as strokes' : 'kept as pixels'}', (
      tester,
    ) async {
      InkStroke across(double y) => InkStroke.fromPoints(
        tool: InkTool.pen,
        color: NoteColors.inverse,
        width: 10,
        xs: <double>[10, 190],
        ys: <double>[y, y],
      );
      final crossing = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: NoteColors.inverse,
        width: 10,
        xs: <double>[20, 20],
        ys: <double>[10, 90],
      );
      final ink = InkElement(
        id: 'ink',
        frame: const Frame(x: 0, y: 0, width: 0, height: 0),
        createdAt: 0,
        updatedAt: 0,
      ).withStrokes(<InkStroke>[across(30), crossing]);
      final drawn = await _drawnOverHalves(
        tester,
        Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (final layer in InkLayer.values)
              CustomPaint(
                painter: InkPainter(
                  elements: <InkElement>[ink],
                  viewport: const CanvasViewport(),
                  layer: layer,
                  pixelsPerUnit: pixelsPerUnit,
                ),
              ),
          ],
        ),
      );

      expect(_at(drawn, 60, 30), (255, 255, 255));
      expect(_at(drawn, 150, 30), (0, 0, 0));
      expect(_at(drawn, 20, 30), (255, 255, 255), reason: 'the crossing');
      expect(_at(drawn, 20, 70), (255, 255, 255));
      expect(_at(drawn, 60, 70), (0, 0, 0), reason: 'no ink here');
    });
  }
}
