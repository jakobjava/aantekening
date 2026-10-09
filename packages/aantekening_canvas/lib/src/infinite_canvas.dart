/// The canvas widget: input handling and the layer stack.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'canvas_controller.dart';
import 'canvas_motion.dart';
import 'canvas_painters.dart';
import 'canvas_scope.dart';
import 'canvas_viewport.dart';
import 'element_transforms.dart';
import 'ink_ahead.dart';
import 'lasso.dart';
import 'page_space.dart';
import 'selection_handles.dart';
import 'tools.dart';

part 'infinite_canvas_gestures.dart';
part 'infinite_canvas_hover.dart';
part 'infinite_canvas_layers.dart';
part 'infinite_canvas_pointer.dart';

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

/// Decides whether a page-space point is on an element's grip: the part
/// that picks it up to move it, such as a text box's band along its top.
typedef CanvasGrip = bool Function(NoteElement element, Offset page);

/// Something fixed to the page but not stored on it, such as its title.
///
/// Laid out at [frame], in page units, it moves and scales with the page as
/// an element does, beneath the elements, and handles the presses that land
/// on it while the select tool is in hand.
@immutable
class CanvasHeader {
  const CanvasHeader({required this.frame, required this.child});

  final Frame frame;
  final Widget child;
}

/// What fingers on a touchpad are doing, where the platform says so:
/// most report fingers put down only once they move.
enum TouchpadFingers {
  /// None are on it, or they lifted from it without moving.
  lifted,

  /// Two or more rest on it, still.
  resting,

  /// They rested, and have moved on: a scroll or a pinch follows.
  moving,
}

/// An infinitely pannable, zoomable page.
///
/// Layers are stacked so each repaints independently: paper, highlighter ink,
/// the element widgets, pen ink, inverting ink, the stroke in progress, and
/// the selection overlay. A new ink sample therefore repaints only the thin
/// wet-ink layer rather than the whole page.
class InfiniteCanvas extends StatefulWidget {
  const InfiniteCanvas({
    required this.controller,
    super.key,
    this.elementBuilder,
    this.claimsPointer,
    this.grips,
    this.onEmptyTap,
    this.onCanvasPress,
    this.onContextMenu,
    this.header,
    this.trackpadPanScale = 1,
    this.selectionColor,
    this.deskColor,
    this.afterSheets,
    this.overlay,
    this.penButtons = const PenButtons(),
    this.shapesOnHold = true,
    this.touchpadFingers,
  });

  final CanvasController controller;

  /// Supplies the widget for text, maths, image, PDF and table elements.
  final CanvasElementBuilder? elementBuilder;

  /// Lets an element's widget take a press with the select tool — a text box
  /// placing its caret, say — instead of the canvas picking the element up.
  final CanvasPointerClaim? claimsPointer;

  /// Finds a selected element's grip under a press. A selected element is
  /// picked up by its grip even where another element lies over it, as the
  /// grip shows it will be.
  final CanvasGrip? grips;

  /// Invoked when empty canvas is clicked or tapped with the select tool,
  /// without dragging. This is where a caret is placed.
  final ValueChanged<Offset>? onEmptyTap;

  /// Invoked for every press the canvas handles itself, with the element under
  /// it if any. The host uses this to end text editing when the user moves on.
  final ValueChanged<NoteElement?>? onCanvasPress;

  /// Invoked for a right-click on the page, with where it was in page units
  /// and on screen, for the host to offer a menu; not where an element's own
  /// widget takes the press ([claimsPointer]), which offers its own.
  final void Function(Offset page, Offset global)? onContextMenu;

  /// Drawn on the page beneath its elements: the page's title, say.
  final CanvasHeader? header;

  /// How far the page moves per logical pixel of pan a trackpad reports.
  ///
  /// 1 wherever the platform reports how far the fingers moved. Flutter on
  /// Linux multiplies the desktop's touchpad scroll deltas by 53, so there the
  /// host passes the factor that brings them back to finger distance; see
  /// the app's `trackpadPanScale`.
  final double trackpadPanScale;

