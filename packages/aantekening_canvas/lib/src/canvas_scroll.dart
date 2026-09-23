/// How far a page scrolls, and where the view is on it.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'canvas_controller.dart';
import 'canvas_viewport.dart';

/// Where the view is along one axis of the page, for a scrollbar or a map
/// of the page to show.
///
/// A page runs on without end to the right and down, so how far it scrolls
/// is made up: from its top-left corner to half a view past its content, and
/// never short of where the view already is.
@immutable
class ScrollSpan {
  const ScrollSpan({
    required this.extent,
    required this.start,
    required this.length,
  });

  /// The span of [controller]'s page and view along [axis].
  factory ScrollSpan.of(CanvasController controller, Axis axis) {
    final visible = controller.viewport.visibleBounds(controller.viewSize);
    final content = controller.contentBounds;
    final vertical = axis == Axis.vertical;
    final start = vertical ? visible.top : visible.left;
    final length = vertical ? visible.height : visible.width;
    final contentEnd = content.isEmpty
        ? 0.0
        : (vertical ? content.bottom : content.right);
    return ScrollSpan(
      extent: math.max(start + length, contentEnd + length / 2),
      start: start,
      length: length,
    );
  }

  /// How far the page scrolls along the axis, in page units.
  final double extent;

  /// Where the view begins along the axis, and how much it shows.
  final double start;
  final double length;

  /// [start] and [length] as parts of [extent].
  double get startFraction => extent > 0 ? start / extent : 0;
  double get lengthFraction =>
      extent > 0 ? (length / extent).clamp(0.0, 1.0) : 1;

  @override
  bool operator ==(Object other) =>
      other is ScrollSpan &&
      other.extent == extent &&
      other.start == start &&
      other.length == length;

  @override
  int get hashCode => Object.hash(extent, start, length);
}

/// Scrolling a canvas along one axis.
extension ScrollTo on CanvasController {
  /// Scrolls the view along [axis] so that it begins at [start], in page
  /// units, the other axis left as it is.
  void scrollTo(Axis axis, double start) {
    final origin = viewport.origin;
    viewport = CanvasViewport(
      origin: axis == Axis.vertical
          ? Offset(origin.dx, start)
          : Offset(start, origin.dy),
      zoom: viewport.zoom,
    );
  }
}
