/// Panes that float over the notes — the menu, the picker, the AI — each
/// moved and sized by hand as the person likes it, and kept where it was
/// left the next time it opens.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The panes that can be moved and sized.
enum Pane {
  menu('The menu'),
  picker('The notebooks and the graph'),
  search('The search line'),
  ai('The AI'),
  cheatSheet('The cheat sheet'),
  minimap('The page drawn small'),
  chooser('Go to and Commands'),
  settings('The settings');

  const Pane(this.label);

  final String label;
}

/// Where a pane was put by hand, and how large it was made, in the area it
/// floats over — each null while it goes, or is as large as it is, by
/// itself.
typedef PanePlacement = ({Offset? at, Size? size});

const PanePlacement _byItself = (at: null, size: null);

/// Where [pane] was left, remembered between sessions.
class PanePlacements extends Notifier<PanePlacement> {
  PanePlacements(this.pane);

  final Pane pane;

  String get _key => 'pane.${pane.name}';

  @override
  PanePlacement build() {
    final saved = ref.preference(_key);
    if (saved is! Map) return _byItself;
    double? read(String name) => (saved[name] as num?)?.toDouble();
    final (x, y, width, height) = (
      read('x'),
      read('y'),
      read('width'),
      read('height'),
    );
    return (
      at: x == null || y == null ? null : Offset(x, y),
      size: width == null || height == null ? null : Size(width, height),
    );
  }

  void place(PanePlacement placement) {
    state = placement;
    final (:at, :size) = placement;
    ref.savePreference(_key, <String, Object?>{
      if (at != null) ...<String, double>{'x': at.dx, 'y': at.dy},
      if (size != null) ...<String, double>{
        'width': size.width,
        'height': size.height,
      },
    });
  }

  /// Lets it go where it goes, as large as it is, by itself again.
  void reset() {
    state = _byItself;
    ref.savePreference(_key, null);
  }
}

final panePlacementProvider =
    NotifierProvider.family<PanePlacements, PanePlacement, Pane>(
      PanePlacements.new,
    );

/// Puts every pane back where it goes by itself.
void resetPanes(WidgetRef ref) {
  for (final pane in Pane.values) {
    ref.read(panePlacementProvider(pane).notifier).reset();
  }
}

/// [child], a pane floating over the area it is given, which can be moved
/// by its top edge — or by its head, a [PaneDragArea] — and sized by any
/// edge or corner, and is kept where it was left (a double-click on its top
/// edge puts it back). Until it is, it is laid out in [natural] and put at
/// [position]; it never goes out of the area.
class FloatingPane extends ConsumerStatefulWidget {
  const FloatingPane({
    required this.pane,
    required this.natural,
    required this.position,
    required this.child,
    this.minSize = const Size(220, 120),
    this.holdsItsTop = false,
    super.key,
  });

  final Pane pane;

  /// What its content is laid out in, in an [area] so large, while it has
  /// not been sized by hand.
  final BoxConstraints Function(Size area) natural;

  /// Where it lies in an [area] so large, being [size], while it has not
  /// been moved by hand.
  final Offset Function(Size area, Size size) position;

  /// The smallest it can be made.
  final Size minSize;

  /// Whether a press on its top edge is the edge's alone, rather than also
  /// what lies under it: for content a drag acts on by itself, as the page
  /// drawn small is scrolled by one.
  final bool holdsItsTop;
  final Widget child;

  /// Whether [context] is in a pane sized by hand, whose content then fills
  /// it rather than being as large as it is.
  static bool sizedByHand(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaneScope>()?.sized ?? false;

  @override
  ConsumerState<FloatingPane> createState() => _FloatingPaneState();
}

/// What is taken hold of: the pane, to move it, or an edge or corner, to
/// size it by.
enum _Grip {
  move(SystemMouseCursors.move),
  left(SystemMouseCursors.resizeLeftRight, movesLeft: true),
  right(SystemMouseCursors.resizeLeftRight, movesRight: true),
  top(SystemMouseCursors.resizeUpDown, movesTop: true),
  bottom(SystemMouseCursors.resizeUpDown, movesBottom: true),
  topLeft(
    SystemMouseCursors.resizeUpLeftDownRight,
    movesTop: true,
    movesLeft: true,
  ),
  bottomRight(
    SystemMouseCursors.resizeUpLeftDownRight,
    movesBottom: true,
    movesRight: true,
  ),
  topRight(
    SystemMouseCursors.resizeUpRightDownLeft,
    movesTop: true,
    movesRight: true,
  ),
  bottomLeft(
    SystemMouseCursors.resizeUpRightDownLeft,
    movesBottom: true,
    movesLeft: true,
  );

