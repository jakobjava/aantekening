/// The painted layers of the canvas: paper, ink, wet ink and selection.
library;

import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'canvas_controller.dart';
import 'canvas_viewport.dart';
import 'lasso.dart';
import 'page_space.dart' show PageSpace;
import 'selection_handles.dart';
import 'sheet_painter.dart';
import 'stroke_geometry.dart';
import 'tools.dart';

/// Draws the paper and its ruling: one paper without end, or sheets on a
/// desk ([paintSheets]).
///
/// Lines are generated for the visible region only and drawn in screen space,
/// so the cost of the background is bounded by the window size rather than by
/// how far the user has panned. It follows [view] by itself, without being
/// built again.
class BackgroundPainter extends CustomPainter {
  BackgroundPainter({
    required this.background,
    required this.view,
    this.paperWidth,
    this.sheets,
    this.desk = const Color(0xFFE4E4E4),
  }) : super(repaint: view);

  final PageBackground background;
  final ValueListenable<CanvasViewport> view;

  /// Optional page-width guide, in page units.
  final double? paperWidth;

  /// The sheets the page is shown as, or null for one paper.
  final Sheets? sheets;

  /// What lies about the sheets.
  final Color desk;

  /// Below this on-screen spacing the ruling reads as a grey wash, so it is
  /// dropped rather than drawn.
  static const double minimumScreenSpacing = 6;

  CanvasViewport get viewport => view.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (sheets case final sheets? when viewport.fold != null) {
      paintSheets(
        canvas,
        size,
        viewport,
        sheets,
        desk: desk,
        paper: Color(background.paperColor),
      );
      return;
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(background.paperColor),
    );

    final spacing = background.spacing * viewport.zoom;
    if (background.kind != PageBackgroundKind.blank &&
        spacing >= minimumScreenSpacing) {
      final paint = Paint()
        ..color = Color(background.lineColor)
        ..strokeWidth = 1
        ..isAntiAlias = false;

      switch (background.kind) {
        case PageBackgroundKind.grid:
          _drawVerticals(canvas, size, spacing, paint);
          _drawHorizontals(canvas, size, spacing, paint);
        case PageBackgroundKind.ruled:
          _drawHorizontals(canvas, size, spacing, paint);
        case PageBackgroundKind.dotted:
          _drawDots(canvas, size, spacing, paint);
        case PageBackgroundKind.blank:
          break;
      }
    }

    _drawPaperGuide(canvas, size);
  }

  void _drawVerticals(Canvas canvas, Size size, double spacing, Paint paint) {
    final first = _firstLine(viewport.origin.dx, background.spacing);
    for (
      var x = viewport.toScreen(Offset(first, 0)).dx;
      x < size.width;
      x += spacing
    ) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawHorizontals(Canvas canvas, Size size, double spacing, Paint paint) {
    final first = _firstLine(viewport.origin.dy, background.spacing);
    for (
      var y = viewport.toScreen(Offset(0, first)).dy;
      y < size.height;
      y += spacing
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDots(Canvas canvas, Size size, double spacing, Paint paint) {
    final dot = Paint()
      ..color = Color(background.lineColor)
      ..style = PaintingStyle.fill;
    final radius = (viewport.zoom).clamp(0.6, 1.6);

    final firstX = _firstLine(viewport.origin.dx, background.spacing);
    final firstY = _firstLine(viewport.origin.dy, background.spacing);
    final startX = viewport.toScreen(Offset(firstX, 0)).dx;
    final startY = viewport.toScreen(Offset(0, firstY)).dy;

    for (var y = startY; y < size.height; y += spacing) {
      for (var x = startX; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dot);
      }
    }
  }

  /// Draws the optional right-hand margin that marks the printable width.
  void _drawPaperGuide(Canvas canvas, Size size) {
    final width = paperWidth;
    if (width == null) return;
    final x = viewport.toScreen(Offset(width, 0)).dx;
    if (x < 0 || x > size.width) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Color(background.lineColor)
        ..strokeWidth = 1,
    );
  }

  /// The first ruling position at or before the visible edge.
  static double _firstLine(double originInPageSpace, double spacing) =>
      (originInPageSpace / spacing).floor() * spacing;

  @override
  bool shouldRepaint(BackgroundPainter old) =>
      old.view != view ||
      old.paperWidth != paperWidth ||
      old.sheets != sheets ||
      old.desk != desk ||
      old.background.kind != background.kind ||
      old.background.spacing != background.spacing ||
      old.background.lineColor != background.lineColor ||
      old.background.paperColor != background.paperColor;
}

