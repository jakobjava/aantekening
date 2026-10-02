/// How far a page scrolls, and where the view is on it.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'canvas_controller.dart';

/// Where the view is along one axis of the page, for a scrollbar or a map
/// of the page to show, in the view's space, from as far back as the view
/// goes ([CanvasController.originRange]).
///
/// One paper runs on without end to the right and down, so how far it
/// scrolls is made up: from its top-left corner to half a view past its
/// content, and never short of where the view already is. Sheets scroll as
/// far as the view goes about them.
@immutable
class ScrollSpan {
  const ScrollSpan({
    required this.extent,
    required this.start,
    required this.length,
  });

  /// The span of [controller]'s page and view along [axis].
  factory ScrollSpan.of(CanvasController controller, Axis axis) {
    final view = controller.viewport;
    final vertical = axis == Axis.vertical;
    final (first, last) = _reach(controller, axis);
    final start = (vertical ? view.origin.dy : view.origin.dx) - first;
    final length =
        (vertical ? controller.viewSize.height : controller.viewSize.width) /
        view.zoom;
    if (view.fold != null) {
      return ScrollSpan(
        extent: math.max(start + length, last - first + length),
        start: start,
        length: length,
      );
    }
    final content = controller.contentBounds;
    final contentEnd = content.isEmpty
        ? 0.0
        : (vertical ? content.bottom : content.right);
    return ScrollSpan(
      extent: math.max(start + length, contentEnd + length / 2),
      start: start,
      length: length,
    );
  }

  /// The first and last place the view's origin goes along [axis].
  static (double, double) _reach(CanvasController controller, Axis axis) {
    final range = controller.originRange(controller.viewport.zoom);
    return axis == Axis.vertical
        ? (range.min.dy, range.max.dy)
        : (range.min.dx, range.max.dx);
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
  /// units from as far back as it goes, as a [ScrollSpan] has it; the other
  /// axis left as it is.
  void scrollTo(Axis axis, double start) {
    final origin = viewport.origin;
    final at = start + ScrollSpan._reach(this, axis).$1;
    viewport = viewport.copyWith(
      origin: axis == Axis.vertical
          ? Offset(origin.dx, at)
          : Offset(at, origin.dy),
    );
  }
}
