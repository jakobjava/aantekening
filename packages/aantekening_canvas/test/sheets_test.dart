import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sheets 100 wide and 200 tall, with gaps of 20 between.
const SheetFold _fold = SheetFold(width: 100, height: 200, count: 3, gap: 20);

InkStroke _line(double x0, double y0, double x1, double y1) =>
    InkStroke.fromPoints(
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 4,
      xs: <double>[x0, (x0 + x1) / 2, x1],
      ys: <double>[y0, (y0 + y1) / 2, y1],
    );

InkElement _ink(String id, List<InkStroke> strokes) => InkElement(
  id: id,
  frame: const Frame(x: 0, y: 0, width: 1, height: 1),
  createdAt: 0,
  updatedAt: 0,
).withStrokes(strokes);

TextElement _box(String id, {required double y}) => TextElement(
  id: id,
  frame: Frame(x: 100, y: y, width: 200, height: 60),
  createdAt: 0,
  updatedAt: 0,
);

/// A page of A4 sheets: lined, then squared.
PageDocument _paged(List<NoteElement> elements) => PageDocument(
  id: 'p',
  canvas: CanvasSettings(
    layout: NoteLayout.pages,
    sheets: Sheets(
      templates: const <SheetTemplate>[SheetTemplate.lined, SheetTemplate.grid],
    ),
  ),
  elements: elements,
);

Widget _host(CanvasController controller, {Widget? afterSheets}) => MaterialApp(
  home: InfiniteCanvas(
    controller: controller,
    afterSheets: afterSheets,
    elementBuilder: (context, element) => ColoredBox(
      key: ValueKey<String>('shown ${element.id}'),
      color: Colors.blue,
    ),
  ),
);