/// Draws committed ink strokes.
///
/// Ink is split into two layers around the widget-based elements: highlighter
/// under them, pen over them. That reproduces what the tools mean physically —
/// a highlighter goes beneath writing, a pen on top — while keeping the text
/// and formula elements as real widgets that can be edited and selected.
///
/// Each ink element is recorded once into a picture in page space and replayed
/// under the viewport transform. Panning and zooming then cost one picture per
/// element rather than rebuilding every stroke's path on every frame.
class InkPainter extends CustomPainter {
  InkPainter({
    required this.elements,
    required this.viewport,
    required this.layer,
    this.pixelsPerUnit,
    this.tiles,
    this.tileScale = 1,
    this.zooming,
    this.pixelRatio = 1,
    this.fold,
    this.devicePixelsPerUnit = 1,
  }) : super(repaint: zooming);

  final List<InkElement> elements;
  final CanvasViewport viewport;
  final InkLayer layer;

  /// The sheets the page is shown as: each sheet's ink is drawn within it,
  /// moved down by the gaps above it. Null for one paper.
  final SheetFold? fold;

  /// Device pixels per page unit, as the page is laid out: the gaps between
  /// sheets are drawn a whole number of them.
  final double devicePixelsPerUnit;

  /// Where the ink is kept as pixels in tiles, for a view that scrolls but
  /// is not being zoomed; null to draw the strokes themselves.
  final InkTiles? tiles;

  /// Device pixels per page unit the [tiles] are drawn at.
  final double tileScale;

  /// The view, while it is being zoomed: zoomed in further than the tiles
  /// were drawn for, the strokes are drawn instead, sharp, and the ink is
  /// drawn again at every step of the zoom.
  final ValueListenable<CanvasViewport>? zooming;

  /// Device pixels per screen pixel.
  final double pixelRatio;

  /// How many pixels a page unit is drawn across, where the ink is to be
  /// kept as pixels, for a view that does not zoom; null to draw the strokes
  /// themselves every frame, sharp at any zoom.
  ///
  /// A page drawn small packs hundreds of strokes into few pixels, and each
  /// stroke's shape costs as much to draw however small it is. Kept as
  /// pixels, drawn once each time the layer is painted, every frame draws
  /// one picture.
  final double? pixelsPerUnit;

  /// The most pixels the ink is kept in; beyond that it is drawn as strokes.
  static const int _maxPixels = 4096 * 4096;

