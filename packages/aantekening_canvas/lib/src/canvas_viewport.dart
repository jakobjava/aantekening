/// The mapping between page space and screen space.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

/// An immutable pan-and-zoom transform over the infinite canvas.
///
/// Page space runs on without end to the right and downwards, and is
/// independent of the window, so a note laid out on a phone opens identically
/// on a desktop. Everything stored in a [PageDocument] is in page space; this
/// class is the only place that converts to and from pixels.
@immutable
class CanvasViewport {
  const CanvasViewport({this.origin = Offset.zero, this.zoom = 1});

  /// The page-space point shown at the top-left of the view.
  final Offset origin;

  /// Pixels per page unit.
  final double zoom;

  /// Zoom bounds, chosen to cover reading a whole lecture at a glance and
  /// annotating a formula closely, without letting rounding become visible.
  static const double minZoom = 0.05;
  static const double maxZoom = 16;

  /// Converts a page-space point to screen pixels.
  Offset toScreen(Offset page) => (page - origin) * zoom;

  /// Converts a screen-space point to page coordinates.
  Offset toPage(Offset screen) =>
      Offset(screen.dx / zoom + origin.dx, screen.dy / zoom + origin.dy);

  /// Converts a screen-space distance to page units.
  double toPageDistance(double screenDistance) => screenDistance / zoom;

  /// The transform applied to the element layer and to the ink painters.
  Matrix4 toMatrix() => Matrix4.identity()
    ..scaleByDouble(zoom, zoom, 1, 1)
    ..translateByDouble(-origin.dx, -origin.dy, 0, 1);

  /// The region of page space currently visible in a view of [size].
  Aabb visibleBounds(Size size) => Aabb(
    origin.dx,
    origin.dy,
    origin.dx + size.width / zoom,
    origin.dy + size.height / zoom,
  );

  /// Returns a viewport panned by a screen-space [delta].
  CanvasViewport panBy(Offset delta) =>
      CanvasViewport(origin: origin - delta / zoom, zoom: zoom);

  /// Returns a viewport zoomed to [targetZoom], keeping the page point beneath
  /// [screenFocus] pinned in place.
  ///
  /// Anchoring on the cursor (or the pinch centre) is what makes zooming feel
  /// like moving a sheet of paper rather than jumping to a new position.
  CanvasViewport zoomAround(double targetZoom, Offset screenFocus) {
    final clamped = targetZoom.clamp(minZoom, maxZoom);
    if (clamped == zoom) return this;
    final pageFocus = toPage(screenFocus);
    return CanvasViewport(
      origin: Offset(
        pageFocus.dx - screenFocus.dx / clamped,
        pageFocus.dy - screenFocus.dy / clamped,
      ),
      zoom: clamped,
    );
  }

  /// Returns a viewport that frames [bounds] within a view of [size].
  CanvasViewport fit(Aabb bounds, Size size, {double padding = 48}) {
    if (bounds.isEmpty || size.isEmpty) {
      return const CanvasViewport();
    }
    final scaleX = (size.width - padding * 2) / bounds.width;
    final scaleY = (size.height - padding * 2) / bounds.height;
    final target = math.min(scaleX, scaleY).clamp(minZoom, maxZoom);
    return CanvasViewport(
      origin: Offset(
        bounds.centerX - size.width / (2 * target),
        bounds.centerY - size.height / (2 * target),
      ),
      zoom: target,
    );
  }

  /// Returns a viewport centred on a page-space point at the current zoom.
  CanvasViewport centeredOn(Offset page, Size size) => CanvasViewport(
    origin: Offset(
      page.dx - size.width / (2 * zoom),
      page.dy - size.height / (2 * zoom),
    ),
    zoom: zoom,
  );

  @override
  bool operator ==(Object other) =>
      other is CanvasViewport && other.origin == origin && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(origin, zoom);

  @override
  String toString() => 'CanvasViewport(origin: $origin, zoom: $zoom)';
}
