/// The canvas widget: input handling and the layer stack.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'canvas_controller.dart';
import 'canvas_painters.dart';
import 'canvas_scope.dart';
import 'canvas_viewport.dart';
import 'element_transforms.dart';
import 'selection_handles.dart';
import 'tools.dart';

/// Builds the widget for an element, or returns null to leave it unpainted.
///
/// Supplied by the host application so that the canvas does not depend on the
/// maths renderer, the PDF renderer or the text editor: it owns layout and
/// input, they own their own content.
typedef CanvasElementBuilder =
    Widget? Function(BuildContext context, NoteElement element);

/// Decides whether an element's own widget handles a press at a page-space
/// point, in which case the canvas leaves that press alone.
typedef CanvasPointerClaim = bool Function(NoteElement element, Offset page);

/// An infinitely pannable, zoomable page.
///
/// Layers are stacked so each repaints independently: paper, highlighter ink,
/// the element widgets, pen ink, the stroke in progress, and the selection
/// overlay. A new ink sample therefore repaints only the thin wet-ink layer
/// rather than the whole page.
class InfiniteCanvas extends StatefulWidget {
  const InfiniteCanvas({
    required this.controller,
    super.key,
    this.elementBuilder,
    this.claimsPointer,
    this.onEmptyTap,
    this.onCanvasPress,
    this.onElementDoubleTap,
    this.trackpadPanScale = 1,
  });

  final CanvasController controller;

  /// Supplies the widget for text, maths, image, PDF and table elements.
  final CanvasElementBuilder? elementBuilder;

  /// Lets an element's widget take a press with the select tool — a text box
  /// placing its caret, say — instead of the canvas picking the element up.
  final CanvasPointerClaim? claimsPointer;

  /// Invoked when empty canvas is clicked or tapped with the select tool,
  /// without dragging. This is where a caret is placed.
  final ValueChanged<Offset>? onEmptyTap;

  /// Invoked for every press the canvas handles itself, with the element under
  /// it if any. The host uses this to end text editing when the user moves on.
  final ValueChanged<NoteElement?>? onCanvasPress;

  /// Invoked when an element is double-tapped.
  final void Function(NoteElement element)? onElementDoubleTap;

  /// How far the page moves per logical pixel of pan a trackpad reports.
  ///
  /// 1 wherever the platform reports how far the fingers moved. Flutter on
  /// Linux multiplies the desktop's touchpad scroll deltas by 53, so there the
  /// host passes the factor that brings them back to finger distance; see
  /// the app's `trackpadPanScale`.
  final double trackpadPanScale;

  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

/// What the pointer currently in contact with the canvas is doing.
enum _PointerAction {
  none,
  draw,
  erase,
  pan,
  move,
  transform,
  marquee,

  /// A touch on empty canvas: a tap if it stays put, a pan if it moves.
  panOrTap,

  /// An element's own widget is handling this pointer.
  claimed,

  /// Two fingers are on the screen.
  pinch,
}

/// A resize or rotation of the selection in progress, measured from where it
/// started so that rounding and snapping never accumulate.
class _TransformGesture {
  _TransformGesture({
    required this.handle,
    required this.originals,
    required this.frame,
    required this.pressPage,
  }) : startAngle = math.atan2(
         pressPage.dy - frame.center.dy,
         pressPage.dx - frame.center.dx,
       );

  final SelectionHandle handle;
  final List<NoteElement> originals;
  final SelectionFrame frame;
  final Offset pressPage;
  final double startAngle;
}

/// A trackpad pan-and-zoom in progress.
///
/// Applied event by event, each step checked before it is used. Platforms do
/// not all report a clean stream: on Linux a two-finger scroll and a pinch are
/// separate streams on one device, each reporting its own running total, so a
/// pinch event can say the pan is zero in the middle of a scroll, and a pinch
/// that pauses and resumes restarts its scale at 1. Taking those totals at
/// face value moves the page by the difference between the streams — it jumps
/// across the screen and back. Here a step no finger movement could make is
/// treated as a new starting point instead.
class _TrackpadGesture {
  _TrackpadGesture({this.lastPan = Offset.zero, this.lastScale = 1})
    : pinchBase = lastScale;

  /// The platform's running pan and scale as of the last event used.
  Offset lastPan;
  double lastScale;

  /// The scale a pinch is measured from until it clears the slop.
  double pinchBase;

  /// Whether the fingers have spread or closed far enough to be a pinch.
  bool pinching = false;