  const _Grip(
    this.cursor, {
    this.movesLeft = false,
    this.movesTop = false,
    this.movesRight = false,
    this.movesBottom = false,
  });

  final MouseCursor cursor;
  final bool movesLeft;
  final bool movesTop;
  final bool movesRight;
  final bool movesBottom;
}

class _FloatingPaneState extends ConsumerState<FloatingPane> {
  final GlobalKey _pane = GlobalKey();

  /// Where it is while it is being moved or sized, until it is let go.
  PanePlacement? _live;

  /// What is being dragged: what was taken hold of, where the pane was
  /// then, and where the pointer was, in the area's own coordinates — the
  /// window's interface may be scaled.
  ({_Grip grip, Rect start, Offset from})? _drag;

  /// How thick the edges are that size it, and how large its corners.
  static const double _edge = 6;
  static const double _corner = 14;

  /// How deep the strip along its top is that moves it, below the edge.
  static const double _strip = 8;

  PanePlacements get _placements =>
      ref.read(panePlacementProvider(widget.pane).notifier);

  /// Where the pane is in its area, and how large.
  Rect? _rect() {
    final pane = _pane.currentContext?.findRenderObject() as RenderBox?;
    final area = context.findRenderObject() as RenderBox?;
    if (pane == null || area == null || !pane.hasSize) return null;
    return pane.localToGlobal(Offset.zero, ancestor: area) & pane.size;
  }

  RenderBox? get _area => context.findRenderObject() as RenderBox?;

  void _begin(_Grip grip, Offset global) {
    final start = _rect();
    final area = _area;
    if (start == null || area == null) return;
    _drag = (grip: grip, start: start, from: area.globalToLocal(global));
  }

  void _move(Offset global) {
    final drag = _drag;
    final area = _area;
    if (drag == null || area == null) return;
    final moved = area.globalToLocal(global) - drag.from;
    final placed = ref.read(panePlacementProvider(widget.pane));
    final start = drag.start;
    setState(() {
      _live = drag.grip == _Grip.move
          // Left within the area, as it is drawn.
          ? (
              at: Offset(
                (start.left + moved.dx).clamp(
                  0,
                  math.max(0, area.size.width - start.width),
                ),
                (start.top + moved.dy).clamp(
                  0,
                  math.max(0, area.size.height - start.height),
                ),
              ),
              size: placed.size,
            )
          : _sized(drag.grip, start, moved, area.size);
    });
  }

  /// [start] with the edges [grip] holds moved by [moved], no smaller than
  /// it can be and within [area].
  PanePlacement _sized(_Grip grip, Rect start, Offset moved, Size area) {
    final least = Size(
      math.min(widget.minSize.width, area.width),
      math.min(widget.minSize.height, area.height),
    );
    var (left, top, right, bottom) = (
      start.left,
      start.top,
      start.right,
      start.bottom,
    );
    if (grip.movesLeft) {
      left = (left + moved.dx).clamp(0, right - least.width);
    }
    if (grip.movesRight) {
      right = (right + moved.dx).clamp(left + least.width, area.width);
    }
    if (grip.movesTop) {
      top = (top + moved.dy).clamp(0, bottom - least.height);
    }
    if (grip.movesBottom) {
      bottom = (bottom + moved.dy).clamp(top + least.height, area.height);
    }
    return (at: Offset(left, top), size: Size(right - left, bottom - top));
  }

  void _end() {
    final live = _live;
    _drag = null;
    if (live == null) return;
    _placements.place(live);
    setState(() => _live = null);
  }

  void _reset() => _placements.reset();

