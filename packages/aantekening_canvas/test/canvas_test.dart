import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_canvas/src/page_space.dart';
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
      const viewport = CanvasViewport(origin: Offset(10, 20));
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
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..extendStroke(const Offset(20, 0));
      final element = controller.endStroke();

      expect(element, isNotNull);
      expect(element!.strokes.single.pointCount, 3);
      expect(controller.document.elements, hasLength(1));
      expect(controller.isDirty, isTrue);
    });

    test('stays unsaved after a change made while it was saved', () {
      final controller = CanvasController();
      controller
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..endStroke();
      final saving = controller.document;

      controller
        ..beginStroke(const Offset(0, 400))
        ..extendStroke(const Offset(10, 410))
        ..endStroke()
        ..markSaved(saving);
      expect(controller.isDirty, isTrue);

      controller.markSaved(controller.document);
      expect(controller.isDirty, isFalse);
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

      expect(controller.wetStrokes.single.pointCount, 1);
    });

    test('smoothed, the line trails the pointer, steady through its '
        'trembling, and catches up where it lifts', () {
      final controller = CanvasController()
        ..inkSmoothing = 8
        ..beginStroke(Offset.zero);
      for (var x = 2.0; x <= 200; x += 2) {
        controller.extendStroke(Offset(x, x % 4 == 0 ? 3 : -3));
      }
      final drawn = controller.wetStrokes.single;
      for (var i = 1; i < drawn.pointCount; i++) {
        expect(drawn.yAt(i).abs(), lessThan(1.5));
      }
      expect(drawn.xAt(drawn.pointCount - 1), lessThan(195));

      final kept = controller.endStroke()!.strokes.single;
      expect(kept.xAt(kept.pointCount - 1), 200);
    });

    test('cancelling leaves the page untouched', () {
      final controller = CanvasController()
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..cancelStroke();

      expect(controller.document.elements, isEmpty);
      expect(controller.wetStrokes, isEmpty);
    });
  });

  group('CanvasController shapes', () {
    /// A stroke drawn from [points], left down.
    CanvasController drawing(List<Offset> points, {CanvasTool? tool}) {
      final controller = CanvasController();
      if (tool != null) controller.setTool(tool);
      controller.beginStroke(points.first);
      for (final point in points.skip(1)) {
        controller.extendStroke(point);
      }
      return controller;
    }

    List<Offset> straight(Offset from, Offset to) => <Offset>[
      for (var i = 0; i <= 40; i++) Offset.lerp(from, to, i / 40)!,
    ];

    test('a stroke held still becomes a line, whose far end then follows '
        'the pointer', () {
      final controller = drawing(
        straight(const Offset(100, 100), const Offset(300, 101)),
      );

      expect(controller.snapToShape(), isTrue);
      expect(controller.isShaping, isTrue);
      controller.extendStroke(const Offset(300, 161));
      final ink = controller.endStroke()!;

      final stroke = ink.strokes.single;
      expect(stroke.xAt(0), closeTo(100, 0.5));
      expect(stroke.yAt(0), closeTo(100.5, 0.5));
      expect(stroke.xAt(stroke.pointCount - 1), closeTo(300, 0.5));
      expect(stroke.yAt(stroke.pointCount - 1), closeTo(160.5, 0.5));
      expect(controller.isShaping, isFalse);
      // Nothing of the stroke as it was drawn is left showing.
      expect(controller.wetStrokes, isEmpty);
    });

    test('a stroke that is no shape stays as it was written', () {
      final controller = drawing(<Offset>[
        for (var x = 0.0; x <= 300; x += 3) Offset(x, 20 * math.sin(x / 30)),
      ]);

      expect(controller.snapToShape(), isFalse);
      controller.extendStroke(const Offset(320, 40));
      expect(
        controller.endStroke()!.strokes.single.pointCount,
        greaterThan(90),
      );
    });

    test('a highlighter is only ever straightened', () {
      final square = <Offset>[
        ...straight(Offset.zero, const Offset(100, 0)),
        ...straight(const Offset(100, 0), const Offset(100, 100)),
        ...straight(const Offset(100, 100), const Offset(0, 100)),
        ...straight(const Offset(0, 100), Offset.zero),
      ];
      expect(drawing(square).snapToShape(), isTrue);
      expect(
        drawing(square, tool: CanvasTool.highlighter).snapToShape(),
        isFalse,
      );
      expect(
        drawing(
          straight(Offset.zero, const Offset(200, 0)),
          tool: CanvasTool.highlighter,
        ).snapToShape(),
        isTrue,
      );
    });

    test('a shape is picked by itself: writing after it starts anew', () {
      final controller = drawing(straight(Offset.zero, const Offset(200, 0)))
        ..snapToShape();
      final line = controller.endStroke()!;
      controller
        ..beginStroke(const Offset(10, 10))
        ..extendStroke(const Offset(20, 20));
      final writing = controller.endStroke()!;

      expect(writing.id, isNot(line.id));
      expect(controller.document.elements, hasLength(2));
    });

    test('the shape tool drags out the shape chosen, square with Shift', () {
      final controller = CanvasController()
        ..setTool(CanvasTool.shape)
        ..setShapeKind(ShapeKind.rectangle)
        ..beginShape(const Offset(10, 10))
        ..extendStroke(const Offset(110, 60));
      expect(controller.endStroke()!.bounds.width, closeTo(102, 3));

      controller
        ..beginShape(const Offset(10, 200))
        ..extendStroke(const Offset(110, 260), constrain: true);
      final square = controller.endStroke()!;
      expect(square.bounds.height, closeTo(square.bounds.width, 1e-6));
    });

    test('a click with the shape tool puts the shape down at its usual '
        'size', () {
      final controller = CanvasController()
        ..setTool(CanvasTool.shape)
        ..setShapeKind(ShapeKind.circle)
        ..beginShape(const Offset(40, 40));
      final circle = controller.endStroke()!;

      // Ink's bounds reach half the pen's width, and a unit, past it.
      final pad = PenSettings.defaultPen.width / 2 + 1;
      expect(circle.bounds.width, closeTo(InkShape.usualWidth + 2 * pad, 1));
      expect(circle.bounds.left, closeTo(40 - pad, 1));
    });

    test('draws with the pen, the inverse of what is beneath included', () {
      final controller = CanvasController()
        ..setPen(PenSettings.defaultPen.copyWith(color: NoteColors.inverse))
        ..setTool(CanvasTool.shape)
        ..beginShape(Offset.zero)
        ..extendStroke(const Offset(100, 100));
      final strokes = controller.wetStrokes;
      final ink = controller.endStroke()!;

      expect(strokes, isNotEmpty);
      for (final stroke in ink.strokes) {
        expect(stroke.color, NoteColors.inverse);
        expect(InkLayer.inverting.accepts(stroke), isTrue);
        expect(InkLayer.above.accepts(stroke), isFalse);
      }
    });
  });

  group('CanvasController erasing', () {
    CanvasController withStroke() {
      final controller = CanvasController()
        ..beginStroke(Offset.zero)
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

    test('a lasso holds what its loop goes round', () {
      // An L: the corner it leaves out is outside.
      final lasso = Lasso(Offset.zero)
          .extendedTo(const Offset(100, 0))
          .extendedTo(const Offset(100, 50))
          .extendedTo(const Offset(50, 50))
          .extendedTo(const Offset(50, 100))
          .extendedTo(const Offset(0, 100));

      expect(lasso.containsPoint(25, 75), isTrue);
      expect(lasso.containsPoint(75, 25), isTrue);
      expect(lasso.containsPoint(75, 75), isFalse);
      expect(lasso.containsPoint(150, 25), isFalse);
      expect(lasso.bounds, const Aabb(0, 0, 100, 100));
    });

    test('marquee selection takes everything it covers', () {
      final controller = CanvasController()
        ..addElement(_text('a'))
        ..addElement(_text('b', x: 400))
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

    test('a placeholder made real arrives in history then, undone whole', () {
      final controller = CanvasController()
        ..addElement(_text('b'))
        ..addElement(_text('a'), recordUndo: false, markDirty: false)
        ..replaceElement(_text('a', x: 5), recordUndo: false, markDirty: false)
        ..replacePlaceholder(_text('a', x: 10));

      expect(controller.document.elementById('a')!.frame.x, 10);
      controller.undo();
      expect(controller.document.elementById('a'), isNull);
      expect(controller.document.elementById('b'), isNotNull);
      controller.redo();
      expect(controller.document.elementById('a')!.frame.x, 10);
    });

    test('loading a document resets history and dirty state', () {
      final controller = CanvasController()..addElement(_text('a'));
      controller.loadDocument(PageDocument.empty(id: 'fresh'));

      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(controller.document.id, 'fresh');
    });

    test('a loaded page shows from its corner, at the zoom in use', () {
      final controller = CanvasController()
        ..viewport = const CanvasViewport(origin: Offset(300, 900), zoom: 1.5);

      controller.loadDocument(PageDocument.empty(id: 'next'));

      expect(controller.viewport.origin, Offset.zero);
      expect(controller.viewport.zoom, 1.5);
    });

    test('content is added and moved on the page, never past its corner', () {
      final controller = CanvasController()
        ..addElement(_text('a', x: -30, y: -5))
        ..addElement(_text('b', x: 10, y: 10));

      expect(controller.document.elementById('a')!.frame.x, 0);
      expect(controller.document.elementById('a')!.frame.y, 0);

      controller
        ..select('b')
        ..translateSelection(const Offset(-50, 20));
      expect(controller.document.elementById('b')!.frame.x, 0);
      expect(controller.document.elementById('b')!.frame.y, 30);
    });

    test('revealing a region scrolls only as far as needed', () {
      final controller = CanvasController()
        ..viewSize = const Size(800, 600)
        ..addElement(_text('a'));

      controller.reveal(const Aabb(100, 100, 300, 200));
      expect(controller.viewport.origin, Offset.zero, reason: 'in view');

      controller.reveal(const Aabb(100, 1000, 300, 1100));
      expect(controller.viewport.origin, const Offset(0, 1100 + 48 - 600));

      controller.reveal(const Aabb(100, 3000, 300, 5000));
      expect(
        controller.viewport.origin.dy,
        3000 - 48,
        reason: 'too tall to fit: its top is shown',
      );
    });

    test('only visible elements are returned for painting', () {
      final controller = CanvasController()
        ..addElement(_text('near'))
        ..addElement(_text('far', x: 100000, y: 100000));

      final visible = controller.elementsIn(
        controller.viewport.visibleBounds(const Size(800, 600)),
      );

      expect(visible.map((e) => e.id), <String>['near']);
    });
  });

  group('InkPainter', () {
    test('repaints only when the ink itself changed', () {
      final controller = CanvasController()
        ..beginStroke(Offset.zero)
        ..extendStroke(const Offset(10, 10))
        ..endStroke();
      List<InkElement> ink() =>
          controller.document.elements.whereType<InkElement>().toList();
      InkPainter painter(List<InkElement> elements) => InkPainter(
        elements: elements,
        viewport: const CanvasViewport(),
        layer: InkLayer.above,
      );
      final before = painter(ink());

      expect(painter(ink()).shouldRepaint(before), isFalse);

      controller
        ..beginStroke(const Offset(0, 400))
        ..extendStroke(const Offset(10, 410))
        ..endStroke();
      expect(painter(ink()).shouldRepaint(before), isTrue);
    });
  });

  group('InkTiles', () {
    InkElement handwriting(String id, Offset at) {
      final stroke = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF1A3C8C,
        width: 2.5,
        xs: <double>[for (var i = 0; i < 60; i++) at.dx + i * 3.0],
        ys: <double>[for (var i = 0; i < 60; i++) at.dy + math.sin(i / 4) * 9],
        pressures: <double>[
          for (var i = 0; i < 60; i++) 0.3 + 0.6 * math.sin(i / 60 * math.pi),
        ],
      );
      final bounds = stroke.bounds;
      return InkElement(
        id: id,
        frame: Frame(
          x: bounds.left,
          y: bounds.top,
          width: bounds.width,
          height: bounds.height,
        ),
        createdAt: 0,
        updatedAt: 0,
        strokes: <InkStroke>[stroke],
      );
    }

    const region = Aabb(0, 0, 800, 500);
    final ink = <InkElement>[
      handwriting('a', const Offset(20, 40)),
      handwriting('b', const Offset(500, 380)),
    ];

    /// The ink drawn over [region] on white, [scale] pixels to a unit.
    Future<List<int>> draw(
      List<InkElement> elements, {
      InkTiles? tiles,
      double scale = 1.5,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xFFFFFFFF), BlendMode.src)
        ..scale(scale);
      InkPainter(
        elements: elements,
        viewport: const CanvasViewport(),
        layer: InkLayer.above,
        tiles: tiles,
        tileScale: scale,
      ).paint(canvas, Size(region.width, region.height));
      final image = await recorder.endRecording().toImage(
        (region.width * scale).round(),
        (region.height * scale).round(),
      );
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }

    test('looks as the strokes drawn themselves do', () async {
      final tiles = InkTiles(InkLayer.above);
      final strokes = await draw(ink);
      final pixels = await draw(ink, tiles: tiles);
      var apart = 0;
      for (var i = 0; i < strokes.length; i++) {
        apart += (strokes[i] - pixels[i]).abs();
      }
      expect(apart / strokes.length, lessThan(0.05));
      tiles.clear();
    });

    test('draws a tile again only once its ink changes', () async {
      final tiles = InkTiles(InkLayer.above);
      await draw(ink, tiles: tiles);
      final first = tiles.drawn;
      expect(first, 2, reason: 'one tile each, the rest empty');

      await draw(ink, tiles: tiles);
      expect(tiles.drawn, first, reason: 'nothing changed');

      await draw(<InkElement>[
        ink.first,
        handwriting('b', const Offset(500, 390)),
      ], tiles: tiles);
      expect(tiles.drawn, first + 1, reason: 'only the tile b is on');

      await draw(ink, tiles: tiles, scale: 2);
      expect(tiles.drawn, greaterThan(first + 1), reason: 'a new zoom');
      tiles.clear();
    });
  });

  group('pageRegion', () {
    test('has its corner a whole number of screen pixels from the page\'s, '
        'at any zoom', () {
      for (final zoom in <double>[0.37, 1, 1.25, 2.9]) {
        final region = pageRegion(
          CanvasViewport(origin: const Offset(123.4, 5678.9), zoom: zoom),
          const Size(1000, 700),
        );
        for (final corner in <double>[region.left, region.top]) {
          final pixels = corner * zoom / 64;
          expect(pixels, closeTo(pixels.roundToDouble(), 1e-6));
        }
      }
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

    test('keeps the corners of a shape, as OneNote keeps its shapes', () {
      // A diamond of five samples, each corner at the far side of one
      // edge: smoothed round them, it would fall short of every one.
      final diamond = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        xs: <double>[50, 100, 50, 0, 50],
        ys: <double>[0, 50, 100, 50, 0],
      );

      expect(
        StrokeGeometry.smoothPath(diamond).getBounds(),
        const Rect.fromLTRB(0, 0, 100, 100),
      );
    });

    test('still smooths the jitter of samples close together', () {
      final jitter = InkStroke.fromPoints(
        tool: InkTool.pen,
        color: 0xFF000000,
        width: 2,
        xs: <double>[0, 1, 2, 3, 4],
        ys: <double>[0, 1, 0, 1, 0],
      );

      // How far down the drawn line reaches, followed along its length.
      var lowest = 0.0;
      for (final metric in StrokeGeometry.smoothPath(jitter).computeMetrics()) {
        for (var at = 0.0; at <= metric.length; at += metric.length / 200) {
          lowest = math.max(
            lowest,
            metric.getTangentForOffset(at)!.position.dy,
          );
        }
      }
      expect(lowest, lessThan(0.9));
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
