import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with a box whose foot is 2000 units down and 1000 across.
PageDocument _tallPage() => PageDocument.empty(id: 'page').withElementAdded(
  const ImageElement(
    id: 'tall',
    frame: Frame(x: 0, y: 0, width: 1000, height: 2000),
    createdAt: 0,
    updatedAt: 0,
    assetId: 'asset',
  ),
);

/// A canvas 800×600, with a scrollbar down its right and along its foot.
Widget _host(CanvasController controller) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 800 + PageScrollbar.thickness,
      height: 600 + PageScrollbar.thickness,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: InfiniteCanvas(controller: controller)),
                PageScrollbar(controller: controller, axis: Axis.vertical),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: PageScrollbar(
                  controller: controller,
                  axis: Axis.horizontal,
                ),
              ),
              const SizedBox.square(dimension: PageScrollbar.thickness),
            ],
          ),
        ],
      ),
    ),
  ),
);

void main() {
  group('how far a page scrolls', () {
    test('half a view past its content, and never short of the view', () {
      final controller = CanvasController()
        ..viewSize = const Size(800, 600)
        ..loadDocument(_tallPage());
      final down = ScrollSpan.of(controller, Axis.vertical);
      expect(down.extent, 2000 + 300);
      expect(down.start, 0);
      expect(down.length, 600);

      controller.viewport = const CanvasViewport(origin: Offset(0, 5000));
      expect(ScrollSpan.of(controller, Axis.vertical).extent, 5600);
    });

    test('an empty page scrolls no further than the view', () {
      final controller = CanvasController()..viewSize = const Size(800, 600);
      final across = ScrollSpan.of(controller, Axis.horizontal);
      expect(across.extent, 800);
      expect(across.lengthFraction, 1);
    });

    test('the view is measured in page units at any zoom', () {
      final controller = CanvasController()
        ..viewSize = const Size(800, 600)
        ..loadDocument(_tallPage())
        ..viewport = const CanvasViewport(zoom: 2);
      expect(ScrollSpan.of(controller, Axis.vertical).length, 300);
    });
  });

  group('a scrollbar', () {
    Future<CanvasController> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = CanvasController()..loadDocument(_tallPage());
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      return controller;
    }

    Rect barOf(WidgetTester tester, Axis axis) => tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is PageScrollbar && widget.axis == axis,
      ),
    );

    testWidgets('scrolls the page as its thumb is dragged', (tester) async {
      final controller = await open(tester);
      final bar = barOf(tester, Axis.vertical);

      // 600 of 2300 units in view: the thumb is the top quarter or so.
      final gesture = await tester.startGesture(
        bar.topCenter + const Offset(0, 20),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 100));
      await gesture.up();
      await tester.pump();

      expect(
        controller.viewport.origin.dy,
        closeTo(100 * 2300 / bar.height, 0.01),
      );
      expect(controller.viewport.origin.dx, 0);
    });

    testWidgets('moves the page on by most of a view when pressed beside its '
        'thumb', (tester) async {
      final controller = await open(tester);
      final bar = barOf(tester, Axis.vertical);

      await tester.tapAt(
        bar.bottomCenter - const Offset(0, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      expect(
        controller.viewport.origin.dy,
        closeTo(600 * PageScrollbar.pageStep, 0.01),
      );
    });

    testWidgets('scrolls the page under the wheel', (tester) async {
      final controller = await open(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(barOf(tester, Axis.horizontal).center),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pump();

      expect(controller.viewport.origin, const Offset(50, 0));
    });
  });
}
