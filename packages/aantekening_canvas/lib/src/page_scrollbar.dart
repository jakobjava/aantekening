/// Scrollbars along the page.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'canvas_controller.dart';
import 'canvas_scroll.dart';

/// A scrollbar floating along one side of the page, over it: a slim
/// rounded thumb and no track, which grows fuller under the hand.
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

  /// How thick the bar is: what takes hold of the pointer, not what is
  /// drawn, which is thinner.
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
    final thumb = active ? _ScrollbarPainter.full : _ScrollbarPainter.slim;
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
        // The thumb follows the page by repainting, with nothing built
        // or laid out again.
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: thumb),
            duration: const Duration(milliseconds: 120),
            builder: (context, width, _) => CustomPaint(
              size: _axis == Axis.vertical
                  ? const Size.fromWidth(PageScrollbar.thickness)
                  : const Size.fromHeight(PageScrollbar.thickness),
              painter: _ScrollbarPainter(
                controller: widget.controller,
                axis: _axis,
                // In the accent, where there is one, or the text's colour.
                colour: scheme.primary,
                width: width,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  _ScrollbarPainter({
    required this.controller,
    required this.axis,
    required this.colour,
    required this.width,
  }) : super(
         repaint: Listenable.merge(<Listenable>[
           controller.view,
           controller.contents,
         ]),
       );

  final CanvasController controller;
  final Axis axis;
  final Color colour;

  /// How thick the thumb is drawn.
  final double width;

  /// How thick the thumb is at rest, and under the hand.
  static const double slim = 4;
  static const double full = 8;

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
    final span = ScrollSpan.of(controller, axis);
    // All of it in view, there is nothing to scroll to, and no thumb.
    if (span.lengthFraction >= 1 && span.start <= 0) return;
    final vertical = axis == Axis.vertical;
    final along = thumbOf(span, vertical ? size.height : size.width);
    // Along the far edge, rounded at its ends.
    const edge = 2.0;
    final across = vertical ? size.width : size.height;
    final from = across - edge - width;
    final rect = vertical
        ? Rect.fromLTRB(from, along.start, from + width, along.end)
        : Rect.fromLTRB(along.start, from, along.end, from + width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(width / 2)),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(_ScrollbarPainter old) =>
      old.controller != controller ||
      old.axis != axis ||
      old.colour != colour ||
      old.width != width;
}
