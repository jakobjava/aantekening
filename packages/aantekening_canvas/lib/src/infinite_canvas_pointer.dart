part of 'infinite_canvas.dart';

/// Presses on the page: what each one does, by tool and by what it lands
/// on, as it moves and as it ends.
extension _Pointer on _InfiniteCanvasState {
  /// Maps a device's raw pressure onto 0..1.
  ///
  /// Devices that do not report pressure leave min and max equal, in which case
  /// a firm, constant stroke is the right default.
  static double _normalizedPressure(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) return 1;
    return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
  }

  /// How far, in screen pixels, what draws trembles held still: a hand
  /// pressing a pen or a finger to the screen moves more than one resting
  /// on a mouse.
  static double _restSlopOf(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse || PointerDeviceKind.trackpad => 4,
    PointerDeviceKind.touch => 12,
    _ => 10,
  };

  /// How long the pen is held still to make a stroke a shape.
  static const Duration _holdToShape = Duration(milliseconds: 500);

  /// How far a press may wander, in screen pixels, and still count as a click.
  static const double _mouseTapSlop = 4;
  void _onPointerDown(PointerDownEvent event) {
    if (event.pointer == _claimedPointer) return;
    _motion.brake();
    _placeNib(event);
    if (event.kind == PointerDeviceKind.mouse) {
      _mousePosition = event.localPosition;
      if (event.buttons & kSecondaryMouseButton != 0) {
        _contextMenu(event);
        return;
      }
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
      case _PointerAction.draw when _controller.tool == CanvasTool.shape:
        _controller.beginShape(page);
      case _PointerAction.draw:
        _strokeSheet = _sheetAt(event.localPosition);
        _controller.beginStroke(
          page,
          pressure: _normalizedPressure(event),
          tilt: event.tilt,
        );
        _restSlop = _restSlopOf(event.kind);
        _restAt(event.localPosition);
      case _PointerAction.erase:
        _controller.eraseAt(page, radius: _eraserRadius);
      case _PointerAction.marquee:
        _marqueeAnchor = page;
        _marquee = Aabb(page.dx, page.dy, page.dx, page.dy);
        if (!HardwareKeyboard.instance.isShiftPressed) {
          _controller.clearSelection();
        }
      case _PointerAction.lasso:
        _lasso = Lasso(page);
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

  /// The rest of a gesture begun on the canvas comes here even once the
  /// canvas has gone — a press that opened another page, say — and is let
  /// go of: the page it was on is no longer here to act on.
  void _onPointerMove(PointerMoveEvent event) {
    if (!mounted) return;
    _placeNib(event);
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
      // Written off the sheet it began on, a line is cut there, as it would
      // be at the edge of paper, not drawn along the edge.
      case _PointerAction.draw
          when _strokeSheet != null &&
              !_controller.isShaping &&
              _controller.tool != CanvasTool.shape &&
              _sheetAt(event.localPosition) != _strokeSheet:
        break;
      case _PointerAction.draw:
        _controller.extendStroke(
          page,
          pressure: _normalizedPressure(event),
          tilt: event.tilt,
          constrain: HardwareKeyboard.instance.isShiftPressed,
        );
        // Moved on from where it rested, the pen is waited for anew — a
        // stroke that was no shape where it paused may be one further on.
        if (!_controller.isShaping &&
            _controller.tool != CanvasTool.shape &&
            (event.localPosition - _restingAt).distance > _restSlop) {
          _restAt(event.localPosition);
        }
      case _PointerAction.erase:
        _controller.eraseAt(page, radius: _eraserRadius);
      case _PointerAction.pan:
      case _PointerAction.panOrTap:
        _controller.stretchBy(screenDelta);
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
        _update(() {
          _marquee = Aabb(
            math.min(anchor.dx, page.dx),
            math.min(anchor.dy, page.dy),
            math.max(anchor.dx, page.dx),
            math.max(anchor.dy, page.dy),
          );
        });
      case _PointerAction.lasso:
        final lasso = _lasso;
        // A point for every couple of pixels the loop goes round.
        if (lasso == null ||
            (page - lasso.points.last).distance <
                _controller.viewport.toPageDistance(2)) {
          break;
        }
        _update(() => _lasso = lasso.extendedTo(page));
      case _PointerAction.claimed:
      case _PointerAction.pinch:
      case _PointerAction.none:
        break;
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (!mounted) return;
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
      case _PointerAction.lasso:
        final additive = HardwareKeyboard.instance.isShiftPressed;
        final lasso = _lasso;
        if (_dragged && lasso != null) {
          _controller.selectWithin(lasso, additive: additive);
        } else if (_controller.hitTest(page) case final hit?) {
          // A tap picks what it lands on, as the select tool's does.
          _controller.select(hit.id, additive: additive);
        }
      case _PointerAction.panOrTap:
      case _PointerAction.pan:
        if (!_dragged && _action == _PointerAction.panOrTap) {
          widget.onEmptyTap?.call(page);
        } else if (event is PointerUpEvent) {
          final velocity = _touchVelocity?.getVelocity().pixelsPerSecond;
          if (velocity != null) _motion.fling(velocity);
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
    if (!mounted) return;
    _touches.remove(event.pointer);
    if (_action == _PointerAction.pinch) {
      if (_touches.isEmpty) _resetPointer();
      return;
    }
    if (event.pointer != _activePointer) return;
    _controller.cancelStroke();
    _resetPointer();
  }

  /// Starts waiting for the pen, come to rest at [screen], to stay there.
  void _restAt(Offset screen) {
    _restingAt = screen;
    _hold?.cancel();
    if (widget.shapesOnHold) _hold = Timer(_holdToShape, _heldStill);
  }

  /// The pen held still: the stroke becomes the shape it was drawn as, if
  /// it is one, and the pen then reshapes it.
  void _heldStill() {
    _hold = null;
    if (_action == _PointerAction.draw &&
        _controller.snapToShape(
          settled: _controller.viewport.toPageDistance(_restSlop),
        )) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _resetPointer() {
    _hold?.cancel();
    _hold = null;
    _motion.settle();
    _update(() {
      _action = _PointerAction.none;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
      _lasso = null;
      _transform = null;
      _touchVelocity = null;
    });
    _syncZooming();
  }

  void _syncZooming() => _zooming.value =
      _action == _PointerAction.pinch ||
      (_trackpad?.zoomed ?? false) ||
      _motion.isZooming;

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
    // Space-drag always pans, whatever tool is selected, so navigating
    // never costs a trip to the toolbar.
    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.space,
    )) {
      return _PointerAction.pan;
    }
    // The desk about sheets is held to move them, unless the press is on
    // a handle of what is picked, which may reach out over it.
    if (_onDesk(event.localPosition) &&
        _handleAt(event, _controller.selectedElements) == null) {
      return _PointerAction.pan;
    }
    // A pen's other end erases, and its buttons do what they were given to.
    if (event.kind == PointerDeviceKind.invertedStylus) {
      _pressed(null);
      return _PointerAction.erase;
    }
    if (event.kind == PointerDeviceKind.stylus) {
      switch (widget.penButtons.actionFor(event.buttons)) {
        case PenButtonAction.erase:
          _pressed(null);
          return _PointerAction.erase;
        case PenButtonAction.select:
          return _resolveSelectAction(event, page);
        case PenButtonAction.lasso:
          return _resolveLassoAction(event, page);
        case PenButtonAction.scroll:
          return _PointerAction.pan;
        case PenButtonAction.none || null:
          break;
      }
    } else if (event.buttons & kMiddleMouseButton != 0) {
      // The middle button pans too. A pen's second button is numbered as
      // it is, and does what it was given to instead.
      return _PointerAction.pan;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kPrimaryMouseButton == 0) {
      return _PointerAction.none;
    }

    switch (_controller.tool) {
      case CanvasTool.pen:
      case CanvasTool.highlighter:
      case CanvasTool.shape:
        _pressed(null);
        return _PointerAction.draw;
      case CanvasTool.eraser:
        _pressed(null);
        return _PointerAction.erase;
      case CanvasTool.select:
        return _resolveSelectAction(event, page);
      case CanvasTool.lasso:
        return _resolveLassoAction(event, page);
    }
  }

  /// Whether [screen] lies on the desk about the sheets of a page shown as
  /// pages.
  bool _onDesk(Offset screen) =>
      _controller.fold != null && _sheetAt(screen) == null;

  /// The sheet [screen] lies on, of a page shown as pages; null on the desk
  /// about them, or on one paper.
  int? _sheetAt(Offset screen) {
    final view = _controller.viewport;
    final fold = view.fold;
    if (fold == null) return null;
    final at = view.origin + screen / view.zoom;
    final sheet = fold.sheetNear(at.dy);
    return fold.sheetInView(sheet).contains(at) ? sheet : null;
  }

  /// The handle of the [selected] elements [event] presses on, if any.
  SelectionHandle? _handleAt(
    PointerDownEvent event,
    List<NoteElement> selected,
  ) => selected.isEmpty
      ? null
      : SelectionHandles.hitTest(
          selected,
          _controller.viewport,
          event.localPosition,
          reach: event.kind == PointerDeviceKind.touch
              ? SelectionHandles.touchReach
              : SelectionHandles.mouseReach,
        );

  /// A lasso's press: on the selection's handles, it resizes or turns it;
  /// anywhere in its box, it moves it; anywhere else, it draws a loop.
  _PointerAction _resolveLassoAction(PointerDownEvent event, Offset page) {
    final selected = _controller.selectedElements;
    if (_onSelectionHandle(event, page, selected) case final action?) {
      return action;
    }
    final frame = SelectionFrame.around(selected);
    if (frame != null && frame.contains(page)) {
      _pressed(selected.length == 1 ? selected.single : null);
      return _PointerAction.move;
    }
    _pressed(null);
    return _PointerAction.lasso;
  }

  /// A press on one of the handles about the [selected] elements: a resize
  /// or a turn of them, or null if it is on none.
  _PointerAction? _onSelectionHandle(
    PointerDownEvent event,
    Offset page,
    List<NoteElement> selected,
  ) {
    final handle = _handleAt(event, selected);
    final frame = SelectionFrame.around(selected);
    if (handle == null || frame == null) return null;
    _transform = _TransformGesture(
      handle: handle,
      originals: selected,
      frame: frame,
      pressPage: page,
    );
    _pressed(selected.length == 1 ? selected.single : null);
    return _PointerAction.transform;
  }

  _PointerAction _resolveSelectAction(PointerDownEvent event, Offset page) {
    final selected = _controller.selectedElements;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Handles come first: they sit on and around the box, where a press would
    // otherwise land on an element or on empty canvas.
    if (_onSelectionHandle(event, page, selected) case final action?) {
      return action;
    }

    final grips = widget.grips;
    if (grips != null) {
      for (final element in selected.reversed) {
        if (!grips(element, page)) continue;
        _pressed(element);
        if (!_controller.selection.contains(element.id)) {
          _controller.select(element.id);
        }
        return _PointerAction.move;
      }
    }

    final hit = _controller.hitTest(page);
    final selection = _controller.selection;

    // The header takes its own presses where no element lies over it.
    if (hit == null &&
        (widget.header?.frame.containsPoint(page.dx, page.dy) ?? false)) {
      return _PointerAction.claimed;
    }

    // Shift adds to the selection or takes away from it, whatever is clicked.
    if (hit != null && shift) {
      _pressed(hit);
      _controller.select(hit.id, additive: true);
      return _PointerAction.move;
    }

    // A group is picked up by any of its members, text boxes included.
    if (_controller.pressesGroup(page, hit)) {
      _pressed(hit);
      return _PointerAction.move;
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

  void _pressed(NoteElement? hit) => widget.onCanvasPress?.call(hit);

  /// A right-click: the host's menu, unless an element's widget answers it.
  /// On several things picked together, it is the host's for all of them.
  void _contextMenu(PointerDownEvent event) {
    final page = _controller.viewport.toPage(event.localPosition);
    final hit = _controller.hitTest(page);
    if (hit != null &&
        !_controller.pressesGroup(page, hit) &&
        (widget.claimsPointer?.call(hit, page) ?? false)) {
      return;
    }
    widget.onContextMenu?.call(page, event.position);
  }
}
