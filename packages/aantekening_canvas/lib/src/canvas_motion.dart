/// How the page moves by itself: coasting on after a flick, and springing
/// back from past its edges, where a scroll may stretch it.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'canvas_controller.dart';
import 'canvas_viewport.dart';

/// Scrolling past the page's edges ([CanvasController.originRange]), which
/// give way a little, less the further they are pulled, as a list on a
/// phone lets itself be pulled a short way past its end.
extension Stretching on CanvasController {
  /// Whether the view lies past one of the page's edges.
  bool get isStretched {
    final view = viewport;
    final range = originRange(view.zoom);
    final origin = view.origin;
    bool past(double at, double min, double max) => at < min || at > max;
    return past(origin.dx, range.min.dx, range.max.dx) ||
        past(origin.dy, range.min.dy, range.max.dy);
  }

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

  /// [view] with [past] applied to how far, in screen pixels, it lies past
  /// each edge.
  CanvasViewport _eachAxis(
    CanvasViewport view,
    double Function(double beyond) past,
  ) {
    final zoom = view.zoom;
    final range = originRange(zoom);
    double along(double start, double min, double max) {
      if (start < min) return min - past((min - start) * zoom) / zoom;
      if (start > max) return max + past((start - max) * zoom) / zoom;
      return start;
    }

    final origin = view.origin;
    return view.copyWith(
      origin: Offset(
        along(origin.dx, range.min.dx, range.max.dx),
        along(origin.dy, range.min.dy, range.max.dy),
      ),
    );
  }
}

/// How near an edge, in screen pixels, a view drawn back to it is put
/// there.
const double _still = 0.5;

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

/// Moves a canvas's view by itself, frame by frame: on after a flick,
/// slowing as a thrown sheet of paper would; back from past the page's
/// edges; and on to where a mouse wheel sent it.
class CanvasMotion {
  CanvasMotion(this._controller, TickerProvider vsync, {this.onZoomed}) {
    _ticker = vsync.createTicker(_tick);
  }

  final CanvasController Function() _controller;
  late final Ticker _ticker;

  /// Told when a zoom the view was gliding through has got where it was
  /// going.
  final VoidCallback? onZoomed;

  /// How quickly a flick slows: its speed falls by a factor of e every this
  /// many seconds, so it coasts about this many seconds' worth of its
  /// starting speed.
  static const double _coast = 0.45;

  /// How quickly a flick carried past an edge is stopped there.
  static const double _brake = 0.04;

  /// How quickly the view comes back from past an edge: it closes a factor
  /// of e of the way every this many seconds.
  static const double _return = 0.07;

  /// How quickly a glide closes on where it is going, likewise: a wheel's
  /// notch goes most of its way in the first frames and is there in a
  /// tenth of a second, as the desktop's own scrolling goes.
  static const double _glide = 0.035;

  /// Flicks slower than this, in pixels per second, are not worth coasting.
  static const double minSpeed = 150;

  /// The fastest a flick starts, in pixels per second: a hard one coasts
  /// four screens or so.
  static const double maxSpeed = 9000;

  Offset _velocity = Offset.zero;
  Duration _last = Duration.zero;

  /// How far, in screen pixels, the view is still to pan, and by how much
  /// — the logarithm of the factor — it is still to zoom, and about where.
  Offset _panning = Offset.zero;
  double _zooming = 0;
  Offset _zoomFocus = Offset.zero;

  /// Whether the view is moving by itself.
  bool get isMoving => _ticker.isActive;

  /// Whether it is gliding through a zoom.
  bool get isZooming => _zooming != 0;

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
    _run();
  }

  /// Pans by a screen-space [delta], as [CanvasController.panBy] does, over
  /// the next frames, on from wherever the last glide has got to.
  void glide(Offset delta) {
    _panning += delta;
    _run();
  }

  /// Zooms by [factor] about [screenFocus], as [CanvasController.zoomBy]
  /// does, over the next frames, on from wherever the last glide has got
  /// to.
  void glideZoom(double factor, Offset screenFocus) {
    _zooming += math.log(factor);
    _zoomFocus = screenFocus;
    _run();
  }

  /// Comes back from past an edge, unless it is moving already.
  void settle() {
    if (!isMoving) fling(Offset.zero);
  }

  /// Stops coasting, still gliding on and coming back from past an edge.
  void brake() {
    _velocity = Offset.zero;
    if (isMoving && !_gliding && !_controller().isStretched) _ticker.stop();
  }

  /// Stops moving at once: fingers have taken hold of the view. Where a
  /// glide was going, it goes, since that was asked for as well.
  void stop() {
    _velocity = Offset.zero;
    _ticker.stop();
    if (_gliding) _step(1);
  }

  void dispose() => _ticker.dispose();

  bool get _gliding => _panning != Offset.zero || _zooming != 0;

  void _run() {
    if (isMoving) return;
    _last = Duration.zero;
    if (_velocity != Offset.zero || _gliding || _controller().isStretched) {
      _ticker.start();
    }
  }

  /// Glides [share] of the rest of the way, and all of it once what is
  /// left would not be seen.
  void _step(double share) {
    final controller = _controller();
    if (_panning != Offset.zero) {
      var pan = _panning * share;
      if ((_panning - pan).distance < 0.5) pan = _panning;
      _panning -= pan;
      controller.panBy(pan);
    }
    if (_zooming != 0) {
      var zoom = _zooming * share;
      if ((_zooming - zoom).abs() < 1e-3) zoom = _zooming;
      _zooming -= zoom;
      controller.zoomBy(math.exp(zoom), _zoomFocus);
      if (_zooming == 0) onZoomed?.call();
    }
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (seconds <= 0) return;
    final controller = _controller();

    _step(1 - math.exp(-seconds / _glide));

    // The exact distance an exponentially slowing flick covers in this
    // time, so it goes as far at 30 frames a second as at 120.
    final decay = math.exp(-seconds / _coast);
    controller.stretchBy(_velocity * (_coast * (1 - decay)));
    _velocity *= decay;

    // Past an edge, a flick still going out is stopped quickly, and the
    // view is drawn back once it has.
    final view = controller.viewport;
    final range = controller.originRange(view.zoom);
    final brake = math.exp(-seconds / _brake);
    final back = math.exp(-seconds / _return);
    (double, double) along(
      double start,
      double velocity,
      double min,
      double max,
    ) {
      if (start >= min && start <= max) return (start, velocity);
      final edge = start < min ? min : max;
      // A positive velocity pans the view back towards the page's start:
      // out past the start's edge, and in from past the far one.
      final outwards = start < min ? velocity : -velocity;
      if (outwards > 0 && outwards * brake > 20) {
        return (start, velocity * brake);
      }
      final shown = edge + (start - edge) * back;
      final settled = ((shown - edge) * view.zoom).abs() < _still;
      return (
        settled ? edge : shown,
        start < min ? math.min(velocity, 0) : math.max(velocity, 0),
      );
    }

    final (x, dx) = along(
      view.origin.dx,
      _velocity.dx,
      range.min.dx,
      range.max.dx,
    );
    final (y, dy) = along(
      view.origin.dy,
      _velocity.dy,
      range.min.dy,
      range.max.dy,
    );
    _velocity = Offset(dx, dy);
    controller.stretchTo(view.copyWith(origin: Offset(x, y)));
    if (_velocity.distance < 20 && !_gliding && !controller.isStretched) {
      _velocity = Offset.zero;
      _ticker.stop();
    }
  }
}