void main() {
  group('SheetFold', () {
    test('lays each sheet out below the gaps above it', () {
      expect(_fold.fold(const Offset(10, 50)), const Offset(10, 50));
      expect(_fold.fold(const Offset(10, 250)), const Offset(10, 270));
      expect(_fold.fold(const Offset(10, 450)), const Offset(10, 490));
      expect(_fold.extent, 3 * 200 + 2 * 20);
    });

    test('finds the page under any point of the view', () {
      for (final y in <double>[0, 50, 199, 250, 599]) {
        final page = Offset(30, y);
        expect(_fold.unfold(_fold.fold(page)), page);
      }
      // In a gap: the nearer sheet's edge.
      expect(_fold.unfold(const Offset(30, 203)).dy, closeTo(200, 1e-2));
      expect(_fold.sheetAt(_fold.unfold(const Offset(30, 203)).dy), 0);
      expect(_fold.unfold(const Offset(30, 217)).dy, 200);
      // Beside and beyond the sheets: their edges.
      expect(_fold.unfold(const Offset(-40, -10)), Offset.zero);
      expect(_fold.unfold(const Offset(500, 5000)).dx, 100);
      expect(_fold.unfold(const Offset(500, 5000)).dy, closeTo(600, 1e-2));
    });

    test('moves a box whole with the sheet its middle is on', () {
      const box = Frame(x: 0, y: 180, width: 50, height: 60);
      expect(_fold.foldFrame(box).y, 200, reason: 'middle at 210');
      expect(_fold.foldFrame(box.translate(0, -40)).y, 140);
    });

    test('ends a box at the bottom of the sheet it ends on', () {
      expect(_fold.foldEnd(200), 200);
      expect(_fold.foldEnd(201), 221);
      expect(_fold.foldEnd(0), 0);
    });

    test('cuts a region into the parts on each sheet', () {
      final pieces = _fold.piecesOf(const Aabb(-50, 150, 300, 450));
      expect(
        <Aabb>[for (final piece in pieces) piece.area],
        <Aabb>[
          const Aabb(0, 150, 100, 200),
          const Aabb(0, 200, 100, 400),
          const Aabb(0, 400, 100, 450),
        ],
      );
      expect(
        <double>[for (final piece in pieces) piece.down],
        <double>[0, 20, 40],
      );
      // A whole number of device pixels down.
      final snapped = _fold.piecesOf(
        const Aabb(0, 150, 100, 250),
        devicePixelsPerUnit: 0.3,
      );
      expect((snapped.last.down * 0.3) % 1, 0);
    });
  });

  group('CanvasController shown as pages', () {
    CanvasController laidOut(PageDocument document) => CanvasController()
      ..viewSize = const Size(1200, 900)
      ..loadDocument(document);

    test('cuts the page into sheets and back, moving nothing on it', () {
      final ink = _ink('ink', <InkStroke>[_line(50, 100, 1500, 3000)]);
      final controller = laidOut(
        PageDocument(id: 'p', elements: <NoteElement>[ink]),
      );
      final before = controller.document.elements;

      controller.setLayout(NoteLayout.pages);
      final sheets = controller.document.canvas.sheetsShown!;
      expect(sheets.width, greaterThanOrEqualTo(1502), reason: 'as wide');
      expect(sheets.count * sheets.height, greaterThanOrEqualTo(3002));
      expect(identical(controller.document.elements, before), isTrue);
      expect(controller.fold, isNotNull);

      controller.setLayout(NoteLayout.canvas);
      expect(controller.fold, isNull);
      expect(identical(controller.document.elements, before), isTrue);
      expect(
        controller.document.canvas.sheets,
        sheets,
        reason: 'kept, to go back to',
      );
    });

    test('keeps the middle of the view where it was', () {
      final controller = laidOut(
        PageDocument(
          id: 'p',
          elements: <NoteElement>[
            _ink('ink', <InkStroke>[_line(10, 10, 600, 4000)]),
          ],
        ),
      )..viewport = const CanvasViewport(origin: Offset(0, 2400));
      final middle = controller.viewport.toPage(const Offset(600, 450));

      controller.setLayout(NoteLayout.pages);
      final shown = controller.viewport.toScreen(middle);
      expect(shown.dy, closeTo(450, 1));
    });

    test('lies in the middle of the view, and stops at the sheets', () {
      final controller = laidOut(_paged(const <NoteElement>[]));
      final fold = controller.fold!;
      final view = controller.viewport;
      final across =
          (view.toScreen(Offset.zero).dx +
              view.toScreen(Offset(fold.width, 0)).dx) /
          2;
      expect(across, closeTo(600, 1), reason: 'in the middle across');

      controller.panBy(const Offset(0, -100000));
      final scrolled = controller.viewport;
      expect(
        (fold.extent - scrolled.origin.dy) * scrolled.zoom,
        closeTo(900 - CanvasController.deskFoot, 1),
        reason: 'no further than the foot below the last sheet',
      );
      controller.panBy(const Offset(0, 100000));
      expect(
        controller.viewport.toScreen(Offset.zero).dy,
        closeTo(CanvasController.deskMargin, 1),
      );
    });

    test('adds a sheet, moving what lies after it down, stroke by stroke', () {
      final height = Sheets().height;
      final controller = laidOut(
        _paged(<NoteElement>[
          _ink('ink', <InkStroke>[
            _line(10, 100, 200, 100),
            _line(10, height + 100, 200, height + 100),
          ]),
          _box('box', y: height + 300),
        ]),
      );

      controller.insertSheet(1, SheetTemplate.music);

      final sheets = controller.document.canvas.sheetsShown!;
      expect(sheets.templates, <SheetTemplate>[
        SheetTemplate.lined,
        SheetTemplate.music,
        SheetTemplate.grid,
      ]);
      final ink = controller.document.elementById('ink')! as InkElement;
      expect(ink.strokes.first.yAt(0), 100, reason: 'on the first sheet');
      expect(ink.strokes.last.yAt(0), 2 * height + 100);
      expect(controller.document.elementById('box')!.frame.y, 2 * height + 300);

      controller.undo();
      expect(controller.document.canvas.sheetsShown!.count, 2);
      expect(
        (controller.document.elementById('ink')! as InkElement).strokes.last
            .yAt(0),
        height + 100,
      );
    });

    test('adds sheets with things on them, undone as one', () {
      final height = Sheets().height;
      final controller = laidOut(
        _paged(<NoteElement>[_box('later', y: height + 10)]),
      );

      controller.insertSheets(
        1,
        const <SheetTemplate>[SheetTemplate.blank, SheetTemplate.blank],
        onThem: <NoteElement>[
          _box('first', y: height + 5),
          _box('second', y: 2 * height + 5),
        ],
      );
      expect(controller.document.canvas.sheetsShown!.count, 4);
      expect(
        controller.document.elementById('later')!.frame.y,
        3 * height + 10,
      );
      expect(
        controller.document.elementById('second')!.frame.y,
        2 * height + 5,
      );

      controller.undo();
      expect(controller.document.elementById('first'), isNull);
      expect(controller.document.elementById('later')!.frame.y, height + 10);
      expect(controller.document.canvas.sheetsShown!.count, 2);
    });

    test('deletes a sheet with what lies on it, moving what follows up', () {
      final height = Sheets().height;
      final controller = laidOut(
        _paged(<NoteElement>[
          _ink('ink', <InkStroke>[
            _line(10, 100, 200, 100),
            _line(10, height + 100, 200, height + 100),
          ]),
          _box('box', y: 300),
          _box('later', y: height + 300),
        ]),
      );

      controller.removeSheet(0);

      expect(controller.document.canvas.sheetsShown!.templates, <SheetTemplate>[
        SheetTemplate.grid,
      ]);
      expect(controller.document.elementById('box'), isNull);
      expect(controller.document.elementById('later')!.frame.y, 300);
      final ink = controller.document.elementById('ink')! as InkElement;
      expect(ink.strokes.single.yAt(0), 100);

      controller.removeSheet(0);
      expect(
        controller.document.canvas.sheetsShown!.count,
        1,
        reason: 'the only sheet is kept',
      );
    });

    test('moves a sheet with what lies on it, the others making room', () {
      final height = Sheets().height;
      final controller = laidOut(
        _paged(<NoteElement>[
          _ink('ink', <InkStroke>[
            _line(10, 100, 200, 100),
            _line(10, height + 100, 200, height + 100),
          ]),
          _box('third', y: 2 * height + 300),
        ]),
      )..insertSheet(2, SheetTemplate.music);
      // Sheets: lined, squared, music; the box below them, on a fourth.
      controller.moveSheet(2, 0);

      expect(
        controller.document.canvas.sheetsShown!.templates.take(3),
        <SheetTemplate>[
          SheetTemplate.music,
          SheetTemplate.lined,
          SheetTemplate.grid,
        ],
      );
      final ink = controller.document.elementById('ink')! as InkElement;
      expect(ink.strokes.first.yAt(0), height + 100, reason: 'down one');
      expect(ink.strokes.last.yAt(0), 2 * height + 100);
      expect(
        controller.document.elementById('third')!.frame.y,
        3 * height + 300,
        reason: 'on a sheet the move did not reach',
      );

      controller.undo();
      expect(
        controller.document.canvas.sheetsShown!.templates.first,
        SheetTemplate.lined,
      );
    });

    test('prints a template on one sheet or every sheet', () {
      final controller = laidOut(_paged(const <NoteElement>[]))
        ..setSheetTemplate(SheetTemplate.cornell, sheet: 1);
      expect(
        controller.document.canvas.sheetsShown!.templates.last,
        SheetTemplate.cornell,
      );
      controller.setSheetTemplate(SheetTemplate.dotted);
      expect(
        controller.document.canvas.sheetsShown!.templates,
        everyElement(SheetTemplate.dotted),
      );
    });

    test('adds sheets for what is put below the last', () {
      final controller = laidOut(_paged(const <NoteElement>[]));
      controller.addElement(_box('far', y: 5000));
      final sheets = controller.document.canvas.sheetsShown!;
      expect(sheets.count * sheets.height, greaterThan(5060));
      expect(sheets.templates.last, SheetTemplate.grid, reason: 'as the last');
    });

    test('undo leaves it shown as it is', () {
      final controller = laidOut(
        PageDocument(id: 'p', elements: <NoteElement>[_box('a', y: 10)]),
      )..addElement(_box('b', y: 300));
      controller.setLayout(NoteLayout.pages);

      controller.undo();
      expect(controller.document.elementById('b'), isNull);
      expect(controller.fold, isNotNull, reason: 'still pages');
      controller.redo();
      expect(controller.fold, isNotNull);
    });
  });

  group('InfiniteCanvas shown as pages', () {
    testWidgets('writes on the sheet under the pen', (tester) async {
      final controller = CanvasController()
        ..loadDocument(_paged(const <NoteElement>[]))
        ..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));
      await tester.pump();
      final fold = controller.fold!;
      // Halfway down the second sheet, on screen.
      final at = controller.viewport.toScreen(
        Offset(fold.width / 2, fold.height * 1.5),
      );
      controller.viewport = controller.viewport.copyWith(
        origin:
            controller.viewport.origin +
            (at - const Offset(400, 300)) / controller.viewport.zoom,
      );
      await tester.pump();

      await tester.dragFrom(
        const Offset(400, 300),
        const Offset(60, 0),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();

      final ink = controller.document.elements.single as InkElement;
      expect(fold.sheetAt(ink.bounds.centerY), 1);
      expect(ink.bounds.centerY, closeTo(fold.height * 1.5, 2));
    });

    testWidgets('the desk is held to move the sheets, not written on', (
      tester,
    ) async {
      final controller = CanvasController()
        ..loadDocument(_paged(const <NoteElement>[]))
        ..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));
      await tester.pump();
      final before = controller.viewport.origin;
      // Left of the sheet, on the desk.
      final desk =
          controller.viewport.toScreen(Offset.zero) + const Offset(-12, 200);

      await tester.dragFrom(
        desk,
        const Offset(0, -150),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();

      expect(controller.document.elements, isEmpty, reason: 'no ink');
      expect(controller.viewport.origin.dy, greaterThan(before.dy + 100));
    });

    testWidgets('over the desk, a pen shows the pointer to move it by', (
      tester,
    ) async {
      final controller = CanvasController()
        ..loadDocument(_paged(const <NoteElement>[]))
        ..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));
      await tester.pump();
      MouseCursor cursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
      final view = controller.viewport;
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: view.toScreen(const Offset(300, 300)));
      await mouse.moveTo(view.toScreen(const Offset(300, 310)));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.none, reason: 'the nib instead');

      await mouse.moveTo(view.toScreen(Offset.zero) + const Offset(-10, 300));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.grab);
      await mouse.removePointer();
    });

    testWidgets('a line written off its sheet is cut at the edge', (
      tester,
    ) async {
      final controller = CanvasController()
        ..loadDocument(_paged(const <NoteElement>[]))
        ..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));
      await tester.pump();
      final view = controller.viewport;
      final fold = controller.fold!;
      final start = view.toScreen(Offset(fold.width - 60, 300));

      final pen = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      for (var x = 0.0; x <= 200; x += 10) {
        await pen.moveTo(start + Offset(x, x / 4));
      }
      await pen.up();
      await tester.pump();

      final ink = controller.document.elements.single as InkElement;
      final stroke = ink.strokes.single;
      for (var i = 0; i < stroke.pointCount; i++) {
        expect(stroke.xAt(i), lessThan(fold.width), reason: 'none off it');
      }
      expect(
        stroke.yAt(stroke.pointCount - 1),
        lessThan(320),
        reason: 'not drawn on down the edge',
      );
    });

    testWidgets('places a box where the sheets lay it out', (tester) async {
      final height = Sheets().height;
      final controller = CanvasController()
        ..loadDocument(_paged(<NoteElement>[_box('box', y: height + 40)]));
      await tester.pumpWidget(_host(controller));
      controller.reveal(Aabb(100, height + 40, 300, height + 100));
      await tester.pump();

      final shown = tester.getTopLeft(
        find.byKey(const ValueKey<String>('shown box')),
      );
      final expected = controller.viewport.toScreen(Offset(100, height + 40));
      expect(shown.dx, closeTo(expected.dx, 1));
      expect(shown.dy, closeTo(expected.dy, 1));
    });

    testWidgets('a press below the last sheet is the button\'s alone', (
      tester,
    ) async {
      var pressed = 0;
      final controller = CanvasController()
        ..loadDocument(_paged(const <NoteElement>[]))
        ..setTool(CanvasTool.pen);
      await tester.pumpWidget(
        _host(
          controller,
          afterSheets: TextButton(
            onPressed: () => pressed++,
            child: const Text('Add sheet'),
          ),
        ),
      );
      controller.panBy(const Offset(0, -100000));
      await tester.pump();

      await tester.tap(find.text('Add sheet'), kind: PointerDeviceKind.stylus);
      await tester.pump();
      expect(pressed, 1);
      expect(controller.document.elements, isEmpty, reason: 'no ink');
    });

    testWidgets('draws ink on the sheet, below the gap', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final height = Sheets().height;
      // Across the second sheet, near its top.
      final controller = CanvasController()
        ..loadDocument(
          _paged(<NoteElement>[
            _ink('ink', <InkStroke>[_line(100, height + 20, 600, height + 20)]),
          ]),
        );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: InfiniteCanvas(controller: controller),
          ),
        ),
      );
      controller.viewport = controller.viewport.copyWith(
        origin: Offset(controller.viewport.origin.dx, height - 100),
      );
      await tester.pump();

      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => render.toImage()))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      int red(Offset at) =>
          bytes.getUint8((at.dy.round() * image.width + at.dx.round()) * 4);
      final shown = controller.viewport.toScreen(Offset(350, height + 20));
      final unfolded = shown - Offset(0, controller.fold!.gap);
      expect(red(shown), lessThan(60), reason: 'black ink where it is shown');
      expect(red(unfolded), greaterThan(150), reason: 'none above the gap');
    });
  });
}