  /// Each element's strokes on each layer, recorded once.
  static final Map<InkLayer, Expando<ui.Picture>> _pictures =
      <InkLayer, Expando<ui.Picture>>{
        for (final layer in InkLayer.values)
          layer: Expando<ui.Picture>(layer.name),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final region = viewport.visibleBounds(size);
    final fold = this.fold;
    final pieces = fold == null
        ? <SheetPiece>[(area: region, down: 0)]
        : fold.piecesOf(region, devicePixelsPerUnit: devicePixelsPerUnit);
    final tiles = this.tiles;
    final zoom = zooming?.value.zoom;
    if (tiles != null && (zoom == null || zoom * pixelRatio <= tileScale)) {
      tiles.paint(
        canvas,
        region,
        elements,
        _pictureOf,
        scale: tileScale,
        pieces: fold == null ? null : pieces,
      );
      return;
    }
    if (elements.isEmpty) return;
    if (fold != null) {
      for (final piece in pieces) {
        canvas
          ..save()
          ..translate(0, piece.down)
          ..clipRect(_rectIn(piece.area, region));
        _drawStrokes(canvas, piece.area);
        canvas.restore();
      }
      return;
    }

    final scale = pixelsPerUnit;
    final width = scale == null ? 0 : (size.width * scale).ceil();
    final height = scale == null ? 0 : (size.height * scale).ceil();
    if (scale == null || width * height > _maxPixels) {
      _drawStrokes(canvas, region);
      return;
    }
    final ink = _inkIn(region);
    if (ink == null) return;

    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..transform(viewport.toMatrix().storage)
      ..drawPicture(ink);
    ink.dispose();
    final scaled = recorder.endRecording();
    final pixels = scaled.toImageSync(width, height);
    scaled.dispose();
    canvas.drawImageRect(
      pixels,
      Offset.zero & Size(width.toDouble(), height.toDouble()),
      Offset.zero & Size(width / scale, height / scale),
      Paint()
        ..filterQuality = FilterQuality.low
        // Kept as pixels, the highlighter still darkens what it lies on, and
        // inverting ink still inverts it.
        ..blendMode = layer.blendMode,
    );
    pixels.dispose();
  }

  /// [area] of the page, in the coordinates of a canvas whose origin lies
  /// at [region]'s corner.
  static Rect _rectIn(Aabb area, Aabb region) => Rect.fromLTRB(
    area.left - region.left,
    area.top - region.top,
    area.right - region.left,
    area.bottom - region.top,
  );

  /// The strokes on this layer of the elements over [visible], recorded as
  /// one picture, or null if there are none.
  ui.Picture? _inkIn(Aabb visible) {
    final strokes = ui.PictureRecorder();
    final target = Canvas(strokes);
    var drawn = false;
    for (final element in elements) {
      if (!element.bounds.intersects(visible)) continue;
      final picture = _pictureOf(element);
      if (picture == null) continue;
      target.drawPicture(picture);
      drawn = true;
    }
    final ink = strokes.endRecording();
    if (drawn) return ink;
    ink.dispose();
    return null;
  }

  /// Draws the strokes over [visible] as they are, sharp at any zoom.
  void _drawStrokes(Canvas canvas, Aabb visible) {
    final ink = _inkIn(visible);
    if (ink == null) return;
    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);
    // Inverting ink is drawn as one, so where two strokes cross the
    // crossing is inverted once, as the rest of them is.
    if (layer == InkLayer.inverting) {
      canvas.saveLayer(
        Rect.fromLTRB(visible.left, visible.top, visible.right, visible.bottom),
        Paint()..blendMode = layer.blendMode,
      );
    }
    canvas.drawPicture(ink);
    if (layer == InkLayer.inverting) canvas.restore();
    canvas.restore();
    ink.dispose();
  }

  /// The element's strokes on this layer, recorded once. Elements are
  /// immutable, so an edited element is a new object with a new picture.
  ui.Picture? _pictureOf(InkElement element) {
    final cache = _pictures[layer]!;
    final cached = cache[element];
    if (cached != null) return cached;
    if (!element.strokes.any(layer.accepts)) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in element.strokes) {
      if (layer.accepts(stroke)) paintStroke(canvas, stroke);
    }
    return cache[element] = recorder.endRecording();
  }

  /// Paints one stroke in page space. Inverting ink is painted white, to
  /// be laid on what is beneath with [InkLayer.inverting]'s blend.
  static void paintStroke(Canvas canvas, InkStroke stroke) {
    if (stroke.tool == InkTool.highlighter) {
      canvas.drawPath(
        StrokeGeometry.chiselPath(stroke),
        Paint()
          ..color = Color(stroke.color)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          // Multiply keeps a highlighter from covering what it marks, and lets
          // overlapping strokes deepen the way a real marker does.
          ..blendMode = BlendMode.multiply,
      );
      return;
    }

    final paint = Paint()
      ..color = stroke.color == NoteColors.inverse
          ? const Color(0xFFFFFFFF)
          : Color(stroke.color)
      ..isAntiAlias = true;

    if (stroke.tool != InkTool.marker &&
        StrokeGeometry.hasPressureVariation(stroke)) {
      canvas.drawPath(StrokeGeometry.pressurePath(stroke), paint);
      return;
    }

    canvas.drawPath(
      StrokeGeometry.smoothPath(stroke),
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width,
    );
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      old.viewport != viewport ||
      old.layer != layer ||
      old.pixelsPerUnit != pixelsPerUnit ||
      !identical(old.tiles, tiles) ||
      old.tileScale != tileScale ||
      old.zooming != zooming ||
      old.pixelRatio != pixelRatio ||
      old.fold != fold ||
      old.devicePixelsPerUnit != devicePixelsPerUnit ||
      !_sameElements(old.elements, elements);
}

