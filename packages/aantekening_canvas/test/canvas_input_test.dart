import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_canvas/src/page_space.dart';
import 'package:aantekening_canvas/src/element_transforms.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ImageElement _image(String id, {double x = 0, double y = 0}) => ImageElement(
  id: id,
  frame: Frame(x: x, y: y, width: 200, height: 100),
  createdAt: 0,
  updatedAt: 0,
  assetId: 'asset',
);

TextElement _textBox(String id, {double x = 0, double y = 0}) => TextElement(
  id: id,
  frame: Frame(x: x, y: y, width: 200, height: 60),
  createdAt: 0,
  updatedAt: 0,
);

/// Hosts a canvas filling an 800×600 view, or the part of it below and to
/// the right of [offset], where an app's toolbars and sidebars leave it.
Widget _host(
  CanvasController controller, {
  CanvasPointerClaim? claimsPointer,
  CanvasGrip? grips,
  ValueChanged<Offset>? onEmptyTap,
  ValueChanged<NoteElement?>? onCanvasPress,
  double trackpadPanScale = 1,
  Offset offset = Offset.zero,
  CanvasHeader? header,
  void Function(Offset page, Offset global)? onContextMenu,
  CanvasElementBuilder? elementBuilder,
  ValueListenable<TouchpadFingers>? touchpadFingers,
}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: EdgeInsets.only(left: offset.dx, top: offset.dy),
      child: InfiniteCanvas(
        controller: controller,
        claimsPointer: claimsPointer,
        grips: grips,
        onEmptyTap: onEmptyTap,
        onCanvasPress: onCanvasPress,
        header: header,
        onContextMenu: onContextMenu,
        trackpadPanScale: trackpadPanScale,
        touchpadFingers: touchpadFingers,
        elementBuilder:
            elementBuilder ??
            (context, element) => const ColoredBox(color: Colors.blue),
      ),
    ),
  ),
);

