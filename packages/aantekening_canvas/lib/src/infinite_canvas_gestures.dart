part of 'infinite_canvas.dart';

/// Moving the view: resizing and turning the selection, pinching, and
/// scrolling with a wheel or a touchpad.
extension _Gestures on _InfiniteCanvasState {
  /// How far two fingers must spread or close, as a ratio, before a trackpad
  /// gesture zooms. Fingers scrolling side by side drift apart a little, and
  /// a touchpad can report the start of a scroll as a pinch; zooming on that
  /// drift made the page lurch at the start of a scroll.
  static const double _pinchSlop = 1.04;

  /// The largest zoom change one trackpad event can plausibly carry.
  static const double _maxScaleStep = 1.33;

  /// The largest pan, in pixels, one trackpad event can plausibly carry.
  /// Events arrive dozens of times a second, so even a fast swipe moves a few
  /// dozen pixels in one; anything beyond this is a platform's running total
  /// starting over, not movement.
  static const double _maxPanStep = 240;

  /// The least speed, in pixels per second, of a flick that adds to the
  /// coasting it caught: a flick made on purpose, not fingers settling as
  /// they are put down to stop the page.
  static const double _flickAgain = 600;

  /// The shortest scroll, in pixels, taken for a mouse wheel's notch, which
  /// the view glides through rather than jumping at once: a touchpad or a
  /// wheel that turns freely reports far less at a time, as smoothly as it
  /// can be followed.
  static const double _notch = 20;

