part of 'infinite_canvas.dart';

/// What the pointer shows while it hovers: the nib, and the cursor.
extension _Hover on _InfiniteCanvasState {
  void _onHover(PointerHoverEvent event) {
    _placeNib(event);
    if (event.kind == PointerDeviceKind.mouse) {
      _mousePosition = event.localPosition;
    }
    final cursor = _cursorAt(event.localPosition);
    if (cursor != _hoverCursor) _update(() => _hoverCursor = cursor);
  }

  /// Puts the nib where [event] is, if a mouse or a pen: a finger has no
  /// cursor, and the desk about sheets is not written on.
  void _placeNib(PointerEvent event) {
    if (_onDesk(event.localPosition)) {
      _nib.value = null;
      return;
    }
    _nib.value = switch (event.kind) {
      PointerDeviceKind.mouse ||
      PointerDeviceKind.stylus => (at: event.localPosition, erasing: false),
      PointerDeviceKind.invertedStylus => (
        at: event.localPosition,
        erasing: true,
      ),
      _ => null,
    };
  }

  MouseCursor _cursorAt(Offset screen) {
    // The desk is held to move the sheets on it.
    if (_onDesk(screen) && !_onHandle(screen)) return SystemMouseCursors.grab;
    if (!_controller.tool.selects) return MouseCursor.defer;
    final selected = _controller.selectedElements;
    if (selected.isNotEmpty) {
      final handle = SelectionHandles.hitTest(
        selected,
        _controller.viewport,
        screen,
      );
      if (handle != null) {
        final frame = SelectionFrame.around(selected);
        return SelectionHandles.cursorFor(handle, frame?.rotation ?? 0);
      }
    }
    final page = _controller.viewport.toPage(screen);
    // What a press would pick up and move: with the lasso, the selection
    // alone, anywhere in its box.
    if (_controller.tool == CanvasTool.lasso) {
      final frame = SelectionFrame.around(selected);
      return frame != null && frame.contains(page)
          ? SystemMouseCursors.move
          : MouseCursor.defer;
    }
    final hit = _controller.hitTest(page);
    return hit == null ? MouseCursor.defer : SystemMouseCursors.move;
  }

  double get _eraserRadius => eraserRadiusIn(_controller.viewport);
}

/// The pen, highlighter and eraser show their nib instead
/// ([NibPainter]); a shape is placed, and a lasso drawn, as precisely as
/// a crosshair can.
MouseCursor _cursorFor(CanvasTool tool) => NibPainter.draws(tool)
    ? SystemMouseCursors.none
    : tool == CanvasTool.shape || tool == CanvasTool.lasso
    ? SystemMouseCursors.precise
    : SystemMouseCursors.basic;
