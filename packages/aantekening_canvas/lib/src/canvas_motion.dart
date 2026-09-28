/// How the page moves by itself: coasting on after a flick, and springing
/// back from past its top and left edges, where a scroll may stretch it.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'canvas_controller.dart';
import 'canvas_viewport.dart';

/// Scrolling past the page's top and left edges, which give way a little,
/// less the further they are pulled, as a list on a phone lets itself be
/// pulled a short way past its end.
extension Stretching on CanvasController {
  /// Whether the view lies past the page's top or left edge.
  bool get isStretched => viewport.origin.dx < 0 || viewport.origin.dy < 0;

  /// Pans by a screen-space [delta] as [panBy] does, but on past the page's
  /// edges, against their pull.
  void stretchBy(Offset delta) => _stretch((free) => free.panBy(delta));

  /// Zooms by [factor] about [screenFocus] as [zoomBy] does, but on past the
  /// page's edges, against their pull.
  void stretchZoomBy(double factor, Offset screenFocus) =>
      _stretch((free) => free.zoomAround(free.zoom * factor, screenFocus));

  /// Moves the view as [move] moves it where the edges do not pull: the
  /// view as far past them as the fingers went, then pulled back.
  void _stretch(CanvasViewport Function(CanvasViewport free) move) =>
      stretchTo(_eachAxis(move(_eachAxis(viewport, _pull)), _give));
}

/// The furthest, in screen pixels, the view goes past an edge, however hard
/// it is pulled.
const double _reach = 100;

/// How far the first pixels of a pull go past an edge, as a part of the
/// pull; each further one goes less, until they hardly go at all.
const double _yield = 0.4;

/// How far past an edge a pull of [pull] pixels shows the view: resisting
/// from the first, and ever harder towards [_reach].
double _give(double pull) => _reach * _tanh(pull * _yield / _reach);

/// The pull, in pixels, that shows the view [shown] pixels past an edge:
/// the inverse of [_give].
double _pull(double shown) {
  final part = math.min(shown / _reach, 0.999);
  return _reach / _yield * 0.5 * math.log((1 + part) / (1 - part));
}

double _tanh(double x) {
  final e = math.exp(-2 * x);
  return (1 - e) / (1 + e);
}

/// [view] with [past] applied to how far, in screen pixels, it lies past
/// each edge.
CanvasViewport _eachAxis(
  CanvasViewport view,
  double Function(double beyond) past,
) {
  final zoom = view.zoom;
  double along(double start) =>
      start >= 0 ? start : -past(-start * zoom) / zoom;
  final origin = view.origin;
  return CanvasViewport(
    origin: Offset(along(origin.dx), along(origin.dy)),
    zoom: zoom,
  );
}

/// Moves a canvas's view by itself, frame by frame: on after a flick,
/// slowing as a thrown sheet of paper would, and back from past the page's
/// edges.
class CanvasMotion {
  CanvasMotion(this._controller, TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  final CanvasController Function() _controller;
  late final Ticker _ticker;

  /// How quickly a flick slows: its speed falls by a factor of e every this
  /// many seconds, so it coasts about this many seconds' worth of its
  /// starting speed.
  static const double _coast = 0.45;

  /// How quickly a flick carried past an edge is stopped there.
  static const double _brake = 0.04;

  /// How quickly the view comes back from past an edge: it closes a factor
  /// of e of the way every this many seconds.
  static const double _return = 0.07;

  /// Flicks slower than this, in pixels per second, are not worth coasting.
  static const double minSpeed = 150;

  /// The fastest a flick starts, in pixels per second: a hard one coasts
  /// four screens or so.
  static const double maxSpeed = 9000;

  Offset _velocity = Offset.zero;
  Duration _last = Duration.zero;

  /// Whether the view is moving by itself.
  bool get isMoving => _ticker.isActive;

  /// How fast it is coasting, in screen pixels per second.
  Offset get velocity => isMoving ? _velocity : Offset.zero;

  /// Coasts on at [velocity], in screen pixels per second of panning, and
  /// comes back from past an edge; only the latter, if it is too slow to be
  /// a flick.
  void fling(Offset velocity) {
    final speed = velocity.distance;
    _velocity = speed < minSpeed
        ? Offset.zero
        : velocity * (math.min(speed, maxSpeed) / speed);
    _ticker.stop();
    _last = Duration.zero;
    if (_velocity != Offset.zero || _controller().isStretched) _ticker.start();
  }

  /// Comes back from past an edge, unless it is moving already.
  void settle() {
    if (!isMoving) fling(Offset.zero);
  }

  /// Stops coasting, still coming back from past an edge.
  void brake() {
    _velocity = Offset.zero;
    if (isMoving && !_controller().isStretched) _ticker.stop();
  }

  /// Stops moving at once, wherever the view is: fingers have taken hold
  /// of it.
  void stop() {
    _velocity = Offset.zero;
    _ticker.stop();
  }

  void dispose() => _ticker.dispose();

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (seconds <= 0) return;
    final controller = _controller();

    // The exact distance an exponentially slowing flick covers in this
    // time, so it goes as far at 30 frames a second as at 120.
    final decay = math.exp(-seconds / _coast);
    controller.stretchBy(_velocity * (_coast * (1 - decay)));
    _velocity *= decay;

    // Past an edge, a flick still going out is stopped quickly, and the
    // view is drawn back once it has.
    final view = controller.viewport;
    final brake = math.exp(-seconds / _brake);
    final back = math.exp(-seconds / _return);
    (double, double) along(double start, double velocity) {
      if (start >= 0) return (start, velocity);
      if (velocity > 0 && velocity * brake > 20) {
        return (start, velocity * brake);
      }
      final shown = start * back;
      return (shown * view.zoom > -0.5 ? 0 : shown, math.min(velocity, 0));
    }

    final (x, dx) = along(view.origin.dx, _velocity.dx);
    final (y, dy) = along(view.origin.dy, _velocity.dy);
    _velocity = Offset(dx, dy);
    controller.stretchTo(CanvasViewport(origin: Offset(x, y), zoom: view.zoom));
    if (_velocity.distance < 20 && !controller.isStretched) _ticker.stop();
  }
}
