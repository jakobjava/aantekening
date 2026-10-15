/// An element drawn as a picture of itself while the view zooms.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'canvas_scope.dart';
import 'canvas_viewport.dart';

/// Shows [child] as a picture of itself while the view zooms, and as itself
/// again once it rests.
///
/// Text scaled by a zoom is drawn again at every frame of it, every letter
/// at its new size: on a page of formulas, most of what a frame of a pinch
/// cost. A picture of it is only scaled, as the ink's tiles and the PDF
/// pages are, softer until the zoom rests, and sharp again then.
///
/// The picture is taken ahead, while nothing moves, and kept until what it
/// shows changes: taken as a zoom began, the pictures of a page of formulas
/// held its first frame up by fifty milliseconds. Without one yet, it is
/// drawn as itself.
///
/// For what is drawn on its own, not in a way that depends on what lies
/// beneath it — text in the inverse of what is beneath would be drawn as
/// though nothing were — and not what something else on the page follows
/// ([CompositedTransformTarget]): drawn as a picture, it is not there to be
/// followed. For those, [enabled] is false; it is switched rather than the
/// widget left out, which would build the child anew.
class ZoomSnapshot extends StatelessWidget {
  const ZoomSnapshot({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// Whether it is drawn as a picture while the view zooms.
  final bool enabled;

  @override
  Widget build(BuildContext context) => _ZoomSnapshot(
    view: CanvasScope.viewOf(context),
    enabled: enabled,
    zooming: CanvasScope.zoomingOf(context),
    pixelsPerUnit:
        CanvasScope.zoomOf(context) *
        (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
    child: child,
  );
}

class _ZoomSnapshot extends SingleChildRenderObjectWidget {
  const _ZoomSnapshot({
    required this.view,
    required this.enabled,
    required this.zooming,
    required this.pixelsPerUnit,
    required super.child,
  });

  final ValueListenable<CanvasViewport>? view;
  final bool enabled;
  final bool zooming;

  /// Device pixels a unit of the child is drawn across, as the view rests.
  final double pixelsPerUnit;

  @override
  RenderZoomSnapshot createRenderObject(BuildContext context) =>
      RenderZoomSnapshot(
        pixelsPerUnit: pixelsPerUnit,
        zooming: zooming,
        enabled: enabled,
        view: view,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderZoomSnapshot renderObject,
  ) {
    renderObject
      ..view = view
      ..enabled = enabled
      ..pixelsPerUnit = pixelsPerUnit
      ..zooming = zooming;
  }
}

/// Paints its child in a layer of its own, and keeps a picture of that.
class RenderZoomSnapshot extends RenderProxyBox {
  RenderZoomSnapshot({
    required double pixelsPerUnit,
    required bool zooming,
    bool enabled = true,
    ValueListenable<CanvasViewport>? view,
  }) : _pixelsPerUnit = pixelsPerUnit,
       _zooming = zooming,
       _enabled = enabled,
       _view = view;

  /// The view of the page it is on, which taking pictures waits on to rest.
  ValueListenable<CanvasViewport>? _view;
  set view(ValueListenable<CanvasViewport>? value) {
    if (identical(value, _view)) return;
    if (attached) {
      _view?.removeListener(_moved);
      value?.addListener(_moved);
    }
    _view = value;
  }

  /// The most device pixels a picture is taken across, either way.
  static const double largest = 2048;

  /// The most pixels all the pictures kept hold together, about a hundred
  /// megabytes of the graphics card's; those shown least recently go
  /// first beyond it.
  static const int budget = 24 << 20;

  /// How long nothing is to change before pictures are taken, and how long
  /// between one and the next: each costs a few milliseconds of drawing.
  static const Duration settle = Duration(milliseconds: 400);
  static const Duration between = Duration(milliseconds: 60);

  double _pixelsPerUnit;
  set pixelsPerUnit(double value) {
    if (value == _pixelsPerUnit) return;
    _pixelsPerUnit = value;
    // The picture there is still shows it, softer, until one is taken for
    // the zoom it has come to.
    _due(this);
  }

  /// Whether it is drawn as a picture while the view zooms, or always as
  /// itself.
  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      _due(this);
    } else {
      _notDue(this);
      if (_snapshot != null) {
        _letGo();
        _ownRepaint = true;
        markNeedsPaint();
      }
    }
  }

  bool _zooming;
  set zooming(bool value) {
    if (value == _zooming) return;
    _zooming = value;
    if (_snapshot != null) {
      _ownRepaint = true;
      markNeedsPaint();
    }
    if (!value) _due(this);
  }

  ui.Image? _snapshot;

  /// The pixels per unit [_snapshot] was taken at.
  double _snapshotPixelsPerUnit = 0;

  /// The size it was laid out at as [_snapshot] was taken. Laid out anew
  /// since — a formula opened or typed in — the picture would be stretched
  /// over what it has become.
  Size _snapshotSize = Size.zero;

  /// Whether [_snapshot] shows the child as it is painted now.
  bool _current = false;

  /// Whether the next paint was asked for here — the picture shown or let
  /// go of — not by the child changing.
  bool _ownRepaint = false;

  /// When it was last painted, by [_clock]: the pictures of those painted
  /// least recently are let go first.
  int _shown = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void markNeedsPaint() {
    // The child changed: the picture no longer shows it.
    if (!_ownRepaint) _current = false;
    super.markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _ownRepaint = false;
    _shown = ++_clock;
    final snapshot = _snapshot;
    // Only a picture of it as it is: one of what it was, changed since, is
    // drawn stretched over it, or shows what is no longer there.
    if (_zooming && snapshot != null && _current && size == _snapshotSize) {
      context.canvas.drawImageRect(
        snapshot,
        Offset.zero &
            Size(snapshot.width.toDouble(), snapshot.height.toDouble()),
        offset & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    super.paint(context, offset);
    if (!_enabled) return;
    if (!_current || _snapshotPixelsPerUnit != _pixelsPerUnit) _due(this);
  }

  /// Whether a picture can be taken of it now: it is shown, and not zoomed.
  bool get _ready {
    final layer = this.layer;
    return attached &&
        _enabled &&
        !_zooming &&
        hasSize &&
        !size.isEmpty &&
        layer is OffsetLayer &&
        layer.attached;
  }

  /// Takes a picture of the child as it was last painted.
  void _take() {
    final layer = this.layer! as OffsetLayer;
    final ratio = math.min(
      _pixelsPerUnit,
      largest / math.max(size.width, size.height),
    );
    if (ratio <= 0) return;
    final ui.Image image;
    try {
      image = layer.toImageSync(Offset.zero & size, pixelRatio: ratio);
    } on Object {
      return;
    }
    _letGo();
    _snapshot = image;
    _snapshotPixelsPerUnit = _pixelsPerUnit;
    _snapshotSize = size;
    _current = true;
    _kept.add(this);
    _keepWithinBudget();
  }

  void _letGo() {
    _snapshot?.dispose();
    _snapshot = null;
    _current = false;
    _kept.remove(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _view?.addListener(_moved);
  }

  @override
  void detach() {
    _view?.removeListener(_moved);
    _notDue(this);
    _letGo();
    super.detach();
  }

  @override
  void dispose() {
    _letGo();
    super.dispose();
  }

  // ------------------------------------------------------- taking pictures

  static int _clock = 0;

  /// Those with a picture.
  static final Set<RenderZoomSnapshot> _kept = <RenderZoomSnapshot>{};

  /// Those whose picture is to be taken.
  static final Set<RenderZoomSnapshot> _waiting = <RenderZoomSnapshot>{};

  /// Those whose picture is to be taken once they are shown: out of view,
  /// they are not painted. Shown again, they are not painted again either —
  /// what they were painted as is shown — so they are tried again once the
  /// view that brought them back rests.
  static final Set<RenderZoomSnapshot> _unseen = <RenderZoomSnapshot>{};

  static Timer? _timer;

  /// Whether a view has moved since pictures were last waited for.
  static bool _movedLately = false;

  static void _moved() {
    _movedLately = true;
    if (_unseen.isEmpty) return;
    _waiting.addAll(_unseen);
    _unseen.clear();
    _timer?.cancel();
    _timer = Timer(settle, _takeNext);
  }

  static void _due(RenderZoomSnapshot box) {
    if (!box._enabled) return;
    _waiting.add(box);
    _timer?.cancel();
    _timer = Timer(settle, _takeNext);
  }

  /// No longer takes a picture of [box], nor waits to.
  static void _notDue(RenderZoomSnapshot box) {
    _unseen.remove(box);
    if (_waiting.remove(box) && _waiting.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Takes the picture of the one painted most recently of those waiting —
  /// between frames, as a timer runs — and the next a while later.
  static void _takeNext() {
    _timer = null;
    _waiting.removeWhere((box) => !box.attached);
    if (_waiting.isEmpty) return;
    // Not while the view moves: each picture holds up the drawing of the
    // frame after it, which a scroll would show as a stutter. Frames drawn
    // with nothing moving — what was put off being built — do not count.
    if (_movedLately) {
      _movedLately = false;
      _timer = Timer(settle, _takeNext);
      return;
    }
    final box = _waiting.reduce((a, b) => a._shown >= b._shown ? a : b);
    _waiting.remove(box);
    if (box._ready) {
      box._take();
    } else {
      _unseen.add(box);
    }
    if (_waiting.isNotEmpty) {
      _timer = Timer(
        box._snapshot == null ? Duration.zero : between,
        _takeNext,
      );
    }
  }

  static void _keepWithinBudget() {
    var pixels = 0;
    for (final box in _kept) {
      pixels += box._snapshot!.width * box._snapshot!.height;
    }
    while (_kept.length > 1 && pixels > budget) {
      final oldest = _kept.reduce((a, b) => a._shown <= b._shown ? a : b);
      pixels -= oldest._snapshot!.width * oldest._snapshot!.height;
      oldest._letGo();
    }
  }
}
