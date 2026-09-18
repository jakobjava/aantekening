import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextElement _text(String id, {double x = 0, double y = 0, double size = 100}) =>
    TextElement(
      id: id,
      frame: Frame(x: x, y: y, width: size, height: size),
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('CanvasViewport', () {
    test('round-trips between page and screen space', () {
      const viewport = CanvasViewport(origin: Offset(100, 50), zoom: 2);
      const page = Offset(180, 90);

      expect(viewport.toScreen(page), const Offset(160, 80));
      expect(viewport.toPage(viewport.toScreen(page)), page);
    });

    test('zooming keeps the point under the cursor fixed', () {
      const viewport = CanvasViewport(origin: Offset(10, 20), zoom: 1);
      const focus = Offset(300, 200);
      final pageFocus = viewport.toPage(focus);

      final zoomed = viewport.zoomAround(3.5, focus);

      expect(zoomed.zoom, 3.5);
      expect(zoomed.toScreen(pageFocus).dx, closeTo(focus.dx, 1e-9));
      expect(zoomed.toScreen(pageFocus).dy, closeTo(focus.dy, 1e-9));
    });

    test('clamps zoom to the supported range', () {
      const viewport = CanvasViewport();
      expect(
        viewport.zoomAround(1000, Offset.zero).zoom,
        CanvasViewport.maxZoom,
      );
      expect(
        viewport.zoomAround(0.0001, Offset.zero).zoom,
        CanvasViewport.minZoom,
      );
    });

    test('visible bounds shrink as zoom increases', () {
      const size = Size(800, 600);
      final wide = const CanvasViewport().visibleBounds(size);
      final close = const CanvasViewport(zoom: 4).visibleBounds(size);

      expect(wide.width, 800);
      expect(close.width, 200);
    });

    test('fit frames the content inside the view', () {
      const bounds = Aabb(0, 0, 1000, 500);
      const size = Size(800, 600);

      final fitted = const CanvasViewport().fit(bounds, size);
      final visible = fitted.visibleBounds(size);

      expect(visible.containsBox(bounds), isTrue);
    });

    test('panning moves by a screen delta scaled to page units', () {
      const viewport = CanvasViewport(zoom: 2);
      expect(viewport.panBy(const Offset(100, 0)).origin.dx, -50);
    });
  });

  group('SpatialIndex', () {
    test('returns only elements that actually intersect', () {
      final index = SpatialIndex(cellSize: 100)
        ..insert('a', const Aabb(0, 0, 50, 50))
        ..insert('b', const Aabb(500, 500, 550, 550));

      expect(index.query(const Aabb(-10, -10, 10, 10)), <String>{'a'});
      expect(index.query(const Aabb(480, 480, 600, 600)), <String>{'b'});
      expect(index.query(const Aabb(200, 200, 300, 300)), isEmpty);
    });

    test('finds elements spanning many cells', () {
      final index = SpatialIndex(cellSize: 64)
        ..insert('wide', const Aabb(0, 0, 1000, 10));

      expect(index.query(const Aabb(900, 0, 950, 5)), <String>{'wide'});
      expect(index.cellCount, greaterThan(1));
    });

    test('re-inserting updates the stored bounds', () {
      final index = SpatialIndex(cellSize: 100)
        ..insert('a', const Aabb(0, 0, 10, 10))
        ..insert('a', const Aabb(900, 900, 910, 910));

      expect(index.query(const Aabb(0, 0, 50, 50)), isEmpty);
      expect(index.query(const Aabb(890, 890, 950, 950)), <String>{'a'});
      expect(index.length, 1);
    });

    test('removal clears empty buckets', () {
      final index = SpatialIndex(cellSize: 100)
        ..insert('a', const Aabb(0, 0, 10, 10))
        ..remove('a');

      expect(index.length, 0);
      expect(index.cellCount, 0);
    });

    test('handles negative coordinates', () {
      final index = SpatialIndex(cellSize: 100)
        ..insert('a', const Aabb(-500, -500, -450, -450));

      expect(index.query(const Aabb(-520, -520, -400, -400)), <String>{'a'});
      expect(index.query(const Aabb(0, 0, 100, 100)), isEmpty);
    });
  });

  group('CanvasController ink capture', () {
    test('commits a stroke into a new ink element', () {
      final controller = CanvasController();

      controller
        ..beginStroke(const Offset(0, 0))
        ..extendStroke(const Offset(10, 10))
        ..extendStroke(const Offset(20, 0));
      final element = controller.endStroke();

      expect(element, isNotNull);
      expect(element!.strokes.single.pointCount, 3);
      expect(controller.document.elements, hasLength(1));
      expect(controller.isDirty, isTrue);
    });

    test('appends consecutive strokes to the same element', () {
      final controller = CanvasController();

      for (var i = 0; i < 3; i++) {
        controller
          ..beginStroke(Offset(i * 50, 0))
          ..extendStroke(Offset(i * 50 + 10, 10))
          ..endStroke();
      }

      // One element with three strokes, not three elements: a page of
      // handwriting must not become thousands of elements.
      expect(controller.document.elements, hasLength(1));
      expect(
        (controller.document.elements.single as InkElement).strokes,
        hasLength(3),
      );
    });

    test('starts a new element after the pen changes', () {
      final controller = CanvasController()
        ..setTool(CanvasTool.pen)
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..endStroke()
        ..setPen(PenSettings.defaultPen.copyWith(color: 0xFFDC2626))
        ..beginStroke(const Offset(12, 0))
        ..extendStroke(const Offset(20, 10))
        ..endStroke();

      expect(controller.document.elements, hasLength(2));
    });

    test('writing somewhere else on the page starts a new element', () {
      final controller = CanvasController()
        ..setTool(CanvasTool.pen)
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..endStroke()
        ..beginStroke(const Offset(400, 400))
        ..extendStroke(const Offset(410, 410))
        ..endStroke();

      expect(controller.document.elements, hasLength(2));
    });

    test('the highlighter keeps its own settings and translucency', () {
      final controller = CanvasController()
        ..setTool(CanvasTool.highlighter)
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(40, 0))
        ..endStroke();

      final stroke =
          (controller.document.elements.single as InkElement).strokes.single;
      expect(stroke.tool, InkTool.highlighter);
      expect(stroke.color >>> 24, PenSettings.highlighterAlpha);
      expect(controller.penSettings, PenSettings.defaultPen);
    });

    test('keeps a tap as a dot', () {
      // Dotting an "i" or placing a decimal point is one sample, and must not
      // be thrown away as noise.
      final controller = CanvasController()..beginStroke(Offset.zero);

      expect(controller.endStroke(), isNotNull);
      expect(controller.document.elements, hasLength(1));
    });

    test('ignores an end with no stroke in progress', () {
      expect(CanvasController().endStroke(), isNull);
    });

    test('drops samples that barely moved', () {
      final controller = CanvasController()..beginStroke(Offset.zero);
      for (var i = 0; i < 50; i++) {
        controller.extendStroke(const Offset(0.01, 0.01));
      }

      expect(controller.wetPoints.length, InkStroke.stride);
    });

    test('cancelling leaves the page untouched', () {
      final controller = CanvasController()
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..cancelStroke();

      expect(controller.document.elements, isEmpty);
      expect(controller.isDrawing, isFalse);
    });
  });

  group('CanvasController erasing', () {
    CanvasController withStroke() {
      final controller = CanvasController()
        ..beginStroke(const Offset(0, 0))
        ..extendStroke(const Offset(50, 0))
        ..extendStroke(const Offset(100, 0));
      controller.endStroke();
      return controller;
    }

    test('removes a whole stroke that is touched', () {
      final controller = withStroke();

      expect(controller.eraseAt(const Offset(50, 0), radius: 5), isTrue);
      expect(controller.document.elements, isEmpty);
    });

    test('leaves strokes it does not touch', () {
      final controller = withStroke();

      expect(controller.eraseAt(const Offset(50, 500), radius: 5), isFalse);
      expect(controller.document.elements, hasLength(1));
    });

    test('keeps the surviving strokes of a multi-stroke element', () {
      final controller = CanvasController();
      for (final y in <double>[0, 400]) {
        controller
          ..beginStroke(Offset(0, y))
          ..extendStroke(Offset(50, y))
          ..endStroke();
      }

      controller.eraseAt(const Offset(25, 0), radius: 6);

      final ink = controller.document.elements.single as InkElement;
      expect(ink.strokes, hasLength(1));
      expect(ink.strokes.single.yAt(0), 400);
    });
  });

  group('CanvasController selection and history', () {
    test('hit testing picks the topmost element', () {
      final controller = CanvasController()
        ..addElement(_text('under'))
        ..addElement(_text('over'));

      expect(controller.hitTest(const Offset(10, 10))?.id, 'over');
      expect(controller.hitTest(const Offset(-900, -900)), isNull);
    });

    test('marquee selection takes everything it covers', () {
      final controller = CanvasController()
        ..addElement(_text('a', x: 0, y: 0))
        ..addElement(_text('b', x: 400, y: 0))
        ..selectIn(const Aabb(-10, -10, 200, 200));

      expect(controller.selection, <String>{'a'});
    });

    test('moving the selection shifts its frames', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller
        ..select('a')
        ..translateSelection(const Offset(25, 40));

      expect(controller.document.elementById('a')!.frame.x, 25);
      expect(controller.document.elementById('a')!.frame.y, 40);
    });

    test('deleting the selection removes it and clears the selection', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller
        ..select('a')
        ..deleteSelection();

      expect(controller.document.elements, isEmpty);
      expect(controller.selection, isEmpty);
    });

    test('undo and redo walk the edit history', () {
      final controller = CanvasController()
        ..addElement(_text('a'))
        ..addElement(_text('b'));

      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.document.elements.map((e) => e.id), <String>['a']);

      controller.undo();
      expect(controller.document.elements, isEmpty);
      expect(controller.canUndo, isFalse);

      controller.redo();
      expect(controller.document.elements.map((e) => e.id), <String>['a']);
    });

    test('a new edit clears the redo stack', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.addElement(_text('b'));

      expect(controller.canRedo, isFalse);
    });

    test('a drag records one undo step, not one per sample', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller.select('a');

      for (var i = 0; i < 20; i++) {
        controller.translateSelection(const Offset(1, 0), recordUndo: false);
      }

      controller.undo();
      expect(
        controller.document.elements,
        isEmpty,
        reason: 'the only recorded step was adding the element',
      );
    });

    test('undo restores the selection to what still exists', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller
        ..select('a')
        ..undo();

      expect(controller.selection, isEmpty);
    });

    test('loading a document resets history and dirty state', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller.loadDocument(PageDocument.empty(id: 'fresh'));

      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(controller.document.id, 'fresh');
    });

    test('only visible elements are returned for painting', () {
      final controller = CanvasController()
        ..addElement(_text('near', x: 0, y: 0))
        ..addElement(_text('far', x: 100000, y: 100000));

      final visible = controller.visibleElements(const Size(800, 600));

      expect(visible.map((e) => e.id), <String>['near']);
    });
  });

  group('StrokeGeometry', () {
    test('a single sample still leaves a mark', () {
      final stroke = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 4,
        xs: <double>[10],
        ys: <double>[10],
      );

      expect(StrokeGeometry.smoothPath(stroke).getBounds().isEmpty, isFalse);
    });

    test('detects a constant-pressure stroke', () {
      final flat = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        xs: <double>[0, 10, 20],
        ys: <double>[0, 0, 0],
        pressures: <double>[0.5, 0.5, 0.5],
      );
      final varying = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        xs: <double>[0, 10, 20],
        ys: <double>[0, 0, 0],
        pressures: <double>[0.1, 0.9, 0.4],
      );

      expect(StrokeGeometry.hasPressureVariation(flat), isFalse);
      expect(StrokeGeometry.hasPressureVariation(varying), isTrue);
    });

    test('width follows pressure within the configured range', () {
      final stroke = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 10,
        xs: <double>[0, 10],
        ys: <double>[0, 0],
        pressures: <double>[0, 1],
      );

      expect(
        StrokeGeometry.widthAt(stroke, 0),
        closeTo(10 * StrokeGeometry.minPressureScale, 1e-6),
      );
      expect(
        StrokeGeometry.widthAt(stroke, 1),
        closeTo(10 * StrokeGeometry.maxPressureScale, 1e-6),
      );
    });
  });
}