/// One layer of ink kept as pixels, in tiles on a grid fixed to the page,
/// drawn as many device pixels to a page unit as it is painted at.
///
/// Impeller keeps nothing between frames: every stroke on screen was
/// drawn again, shape and all, at every frame of a scroll. Kept as tiles,
/// a frame draws a picture of each, and a tile is drawn again only once
/// the ink on it changes — or the zoom does, which leaves none of them. A
/// tile lands on the screen's own pixels, as the page is moved by whole
/// ones ([PageSpace]) from a corner a whole number of them from the page's
/// ([pageRegion]), so the ink looks as it does drawn as strokes.
class InkTiles {
  InkTiles(this.layer);

  final InkLayer layer;

  /// Device pixels per page unit the tiles are drawn at.
  double _scale = 0;

  /// The side of a tile, in device pixels.
  static const int side = 512;

  final Map<(int, int), _InkTile> _tiles = <(int, int), _InkTile>{};

  /// How many tiles have been drawn, again or for the first time.
  @visibleForTesting
  int get drawn => _drawn;
  int _drawn = 0;

  /// Lets go of every tile.
  void clear() {
    for (final tile in _tiles.values) {
      tile.image.dispose();
    }
    _tiles.clear();
  }

  /// Draws [region] of the page, the page point at its corner at
  /// [canvas]'s origin, from [elements], whose strokes on this layer
  /// [pictureOf] gives, [scale] device pixels to a page unit, drawing again
  /// the tiles whose ink has changed.
  ///
  /// On sheets, each of [pieces] is drawn within its sheet, moved down as
  /// it says; a tile over two sheets is drawn on each, cut at its edge.
  void paint(
    Canvas canvas,
    Aabb region,
    List<InkElement> elements,
    ui.Picture? Function(InkElement element) pictureOf, {
    required double scale,
    List<SheetPiece>? pieces,
  }) {
    if (scale != _scale) {
      clear();
      _scale = scale;
    }
    final shown = <(int, int)>{};
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..blendMode = layer.blendMode;
    if (pieces == null) {
      _paintArea(canvas, region, region, elements, pictureOf, shown, paint);
    } else {
      for (final piece in pieces) {
        canvas
          ..save()
          ..translate(0, piece.down)
          ..clipRect(InkPainter._rectIn(piece.area, region));
        _paintArea(
          canvas,
          piece.area,
          region,
          elements,
          pictureOf,
          shown,
          paint,
        );
        canvas.restore();
      }
    }
    // What is no longer about the view, or no longer inked, is let go.
    _tiles.removeWhere((key, tile) {
      if (shown.contains(key)) return false;
      tile.image.dispose();
      return true;
    });
  }

