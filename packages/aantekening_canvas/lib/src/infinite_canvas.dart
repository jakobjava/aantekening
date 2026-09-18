/// The canvas widget: input handling and the layer stack.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas_controller.dart';
import 'canvas_painters.dart';
import 'canvas_viewport.dart';
import 'tools.dart';

/// Builds the widget for an element, or returns null to leave it unpainted.
///
/// Supplied by the host application so that the canvas does not depend on the
/// maths renderer, the PDF renderer or the text editor: it owns layout and
/// input, they own their own content.
typedef CanvasElementBuilder =
    Widget? Function(BuildContext context, NoteElement element);

/// Called when a tool asks for a new element at a page-space point.
typedef CanvasCreateCallback = void Function(CanvasTool tool, Offset page);

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
    this.onCreate,
    this.onElementDoubleTap,
  });

  final CanvasController controller;

  /// Supplies the widget for text, maths, image, PDF and table elements.
  final CanvasElementBuilder? elementBuilder;

  /// Invoked when the text or maths tool is used on empty canvas.
  final CanvasCreateCallback? onCreate;

  /// Invoked when an element is double-tapped, typically to start editing it.
  final void Function(NoteElement element)? onElementDoubleTap;

  @override
  State<InfiniteCanvas> createState() => _InfiniteCanvasState();
}

/// What the pointer currently in contact with the canvas is doing.
enum _PointerAction { none, draw, erase, pan, move, marquee }

class _InfiniteCanvasState extends State<InfiniteCanvas> {
  static const double _scrollZoomSensitivity = 0.0015;

  _PointerAction _action = _PointerAction.none;
  int? _activePointer;
  Offset _lastScreenPosition = Offset.zero;
  Offset? _marqueeAnchor;
  Aabb? _marquee;
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
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------- pointer

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _lastScreenPosition = event.localPosition;

    final page = _controller.viewport.toPage(event.localPosition);
    _action = _resolveAction(event);