  bool zoomed = false;

  /// Recent pan steps, for the momentum when the fingers lift.
  final List<(Duration, Offset)> steps = <(Duration, Offset)>[];
}

class _InfiniteCanvasState extends State<InfiniteCanvas>
    with SingleTickerProviderStateMixin {
  /// Zoom change per logical pixel of scrolling while Ctrl is held.
  ///
  /// Applied exponentially, so a mouse-wheel notch (about 50 px on Linux and
  /// Windows) zooms by roughly ten percent, and a trackpad swipe of the same
  /// distance zooms by the same amount spread smoothly across its events.
  static const double _scrollZoomRate = 0.002;

  /// How far a press may wander, in screen pixels, and still count as a click.
  static const double _mouseTapSlop = 4;

  /// How quickly a fling slows down: its speed falls by a factor of e every
  /// this many seconds, so it coasts about this many seconds' worth of its
  /// starting speed.
  static const double _flingDecay = 0.25;

  /// Flings slower than this, in pixels per second, are not worth animating.
  static const double _minFlingSpeed = 150;

  /// The fastest a fling starts, in pixels per second: a hard flick coasts
  /// about half a screen, never out of sight of where it was.
  static const double _maxFlingSpeed = 2400;

  /// The largest pan, in pixels, one trackpad event can plausibly carry.
  /// Events arrive dozens of times a second, so even a fast swipe moves a few
  /// dozen pixels in one; anything beyond this is a platform's running total
  /// starting over, not movement.
  static const double _maxPanStep = 240;

  /// The largest zoom change one trackpad event can plausibly carry.
  static const double _maxScaleStep = 1.33;

  /// How far two fingers must spread or close, as a ratio, before a trackpad
  /// gesture zooms. Fingers scrolling side by side drift apart a little, and
  /// a touchpad can report the start of a scroll as a pinch; zooming on that
  /// drift made the page lurch at the start of a scroll.
  static const double _pinchSlop = 1.04;

  _PointerAction _action = _PointerAction.none;
  int? _activePointer;
  Offset _pressPosition = Offset.zero;
  Offset _lastScreenPosition = Offset.zero;
  bool _dragged = false;

  /// Whether the next change made by the current drag should be recorded as
  /// an undo step. Only the first is, so a whole drag undoes in one go.
  bool _recordNextChange = false;

  _TransformGesture? _transform;

  Offset? _marqueeAnchor;
  Aabb? _marquee;

  /// Touch pointers currently down, by pointer id, at their latest position.
  final Map<int, Offset> _touches = <int, Offset>{};
  VelocityTracker? _touchVelocity;

  _TrackpadGesture? _trackpad;

  late final Ticker _fling = createTicker(_onFlingTick);
  Offset _flingVelocity = Offset.zero;
  Duration _lastFlingTick = Duration.zero;

  MouseCursor _hoverCursor = MouseCursor.defer;

  /// Where the mouse pointer is, which a trackpad pinch zooms about. Linux
  /// reports a pinch at the last place clicked rather than at the pointer.
  Offset? _mousePosition;

  Size _size = Size.zero;

  CanvasController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(InfiniteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _fling.dispose();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------- pointer

  void _onPointerDown(PointerDownEvent event) {
    _stopFling();
    if (event.kind == PointerDeviceKind.mouse) {
      _mousePosition = event.localPosition;
    }
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length == 2) {
        _beginPinch();
        return;
      }
      if (_touches.length > 2 || _action == _PointerAction.pinch) return;
    }
    if (_activePointer != null) return;

    _activePointer = event.pointer;
    _pressPosition = event.localPosition;
    _lastScreenPosition = event.localPosition;
    _dragged = false;
    _recordNextChange = true;
    _touchVelocity = event.kind == PointerDeviceKind.touch
        ? (VelocityTracker.withKind(event.kind)
            ..addPosition(event.timeStamp, event.localPosition))
        : null;

    final page = _controller.viewport.toPage(event.localPosition);
    _action = _resolveAction(event, page);

    switch (_action) {
      case _PointerAction.draw:
        _controller.beginStroke(
          page,
          pressure: _normalizedPressure(event),
          tilt: event.tilt,
        );
      case _PointerAction.erase:
        _controller.eraseAt(page, radius: _eraserRadius);
      case _PointerAction.marquee:
        _marqueeAnchor = page;
        _marquee = Aabb(page.dx, page.dy, page.dx, page.dy);
        if (!HardwareKeyboard.instance.isShiftPressed) {
          _controller.clearSelection();
        }
      case _PointerAction.panOrTap:
        _controller.clearSelection();
      case _PointerAction.move:
      case _PointerAction.transform:
      case _PointerAction.pan:
      case _PointerAction.claimed:
      case _PointerAction.pinch:
      case _PointerAction.none:
        break;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mousePosition = event.localPosition;
    }
    if (_touches.containsKey(event.pointer)) {
      if (_action == _PointerAction.pinch) {
        _updatePinch(event.pointer, event.localPosition);
        return;
      }
      _touches[event.pointer] = event.localPosition;
    }
    if (event.pointer != _activePointer) return;
    _touchVelocity?.addPosition(event.timeStamp, event.localPosition);

    final page = _controller.viewport.toPage(event.localPosition);
    var screenDelta = event.localPosition - _lastScreenPosition;
    _lastScreenPosition = event.localPosition;
    if (!_dragged) {
      if ((event.localPosition - _pressPosition).distance <= _tapSlop(event)) {
        screenDelta = Offset.zero;
      } else {
        // Movement inside the slop was held back in case this was a tap; now
        // that it is a drag, catch up so the content stays under the pointer.
        _dragged = true;
        screenDelta = event.localPosition - _pressPosition;
      }
    }

    switch (_action) {
      case _PointerAction.draw:
        _controller.extendStroke(
          page,
          pressure: _normalizedPressure(event),
          tilt: event.tilt,
        );
      case _PointerAction.erase:
        _controller.eraseAt(page, radius: _eraserRadius);
      case _PointerAction.pan:
      case _PointerAction.panOrTap:
        _controller.panBy(screenDelta);
      case _PointerAction.move:
        if (screenDelta == Offset.zero) break;
        _controller.translateSelection(
          screenDelta / _controller.viewport.zoom,
          recordUndo: _takeUndoRecord(),
        );
      case _PointerAction.transform:
        if (_dragged) _updateTransform(page);
      case _PointerAction.marquee:
        final anchor = _marqueeAnchor;
        if (anchor == null) break;
        setState(() {
          _marquee = Aabb(
            math.min(anchor.dx, page.dx),
            math.min(anchor.dy, page.dy),
            math.max(anchor.dx, page.dx),
            math.max(anchor.dy, page.dy),
          );
        });
      case _PointerAction.claimed:
      case _PointerAction.pinch:
      case _PointerAction.none:
        break;
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_touches.remove(event.pointer) != null &&
        _action == _PointerAction.pinch) {
      // The pinch ends only when every finger has lifted; the finger left
      // behind must not suddenly start drawing or selecting.
      if (_touches.isEmpty) _resetPointer();
      return;
    }
    if (event.pointer != _activePointer) return;

    final page = _controller.viewport.toPage(event.localPosition);
    switch (_action) {
      case _PointerAction.draw:
        _controller.endStroke();
      case _PointerAction.marquee:
        final band = _marquee;
        if (!_dragged) {
          widget.onEmptyTap?.call(page);
        } else if (band != null) {
          _controller.selectIn(
            band,
            additive: HardwareKeyboard.instance.isShiftPressed,
          );
        }
      case _PointerAction.panOrTap:
      case _PointerAction.pan:
        if (!_dragged && _action == _PointerAction.panOrTap) {
          widget.onEmptyTap?.call(page);
        } else if (event is PointerUpEvent) {
          final velocity = _touchVelocity?.getVelocity().pixelsPerSecond;
          if (velocity != null) _startFling(velocity);
        }
      case _PointerAction.erase:
      case _PointerAction.move:
      case _PointerAction.transform:
      case _PointerAction.claimed:
      case _PointerAction.pinch:
      case _PointerAction.none:
        break;
    }

    _resetPointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touches.remove(event.pointer);
    if (_action == _PointerAction.pinch) {
      if (_touches.isEmpty) _resetPointer();
      return;
    }
    if (event.pointer != _activePointer) return;
    _controller.cancelStroke();
    _resetPointer();
  }