  /// What the selection's frame and handles, and the band dragged to
  /// select, are drawn in: the theme's primary colour, if not given.
  final Color? selectionColor;

  /// What lies about a page shown as sheets.
  final Color? deskColor;

  /// What is shown below the last sheet of a page shown as sheets, in the
  /// middle of it: a button to add another, say. A press on it is its own,
  /// and draws nothing on the page.
  final Widget? afterSheets;

  /// Drawn over everything on the page, its selection and handles included,
  /// within the canvas: what is being worked on, such as the source of a
  /// formula being typed, placed where it follows. A press on it is its own,
  /// as on [afterSheets].
  final Widget? overlay;

  /// What a pen does pressed with one of its buttons held. Its other end,
  /// where a pen has an eraser, always erases.
  final PenButtons penButtons;

  /// Whether a stroke held still at its end becomes the shape it was drawn
  /// as.
  final bool shapesOnHold;

  /// What fingers on a touchpad are doing, where the platform tells of
  /// fingers put down that have not moved: put down, they stop the page
  /// coasting, as they do once they move.
  final ValueListenable<TouchpadFingers>? touchpadFingers;

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
  lasso,

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
  /// Rebuilds the canvas after [change], for the parts of it kept in other
  /// files of this library, which cannot call [setState] themselves.
  void _update(VoidCallback change) => setState(change);

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
  Lasso? _lasso;

  /// The pointer last pressed on [InfiniteCanvas.afterSheets] or
  /// [InfiniteCanvas.overlay], whose press it is alone.
  int? _claimedPointer;

  /// The sheet the line being drawn began on, of a page shown as pages.
  int? _strokeSheet;

  /// Where the pen came to rest while drawing, how far it may tremble
  /// there and still be at rest, and the wait for it to stay there long
  /// enough for the stroke to become a shape.
  Offset _restingAt = Offset.zero;
  double _restSlop = 0;
  Timer? _hold;

  /// Touch pointers currently down, by pointer id, at their latest position.
  final Map<int, Offset> _touches = <int, Offset>{};
  VelocityTracker? _touchVelocity;

  _TrackpadGesture? _trackpad;

  late final CanvasMotion _motion = CanvasMotion(
    () => _controller,
    this,
    onZoomed: _syncZooming,
  );

  /// Whether the view is being zoomed — by fingers, or gliding through a
  /// wheel's zoom — for the page to be scaled as it is laid out meanwhile,
  /// and laid out for the zoom it comes to once it is done.
  final ValueNotifier<bool> _zooming = ValueNotifier<bool>(false);

  /// How fast the view was coasting when a touchpad gesture caught it: a
  /// flick the same way adds to it, as flicking a list on a phone again
  /// does.
  Offset _caught = Offset.zero;

  MouseCursor _hoverCursor = MouseCursor.defer;

  /// Where the mouse pointer is, which a trackpad pinch zooms about. Linux
  /// reports a pinch at the last place clicked rather than at the pointer.
  Offset? _mousePosition;

  /// Where a mouse or pen is over the page, for the nib drawn there in
  /// place of a cursor ([NibPainter]).
  final ValueNotifier<NibPlace?> _nib = ValueNotifier<NibPlace?>(null);

  Size _size = Size.zero;

  CanvasController get _controller => widget.controller;

  /// The page's ink, made ready to draw while nothing moves.
  late InkAhead _inkAhead;

  @override
  void initState() {
    super.initState();
    _listen(_controller);
    _inkAhead = InkAhead(_controller);
    widget.touchpadFingers?.addListener(_onTouchpadFingers);
  }

