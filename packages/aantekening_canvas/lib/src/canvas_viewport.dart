/// The mapping between page space and screen space.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// An immutable pan-and-zoom transform over the infinite canvas.
///
/// Page space runs on without end to the right and downwards, and is
/// independent of the window, so a note laid out on a phone opens identically
/// on a desktop. Everything stored in a [PageDocument] is in page space; this
/// class is the only place that converts to and from pixels.
///
/// A page shown as sheets is seen through a [fold]: page space is cut into
/// the sheets' bands, and the view lays them out with gaps between. The view
/// pans and zooms over that laid-out space — the view's space — and page
/// space is reached through the fold.
@immutable
class CanvasViewport {
  const CanvasViewport({this.origin = Offset.zero, this.zoom = 1, this.fold});

  /// The point of the view's space shown at the top-left of the view: of
  /// page space, but for a page shown as sheets.
  final Offset origin;

  /// Pixels per page unit.
  final double zoom;

  /// The sheets the page is shown as, or null for one paper.
  final SheetFold? fold;

  /// This view moved to [origin], or zoomed to [zoom], through the same
  /// fold.
  CanvasViewport copyWith({Offset? origin, double? zoom}) => CanvasViewport(
    origin: origin ?? this.origin,
    zoom: zoom ?? this.zoom,
    fold: fold,
  );

  /// This view, through [fold] instead.
  CanvasViewport withFold(SheetFold? fold) => fold == this.fold
      ? this
      : CanvasViewport(origin: origin, zoom: zoom, fold: fold);

  /// Where the page point [page] lies in the view's space.
  Offset toView(Offset page) => fold?.fold(page) ?? page;

  /// The page point shown at [view] in the view's space.
  Offset fromView(Offset view) => fold?.unfold(view) ?? view;

  /// Where [frame] lies in the view's space: moved whole, with the sheet
  /// its middle is on.
  Frame frameInView(Frame frame) => fold?.foldFrame(frame) ?? frame;

  /// Converts [page], a point of something moved whole with the sheet
  /// [middle] is on, to screen pixels: a corner of a box, say, which stays
  /// a box across a gap between sheets.
  Offset toScreenWith(Offset page, Offset middle) {
    final fold = this.fold;
    final shift = fold?.shiftAt(middle.dy) ?? 0;
    final across = fold?.acrossAt(middle.dy) ?? 0;
    return Offset(page.dx + across - origin.dx, page.dy + shift - origin.dy) *
        zoom;
  }

  /// Zoom bounds, chosen to cover reading a whole lecture at a glance and
  /// annotating a formula closely, without letting rounding become visible.
  static const double minZoom = 0.05;
  static const double maxZoom = 16;

  /// Converts a page-space point to screen pixels.
  Offset toScreen(Offset page) => (toView(page) - origin) * zoom;

  /// Converts a screen-space point to page coordinates.
  Offset toPage(Offset screen) => fromView(_viewAt(screen));

  /// The point of the view's space at [screen].
  Offset _viewAt(Offset screen) =>
      Offset(screen.dx / zoom + origin.dx, screen.dy / zoom + origin.dy);

  /// Converts a screen-space distance to page units.
  double toPageDistance(double screenDistance) => screenDistance / zoom;

  /// The transform from the view's space to the screen.
  Matrix4 toMatrix() => Matrix4.identity()
    ..scaleByDouble(zoom, zoom, 1, 1)
    ..translateByDouble(-origin.dx, -origin.dy, 0, 1);

  /// The region of page space currently visible in a view of [size].
  Aabb visibleBounds(Size size) {
    final fold = this.fold;
    if (fold != null) {
      return fold.seenIn(
        Rect.fromPoints(origin, _viewAt(size.bottomRight(Offset.zero))),
      );
    }
    final topLeft = fromView(origin);
    final bottomRight = fromView(_viewAt(Offset(size.width, size.height)));
    return Aabb(topLeft.dx, topLeft.dy, bottomRight.dx, bottomRight.dy);
  }

  /// Returns a viewport panned by a screen-space [delta].
  CanvasViewport panBy(Offset delta) => copyWith(origin: origin - delta / zoom);

  /// Returns a viewport zoomed to [targetZoom], keeping the page point beneath
  /// [screenFocus] pinned in place.
  ///
  /// Anchoring on the cursor (or the pinch centre) is what makes zooming feel
  /// like moving a sheet of paper rather than jumping to a new position.
  CanvasViewport zoomAround(double targetZoom, Offset screenFocus) {
    final clamped = targetZoom.clamp(minZoom, maxZoom);
    if (clamped == zoom) return this;
    // In the view's space, so that it holds over the gaps between sheets
    // and beside them too.
    final focus = _viewAt(screenFocus);
    return copyWith(
      origin: Offset(
        focus.dx - screenFocus.dx / clamped,
        focus.dy - screenFocus.dy / clamped,
      ),
      zoom: clamped,
    );
  }