  void _resetPointer() {
    setState(() {
      _action = _PointerAction.none;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
      _transform = null;
      _touchVelocity = null;
    });
  }

  /// Whether this change should open a new undo step, consuming the
  /// allowance so that the rest of the drag joins it.
  bool _takeUndoRecord() {
    final record = _recordNextChange;
    _recordNextChange = false;
    return record;
  }

  static double _tapSlop(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch ? kTouchSlop : _mouseTapSlop;

  /// Chooses what a press does, from the tool and the pointer's own state.
  _PointerAction _resolveAction(PointerDownEvent event, Offset page) {
    // The middle button and space-drag always pan, whatever tool is selected,
    // so navigating never costs a trip to the toolbar.
    if (event.buttons & kMiddleMouseButton != 0) return _PointerAction.pan;
    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.space,
    )) {
      return _PointerAction.pan;
    }
    // Most styluses report the barrel button as the secondary button; treating
    // it as an eraser matches what the hardware is usually labelled for.
    if (event.kind == PointerDeviceKind.stylus &&
        event.buttons & kSecondaryStylusButton != 0) {
      _pressed(null);
      return _PointerAction.erase;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kPrimaryMouseButton == 0) {
      return _PointerAction.none;
    }

    switch (_controller.tool) {
      case CanvasTool.pen:
      case CanvasTool.highlighter:
        _pressed(null);
        return _PointerAction.draw;
      case CanvasTool.eraser:
        _pressed(null);
        return _PointerAction.erase;
      case CanvasTool.select:
        return _resolveSelectAction(event, page);
    }
  }

  _PointerAction _resolveSelectAction(PointerDownEvent event, Offset page) {
    final selected = _controller.selectedElements;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Handles come first: they sit on and around the box, where a press would
    // otherwise land on an element or on empty canvas.
    if (selected.isNotEmpty) {
      final handle = SelectionHandles.hitTest(
        selected,
        _controller.viewport,
        event.localPosition,
        reach: event.kind == PointerDeviceKind.touch
            ? SelectionHandles.touchReach
            : SelectionHandles.mouseReach,
      );
      final frame = SelectionFrame.around(selected);
      if (handle != null && frame != null) {
        _transform = _TransformGesture(
          handle: handle,
          originals: selected,
          frame: frame,
          pressPage: page,
        );
        _pressed(selected.length == 1 ? selected.single : null);
        return _PointerAction.transform;
      }
    }

    final hit = _controller.hitTest(page);
    final selection = _controller.selection;

    // Shift adds to the selection or takes away from it, whatever is clicked.
    if (hit != null && shift) {
      _pressed(hit);
      _controller.select(hit.id, additive: true);
      return _PointerAction.move;
    }

    // A group is picked up by any of its members, or by the empty space
    // inside its box, text boxes included.
    if (selection.length > 1) {
      final frame = SelectionFrame.around(selected);
      final insideGroup =
          (hit != null && selection.contains(hit.id)) ||
          (hit == null && frame != null && _frameContains(frame, page));
      if (insideGroup) {
        _pressed(hit);
        return _PointerAction.move;
      }
    }

    if (hit != null && (widget.claimsPointer?.call(hit, page) ?? false)) {
      return _PointerAction.claimed;
    }
    _pressed(hit);
    if (hit != null) {
      if (!selection.contains(hit.id)) _controller.select(hit.id);
      return _PointerAction.move;
    }
    // A finger dragged across empty canvas scrolls it, as it would any other
    // surface on a phone; a mouse drags out a selection rectangle instead.
    return event.kind == PointerDeviceKind.touch
        ? _PointerAction.panOrTap
        : _PointerAction.marquee;
  }

  static bool _frameContains(SelectionFrame frame, Offset page) => Frame(
    x: frame.center.dx - frame.width / 2,
    y: frame.center.dy - frame.height / 2,
    width: frame.width,
    height: frame.height,
    rotation: frame.rotation,
  ).containsPoint(page.dx, page.dy);

  void _pressed(NoteElement? hit) => widget.onCanvasPress?.call(hit);

  // --------------------------------------------------------------- transform

  void _updateTransform(Offset page) {
    final gesture = _transform;
    if (gesture == null) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final List<NoteElement> updated;

    if (gesture.handle == SelectionHandle.rotate) {
      final center = gesture.frame.center;
      var angle =
          math.atan2(page.dy - center.dy, page.dx - center.dx) -
          gesture.startAngle;
      final single = gesture.originals.length == 1
          ? gesture.originals.single
          : null;
      if (single != null && single is! InkElement) {
        // A lone object snaps by where it ends up: upright, sideways,
        // diagonal.
        final start = single.frame.rotation;
        angle =
            ElementTransforms.snapRotation(start + angle, fine: shift) - start;
      } else {
        angle = ElementTransforms.snapRotation(angle, fine: shift);
      }
      updated = <NoteElement>[
        for (final element in gesture.originals)
          ElementTransforms.rotate(element, angle, center),
      ];
    } else if (gesture.originals.length == 1) {
      final original = gesture.originals.single;
      // A text box's height follows its text, which reflows as the box is
      // resized; the height it has now is kept rather than the one it
      // started with.
      final height =
          SelectionHandles.behaviorOf(original) == ResizeBehavior.horizontal
          ? _controller.document.elementById(original.id)?.frame.height
          : null;
      updated = <NoteElement>[
        ElementTransforms.resize(
          original,
          gesture.handle,
          page - gesture.pressPage,
          height: height,
        ),
      ];
    } else {
      // A group scales about its opposite corner, by how far the handle has
      // been dragged along the diagonal; by a side, it stretches in that
      // direction alone, about the opposite side.
      final anchor = gesture.frame.oppositeOf(gesture.handle);
      final start = gesture.frame.anchorOf(gesture.handle) - anchor;
      final now = start + (page - gesture.pressPage);
      final handle = gesture.handle;
      if (handle.isSide) {
        final horizontal =
            handle == SelectionHandle.left || handle == SelectionHandle.right;
        final extent = horizontal ? start.dx : start.dy;
        if (extent == 0) return;
        final factor = math.max(0.05, (horizontal ? now.dx : now.dy) / extent);
        updated = <NoteElement>[
          for (final element in gesture.originals)
            ElementTransforms.stretch(
              element,
              horizontal ? factor : 1,
              horizontal ? 1 : factor,
              anchor,
            ),
        ];
      } else {
        final lengthSquared = start.distanceSquared;
        if (lengthSquared == 0) return;
        final factor = math.max(
          0.05,
          (now.dx * start.dx + now.dy * start.dy) / lengthSquared,
        );
        updated = <NoteElement>[
          for (final element in gesture.originals)
            ElementTransforms.scale(element, factor, anchor),
        ];
      }
    }
    _controller.replaceElements(updated, recordUndo: _takeUndoRecord());
  }

  // ------------------------------------------------------------------- pinch

  void _beginPinch() {
    // A second finger means the user wants to navigate, so whatever the first
    // finger started is abandoned rather than finished.
    if (_action == _PointerAction.draw) _controller.cancelStroke();
    setState(() {
      _action = _PointerAction.pinch;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
      _transform = null;
    });
  }

  void _updatePinch(int pointer, Offset position) {
    if (_touches.length < 2) {
      _touches[pointer] = position;
      return;
    }
    final before = _touches.values.take(2).toList();
    _touches[pointer] = position;
    final after = _touches.values.take(2).toList();

    final beforeCenter = (before[0] + before[1]) / 2;
    final afterCenter = (after[0] + after[1]) / 2;
    final beforeSpan = (before[0] - before[1]).distance;
    final afterSpan = (after[0] - after[1]).distance;

    _controller.panBy(afterCenter - beforeCenter);
    if (beforeSpan > 0 && afterSpan > 0) {
      _controller.zoomBy(afterSpan / beforeSpan, afterCenter);
    }
  }

  // ------------------------------------------------------------------ scroll

  void _onPointerSignal(PointerSignalEvent event) {
    _stopFling();
    switch (event) {
      case PointerScrollEvent():
        if (_isZoomModifierPressed) {
          _zoomByScroll(event.scrollDelta.dy, event.localPosition);
          return;
        }
        final delta = HardwareKeyboard.instance.isShiftPressed
            ? Offset(event.scrollDelta.dy, 0)
            : event.scrollDelta;
        _controller.panBy(-delta);
      case PointerScaleEvent():
        _controller.zoomBy(event.scale, event.localPosition);
      case _:
        break;
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _stopFling();
    final current = _trackpad;
    // A start while a gesture is under way is the other stream beginning —
    // on Linux a pinch starting before the scroll has reported its end. The
    // scroll carries on counting from its own total, so that is kept.
    _trackpad = _TrackpadGesture(lastPan: current?.lastPan ?? Offset.zero);
  }

  /// A trackpad gesture: two-finger scrolling and pinching.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _stopFling();
    final gesture = _trackpad;
    if (gesture == null) {
      // An update without a start: one stream ended the gesture while the
      // other is still going. Carry on from here rather than drop it.
      _trackpad = _TrackpadGesture(lastPan: event.pan, lastScale: event.scale);
      return;
    }

    // The running pan is followed in window coordinates. Flutter's localPan
    // converts it as though it were a point, subtracting where the canvas
    // sits in the window: measured from the zero a gesture starts at, the
    // page jumped by the width of the sidebars and the height of the ribbon
    // at the start of every scroll.
    final pan = PointerEvent.transformDeltaViaPositions(
      transform: event.transform,
      untransformedEndPosition: event.position,
      untransformedDelta: _panStep(gesture, event.pan),
    );
    final scale = _scaleStep(gesture, event.scale, event.pan);
    // The pointer stays where it is while fingers move on a trackpad, so it
    // is what a pinch zooms about, as everywhere else on the desktop.
    final focus = _mousePosition ?? event.localPosition;

    if (_isZoomModifierPressed) {
      // Ctrl with a two-finger swipe zooms, as Ctrl with the wheel does.
      _zoomByScroll(-pan.dy, focus);
      return;
    }
    if (scale != 1) {
      gesture.zoomed = true;
      _controller.zoomBy(scale, focus);
    }
    if (pan != Offset.zero) {
      _controller.panBy(pan);
      gesture.steps.add((event.timeStamp, pan));
      while (gesture.steps.length > 12) {
        gesture.steps.removeAt(0);
      }
    }
  }

  /// How far this event moves the page, in window coordinates.
  Offset _panStep(_TrackpadGesture gesture, Offset total) {
    // A pinch reports no pan at all; in the middle of a scroll that is the
    // other stream speaking, not the fingers going back to where they began.
    if (total == Offset.zero && gesture.lastPan != Offset.zero) {
      return Offset.zero;
    }
    final step = (total - gesture.lastPan) * widget.trackpadPanScale;
    gesture.lastPan = total;
    return step.distance > _maxPanStep ? Offset.zero : step;
  }

  /// How much this event zooms by, as a factor.
  double _scaleStep(_TrackpadGesture gesture, double total, Offset pan) {
    if (total <= 0) return 1;
    if (total == 1 && gesture.lastScale != 1) {
      // Exactly 1 after a change is not a pinch moving. With a pan it is the
      // scroll stream, which always reports 1; without, a pinch that paused
      // and resumed, restarting its count at 1.
      if (pan == Offset.zero) {
        gesture
          ..lastScale = 1
          ..pinchBase = 1;
      }
      return 1;
    }
    final step = total / gesture.lastScale;
    gesture.lastScale = total;
    if (step > _maxScaleStep || step < 1 / _maxScaleStep) {
      gesture.pinchBase = total;
      return 1;
    }
    if (gesture.pinching) return step;

    // Not a pinch until the fingers have clearly spread or closed; from then
    // on it zooms by what lies beyond the slop, so it starts without a jump.
    final spread = total / gesture.pinchBase;
    if (spread < _pinchSlop && spread > 1 / _pinchSlop) return 1;
    gesture.pinching = true;
    return spread >= _pinchSlop ? spread / _pinchSlop : spread * _pinchSlop;
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    final gesture = _trackpad;
    _trackpad = null;
    if (gesture == null || gesture.zoomed || gesture.steps.length < 3) return;

    // Momentum from the last moments of a two-finger scroll, as scrolling
    // elsewhere on the desktop has; a pinch ends where the fingers leave it.
    final last = gesture.steps.last.$1;
    // A pause before lifting the fingers means the scroll was placed, not
    // thrown.
    if (event.timeStamp - last > const Duration(milliseconds: 60)) return;
    var distance = Offset.zero;
    Duration? first;
    var count = 0;
    for (final (time, delta) in gesture.steps.reversed) {
      if (last - time > const Duration(milliseconds: 100)) break;
      // The newest step's distance was covered since the one before it, so
      // the oldest step in the window only marks where the time starts.
      if (first != null) distance += delta;
      first = time;
      count++;
    }
    if (first == null || count < 3) return;
    // Measured over at least a few frames, so two events delivered together
    // cannot make a tiny movement look like a very fast one.
    final seconds = (last - first).inMicroseconds / 1e6;
    if (seconds < 0.02) return;
    var velocity = distance / seconds;
    if (velocity.distance > _maxFlingSpeed) {
      velocity = velocity * (_maxFlingSpeed / velocity.distance);
    }
    _startFling(velocity);
  }

  void _zoomByScroll(double scrollDelta, Offset focus) {
    final factor = math.exp(-scrollDelta * _scrollZoomRate).clamp(0.8, 1.25);
    _controller.zoomBy(factor, focus);
  }

  bool get _isZoomModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  // ------------------------------------------------------------------- fling

  void _startFling(Offset velocity) {
    if (velocity.distance < _minFlingSpeed) return;
    _flingVelocity = velocity;
    _lastFlingTick = Duration.zero;
    _fling
      ..stop()
      ..start();
  }

  void _stopFling() {
    if (_fling.isActive) _fling.stop();
  }

  void _onFlingTick(Duration elapsed) {
    final seconds = (elapsed - _lastFlingTick).inMicroseconds / 1e6;
    _lastFlingTick = elapsed;
    if (seconds <= 0) return;
    // The exact distance an exponentially slowing fling covers in this time,
    // so it goes as far at 30 frames a second as at 120.
    final decay = math.exp(-seconds / _flingDecay);
    _controller.panBy(_flingVelocity * (_flingDecay * (1 - decay)));
    _flingVelocity *= decay;
    if (_flingVelocity.distance < 20) _fling.stop();
  }

  // ------------------------------------------------------------------- hover

  void _onHover(PointerHoverEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mousePosition = event.localPosition;
    }
    final cursor = _cursorAt(event.localPosition);
    if (cursor != _hoverCursor) setState(() => _hoverCursor = cursor);
  }

  MouseCursor _cursorAt(Offset screen) {
    if (_controller.tool != CanvasTool.select) return MouseCursor.defer;
    final selected = _controller.selectedElements;
    if (selected.isNotEmpty) {
      final handle = SelectionHandles.hitTest(
        selected,
        _controller.viewport,
        screen,
      );
      if (handle != null) {
        final frame = SelectionFrame.around(selected);
        return _cursorForHandle(handle, frame?.rotation ?? 0);
      }
    }
    final hit = _controller.hitTest(_controller.viewport.toPage(screen));
    return hit == null ? MouseCursor.defer : SystemMouseCursors.move;
  }

  /// A resize cursor pointing the way the handle drags, turned with the box.
  static MouseCursor _cursorForHandle(SelectionHandle handle, double rotation) {
    final base = switch (handle) {
      SelectionHandle.rotate => null,
      SelectionHandle.left || SelectionHandle.right => 0.0,
      SelectionHandle.top || SelectionHandle.bottom => math.pi / 2,
      SelectionHandle.topLeft || SelectionHandle.bottomRight => math.pi / 4,
      SelectionHandle.topRight || SelectionHandle.bottomLeft => -math.pi / 4,
    };
    if (base == null) return SystemMouseCursors.grab;
    final octant = (((base + rotation) / (math.pi / 4)).round()) % 4;
    return switch (octant) {
      0 => SystemMouseCursors.resizeLeftRight,
      1 => SystemMouseCursors.resizeUpLeftDownRight,
      2 => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }

  double get _eraserRadius =>
      _controller.viewport.toPageDistance(12).clamp(4.0, 64.0);

  /// Maps a device's raw pressure onto 0..1.
  ///
  /// Devices that do not report pressure leave min and max equal, in which case
  /// a firm, constant stroke is the right default.
  static double _normalizedPressure(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) return 1;
    return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final controller = _controller..viewSize = _size;
        final viewport = controller.viewport;
        final elements = controller.visibleElements(_size);
        final ink = <InkElement>[
          for (final element in elements)
            if (element is InkElement) element,
        ];

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerHover: _onHover,
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          onPointerPanZoomEnd: _onPanZoomEnd,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: _hoverCursor == MouseCursor.defer
                ? _cursorFor(controller.tool)
                : _hoverCursor,
            child: ClipRect(
              // Only the element layer takes pointers. The painted layers
              // would otherwise count as hit everywhere — a CustomPaint does by
              // default — and the ones above the elements would swallow every
              // press meant for a text box.
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: BackgroundPainter(
                          background: controller.document.canvas.background,
                          viewport: viewport,
                          paperWidth: controller.document.canvas.paperWidth,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: InkPainter(
                          elements: ink,
                          viewport: viewport,
                          layer: InkLayer.beneath,
                        ),
                      ),
                    ),
                  ),
                  CanvasScope(
                    zoom: viewport.zoom,
                    child: _ElementLayer(
                      elements: elements,
                      viewport: viewport,
                      builder: widget.elementBuilder,
                      onDoubleTap: widget.onElementDoubleTap,
                    ),
                  ),
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: InkPainter(
                          elements: ink,
                          viewport: viewport,
                          layer: InkLayer.above,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: WetInkPainter(
                          points: controller.wetPoints,
                          pen: controller.pen,
                          viewport: viewport,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: SelectionPainter(
                          selected: controller.selectedElements,
                          viewport: viewport,
                          accent: Theme.of(context).colorScheme.primary,
                          marquee: _marquee,
                        ),
                      ),
                    ),
                  ),
                  // Above everything: a press on a handle or a side of the
                  // selection is the canvas's alone. Without this the text
                  // box beneath the edge would take it too, placing its caret
                  // and selecting text while the box is resized.
                  _HandleTargets(hits: _onHandle),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Whether a mouse press at [screen] would take hold of the selection's
  /// handles or sides.
  bool _onHandle(Offset screen) {
    if (_controller.tool != CanvasTool.select) return false;
    final selected = _controller.selectedElements;
    return selected.isNotEmpty &&
        SelectionHandles.hitTest(selected, _controller.viewport, screen) !=
            null;
  }

  static MouseCursor _cursorFor(CanvasTool tool) => switch (tool) {
    CanvasTool.pen ||
    CanvasTool.highlighter ||
    CanvasTool.eraser => SystemMouseCursors.precise,
    CanvasTool.select => SystemMouseCursors.basic,
  };
}