void main() {
  group('the background', () {
    CanvasController withPicture() => CanvasController()
      ..loadDocument(
        PageDocument.empty(id: 'p')
            .withElementAdded(_textBox('first', x: 20, y: 20))
            .withElementAdded(_image('picture', x: 10, y: 10)),
      );

    test('takes a picture beneath the rest, out of reach, and back', () {
      final controller = withPicture()..select('picture');
      controller.setBackground('picture', background: true);

      final picture = controller.document.elementById('picture')!;
      expect(picture.locked, isTrue);
      expect(picture.z, lessThan(controller.document.elementById('first')!.z));
      expect(controller.selection, isEmpty);
      expect(controller.hitTest(const Offset(150, 100)), isNull);
      expect(controller.backgroundAt(const Offset(150, 100))?.id, 'picture');

      controller.selectEverything();
      expect(controller.selection, <String>{'first'});

      controller.setBackground('picture', background: false);
      expect(controller.hitTest(const Offset(150, 100))?.id, 'picture');
      controller.undo();
      expect(controller.document.elementById('picture')!.locked, isTrue);
    });

    testWidgets('a right-click reports where it was, and picks nothing', (
      tester,
    ) async {
      final controller = withPicture();
      final reported = <Offset>[];
      await tester.pumpWidget(
        _host(controller, onContextMenu: (page, global) => reported.add(page)),
      );
      await tester.tapAt(
        controller.viewport.toScreen(const Offset(150, 100)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      expect(reported.single.dx, closeTo(150, 0.01));
      expect(reported.single.dy, closeTo(100, 0.01));
      expect(controller.selection, isEmpty);
    });

    testWidgets('a right-click on what claims presses is left to it', (
      tester,
    ) async {
      final controller = withPicture();
      final reported = <Offset>[];
      await tester.pumpWidget(
        _host(
          controller,
          claimsPointer: (element, page) => true,
          onContextMenu: (page, global) => reported.add(page),
        ),
      );
      await tester.tapAt(
        controller.viewport.toScreen(const Offset(150, 100)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(reported, isEmpty);
    });
  });

  group('SelectionHandles', () {
    test('a text box resizes sideways only', () {
      final behavior = SelectionHandles.behaviorOf(_textBox('t'));
      expect(behavior, ResizeBehavior.horizontal);
      expect(
        SelectionHandles.handlesOf(<NoteElement>[_textBox('t')]),
        <SelectionHandle>[
          SelectionHandle.left,
          SelectionHandle.right,
          SelectionHandle.rotate,
        ],
      );

      final frame = SelectionHandles.resize(
        const Frame(x: 10, y: 10, width: 200, height: 60),
        SelectionHandle.left,
        const Offset(50, 30),
        behavior,
      );
      expect(frame, const Frame(x: 60, y: 10, width: 150, height: 60));
    });

    test('a text box never becomes narrower than the minimum', () {
      final frame = SelectionHandles.resize(
        const Frame(x: 0, y: 0, width: 200, height: 60),
        SelectionHandle.right,
        const Offset(-500, 0),
        ResizeBehavior.horizontal,
      );
      expect(frame.width, SelectionHandles.minTextWidth);
    });

    test('pictures keep their aspect ratio, anchored at the far corner', () {
      final frame = SelectionHandles.resize(
        const Frame(x: 0, y: 0, width: 200, height: 100),
        SelectionHandle.topLeft,
        const Offset(-200, 0),
        ResizeBehavior.proportional,
      );
      expect(frame.width, 400);
      expect(frame.height, 200);
      expect(frame.x + frame.width, 200, reason: 'right edge stays put');
      expect(frame.y + frame.height, 100, reason: 'bottom edge stays put');
    });

    test('pictures offer their corners and all four sides', () {
      expect(
        SelectionHandles.handlesOf(<NoteElement>[_image('a')]),
        containsAll(<SelectionHandle>[
          SelectionHandle.topLeft,
          SelectionHandle.bottomRight,
          SelectionHandle.left,
          SelectionHandle.right,
          SelectionHandle.top,
          SelectionHandle.bottom,
        ]),
      );
    });

    test('a side stretches in its own direction only', () {
      const start = Frame(x: 0, y: 0, width: 200, height: 100);
      final taller = SelectionHandles.resize(
        start,
        SelectionHandle.top,
        const Offset(40, -30),
        ResizeBehavior.proportional,
      );
      expect(taller, const Frame(x: 0, y: -30, width: 200, height: 130));
      final wider = SelectionHandles.resize(
        start,
        SelectionHandle.right,
        const Offset(50, 20),
        ResizeBehavior.proportional,
      );
      expect(wider, const Frame(x: 0, y: 0, width: 250, height: 100));
    });

    test('the whole length of a side can be taken hold of', () {
      final selection = <NoteElement>[_image('a', x: 50, y: 50)];
      final viewport = CanvasController().viewport;
      // The right side runs from (253, 47) to (253, 153) on screen, the
      // outline standing 3 px off the picture.
      expect(
        SelectionHandles.hitTest(selection, viewport, const Offset(255, 70)),
        SelectionHandle.right,
      );
      expect(
        SelectionHandles.hitTest(selection, viewport, const Offset(120, 151)),
        SelectionHandle.bottom,
      );
      expect(
        SelectionHandles.hitTest(selection, viewport, const Offset(150, 100)),
        isNull,
        reason: 'the middle is for moving it',
      );
    });

    test('a turned text box keeps its top edge while resized', () {
      final box = TextElement(
        id: 't',
        frame: const Frame(x: 0, y: 0, width: 200, height: 60, rotation: 0.6),
        createdAt: 0,
        updatedAt: 0,
      );
      // Narrower, so its text wraps onto more lines and it grows taller.
      final resized = ElementTransforms.resize(
        box,
        SelectionHandle.right,
        Offset(-50 * math.cos(0.6), -50 * math.sin(0.6)),
        height: 90,
      );
      expect(resized.frame.width, closeTo(150, 1e-9));
      expect(resized.frame.height, 90);
      final before = box.frame.corners.first;
      final after = resized.frame.corners.first;
      expect(after.x, closeTo(before.x, 1e-9));
      expect(after.y, closeTo(before.y, 1e-9));
    });
  });

  group('InfiniteCanvas wheel', () {
    testWidgets('a notch glides the page on, and there exactly', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(400, 300)));

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      expect(controller.viewport.origin.dy, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.viewport.origin.dy, inExclusiveRange(0, 60));
      await tester.pumpAndSettle();
      expect(controller.viewport.origin.dy, 60);
    });

    testWidgets('notches in quick succession add up', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(400, 300)));

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
      await tester.pumpAndSettle();
      expect(controller.viewport.origin.dy, 120);
    });

    testWidgets('a smooth wheel or a touchpad is followed at once', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(400, 300)));

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 6)));
      expect(controller.viewport.origin.dy, 6);
    });
  });

  group('InfiniteCanvas laying out', () {
    testWidgets('a pinch scales the page as it is laid out, and lays it '
        'out for the zoom it comes to once it is done', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 300, y: 200));
      var built = 0;
      final zooms = <double>[];
      await tester.pumpWidget(
        _host(
          controller,
          elementBuilder: (context, element) {
            built++;
            return Builder(
              builder: (context) {
                zooms.add(CanvasScope.zoomOf(context));
                return const ColoredBox(color: Colors.blue);
              },
            );
          },
        ),
      );
      expect(built, 1);
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 8; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(at, scale: 1 + i * 0.05),
        );
        await tester.pump();
      }
      expect(controller.viewport.zoom, greaterThan(1.3));
      expect(built, 1);
      expect(zooms, <double>[1]);

      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pumpAndSettle();
      expect(built, 1);
      expect(zooms.last, controller.viewport.zoom);
    });

    testWidgets('the page lands on whole device pixels, wherever it is '
        'scrolled to', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 300, y: 200));
      await tester.pumpWidget(_host(controller));
      final ratio = tester.view.devicePixelRatio;
      for (final origin in <Offset>[
        const Offset(10.123, 7.77),
        const Offset(250.4, 1001.01),
      ]) {
        controller.viewport = CanvasViewport(origin: origin, zoom: 1.37);
        await tester.pump();
        final page = tester
            .renderObject<RenderPageSpace>(find.byType(PageSpace))
            .child!
            .localToGlobal(Offset.zero);
        expect(
          page.dx * ratio,
          closeTo((page.dx * ratio).roundToDouble(), 1e-6),
        );
        expect(
          page.dy * ratio,
          closeTo((page.dy * ratio).roundToDouble(), 1e-6),
        );
      }
    });

    testWidgets('scrolling on does not build again what is on the page', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElements(<NoteElement>[
          for (var i = 0; i < 20; i++) _image('$i', x: 100, y: i * 150.0),
        ]);
      final built = <String, int>{};
      await tester.pumpWidget(
        _host(
          controller,
          elementBuilder: (context, element) {
            built[element.id] = (built[element.id] ?? 0) + 1;
            return const ColoredBox(color: Colors.blue);
          },
        ),
      );
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(400, 300)));

      // Down more than a view's height, a few pixels at a time: the part of
      // the page laid out moves on several times.
      for (var i = 0; i < 80; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 10)));
        await tester.pump();
      }
      expect(controller.viewport.origin.dy, 800);
      expect(built.values, everyElement(1));
      expect(built.length, greaterThan(8));
    });
  });

  group('InfiniteCanvas zooming', () {
    testWidgets('a trackpad pinch zooms by its total scale beyond the slop', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (final scale in <double>[1.1, 1.2, 1.3, 1.5]) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(at, scale: scale),
        );
      }
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      // Not compounded, and measured from where the fingers had spread far
      // enough to count as a pinch.
      expect(controller.viewport.zoom, closeTo(1.5 / 1.04, 1e-9));
    });

    testWidgets('two-finger trackpad scrolling pans', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, pan: const Offset(0, -40)),
      );
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(controller.viewport.zoom, 1);
      expect(controller.viewport.origin, const Offset(0, 40));
    });

    testWidgets('a mouse-wheel notch with Ctrl zooms gently', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(400, 300)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -53)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // It glides there over the next frames.
      await tester.pumpAndSettle();

      expect(controller.viewport.zoom, greaterThan(1.05));
      expect(controller.viewport.zoom, lessThan(1.2));
    });

    testWidgets('spreading two fingers zooms about their midpoint', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final first = await tester.startGesture(
        const Offset(300, 300),
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(500, 300),
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await first.moveTo(const Offset(200, 300));
      await second.moveTo(const Offset(600, 300));
      await first.up();
      await second.up();

      expect(controller.viewport.zoom, closeTo(2, 1e-9));
      expect(
        controller.viewport.toScreen(
          controller.viewport.toPage(const Offset(400, 300)),
        ),
        const Offset(400, 300),
      );
      expect(controller.document.elements, isEmpty, reason: 'nothing drawn');
    });
  });

  group('InfiniteCanvas selecting', () {
    testWidgets('a stroke held still becomes the shape it was drawn as, '
        'reshaped until the pen lifts', (tester) async {
      final controller = CanvasController()..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));

      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 0; i < 20; i++) {
        await pen.moveBy(const Offset(10, 0));
      }
      // A pause shorter than the hold leaves the stroke a stroke.
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isShaping, isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isShaping, isTrue);

      await pen.moveBy(const Offset(0, 80));
      await pen.up();
      final line = controller.document.elements.single as InkElement;
      final stroke = line.strokes.single;
      expect(stroke.pointCount, 2);
      expect(stroke.xAt(1), closeTo(300, 0.5));
      expect(stroke.yAt(1), closeTo(180, 0.5));
    });

    testWidgets('the pen shows its nib, in its colour, for a cursor', (
      tester,
    ) async {
      final controller = CanvasController()
        ..setTool(CanvasTool.pen)
        ..setPen(PenSettings.defaultPen.copyWith(color: 0xFFD93025, width: 8));
      tester.view
        ..physicalSize = const Size(800, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(controller));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(300, 300));
      await mouse.moveTo(const Offset(320, 300));
      await tester.pump();

      final region = tester.widget<MouseRegion>(
        find
            .descendant(
              of: find.byType(InfiniteCanvas),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(region.cursor, SystemMouseCursors.none);
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      final image = (await tester.runAsync(
        () => layer.toImage(const Rect.fromLTWH(0, 0, 800, 600)),
      ))!;
      final pixels = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      int red(int x, int y) => pixels.getUint8((y * 800 + x) * 4);
      int green(int x, int y) => pixels.getUint8((y * 800 + x) * 4 + 1);
      expect((red(320, 300), green(320, 300)), (0xD9, 0x30));
      expect(green(340, 300), 255, reason: 'paper beyond the nib');
      await mouse.removePointer();
    });

    testWidgets('a pen trembling where it is held still still makes the '
        'shape', (tester) async {
      final controller = CanvasController()..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));

      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      for (var i = 0; i < 20; i++) {
        await pen.moveBy(const Offset(10, 0));
      }
      // Held, it trembles a few pixels this way and that for half a second.
      for (var i = 0; i < 10; i++) {
        await pen.moveTo(Offset(300.0 + (i.isEven ? 4 : -3), 100 + i % 3 * 3));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(controller.isShaping, isTrue);
      await pen.up();

      final stroke =
          (controller.document.elements.single as InkElement).strokes.single;
      expect(stroke.pointCount, 2);
      expect(stroke.yAt(0), stroke.yAt(1), reason: 'a level line');
    });

    testWidgets("a pen's buttons erase and select, and its other end erases", (
      tester,
    ) async {
      final controller = CanvasController()..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));
      Future<void> stroke(
        Offset from,
        Offset by, {
        int buttons = kPrimaryButton,
        PointerDeviceKind kind = PointerDeviceKind.stylus,
      }) async {
        final pen = await tester.startGesture(
          from,
          kind: kind,
          buttons: buttons,
        );
        for (var i = 1; i <= 10; i++) {
          await pen.moveTo(from + by * (i / 10));
        }
        await pen.up();
        await tester.pump();
      }

      await stroke(const Offset(100, 100), const Offset(200, 0));
      await stroke(const Offset(100, 300), const Offset(200, 0));
      expect(controller.document.elements, hasLength(2));

      // The first button erases what it passes over.
      await stroke(
        const Offset(200, 50),
        const Offset(0, 100),
        buttons: kPrimaryButton | kPrimaryStylusButton,
      );
      expect(controller.document.elements, hasLength(1));

      // The second picks what it drags round, and does not move the page.
      await stroke(
        const Offset(50, 250),
        const Offset(300, 100),
        buttons: kPrimaryButton | kSecondaryStylusButton,
      );
      expect(controller.selection, hasLength(1));
      expect(controller.viewport.origin, Offset.zero);
      expect(controller.document.elements, hasLength(1), reason: 'no ink');

      // Drawing again lets go of it; the pen's other end erases.
      await stroke(const Offset(100, 500), const Offset(100, 0));
      expect(controller.selection, isEmpty);
      await stroke(
        const Offset(150, 450),
        const Offset(0, 100),
        kind: PointerDeviceKind.invertedStylus,
      );
      expect(controller.document.elements, hasLength(1));
    });

    testWidgets('writing that pauses mid-stroke carries on as writing', (
      tester,
    ) async {
      final controller = CanvasController()..setTool(CanvasTool.pen);
      await tester.pumpWidget(_host(controller));

      final pen = await tester.startGesture(
        const Offset(100, 100),
        kind: PointerDeviceKind.stylus,
      );
      for (var x = 0.0; x <= 200; x += 5) {
        await pen.moveTo(Offset(100 + x, 100 + 20 * math.sin(x / 20)));
      }
      await tester.pump(const Duration(seconds: 1));
      await pen.moveBy(const Offset(10, 10));
      await pen.up();

      expect(controller.isShaping, isFalse);
      final ink = controller.document.elements.single as InkElement;
      expect(ink.strokes.single.pointCount, greaterThan(30));
    });

    testWidgets('a press let go of after the canvas has gone does nothing', (
      tester,
    ) async {
      final controller = CanvasController();
      final taps = <Offset>[];
      await tester.pumpWidget(_host(controller, onEmptyTap: taps.add));
      final gesture = await tester.startGesture(
        const Offset(120, 80),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      // The press took the canvas away — it opened another page, say.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await gesture.moveBy(const Offset(40, 30));
      await gesture.up();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(taps, isEmpty);
    });

    testWidgets('a click on empty canvas reports a tap in page space', (
      tester,
    ) async {
      final controller = CanvasController();
      final taps = <Offset>[];
      await tester.pumpWidget(_host(controller, onEmptyTap: taps.add));

      await tester.tapAt(const Offset(120, 80));

      expect(taps, <Offset>[const Offset(120, 80)]);
    });

    testWidgets('dragging on empty canvas selects instead of tapping', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50));
      final taps = <Offset>[];
      await tester.pumpWidget(_host(controller, onEmptyTap: taps.add));

      await tester.dragFrom(
        const Offset(10, 10),
        const Offset(400, 300),
        kind: PointerDeviceKind.mouse,
      );

      expect(taps, isEmpty);
      expect(controller.selection, <String>{'a'});
    });

    testWidgets('a finger dragged across empty canvas scrolls it', (
      tester,
    ) async {
      final controller = CanvasController();
      final taps = <Offset>[];
      await tester.pumpWidget(_host(controller, onEmptyTap: taps.add));

      await tester.dragFrom(const Offset(300, 300), const Offset(0, -100));

      expect(taps, isEmpty);
      expect(controller.viewport.origin, const Offset(0, 100));
    });

    testWidgets('element widgets receive presses through the ink layers', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_textBox('t', x: 50, y: 50));
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfiniteCanvas(
              controller: controller,
              claimsPointer: (element, page) => true,
              elementBuilder: (context, element) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(100, 80));

      expect(taps, 1);
    });

    testWidgets('an element that claims the press is left alone', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_textBox('t', x: 50, y: 50));
      final presses = <NoteElement?>[];
      await tester.pumpWidget(
        _host(
          controller,
          claimsPointer: (element, page) => true,
          onCanvasPress: presses.add,
        ),
      );

      await tester.dragFrom(const Offset(100, 70), const Offset(80, 0));

      expect(controller.selection, isEmpty);
      expect(controller.document.elementById('t')!.frame.x, 50);
      expect(presses, isEmpty);
    });

    testWidgets("a selected box's grip picks it up under another box", (
      tester,
    ) async {
      // The lower box's band along its top lies under the upper box.
      final controller = CanvasController()
        ..addElement(_textBox('lower', x: 50, y: 100))
        ..addElement(_textBox('upper', x: 50, y: 60))
        ..select('lower');
      final presses = <NoteElement?>[];
      await tester.pumpWidget(
        _host(
          controller,
          claimsPointer: (element, page) => true,
          grips: (element, page) =>
              element.frame.containsPoint(page.dx, page.dy) &&
              element.frame.pageToLocal(page.dx, page.dy).y < 12,
          onCanvasPress: presses.add,
        ),
      );

      await tester.dragFrom(
        const Offset(150, 105),
        const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      );

      expect(controller.document.elementById('lower')!.frame.y, 200);
      expect(controller.document.elementById('upper')!.frame.y, 60);
      expect(presses.single?.id, 'lower');

      // Where no selected box's grip is, the box on top takes the press.
      controller.clearSelection();
      await tester.dragFrom(
        const Offset(150, 110),
        const Offset(0, 50),
        kind: PointerDeviceKind.mouse,
      );
      expect(controller.document.elementById('upper')!.frame.y, 60);
    });

    testWidgets('dragging an element moves it as one undo step', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50));
      await tester.pumpWidget(_host(controller));

      final gesture = await tester.startGesture(const Offset(100, 100));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(10, 0));
      }
      await gesture.up();

      expect(controller.document.elementById('a')!.frame.x, 150);
      controller.undo();
      expect(
        controller.document.elementById('a')!.frame.x,
        50,
        reason: 'one undo reverses the whole drag',
      );
    });

    testWidgets('dragging a corner handle resizes in proportion', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50));
      controller.select('a');
      await tester.pumpWidget(_host(controller));

      // The bottom-right handle sits on the outline, just outside the frame.
      final gesture = await tester.startGesture(const Offset(252, 152));
      await gesture.moveBy(const Offset(100, 0));
      await gesture.moveBy(const Offset(100, 0));
      await gesture.up();

      final frame = controller.document.elementById('a')!.frame;
      expect(frame.width, 400);
      expect(frame.height, 200);
      expect(frame.x, 50);
      controller.undo();
      expect(controller.document.elementById('a')!.frame.width, 200);
    });
  });

  group('InfiniteCanvas page edges', () {
    testWidgets('the view stops at the top and left of the page', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      await tester.dragFrom(const Offset(300, 300), const Offset(150, 100));
      await tester.pumpAndSettle();
      expect(controller.viewport.origin, Offset.zero);

      // Zooming out about a point far from the corner keeps the corner.
      await tester.sendEventToBinding(
        const PointerScaleEvent(position: Offset(600, 400), scale: 0.5),
      );
      expect(controller.viewport.zoom, 0.5);
      expect(controller.viewport.origin, Offset.zero);
    });

    testWidgets('an element dragged past the edge stops at it', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50));
      await tester.pumpWidget(_host(controller));

      await tester.dragFrom(
        const Offset(100, 100),
        const Offset(-200, -30),
        kind: PointerDeviceKind.mouse,
      );

      final frame = controller.document.elementById('a')!.frame;
      expect(frame.x, 0);
      expect(frame.y, 20);
    });

    testWidgets('a handle stops at the edge', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50));
      controller.select('a');
      await tester.pumpWidget(_host(controller));

      // The left side's handle, dragged far past the page's left edge.
      final gesture = await tester.startGesture(const Offset(48, 100));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-200, 0));
      await gesture.up();

      final frame = controller.document.elementById('a')!.frame;
      expect(frame.x, closeTo(0, 2));
      expect(frame.x + frame.width, 250, reason: 'the far side stays put');
    });

    testWidgets('the header takes its own presses, but not the pen', (
      tester,
    ) async {
      final controller = CanvasController();
      final taps = <Offset>[];
      var headerTaps = 0;
      await tester.pumpWidget(
        _host(
          controller,
          onEmptyTap: taps.add,
          header: CanvasHeader(
            frame: const Frame(x: 40, y: 20, width: 300, height: 60),
            child: GestureDetector(
              onTap: () => headerTaps++,
              child: const ColoredBox(color: Colors.amber),
            ),
          ),
        ),
      );

      await tester.tapAt(const Offset(100, 50), kind: PointerDeviceKind.mouse);
      expect(headerTaps, 1);
      expect(taps, isEmpty, reason: 'no text box is started under the title');

      controller.setTool(CanvasTool.pen);
      await tester.pump();
      await tester.dragFrom(const Offset(100, 50), const Offset(80, 10));
      expect(headerTaps, 1);
      expect(
        controller.document.elements.whereType<InkElement>(),
        hasLength(1),
      );
    });

    testWidgets('the header moves and scales with the page', (tester) async {
      final controller = CanvasController()
        ..viewport = const CanvasViewport(origin: Offset(20, 10), zoom: 2);
      await tester.pumpWidget(
        _host(
          controller,
          header: const CanvasHeader(
            frame: Frame(x: 40, y: 20, width: 100, height: 30),
            child: ColoredBox(
              key: ValueKey<String>('title'),
              color: Colors.amber,
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(const ValueKey<String>('title')));
      expect(rect.topLeft, const Offset(40, 20));
      expect(rect.size, const Size(200, 60));
    });
  });

  group('InfiniteCanvas selection tool', () {
    testWidgets('the rotation knob turns an object and snaps upright', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50))
        ..select('a');
      await tester.pumpWidget(_host(controller));

      // The knob sits above the middle of the top edge; the image's centre is
      // at (150, 100). Dragging round to its right is a quarter turn.
      final knob = SelectionHandles.positionsFor(
        controller.selectedElements,
        controller.viewport,
      )[SelectionHandle.rotate]!;
      final gesture = await tester.startGesture(
        knob,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(const Offset(250, 30));
      await gesture.moveTo(const Offset(350, 97));
      await gesture.up();

      final frame = controller.document.elementById('a')!.frame;
      expect(frame.rotation, math.pi / 2, reason: 'snapped from about 89°');
      expect(frame.centerX, 150);
      expect(frame.centerY, 100);
      controller.undo();
      expect(controller.document.elementById('a')!.frame.rotation, 0);
    });

    testWidgets('a group scales together about its far corner', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50))
        ..addElement(_image('b', x: 300, y: 50))
        ..select('a')
        ..select('b', additive: true);
      await tester.pumpWidget(_host(controller));

      final corner = SelectionHandles.positionsFor(
        controller.selectedElements,
        controller.viewport,
      )[SelectionHandle.bottomRight]!;
      final gesture = await tester.startGesture(
        corner,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(200, 50));
      await gesture.moveBy(const Offset(250, 50));
      await gesture.up();

      final a = controller.document.elementById('a')!.frame;
      final b = controller.document.elementById('b')!.frame;
      expect(a.x, closeTo(50, 1), reason: 'the far corner stays put');
      expect(a.width, closeTo(400, 8));
      expect(b.x, closeTo(550, 10), reason: 'the gap scales too');
    });

    testWidgets('dragging a side of a picture stretches it that way', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50))
        ..select('a');
      await tester.pumpWidget(_host(controller));

      // Anywhere along the right side, not just at its handle.
      final gesture = await tester.startGesture(
        const Offset(253, 65),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(40, 30));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();

      final image = controller.document.elementById('a')! as ImageElement;
      expect(image.frame, const Frame(x: 50, y: 50, width: 280, height: 100));
      expect(image.fit, MediaFit.stretch, reason: 'it fills its new shape');
    });

    testWidgets('dragging a side of a group stretches it that way', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50))
        ..addElement(_image('b', x: 50, y: 200))
        ..select('a')
        ..select('b', additive: true);
      await tester.pumpWidget(_host(controller));

      // The group spans y 50 to 300; its bottom side is dragged down by 250.
      final gesture = await tester.startGesture(
        const Offset(120, 303),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(10, 125));
      await gesture.moveBy(const Offset(10, 125));
      await gesture.up();

      final a = controller.document.elementById('a')!.frame;
      final b = controller.document.elementById('b')!.frame;
      expect(a.y, closeTo(50, 1e-9), reason: 'the top side stays put');
      expect(a.height, closeTo(200, 1e-9));
      expect(a.width, 200, reason: 'nothing changes across');
      expect(b.y, closeTo(350, 1e-9), reason: 'the gap stretches too');
    });

    testWidgets("a handle over an element is the canvas's alone", (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(_textBox('t', x: 50, y: 50))
        ..select('t');
      var elementPresses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfiniteCanvas(
              controller: controller,
              claimsPointer: (element, page) => true,
              elementBuilder: (context, element) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => elementPresses++,
              ),
            ),
          ),
        ),
      );

      // Just inside the box's right edge, within reach of its side.
      final gesture = await tester.startGesture(
        const Offset(248, 80),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();

      expect(elementPresses, 0);
      expect(controller.document.elementById('t')!.frame.width, 260);

      // Further in, the press is the box's own again.
      await tester.tapAt(const Offset(150, 80), kind: PointerDeviceKind.mouse);
      expect(elementPresses, 1);
    });

    testWidgets('any member of a group drags the whole group', (tester) async {
      final controller = CanvasController()
        ..addElement(_image('a', x: 50, y: 50))
        ..addElement(_textBox('t', x: 300, y: 50))
        ..select('a')
        ..select('t', additive: true);
      await tester.pumpWidget(
        _host(controller, claimsPointer: (element, page) => true),
      );

      // Pressing the text box's body would place a caret on its own; in a
      // group it picks the group up.
      await tester.dragFrom(
        const Offset(350, 80),
        const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      );

      expect(controller.document.elementById('a')!.frame.y, 150);
      expect(controller.document.elementById('t')!.frame.y, 150);
    });

    testWidgets('clicks pass through the empty paper inside handwriting', (
      tester,
    ) async {
      final controller = CanvasController()
        ..addElement(
          InkElement(
            id: 'ink',
            frame: const Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 0,
            updatedAt: 0,
          ).withStrokes(<InkStroke>[
            _line(20, 20, 400, 20),
            _line(20, 400, 400, 400),
          ]),
        );
      final taps = <Offset>[];
      await tester.pumpWidget(_host(controller, onEmptyTap: taps.add));

      await tester.tapAt(const Offset(200, 200), kind: PointerDeviceKind.mouse);

      expect(controller.selection, isEmpty);
      expect(taps, hasLength(1));
    });
  });

  group('marquee over handwriting', () {
    test('takes only the strokes inside it, as an element of their own', () {
      final controller = CanvasController()
        ..addElement(
          InkElement(
            id: 'ink',
            frame: const Frame(x: 0, y: 0, width: 1, height: 1),
            createdAt: 0,
            updatedAt: 0,
          ).withStrokes(<InkStroke>[
            _line(10, 10, 60, 10),
            _line(10, 200, 60, 200),
          ]),
        );

      controller.selectIn(const Aabb(0, 150, 100, 250));

      expect(controller.document.elements, hasLength(2));
      final selected = controller.selectedElements.single as InkElement;
      expect(selected.id, isNot('ink'));
      expect(selected.strokes.single.yAt(0), 200);
      final rest = controller.document.elementById('ink')! as InkElement;
      expect(rest.strokes.single.yAt(0), 10);
    });
  });

  group('InfiniteCanvas trackpad', () {
    testWidgets('a pinch after a scroll zooms about the pointer', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, pan: const Offset(0, -40)),
      );
      // The scroll has brought this page point under the pointer.
      final underPointer = controller.viewport.toPage(at);
      for (final scale in <double>[1.2, 1.5, 1.8, 2]) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(at, pan: const Offset(0, -40), scale: scale),
        );
      }
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(controller.viewport.zoom, closeTo(2 / 1.04, 1e-9));
      final screen = controller.viewport.toScreen(underPointer);
      expect(screen.dx, closeTo(at.dx, 1e-6));
      expect(screen.dy, closeTo(at.dy, 1e-6));
    });

    testWidgets('a pinch that also reports the pan of zooming about the '
        'fingers keeps the point under the pointer', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      // Windows reports a pinch about the fingers' middle as a scale and
      // the pan that scaling about it makes.
      final mouse = TestPointer(9, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(200, 150)));
      final underPointer = controller.viewport.toPage(const Offset(200, 150));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const fingers = Offset(400, 300);

      await tester.sendEventToBinding(trackpad.panZoomStart(fingers));
      for (final scale in <double>[1.02, 1.05, 1.1, 1.3, 1.6, 2]) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            fingers,
            scale: scale,
            pan: fingers * (1 - scale),
          ),
        );
        await tester.pump();
      }
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();

      expect(controller.viewport.zoom, greaterThan(1.8));
      final screen = controller.viewport.toScreen(underPointer);
      expect(screen.dx, closeTo(200, 1e-6));
      expect(screen.dy, closeTo(150, 1e-6));
    });

    testWidgets('a scale that restarts mid-gesture does not jump', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (final scale in <double>[1.1, 1.2, 1.3, 1.0, 1.1]) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(at, scale: scale),
        );
      }
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(controller.viewport.zoom, closeTo(1.3 * 1.1 / 1.04, 1e-9));
    });

    testWidgets('a quick two-finger scroll carries on after the fingers lift', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 6; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            at,
            pan: Offset(0, -20.0 * i),
            timeStamp: Duration(milliseconds: 16 * i),
          ),
        );
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 100)),
      );
      final lifted = controller.viewport.origin.dy;

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(controller.viewport.origin.dy, greaterThan(lifted + 50));
    });

    testWidgets('a scroll follows the fingers exactly, and a quick one '
        'coasts on', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);

      /// Scrolls 200 pixels down in ten steps [step] apart, and says how far
      /// the page went before it could coast, and how far in all.
      Future<(double, double)> scroll(Duration step) async {
        final before = controller.viewport.origin.dy;
        await tester.sendEventToBinding(trackpad.panZoomStart(at));
        for (var i = 1; i <= 10; i++) {
          await tester.sendEventToBinding(
            trackpad.panZoomUpdate(
              at,
              pan: Offset(0, -20.0 * i),
              timeStamp: step * i,
            ),
          );
        }
        final moved = controller.viewport.origin.dy - before;
        await tester.sendEventToBinding(
          trackpad.panZoomEnd(timeStamp: step * 11),
        );
        await tester.pumpAndSettle();
        return (moved, controller.viewport.origin.dy - before);
      }

      final (slow, slowInAll) = await scroll(const Duration(milliseconds: 100));
      expect(slow, 200);
      expect(slowInAll, 200);
      final (quick, quickInAll) = await scroll(const Duration(milliseconds: 8));
      expect(quick, 200);
      expect(quickInAll, greaterThan(400));
    });

    testWidgets('scrolled past the top, the page gives a little and springs '
        'back', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 10; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            at,
            pan: Offset(0, 20.0 * i),
            timeStamp: Duration(milliseconds: 100 * i),
          ),
        );
      }
      final stretched = controller.viewport.origin.dy;
      expect(stretched, lessThan(-40), reason: 'it gives');
      expect(stretched, greaterThan(-100), reason: 'less than the fingers');

      // Pulled on and on, it goes hardly any further.
      for (var i = 11; i <= 60; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            at,
            pan: Offset(0, 20.0 * i),
            timeStamp: Duration(milliseconds: 100 * i),
          ),
        );
      }
      final furthest = controller.viewport.origin.dy;
      expect(furthest, lessThan(stretched));
      expect(furthest, greaterThan(-100), reason: 'however hard it is pulled');

      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(seconds: 7)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      final returning = controller.viewport.origin.dy;
      expect(returning, greaterThan(stretched));
      await tester.pumpAndSettle();
      expect(controller.viewport.origin, Offset.zero);
    });

    testWidgets('a flick up the page stops at the top and springs back', (
      tester,
    ) async {
      final controller = CanvasController()
        ..viewport = const CanvasViewport(origin: Offset(0, 300));
      await tester.pumpWidget(_host(controller));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 8; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            at,
            pan: Offset(0, 30.0 * i),
            timeStamp: Duration(milliseconds: 8 * i),
          ),
        );
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 70)),
      );
      var furthest = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        furthest = math.min(furthest, controller.viewport.origin.dy);
      }
      expect(furthest, lessThan(0), reason: 'it went past the top');
      await tester.pumpAndSettle();
      expect(controller.viewport.origin, Offset.zero);
    });

    testWidgets('a hard flick coasts far, but a bounded distance', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 8; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            at,
            pan: Offset(0, -200.0 * i),
            timeStamp: Duration(milliseconds: 8 * i),
          ),
        );
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 70)),
      );
      final lifted = controller.viewport.origin.dy;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      final coasted = controller.viewport.origin.dy - lifted;
      expect(coasted, greaterThan(1500));
      expect(coasted, lessThan(4100));
    });

    group('caught as it coasts', () {
      const at = Offset(400, 300);

      /// Scrolls down [steps] times by [step] pixels, [every] apart, from
      /// [from] on the gesture's clock, and lifts [every] after the last.
      Future<void> scroll(
        WidgetTester tester,
        TestPointer trackpad, {
        required double step,
        required int steps,
        required Duration every,
        Duration from = Duration.zero,
      }) async {
        await tester.sendEventToBinding(trackpad.panZoomStart(at));
        for (var i = 1; i <= steps; i++) {
          await tester.sendEventToBinding(
            trackpad.panZoomUpdate(
              at,
              pan: Offset(0, -step * i),
              timeStamp: from + every * i,
            ),
          );
        }
        await tester.sendEventToBinding(
          trackpad.panZoomEnd(timeStamp: from + every * (steps + 1)),
        );
      }

      testWidgets('fingers put down stop the page where they catch it', (
        tester,
      ) async {
        final controller = CanvasController();
        await tester.pumpWidget(_host(controller));
        final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
        await scroll(
          tester,
          trackpad,
          step: 100,
          steps: 8,
          every: const Duration(milliseconds: 8),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Two fingers put down, settling a pixel or two the same way.
        await scroll(
          tester,
          trackpad,
          step: 1,
          steps: 3,
          every: const Duration(milliseconds: 10),
          from: const Duration(seconds: 1),
        );
        final caught = controller.viewport.origin.dy;
        await tester.pumpAndSettle();
        expect(controller.viewport.origin.dy, closeTo(caught, 1));
      });

      testWidgets('fingers resting stop it before they move, where the '
          'platform tells of them', (tester) async {
        final controller = CanvasController();
        final fingers = ValueNotifier<TouchpadFingers>(TouchpadFingers.lifted);
        addTearDown(fingers.dispose);
        await tester.pumpWidget(_host(controller, touchpadFingers: fingers));
        final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
        await scroll(
          tester,
          trackpad,
          step: 100,
          steps: 8,
          every: const Duration(milliseconds: 8),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        fingers.value = TouchpadFingers.resting;
        final caught = controller.viewport.origin.dy;
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.viewport.origin.dy, caught);

        fingers.value = TouchpadFingers.lifted;
        await tester.pumpAndSettle();
        expect(controller.viewport.origin.dy, caught);
      });

      testWidgets('a flick the same way sends it faster still', (tester) async {
        Future<double> coasted({required bool again}) async {
          final controller = CanvasController();
          await tester.pumpWidget(_host(controller));
          final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
          await scroll(
            tester,
            trackpad,
            step: 60,
            steps: 8,
            every: const Duration(milliseconds: 8),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          if (again) {
            await scroll(
              tester,
              trackpad,
              step: 60,
              steps: 8,
              every: const Duration(milliseconds: 8),
              from: const Duration(seconds: 1),
            );
          }
          final before = controller.viewport.origin.dy;
          await tester.pumpAndSettle();
          return controller.viewport.origin.dy - before;
        }

        final once = await coasted(again: false);
        expect(await coasted(again: true), greaterThan(once * 1.3));
      });
    });

    testWidgets('a pan scale brings touchpad deltas back to finger distance', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller, trackpadPanScale: 10 / 53));

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      const at = Offset(400, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      for (var i = 1; i <= 4; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(at, pan: Offset(0, -53.0 * i)),
        );
      }
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(controller.viewport.origin.dy, closeTo(40, 1e-9));
    });
  });

  // Flutter on Linux reports a two-finger scroll and a pinch as two streams on
  // one device, each with its own running totals: the scroll's pan grows while
  // it reports a scale of 1, the pinch reports a pan of zero, and each start
  // takes a new pointer id that later events of both streams carry. See the
  // engine's shell/platform/linux/fl_scrolling_manager.cc and
  // lib/ui/window/pointer_data_packet_converter.cc.
  group('InfiniteCanvas trackpad on Linux', () {
    const at = Offset(400, 300);
    PointerEvent start(int pointer) =>
        PointerPanZoomStartEvent(pointer: pointer, device: 1, position: at);
    PointerEvent update(
      int pointer, {
      Offset pan = Offset.zero,
      double scale = 1,
    }) => PointerPanZoomUpdateEvent(
      pointer: pointer,
      device: 1,
      position: at,
      pan: pan,
      scale: scale,
    );
    PointerEvent end(int pointer) =>
        PointerPanZoomEndEvent(pointer: pointer, device: 1, position: at);

    /// Sends [events] and returns the furthest any one of them moved the
    /// page from under the pointer. Zooming about the pointer moves nothing.
    Future<double> largestStep(
      WidgetTester tester,
      CanvasController controller,
      List<PointerEvent> events,
    ) async {
      var largest = 0.0;
      for (final event in events) {
        final underPointer = controller.viewport.toPage(at);
        await tester.sendEventToBinding(event);
        final moved = controller.viewport.toScreen(underPointer) - at;
        largest = math.max(largest, moved.distance);
      }
      return largest;
    }

    testWidgets('a scroll starts smoothly wherever the canvas sits', (
      tester,
    ) async {
      // Scrolled down the page, away from its top and left edges.
      final controller = CanvasController()
        ..viewport = const CanvasViewport(origin: Offset(500, 500));
      // Below a ribbon and beside the sidebars, as in the app. The events are
      // as recorded from a touchpad under KDE Plasma: each reports the running
      // pan, 5.3 times as far as the fingers went.
      await tester.pumpWidget(
        _host(
          controller,
          trackpadPanScale: 10 / 53,
          offset: const Offset(255, 81),
        ),
      );

      final largest = await largestStep(tester, controller, <PointerEvent>[
        start(1),
        for (var i = 1; i <= 10; i++) update(1, pan: Offset(8.1 * i, 0)),
        end(1),
        start(2),
        for (var i = 1; i <= 10; i++) update(2, pan: Offset(8.1 * i, 0)),
        end(2),
      ]);

      expect(largest, lessThan(2));
      expect(
        controller.viewport.origin.dx,
        closeTo(500 - 2 * 81 * 10 / 53, 1e-9),
      );
      expect(controller.viewport.origin.dy, 500);
    });

    testWidgets('a pinch event in the middle of a scroll does not jump', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final largest = await largestStep(tester, controller, <PointerEvent>[
        start(1),
        for (var i = 1; i <= 20; i++) update(1, pan: Offset(0, -10.0 * i)),
        update(1, scale: 1.1),
        for (var i = 21; i <= 30; i++) update(1, pan: Offset(0, -10.0 * i)),
        end(1),
      ]);

      expect(largest, lessThan(20));
      expect(controller.viewport.zoom, closeTo(1.1 / 1.04, 1e-9));
    });

    testWidgets('a pinch starting before the scroll ends does not jump', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      await tester.sendEventToBinding(start(1));
      for (var i = 1; i <= 30; i++) {
        await tester.sendEventToBinding(update(1, pan: Offset(0, -10.0 * i)));
      }
      expect(controller.viewport.origin.dy, closeTo(300, 1e-9));

      // The pinch starts while the scroll is still reporting; both streams
      // then speak through the pinch's pointer.
      final largest = await largestStep(tester, controller, <PointerEvent>[
        start(2),
        update(2, scale: 1.05),
        update(2, pan: const Offset(0, -310)),
        update(2, scale: 1.1),
        update(2, pan: const Offset(0, -320)),
        update(2, scale: 1.15),
        end(2),
      ]);

      expect(largest, lessThan(30));
      expect(controller.viewport.zoom, closeTo(1.15 / 1.04, 1e-9));
    });

    testWidgets('fingers drifting apart as they scroll do not zoom', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      // A touchpad can report the start of a two-finger scroll as a pinch
      // whose scale wanders a little around 1.
      await largestStep(tester, controller, <PointerEvent>[
        start(1),
        for (final scale in <double>[1.01, 1.02, 1.03, 1.02, 0.99, 0.975])
          update(1, scale: scale),
        end(1),
      ]);

      expect(controller.viewport.zoom, 1);
    });

    testWidgets('a pinch zooms about the mouse pointer, not the last click', (
      tester,
    ) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));
      // Linux reports the pinch where the mouse was last clicked; the
      // pointer has since moved on.
      final mouse = TestPointer(9, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(200, 150)));
      final underPointer = controller.viewport.toPage(const Offset(200, 150));

      await largestStep(tester, controller, <PointerEvent>[
        start(1),
        for (final scale in <double>[1.1, 1.3, 1.6, 2]) update(1, scale: scale),
        end(1),
      ]);

      expect(controller.viewport.zoom, greaterThan(1.8));
      final screen = controller.viewport.toScreen(underPointer);
      expect(screen.dx, closeTo(200, 1e-6));
      expect(screen.dy, closeTo(150, 1e-6));
    });

    testWidgets('a new scroll after a lost end does not jump', (tester) async {
      final controller = CanvasController();
      await tester.pumpWidget(_host(controller));

      final largest = await largestStep(tester, controller, <PointerEvent>[
        start(1),
        for (var i = 1; i <= 40; i++) update(1, pan: Offset(0, -10.0 * i)),
        // No end arrives; the next gesture starts its totals from zero.
        start(2),
        for (var i = 1; i <= 5; i++) update(2, pan: Offset(0, 10.0 * i)),
        end(2),
      ]);

      expect(largest, lessThan(20));
    });
  });
}

InkStroke _line(double x0, double y0, double x1, double y1) =>
    InkStroke.fromPoints(
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 2,
      xs: <double>[x0, (x0 + x1) / 2, x1],
      ys: <double>[y0, (y0 + y1) / 2, y1],
    );