  /// Returns a viewport that frames [bounds] of the page within a view of
  /// [size].
  CanvasViewport fit(Aabb bounds, Size size, {double padding = 48}) {
    if (bounds.isEmpty || size.isEmpty) {
      return CanvasViewport(fold: fold);
    }
    final shown = inView(bounds);
    final scaleX = (size.width - padding * 2) / shown.width;
    final scaleY = (size.height - padding * 2) / shown.height;
    final target = math.min(scaleX, scaleY).clamp(minZoom, maxZoom);
    return copyWith(
      origin: Offset(
        shown.centerX - size.width / (2 * target),
        shown.centerY - size.height / (2 * target),
      ),
      zoom: target,
    );
  }

  /// [bounds] of the page as the view's space lays it out: taller by the
  /// gaps between the sheets it spans, and moved right as the sheet its
  /// middle is on.
  Aabb inView(Aabb bounds) {
    final fold = this.fold;
    if (fold == null) return bounds;
    final across = fold.acrossAt(bounds.centerY);
    return Aabb(
      bounds.left + across,
      fold.foldY(bounds.top),
      bounds.right + across,
      fold.foldEnd(bounds.bottom),
    );
  }

  /// Returns a viewport centred on a page-space point at the current zoom.
  CanvasViewport centeredOn(Offset page, Size size) {
    final at = toView(page);
    return copyWith(
      origin: Offset(
        at.dx - size.width / (2 * zoom),
        at.dy - size.height / (2 * zoom),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasViewport &&
      other.origin == origin &&
      other.zoom == zoom &&
      other.fold == fold;

  @override
  int get hashCode => Object.hash(origin, zoom, fold);

  @override
  String toString() => 'CanvasViewport(origin: $origin, zoom: $zoom)';
}

/// The part [area] of the page on one sheet, laid out [down] page units
/// further down, and [across] further right, than where it lies.
typedef SheetPiece = ({Aabb area, double down, double across});

/// Sheets laid out one under another with a gap between each: the page cut
/// into bands, each as tall as its sheet, and each moved down by the gaps
/// above it — and a sheet narrower than the widest moved right, to lie in
/// the middle under it.
///
/// The page's content is where it is either way; only where it is shown
/// changes, so a page shown as sheets and as one paper again is as it was.
@immutable
class SheetFold {
  /// [count] sheets, each [width] by [height].
  SheetFold({
    required double width,
    required double height,
    required int count,
    double gap = defaultGap,
  }) : this.sized(<Size>[
         for (var i = 0; i < math.max(1, count); i++) Size(width, height),
       ], gap: gap);

  /// A sheet of each of [sizes], the first first.
  SheetFold.sized(List<Size> sizes, {this.gap = defaultGap})
    : sizes = List<Size>.unmodifiable(sizes),
      width = sizes.map((size) => size.width).reduce(math.max),
      _tops = _topsOf(sizes);

  /// The fold of [sheets].
  factory SheetFold.of(Sheets sheets) => SheetFold.sized(<Size>[
    for (var i = 0; i < sheets.count; i++)
      Size(sheets.widthOf(i), sheets.heightOf(i)),
  ]);

  static List<double> _topsOf(List<Size> sizes) {
    final tops = <double>[0];
    for (final size in sizes) {
      tops.add(tops.last + size.height);
    }
    return tops;
  }

  /// The gap between two sheets, in page units.
  static const double defaultGap = 28;

  /// How large each sheet is, in page units.
  final List<Size> sizes;

  /// How wide the widest sheet is.
  final double width;
  final double gap;

  /// Where each sheet's top lies on the page, and after them the last's
  /// bottom.
  final List<double> _tops;

  int get count => sizes.length;

  /// How wide and tall the sheet [index] is: past the last, as the last is.
  double widthOf(int index) => sizes[index.clamp(0, count - 1)].width;
  double heightOf(int index) => sizes[index.clamp(0, count - 1)].height;

  /// How far right the sheet [index] is laid out, to lie in the middle under
  /// the widest.
  double acrossOf(int index) => (width - widthOf(index)) / 2;

  /// Where the top of the sheet [index] lies on the page: past the last, as
  /// though there were more sheets as tall as it.
  double topOf(int index) {
    if (index <= 0) return 0;
    if (index <= count) return _tops[index];
    return _tops[count] + (index - count) * heightOf(count - 1);
  }

  /// Where the top of the sheet [index] lies in the view's space.
  double viewTopOf(int index) => topOf(index) + index * gap;

  /// How tall the sheets are laid out, gaps and all.
  double get extent => _tops[count] + (count - 1) * gap;

  /// The sheet the page's [y] lies on, however far below the last.
  int sheetAt(double y) => sheetOn(_tops, y, heightOf(count - 1));

  /// The sheet the view's [view] lies on or in the gap below, of the sheets
  /// there are.
  int sheetAtView(double view) {
    var low = 0;
    var high = count - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (viewTopOf(middle) <= view) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// Where the page's [y] lies in the view's space.
  double foldY(double y) => y + shiftAt(y);

  /// Where the page's [y] lies in the view's space, as the end of something
  /// above it: a sheet's bottom edge is the end of that sheet, not the
  /// start of the next.
  double foldEnd(double y) {
    final sheet = sheetAt(y);
    final ending = sheet > 0 && topOf(sheet) == y ? sheet - 1 : sheet;
    return y + gap * ending;
  }

  /// How far down the view's space lays out the page's [y]: by the gaps
  /// above its sheet.
  double shiftAt(double y) => gap * sheetAt(y);

  /// How far right the view's space lays out the page's [y]: as its sheet.
  double acrossAt(double y) => acrossOf(sheetAt(y));

  /// Where [frame] lies in the view's space: moved whole with the sheet its
  /// middle is on, so that what straddles two sheets is not torn apart.
  Frame foldFrame(Frame frame) {
    final sheet = sheetAt(frame.y + frame.height / 2);
    final down = gap * sheet;
    final across = acrossOf(sheet);
    return down == 0 && across == 0 ? frame : frame.translate(across, down);
  }

  /// The parts of [region] of the page that lie on sheets, each with how
  /// much further down and right the view's space lays it out than it does
  /// [region]'s top: each a whole number of device pixels at
  /// [devicePixelsPerUnit], so that what is drawn in pixels stays on the
  /// screen's own.
  List<SheetPiece> piecesOf(Aabb region, {double devicePixelsPerUnit = 1}) {
    final first = sheetAt(region.top);
    final last = math.min(sheetAt(region.bottom), count - 1);
    double whole(double units) =>
        (units * devicePixelsPerUnit).roundToDouble() / devicePixelsPerUnit;
    return <SheetPiece>[
      for (var sheet = first; sheet <= last; sheet++)
        if (Aabb(
              math.max(region.left, 0.0),
              math.max(region.top, topOf(sheet)),
              math.min(region.right, widthOf(sheet)),
              math.min(region.bottom, topOf(sheet + 1)),
            )
            case final area when !area.isEmpty)
          (
            area: area,
            down: whole(gap * (sheet - first)),
            across: whole(acrossOf(sheet) - acrossOf(first)),
          ),
    ];
  }

  /// Where [page] lies in the view's space.
  Offset fold(Offset page) =>
      Offset(page.dx + acrossAt(page.dy), foldY(page.dy));

  /// The page point at [view]: on a sheet, the point under it; beside one,
  /// the nearest of its edge; in a gap, the nearer sheet's edge. Nothing
  /// is written off the sheets.
  Offset unfold(Offset view) {
    var sheet = sheetAtView(view.dy);
    final within = view.dy - viewTopOf(sheet);
    final height = heightOf(sheet);
    final double y;
    if (within <= height) {
      y = topOf(sheet) + math.max(0.0, within);
    } else if (within - height < gap / 2 || sheet == count - 1) {
      // Just within the sheet above.
      y = topOf(sheet + 1) - _edge;
    } else {
      sheet++;
      y = topOf(sheet);
    }
    return Offset((view.dx - acrossOf(sheet)).clamp(0.0, widthOf(sheet)), y);
  }

  /// The part of the page seen in [view], of the view's space: from the
  /// sheet at its top to that at its bottom, and across as far as any of
  /// them is seen.
  Aabb seenIn(Rect view) {
    final top = unfold(view.topLeft).dy;
    final bottom = unfold(view.bottomRight).dy;
    var left = width;
    var right = 0.0;
    final last = math.min(sheetAt(bottom), count - 1);
    for (var sheet = math.min(sheetAt(top), last); sheet <= last; sheet++) {
      final across = acrossOf(sheet);
      left = math.min(left, (view.left - across).clamp(0.0, widthOf(sheet)));
      right = math.max(right, (view.right - across).clamp(0.0, widthOf(sheet)));
    }
    return Aabb(left, top, math.max(left, right), bottom);
  }

  /// How far inside a sheet's bottom edge a point in the gap below it is
  /// taken to lie, to be on that sheet.
  static const double _edge = 1e-3;

  /// Where sheet [index] lies in the view's space.
  Rect sheetInView(int index) => Rect.fromLTWH(
    acrossOf(index),
    viewTopOf(index),
    widthOf(index),
    heightOf(index),
  );

  /// The sheet [view] lies on or nearest, in the view's space.
  int sheetNear(double view) => sheetAtView(view + gap / 2);

  @override
  bool operator ==(Object other) =>
      other is SheetFold && other.gap == gap && listEquals(other.sizes, sizes);

  @override
  int get hashCode => Object.hash(Object.hashAll(sizes), gap);
}
