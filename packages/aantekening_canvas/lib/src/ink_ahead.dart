/// The strokes of a page made ready to draw before they come into view.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/scheduler.dart';

import 'canvas_controller.dart';
import 'canvas_painters.dart';

/// Records the ink of [controller]'s page as [InkPainter] draws it, ahead
/// of its being drawn: a few milliseconds at a time while nothing moves,
/// what lies nearest the view first.
///
/// Working out a stroke's shape is most of what drawing it costs, and is
/// done once for each stroke; done as a page scrolled onto strokes not yet
/// drawn, it took up to half the time a frame has, and frames were missed.
class InkAhead {
  InkAhead(this.controller) {
    controller.contents.addListener(_changed);
    _changed();
  }

  final CanvasController controller;

  /// How long each turn records for, between frames.
  static const Duration _turn = Duration(milliseconds: 4);

  /// How long it waits while the view moves, or anything else does.
  static const Duration _busy = Duration(milliseconds: 100);

  /// The ink not yet recorded, the nearest the view last.
  List<InkElement> _waiting = const <InkElement>[];
  PageDocument? _seen;
  Timer? _next;

  void _changed() {
    final document = controller.document;
    if (identical(document, _seen)) return;
    _seen = document;
    final view = controller.viewport.visibleBounds(controller.viewSize);
    final x = (view.left + view.right) / 2;
    final y = (view.top + view.bottom) / 2;
    double away(InkElement element) {
      final bounds = element.bounds;
      final dx = (bounds.left + bounds.right) / 2 - x;
      final dy = (bounds.top + bounds.bottom) / 2 - y;
      return dx * dx + dy * dy;
    }

    _waiting = <InkElement>[
      for (final element in document.elements)
        if (element is InkElement && !InkPainter.isRecorded(element)) element,
    ]..sort((a, b) => away(b).compareTo(away(a)));
    _schedule();
  }

  void _schedule([Duration after = Duration.zero]) {
    if (_waiting.isEmpty || (_next?.isActive ?? false)) return;
    _next = Timer(after, _record);
  }

  void _record() {
    final scheduler = SchedulerBinding.instance;
    // Not while a frame is due, or anything animates — the view gliding
    // among the strokes, say.
    if (scheduler.hasScheduledFrame || scheduler.transientCallbackCount > 0) {
      _schedule(_busy);
      return;
    }
    final watch = Stopwatch()..start();
    while (_waiting.isNotEmpty && watch.elapsed < _turn) {
      InkPainter.record(_waiting.removeLast());
    }
    _schedule();
  }

  void dispose() {
    _next?.cancel();
    _waiting = const <InkElement>[];
    controller.contents.removeListener(_changed);
  }
}