  /// Zoom change per logical pixel of scrolling while Ctrl is held.
  ///
  /// Applied exponentially, so a mouse-wheel notch (about 50 px on Linux and
  /// Windows) zooms by roughly ten percent, and a trackpad swipe of the same
  /// distance zooms by the same amount spread smoothly across its events.
  static const double _scrollZoomRate = 0.002;
  void _updateTransform(Offset pointer) {
    final gesture = _transform;
    if (gesture == null) return;
    // A handle is dragged no further than the page's top and left edges.
    final page = gesture.handle == SelectionHandle.rotate
        ? pointer
        : Offset(math.max(0, pointer.dx), math.max(0, pointer.dy));
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
          ? _controller.elementById(original.id)?.frame.height
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

  void _beginPinch() {
    // A second finger means the user wants to navigate, so whatever the first
    // finger started is abandoned rather than finished.
    if (_action == _PointerAction.draw) _controller.cancelStroke();
    _update(() {
      _action = _PointerAction.pinch;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
      _lasso = null;
      _transform = null;
    });
    _syncZooming();
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

    _controller.stretchBy(afterCenter - beforeCenter);
    if (beforeSpan > 0 && afterSpan > 0) {
      _controller.stretchZoomBy(afterSpan / beforeSpan, afterCenter);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    _motion.brake();
    switch (event) {
      case PointerScrollEvent():
        if (_isZoomModifierPressed) {
          // Glided through, notch or not: a zoom at every event would lay
          // the page out again at every one.
          _motion.glideZoom(
            _scrollZoom(event.scrollDelta.dy),
            event.localPosition,
          );
          _syncZooming();
          return;
        }
        final pan = -(HardwareKeyboard.instance.isShiftPressed
            ? Offset(event.scrollDelta.dy, 0)
            : event.scrollDelta);
        if (pan.distance >= _notch) {
          _motion.glide(pan);
        } else {
          _controller.panBy(pan);
        }
      case PointerScaleEvent():
        _controller.zoomBy(event.scale, event.localPosition);
      case _:
        break;
    }
  }

  /// Fingers put down on the touchpad, before they move: they catch the
  /// page as a scroll's start would, and lifted again without moving leave
  /// it where they caught it.
  void _onTouchpadFingers() {
    switch (widget.touchpadFingers!.value) {
      case TouchpadFingers.resting:
        _caught = _motion.velocity;
        _motion.stop();
      case TouchpadFingers.lifted:
        _caught = Offset.zero;
        _motion.settle();
      case TouchpadFingers.moving:
        break;
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    // Caught by fingers resting first, it was caught going as fast as it
    // went then.
    if (_motion.isMoving) _caught = _motion.velocity;
    _motion.stop();
    final current = _trackpad;
    // A start while a gesture is under way is the other stream beginning —
    // on Linux a pinch starting before the scroll has reported its end. The
    // scroll carries on counting from its own total, so that is kept.
    _trackpad = _TrackpadGesture(lastPan: current?.lastPan ?? Offset.zero);
  }

  /// A trackpad gesture: two-finger scrolling and pinching.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!mounted) return;
    _motion.stop();
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
    // page jumped by the width of the sidebars and the height of the status
    // line at the start of every scroll.
    // The page follows the fingers exactly, and coasts on as they lift.
    final pan = PointerEvent.transformDeltaViaPositions(
      transform: event.transform,
      untransformedEndPosition: event.position,
      untransformedDelta: _panStep(gesture, event.pan),
    );
    // An event whose own scale moves is zooming: its pan is what zooming
    // about the fingers moved, as Windows reports a pinch, and the page is
    // zoomed about the pointer instead. Scrolls report a scale of exactly 1.
    final zooming = event.scale != 1 && event.scale != gesture.lastScale;
    final scale = _scaleStep(gesture, event.scale, event.pan);
    // The pointer stays where it is while fingers move on a trackpad, so it
    // is what a pinch zooms about, as everywhere else on the desktop.
    final focus = _mousePosition ?? event.localPosition;

    if (_isZoomModifierPressed) {
      // Ctrl with a two-finger swipe zooms, as Ctrl with the wheel does.
      if (pan.dy == 0) return;
      gesture.zoomed = true;
      _syncZooming();
      _controller.zoomBy(_scrollZoom(-pan.dy), focus);
      return;
    }
    if (scale != 1) {
      gesture.zoomed = true;
      _syncZooming();
      _controller.stretchZoomBy(scale, focus);
    }
    if (pan != Offset.zero && !zooming) {
      _controller.stretchBy(pan);
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
    if (!mounted) return;
    final gesture = _trackpad;
    _trackpad = null;
    _syncZooming();
    final flick = gesture == null ? Offset.zero : _flick(gesture, event);
    final caught = _caught;
    _caught = Offset.zero;
    // Flicked again the way it was coasting, it goes faster still. Only a
    // flick: fingers put down to stop it barely move, and lifted again
    // leave it where they caught it, whichever way they moved.
    final again =
        flick.distance >= _flickAgain &&
        flick.dx * caught.dx + flick.dy * caught.dy > 0;
    _motion.fling(again ? flick + caught : flick);
  }

  /// How fast the fingers were moving as they lifted from a two-finger
  /// scroll, in pixels per second, for it to coast on as scrolling elsewhere
  /// on the desktop does; nothing, if they were not moving, or pinched.
  Offset _flick(_TrackpadGesture gesture, PointerPanZoomEndEvent event) {
    if (gesture.zoomed || gesture.steps.length < 3) return Offset.zero;
    final last = gesture.steps.last.$1;
    // A pause before lifting the fingers means the scroll was placed, not
    // thrown.
    if (event.timeStamp - last > const Duration(milliseconds: 60)) {
      return Offset.zero;
    }
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
    if (first == null || count < 3) return Offset.zero;
    // Measured over at least a few frames, so two events delivered together
    // cannot make a tiny movement look like a very fast one.
    final seconds = (last - first).inMicroseconds / 1e6;
    return seconds < 0.02 ? Offset.zero : distance / seconds;
  }

  /// How much a scroll of [scrollDelta] pixels with Ctrl held zooms by.
  static double _scrollZoom(double scrollDelta) =>
      math.exp(-scrollDelta * _scrollZoomRate).clamp(0.8, 1.25);

  bool get _isZoomModifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
}