  /// Draws the tiles over [area], [region]'s corner at [canvas]'s origin,
  /// adding each drawn to [shown].
  void _paintArea(
    Canvas canvas,
    Aabb area,
    Aabb region,
    List<InkElement> elements,
    ui.Picture? Function(InkElement element) pictureOf,
    Set<(int, int)> shown,
    Paint paint,
  ) {
    final unit = side / _scale;
    final first = ((area.left / unit).floor(), (area.top / unit).floor());
    final last = ((area.right / unit).ceil(), (area.bottom / unit).ceil());
    for (var row = first.$2; row < last.$2; row++) {
      for (var column = first.$1; column < last.$1; column++) {
        final place = Aabb(
          column * unit,
          row * unit,
          (column + 1) * unit,
          (row + 1) * unit,
        );
        final inked = <InkElement>[
          for (final element in elements)
            if (element.bounds.intersects(place) && pictureOf(element) != null)
              element,
        ];
        if (inked.isEmpty) continue;
        final key = (column, row);
        shown.add(key);
        var tile = _tiles[key];
        if (tile == null || !_sameElements(tile.elements, inked)) {
          tile?.image.dispose();
          tile = _tiles[key] = _InkTile(inked, _draw(place, inked, pictureOf));
        }
        canvas.drawImageRect(
          tile.image,
          const Rect.fromLTWH(0, 0, side + 0.0, side + 0.0),
          Rect.fromLTRB(
            place.left - region.left,
            place.top - region.top,
            place.right - region.left,
            place.bottom - region.top,
          ),
          paint,
        );
      }
    }
  }

  ui.Image _draw(
    Aabb place,
    List<InkElement> inked,
    ui.Picture? Function(InkElement element) pictureOf,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(_scale)
      ..translate(-place.left, -place.top);
    for (final element in inked) {
      canvas.drawPicture(pictureOf(element)!);
    }
    final picture = recorder.endRecording();
    _drawn++;
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return image;
  }
}

class _InkTile {
  _InkTile(this.elements, this.image);

  /// The ink on it, which it was drawn from.
  final List<InkElement> elements;
  final ui.Image image;
}

/// Which strokes an [InkPainter] draws.
enum InkLayer {
  /// Highlighter, drawn beneath the element widgets.
  beneath(BlendMode.multiply),

  /// Pen, pencil and marker, drawn above them.
  above(BlendMode.srcOver),

  /// Ink in the inverse of what is beneath it ([NoteColors.inverse]),
  /// drawn over everything else, since it is the inverse of all of it.
  inverting(BlendMode.difference);

  const InkLayer(this.blendMode);

  /// How the layer is laid over what is beneath it: a white stroke
  /// differenced from what it covers is its inverse.
  final BlendMode blendMode;

  bool accepts(InkStroke stroke) => switch (this) {
    InkLayer.inverting => stroke.color == NoteColors.inverse,
    _ when stroke.color == NoteColors.inverse => false,
    InkLayer.beneath => stroke.tool == InkTool.highlighter,
    InkLayer.above => stroke.tool != InkTool.highlighter,
  };
}

/// Draws the stroke currently under the pointer, or the shape it became.
///
/// The in-progress stroke lives in its own layer so that each new sample
/// repaints only this painter, leaving the committed ink and the element
/// widgets untouched. That is what keeps the line under the pen from lagging
/// on a page that already holds a lot of content.
class WetInkPainter extends CustomPainter {
  WetInkPainter({
    required this.controller,
    required this.viewport,
    this.fold,
    this.devicePixelsPerUnit = 1,
  }) : super(repaint: controller.wetInk);

  /// Where the strokes in progress come from.
  final CanvasController controller;

  final CanvasViewport viewport;