    switch (_action) {
      case _PointerAction.draw:
        _controller.beginStroke(
          page,
          pressure: _normalizedPressure(event),
          tilt: event.tilt,
        );
      case _PointerAction.erase:
        _controller.eraseAt(page, radius: _eraserRadius);
      case _PointerAction.move:
        final hit = _controller.hitTest(page);
        if (hit != null && !_controller.selection.contains(hit.id)) {
          _controller.select(
            hit.id,
            additive: HardwareKeyboard.instance.isShiftPressed,
          );
        }
      case _PointerAction.marquee:
        _marqueeAnchor = page;
        _marquee = Aabb(page.dx, page.dy, page.dx, page.dy);
        if (!HardwareKeyboard.instance.isShiftPressed) {
          _controller.clearSelection();
        }
      case _PointerAction.pan:
      case _PointerAction.none:
        break;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;

    final page = _controller.viewport.toPage(event.localPosition);
    final screenDelta = event.localPosition - _lastScreenPosition;
    _lastScreenPosition = event.localPosition;

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
        _controller.panBy(screenDelta);
      case _PointerAction.move:
        // Intermediate drags are not recorded, so an entire drag undoes as one
        // step rather than one per pointer sample.
        _controller.translateSelection(
          screenDelta / _controller.viewport.zoom,
          recordUndo: false,
        );
      case _PointerAction.marquee:
        final anchor = _marqueeAnchor;
        if (anchor == null) break;
        setState(() {
          _marquee = Aabb(
            anchor.dx < page.dx ? anchor.dx : page.dx,
            anchor.dy < page.dy ? anchor.dy : page.dy,
            anchor.dx > page.dx ? anchor.dx : page.dx,
            anchor.dy > page.dy ? anchor.dy : page.dy,
          );
        });
      case _PointerAction.none:
        break;
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;

    switch (_action) {
      case _PointerAction.draw:
        _controller.endStroke();
      case _PointerAction.marquee:
        final band = _marquee;
        if (band != null) {
          _controller.selectIn(
            band,
            additive: HardwareKeyboard.instance.isShiftPressed,
          );
        }
      case _PointerAction.none:
        // A press with no drag on a creation tool places a new element.
        _maybeCreate(event);
      case _PointerAction.erase:
      case _PointerAction.pan:
      case _PointerAction.move:
        break;
    }

    setState(() {
      _action = _PointerAction.none;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _controller.cancelStroke();
    setState(() {
      _action = _PointerAction.none;
      _activePointer = null;
      _marquee = null;
      _marqueeAnchor = null;
    });
  }

  void _maybeCreate(PointerEvent event) {
    final tool = _controller.tool;
    if (tool != CanvasTool.text && tool != CanvasTool.math) return;
    widget.onCreate?.call(
      tool,
      _controller.viewport.toPage(event.localPosition),
    );
  }

  /// Chooses what a press does, from the tool and the pointer's own state.
  _PointerAction _resolveAction(PointerDownEvent event) {
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
      return _PointerAction.erase;
    }

    return switch (_controller.tool) {
      CanvasTool.pan => _PointerAction.pan,
      CanvasTool.draw => _PointerAction.draw,
      CanvasTool.eraser => _PointerAction.erase,
      CanvasTool.select =>
        _controller.hitTest(_controller.viewport.toPage(event.localPosition)) !=
                null
            ? _PointerAction.move
            : _PointerAction.marquee,
      CanvasTool.text || CanvasTool.math => _PointerAction.none,
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

  // ------------------------------------------------------------------ scroll

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Exponential so that each notch changes the zoom by the same ratio,
      // which is what makes zooming feel linear to the hand.
      final factor = (1 - event.scrollDelta.dy * _scrollZoomSensitivity).clamp(
        0.2,
        5.0,
      );
      _controller.zoomBy(factor, event.localPosition);
      return;
    }

    final delta = HardwareKeyboard.instance.isShiftPressed
        ? Offset(event.scrollDelta.dy, 0)
        : event.scrollDelta;
    _controller.panBy(-delta);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _controller.panBy(event.panDelta);
    if (event.scale != 1) {
      _controller.zoomBy(1 + (event.scale - 1) * 0.5, event.localPosition);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final controller = _controller;
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
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: _cursorFor(controller.tool),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: BackgroundPainter(
                        background: controller.document.canvas.background,
                        viewport: viewport,
                        paperWidth: controller.document.canvas.paperWidth,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: InkPainter(
                        elements: ink,
                        viewport: viewport,
                        layer: InkLayer.beneath,
                      ),
                    ),
                  ),
                  _ElementLayer(
                    elements: elements,
                    viewport: viewport,
                    builder: widget.elementBuilder,
                    onDoubleTap: widget.onElementDoubleTap,
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: InkPainter(
                        elements: ink,
                        viewport: viewport,
                        layer: InkLayer.above,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: WetInkPainter(
                        points: controller.wetPoints,
                        pen: (
                          tool: controller.pen.tool,
                          color: controller.pen.color,
                          width: controller.pen.width,
                        ),
                        viewport: viewport,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: SelectionPainter(
                        selected: controller.selectedElements,
                        viewport: viewport,
                        accent: Theme.of(context).colorScheme.primary,
                        marquee: _marquee,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static MouseCursor _cursorFor(CanvasTool tool) => switch (tool) {
    CanvasTool.pan => SystemMouseCursors.grab,
    CanvasTool.draw || CanvasTool.eraser => SystemMouseCursors.precise,
    CanvasTool.text => SystemMouseCursors.text,
    CanvasTool.math => SystemMouseCursors.cell,
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

    final children = <Widget>[];
    for (final element in elements) {
      if (element is InkElement) continue;

      final content = build(context, element);
      if (content == null) continue;

      final frame = element.frame;
      final topLeft = viewport.toScreen(Offset(frame.x, frame.y));
      children.add(
        Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          width: frame.width * viewport.zoom,
          height: frame.height * viewport.zoom,
          child: GestureDetector(
            onDoubleTap: onDoubleTap == null
                ? null
                : () => onDoubleTap!(element),
            behavior: HitTestBehavior.deferToChild,
            child: Transform.scale(
              scale: viewport.zoom,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: frame.rotation == 0
                    ? content
                    : Transform.rotate(angle: frame.rotation, child: content),
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}