  @override
  void didUpdateWidget(InfiniteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _stopListening(oldWidget.controller);
      _listen(widget.controller);
      _inkAhead.dispose();
      _inkAhead = InkAhead(widget.controller);
    }
    if (oldWidget.touchpadFingers != widget.touchpadFingers) {
      oldWidget.touchpadFingers?.removeListener(_onTouchpadFingers);
      widget.touchpadFingers?.addListener(_onTouchpadFingers);
    }
  }

  @override
  void dispose() {
    widget.touchpadFingers?.removeListener(_onTouchpadFingers);
    _zooming.dispose();
    _nib.dispose();
    _hold?.cancel();
    _motion.dispose();
    _stopListening(_controller);
    _inkAhead.dispose();
    super.dispose();
  }

  // Only what the page holds rebuilds the canvas: its layers follow the
  // view by themselves.
  void _listen(CanvasController controller) =>
      controller.contents.addListener(_onContentsChanged);

  void _stopListening(CanvasController controller) =>
      controller.contents.removeListener(_onContentsChanged);

  void _onContentsChanged() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // The page is built again inside the layout builder as the view moves
    // on, which lays the builder out again, and paints what holds it: all
    // of the window around the page, at every step of a scroll, but for
    // this.
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size != _size && _controller.fold != null) {
            // Sheets lie in the middle of the view: once it is this size,
            // they are put in the middle of it.
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) _controller.settleView();
            });
          }
          _size = size;
          final controller = _controller..viewSize = _size;

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
              onExit: (_) => _nib.value = null,
              cursor: _hoverCursor == MouseCursor.defer
                  ? _cursorFor(controller.tool)
                  : _hoverCursor,
              child: ClipRect(
                // Only the element layer takes pointers. The painted
                // layers would otherwise count as hit everywhere — a
                // CustomPaint does by default — and the ones above the
                // elements would swallow every press meant for a text box.
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: BackgroundPainter(
                            background: controller.document.canvas.background,
                            view: controller.view,
                            paperWidth: controller.document.canvas.paperWidth,
                            sheets: controller.document.canvas.sheetsShown,
                            desk: widget.deskColor ?? const Color(0xFFE4E4E4),
                          ),
                        ),
                      ),
                    ),
                    _PageContent(
                      controller: controller,
                      view: controller.view,
                      zooming: _zooming,
                      size: _size,
                      builder: widget.elementBuilder,
                      header: widget.header,
                      headerInteractive: controller.tool == CanvasTool.select,
                    ),
                    if (widget.afterSheets case final after?
                        when controller.fold != null)
                      CustomSingleChildLayout(
                        delegate: _AfterSheets(controller.view),
                        child: Listener(
                          // Pressed, it is the press's alone: the canvas,
                          // which hears of it after, leaves it be.
                          onPointerDown: (event) =>
                              _claimedPointer = event.pointer,
                          child: after,
                        ),
                      ),
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: SelectionPainter(
                            selected: controller.selectedElements,
                            view: controller.view,
                            accent:
                                widget.selectionColor ??
                                Theme.of(context).colorScheme.primary,
                            marquee: _marquee,
                            lasso: _lasso,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: NibPainter(
                            place: _nib,
                            controller: controller,
                          ),
                        ),
                      ),
                    ),
                    // Above everything: a press on a handle or a side of the
                    // selection is the canvas's alone. Without this the text
                    // box beneath the edge would take it too, placing its caret
                    // and selecting text while the box is resized.
                    _HandleTargets(hits: _onHandle),
                    if (widget.overlay case final overlay?)
                      Listener(
                        onPointerDown: (event) =>
                            _claimedPointer = event.pointer,
                        child: overlay,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Whether a mouse press at [screen] would take hold of the selection's
  /// handles or sides.
  bool _onHandle(Offset screen) {
    if (!_controller.tool.selects) return false;
    final selected = _controller.selectedElements;
    return selected.isNotEmpty &&
        SelectionHandles.hitTest(selected, _controller.viewport, screen) !=
            null;
  }
}