  /// The sheets the page is shown as, as [InkPainter.fold].
  final SheetFold? fold;
  final double devicePixelsPerUnit;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = controller.wetStrokes;
    if (strokes.isEmpty) return;
    final region = viewport.visibleBounds(size);
    final fold = this.fold;
    if (fold == null) {
      _paint(canvas, strokes, region);
      return;
    }
    for (final piece in fold.piecesOf(
      region,
      devicePixelsPerUnit: devicePixelsPerUnit,
    )) {
      canvas
        ..save()
        ..translate(0, piece.down)
        ..clipRect(InkPainter._rectIn(piece.area, region));
      _paint(canvas, strokes, piece.area);
      canvas.restore();
    }
  }

  void _paint(Canvas canvas, List<InkStroke> strokes, Aabb visible) {
    final inverting = strokes.first.color == NoteColors.inverse;
    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);
    if (inverting) {
      canvas.saveLayer(
        Rect.fromLTRB(visible.left, visible.top, visible.right, visible.bottom),
        Paint()..blendMode = InkLayer.inverting.blendMode,
      );
    }
    for (final stroke in strokes) {
      InkPainter.paintStroke(canvas, stroke);
    }
    if (inverting) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(WetInkPainter old) =>
      old.controller != controller ||
      old.viewport != viewport ||
      old.fold != fold ||
      old.devicePixelsPerUnit != devicePixelsPerUnit;
}

/// How far round the eraser reaches, in page units, seen from [viewport]:
/// about the same on screen at any zoom, within reason.
double eraserRadiusIn(CanvasViewport viewport) =>
    viewport.toPageDistance(12).clamp(4.0, 64.0);

/// Where the pointer, hovering or pressed, is over the page, and whether it
/// is a pen's other end, which erases.
typedef NibPlace = ({Offset at, bool erasing});

/// Draws, in place of the pointer's own cursor, what the tool in hand would
/// touch the page with: the pen's nib as thick as its line and in its
/// colour, the highlighter's chisel, the eraser's reach — each ringed in
/// light and dark, so it shows on paper and on a dark picture alike.
class NibPainter extends CustomPainter {
  /// Drawn again as the pointer moves, as the view zooms, and as the pen
  /// changes.
  NibPainter({required this.place, required this.controller})
    : super(
        repaint: Listenable.merge(<Listenable>[
          place,
          controller.view,
          controller.contents,
        ]),
      );

  /// Where the pointer is on screen, or null where there is none to draw.
  final ValueListenable<NibPlace?> place;
  final CanvasController controller;

  /// Whether [tool] is drawn this way rather than with a system cursor.
  static bool draws(CanvasTool tool) =>
      tool == CanvasTool.pen ||
      tool == CanvasTool.highlighter ||
      tool == CanvasTool.eraser;

