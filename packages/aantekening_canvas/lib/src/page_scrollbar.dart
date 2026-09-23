/// Scrollbars along the page.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'canvas_controller.dart';
import 'canvas_scroll.dart';

/// A scrollbar along one side of the page.
///
/// Its thumb shows how much of the page is in view, and where; dragging the
/// thumb scrolls the page, a press either side of it moves the page on by
/// most of a view, and the wheel over it scrolls as it does over the page.
class PageScrollbar extends StatefulWidget {
  const PageScrollbar({
    required this.controller,
    required this.axis,
    super.key,
  });

  final CanvasController controller;
  final Axis axis;

  /// How thick the bar is.
  static const double thickness = 12;

  /// How much of a view a press beside the thumb moves the page on by.
  static const double pageStep = 0.9;

  @override
  State<PageScrollbar> createState() => _PageScrollbarState();
}

class _PageScrollbarState extends State<PageScrollbar> {
  bool _hovering = false;

  /// The drag of the thumb under way: where the pointer and the view began,
  /// and how far the page scrolled then, which holds for the whole drag so
  /// the thumb stays under the pointer as the page's extent changes.
  ({double pointer, double start, double extent})? _drag;

  Axis get _axis => widget.axis;

  double _along(Offset offset) =>
      _axis == Axis.vertical ? offset.dy : offset.dx;

  double _length(Size size) =>
      _axis == Axis.vertical ? size.height : size.width;

  void _onPointerDown(PointerDownEvent event) {
    final box = context.findRenderObject()! as RenderBox;
    final span = ScrollSpan.of(widget.controller, _axis);
    final track = _length(box.size);
    final at = _along(event.localPosition);
    final thumb = _ScrollbarPainter.thumbOf(span, track);
    if (at >= thumb.start && at <= thumb.end) {
      setState(
        () => _drag = (pointer: at, start: span.start, extent: span.extent),
      );
      return;
    }
    final step = span.length * PageScrollbar.pageStep;
    widget.controller.scrollTo(
      _axis,
      at < thumb.start ? span.start - step : span.start + step,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final drag = _drag;
    if (drag == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final track = _length(box.size);
    if (track <= 0) return;
    final moved = _along(event.localPosition) - drag.pointer;
    widget.controller.scrollTo(_axis, drag.start + moved * drag.extent / track);
  }

  void _onPointerUp(PointerEvent event) {
    if (_drag != null) setState(() => _drag = null);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    // A wheel turns along the bar whichever way it turns.
    final along = _axis == Axis.vertical
        ? delta.dy
        : (delta.dx != 0 ? delta.dx : delta.dy);
    final span = ScrollSpan.of(widget.controller, _axis);
    widget.controller.scrollTo(
      _axis,
      span.start + widget.controller.viewport.toPageDistance(along),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovering || _drag != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        onPointerSignal: _onPointerSignal,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => CustomPaint(
            size: _axis == Axis.vertical
                ? const Size.fromWidth(PageScrollbar.thickness)
                : const Size.fromHeight(PageScrollbar.thickness),
            painter: _ScrollbarPainter(
              span: ScrollSpan.of(widget.controller, _axis),
              axis: _axis,
              track: scheme.surfaceContainerLow,
              thumb: scheme.onSurface.withValues(alpha: active ? 0.45 : 0.25),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter({
    required this.span,
    required this.axis,
    required this.track,
    required this.thumb,
  });

  final ScrollSpan span;
  final Axis axis;
  final Color track;
  final Color thumb;

  /// The shortest the thumb is drawn, so it can always be taken hold of.
  static const double minThumb = 24;

  /// Where the thumb runs along a track [track] long.
  static ({double start, double end}) thumbOf(ScrollSpan span, double track) {
    final length = math.min(
      track,
      math.max(minThumb, span.lengthFraction * track),
    );
    final start = (span.startFraction * track).clamp(0.0, track - length);
    return (start: start, end: start + length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final vertical = axis == Axis.vertical;
    final along = thumbOf(span, vertical ? size.height : size.width);
    const inset = 3.0;
    final rect = vertical
        ? Rect.fromLTRB(inset, along.start, size.width - inset, along.end)
        : Rect.fromLTRB(along.start, inset, along.end, size.height - inset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = thumb,
    );
  }

  @override
  bool shouldRepaint(_ScrollbarPainter old) =>
      old.span != span ||
      old.axis != axis ||
      old.track != track ||
      old.thumb != thumb;
}