  Widget _grip(
    _Grip grip, {
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) => Positioned(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: width,
    height: height,
    child: MouseRegion(
      cursor: grip.cursor,
      child: GestureDetector(
        // What lies under an edge is still pressed through it, unless the
        // pane holds its top.
        behavior: grip == _Grip.move && widget.holdsItsTop
            ? HitTestBehavior.opaque
            : HitTestBehavior.translucent,
        // From where it was taken hold of, so it keeps under the pointer.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) => _begin(grip, details.globalPosition),
        onPanUpdate: (details) => _move(details.globalPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        onDoubleTap: grip == _Grip.move ? _reset : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final placed = ref.watch(panePlacementProvider(widget.pane));
    final placement = _live ?? placed;
    return _PaneScope(
      state: this,
      sized: placement.size != null,
      child: CustomSingleChildLayout(
        delegate: _PaneLayout(
          placement: placement,
          natural: widget.natural,
          position: widget.position,
          minSize: widget.minSize,
        ),
        child: Stack(
          key: _pane,
          children: <Widget>[
            widget.child,
            _grip(
              _Grip.move,
              left: _corner,
              right: _corner,
              top: _edge,
              height: _strip,
            ),
            _grip(
              _Grip.top,
              left: _corner,
              right: _corner,
              top: 0,
              height: _edge,
            ),
            _grip(
              _Grip.bottom,
              left: _corner,
              right: _corner,
              bottom: 0,
              height: _edge,
            ),
            _grip(
              _Grip.left,
              left: 0,
              top: _corner,
              bottom: _corner,
              width: _edge,
            ),
            _grip(
              _Grip.right,
              right: 0,
              top: _corner,
              bottom: _corner,
              width: _edge,
            ),
            _grip(
              _Grip.topLeft,
              left: 0,
              top: 0,
              width: _corner,
              height: _corner,
            ),
            _grip(
              _Grip.topRight,
              right: 0,
              top: 0,
              width: _corner,
              height: _corner,
            ),
            _grip(
              _Grip.bottomLeft,
              left: 0,
              bottom: 0,
              width: _corner,
              height: _corner,
            ),
            _grip(
              _Grip.bottomRight,
              right: 0,
              bottom: 0,
              width: _corner,
              height: _corner,
            ),
          ],
        ),
      ),
    );
  }
}

/// The pane a [PaneDragArea] moves, and whether it was sized by hand.
class _PaneScope extends InheritedWidget {
  const _PaneScope({
    required this.state,
    required this.sized,
    required super.child,
  });

  final _FloatingPaneState state;
  final bool sized;

  @override
  bool updateShouldNotify(_PaneScope oldWidget) =>
      oldWidget.sized != sized || oldWidget.state != state;
}

/// [child], a pane's head, which moves the pane when dragged — what is
/// pressed on it still pressed.
class PaneDragArea extends StatelessWidget {
  const PaneDragArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_PaneScope>();
    if (scope == null) return child;
    final pane = scope.state;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (details) => pane._begin(_Grip.move, details.globalPosition),
      onPanUpdate: (details) => pane._move(details.globalPosition),
      onPanEnd: (_) => pane._end(),
      onPanCancel: pane._end,
      child: child,
    );
  }
}

/// Lays a pane out as it was left, or as it goes by itself, within its
/// area.
class _PaneLayout extends SingleChildLayoutDelegate {
  const _PaneLayout({
    required this.placement,
    required this.natural,
    required this.position,
    required this.minSize,
  });

  final PanePlacement placement;
  final BoxConstraints Function(Size area) natural;
  final Offset Function(Size area, Size size) position;
  final Size minSize;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final area = constraints.biggest;
    final size = placement.size;
    if (size == null) {
      return natural(area).enforce(BoxConstraints.loose(area));
    }
    return BoxConstraints.tight(
      Size(
        size.width.clamp(math.min(minSize.width, area.width), area.width),
        size.height.clamp(math.min(minSize.height, area.height), area.height),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size area, Size child) {
    final at = placement.at ?? position(area, child);
    return Offset(
      at.dx.clamp(0, math.max(0, area.width - child.width)),
      at.dy.clamp(0, math.max(0, area.height - child.height)),
    );
  }

  @override
  bool shouldRelayout(_PaneLayout oldDelegate) =>
      oldDelegate.placement != placement ||
      oldDelegate.natural != natural ||
      oldDelegate.position != position ||
      oldDelegate.minSize != minSize;
}