/// Positions element widgets over the canvas.
///
/// Each element is placed at its on-screen rectangle and scaled from page
/// units, rather than the whole layer being transformed. Keeping every child
/// inside the viewport's own box is what lets them receive hits and keyboard
/// focus, which a transformed, overflowing layer would silently lose.
class _ElementLayer extends StatelessWidget {
  const _ElementLayer({
    required this.elements,
    required this.viewport,
    required this.builder,
    this.onDoubleTap,
  });

  final List<NoteElement> elements;
  final CanvasViewport viewport;
  final CanvasElementBuilder? builder;
  final void Function(NoteElement element)? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final build = builder;
    if (build == null) return const SizedBox.shrink();

    final zoom = viewport.zoom;
    final children = <Widget>[];
    for (final element in elements) {
      if (element is InkElement) continue;

      final content = build(context, element);
      if (content == null) continue;

      final frame = element.frame;
      // The element is laid out at its size in page units and then scaled as
      // a whole; scaling the constraints instead would reflow text
      // differently at every zoom level. It is placed in the box around its
      // turned shape, so every visible part of it is inside its parent and can
      // be hit. The structure is the same at any angle, so turning an element
      // never rebuilds it from scratch.
      final box = frame.rotatedBounds;
      final placed = OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.rotate(
          angle: frame.rotation,
          child: SizedBox(
            width: frame.width * zoom,
            height: frame.height * zoom,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: content,
              ),
            ),
          ),
        ),
      );

      final topLeft = viewport.toScreen(Offset(box.left, box.top));
      children.add(
        Positioned(
          // Keyed by identity so an element keeps its widget state — a text
          // box its caret, a PDF page its rendered image — while others are
          // added, removed or scrolled out of view around it.
          key: ValueKey<String>(element.id),
          left: topLeft.dx,
          top: topLeft.dy,
          width: box.width * zoom,
          height: box.height * zoom,
          child: GestureDetector(
            onDoubleTap: onDoubleTap == null
                ? null
                : () => onDoubleTap!(element),
            behavior: HitTestBehavior.deferToChild,
            child: placed,
          ),
        ),
      );
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }
}

/// Takes pointer presses on the selection's handles and sides, so that they
/// reach only the canvas and not the element under the edge.
///
/// Its own parent's listener still sees the press, since it is an ancestor
/// of this; what it keeps out are the element widgets beneath in the stack.
class _HandleTargets extends LeafRenderObjectWidget {
  const _HandleTargets({required this.hits});

  final bool Function(Offset position) hits;

  @override
  _RenderHandleTargets createRenderObject(BuildContext context) =>
      _RenderHandleTargets(hits);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHandleTargets renderObject,
  ) {
    renderObject.hits = hits;
  }
}

class _RenderHandleTargets extends RenderBox {
  _RenderHandleTargets(this.hits);

  bool Function(Offset position) hits;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => hits(position);
}