  @override
  void paint(Canvas canvas, Size size) {
    final place = this.place.value;
    final tool = controller.tool;
    if (place == null || !(place.erasing || draws(tool))) return;
    final viewport = controller.viewport;
    // Where the tool would touch the page, drawn in the view's space: on a
    // sheet, kept within it.
    final at = viewport.toView(viewport.toPage(place.at));
    canvas
      ..save()
      ..transform(viewport.toMatrix().storage);

    // What the nib covers, round or square, to be ringed just outside it.
    final Rect nib;
    final bool round;
    if (place.erasing || tool == CanvasTool.eraser) {
      nib = Rect.fromCircle(center: at, radius: eraserRadiusIn(viewport));
      round = true;
    } else {
      final pen = controller.pen;
      final sample = InkStroke.fromPoints(
        tool: pen.tool,
        color: pen.strokeColor,
        width: pen.width,
        xs: <double>[at.dx],
        ys: <double>[at.dy],
      );
      if (pen.tool == InkTool.highlighter) {
        nib = StrokeGeometry.chiselPath(sample).getBounds();
        round = false;
        InkPainter.paintStroke(canvas, sample);
      } else {
        // As thick as the pen's line, not its dot, which is rounder.
        nib = Rect.fromCircle(center: at, radius: pen.width / 2);
        round = true;
        final inverting = pen.strokeColor == NoteColors.inverse;
        canvas.drawOval(
          nib,
          Paint()
            ..color = inverting ? const Color(0xFFFFFFFF) : Color(pen.color)
            ..blendMode = inverting
                ? InkLayer.inverting.blendMode
                : BlendMode.srcOver,
        );
      }
    }
    // A light ring and a dark one round it, a pixel each.
    final pixel = 1 / viewport.zoom;
    for (final (out, colour) in <(double, Color)>[
      (1, const Color(0xFFFFFFFF)),
      (2, const Color(0x80000000)),
    ]) {
      final ring = nib.inflate(out * pixel);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pixel
        ..color = colour;
      if (round) {
        canvas.drawOval(ring, paint);
      } else {
        canvas.drawRect(ring, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(NibPainter old) =>
      old.place != place || old.controller != controller;
}

/// Draws the selection box, its handles, and the marquee or lasso being
/// drawn.
///
/// Every selected object gets a thin outline of its own; the box that can be
/// dragged, resized and turned goes round the whole selection. Only the handles
/// the selection actually supports are drawn — a text box offers its left
/// and right sides, a picture its corners and all four sides — because a
/// handle that does nothing is worse than none.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.selected,
    required this.view,
    required this.accent,
    this.marquee,
    this.lasso,
    this.showHandles = true,
  }) : super(repaint: view);

  final List<NoteElement> selected;

  /// The view, which the painter follows by itself.
  final ValueListenable<CanvasViewport> view;

  CanvasViewport get viewport => view.value;
  final Color accent;

  /// The rubber-band rectangle being dragged, in page space.
  final Aabb? marquee;

  /// The loop being drawn round what to select.
  final Lasso? lasso;

  /// Whether to draw the box and its handles, or only the outlines.
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (selected.length > 1) {
      for (final element in selected) {
        final frame = SelectionFrame.around(<NoteElement>[element]);
        if (frame != null) {
          canvas.drawPath(
            _polygon(SelectionHandles.outlineOf(frame, viewport)),
            thin,
          );
        }
      }
    }

    final frame = SelectionFrame.around(selected);
    if (frame != null) {
      SelectionHandles.paintOutline(
        canvas,
        SelectionHandles.outlineOf(frame, viewport),
        accent,
      );
      if (showHandles) _drawHandles(canvas, frame);
    }

    final band = marquee;
    if (band != null) {
      final rect = Rect.fromPoints(
        viewport.toScreen(Offset(band.left, band.top)),
        viewport.toScreen(Offset(band.right, band.bottom)),
      );
      canvas
        ..drawRect(rect, Paint()..color = accent.withValues(alpha: 0.12))
        ..drawRect(rect, outline);
    }

    if (lasso case final lasso?) {
      final loop = _polygon(<Offset>[
        for (final point in lasso.points) viewport.toScreen(point),
      ]);
      canvas
        ..drawPath(loop, Paint()..color = accent.withValues(alpha: 0.12))
        ..drawPath(loop, outline);
    }
  }

  void _drawHandles(Canvas canvas, SelectionFrame frame) {
    final fill = Paint()..color = accent;
    final ring = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final positions = SelectionHandles.positionsFor(selected, viewport);

    final knob = positions[SelectionHandle.rotate];
    if (knob != null) {
      final outline = SelectionHandles.outlineOf(frame, viewport);
      canvas
        ..drawLine(
          (outline[0] + outline[1]) / 2,
          knob,
          Paint()
            ..color = accent
            ..strokeWidth = 1.2,
        )
        ..drawRect(
          Rect.fromCircle(center: knob, radius: SelectionHandles.size * 0.6),
          fill,
        )
        ..drawRect(
          Rect.fromCircle(center: knob, radius: SelectionHandles.size * 0.6),
          ring,
        );
    }

    SelectionHandles.paintHandles(
      canvas,
      positions,
      accent,
      rotation: frame.rotation,
    );
  }

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.view != view ||
      old.marquee != marquee ||
      !identical(old.lasso, lasso) ||
      old.accent != accent ||
      old.showHandles != showHandles ||
      !_sameElements(old.selected, selected);
}

/// Whether [a] and [b] hold the very same elements in the same order: a
/// list made again of what has not changed draws nothing new.
bool _sameElements(List<NoteElement> a, List<NoteElement> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}
