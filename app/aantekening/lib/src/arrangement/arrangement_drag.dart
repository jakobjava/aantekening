/// Rearranging buttons by dragging them: picking one up, showing where it
/// would land, and dropping it into a group.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Where a dragged item would land: in front of the item now at [index] in
/// [group], or at its end.
typedef ArrangementSlot<G> = ({G group, int index});

/// The state of dragging items around: which item is held, where it would
/// land, and where each item is on screen.
///
/// Owned by the widget showing the items, which disposes it.
class ArrangementDrag<G, I extends Object> {
  /// The item being dragged, if any.
  final ValueNotifier<I?> dragging = ValueNotifier<I?>(null);

  /// Where it would land if dropped now.
  final ValueNotifier<ArrangementSlot<G>?> slot =
      ValueNotifier<ArrangementSlot<G>?>(null);

  final Map<I, GlobalKey> _keys = <I, GlobalKey>{};

  /// The key [item]'s widget is placed under: by it, its place on screen is
  /// found while another item is dragged over it, and a moved item keeps its
  /// state.
  GlobalKey keyOf(I item) =>
      _keys[item] ??= GlobalKey(debugLabel: 'arranged $item');

  void end() {
    dragging.value = null;
    slot.value = null;
  }

  /// Where [pointer], in global coordinates, falls among [items] laid out
  /// along [axis]: in front of the nearest item, or after it if the pointer
  /// is past its middle.
  int indexAt(List<I> items, Offset pointer, Axis axis) {
    var best = items.length;
    var bestDistance = double.infinity;
    for (var i = 0; i < items.length; i++) {
      final box = _keys[items[i]]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final distance = (center - pointer).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        final before = axis == Axis.horizontal
            ? pointer.dx < center.dx
            : pointer.dy < center.dy;
        best = before ? i : i + 1;
      }
    }
    return best;
  }

  void dispose() {
    dragging.dispose();
    slot.dispose();
  }
}

/// An item that can be picked up and dropped elsewhere: the one at [index]
/// of the [count] in [group], laid out along [axis].
///
/// A mouse picks it up once it has moved a few pixels, and a finger once it
/// has held it, so a click still presses the button and a finger swiping
/// along still scrolls. While another item is dragged over it, a line shows
/// which side of it that one would land.
class ArrangeableItem<G, I extends Object> extends StatelessWidget {
  const ArrangeableItem({
    required this.drag,
    required this.item,
    required this.group,
    required this.index,
    required this.count,
    required this.axis,
    required this.icon,
    required this.label,
    required this.child,
    super.key,
  });

  final ArrangementDrag<G, I> drag;
  final I item;
  final G group;
  final int index;
  final int count;
  final Axis axis;

  /// What the item is shown as while it is dragged.
  final Widget icon;
  final String label;

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ArrangementSlot<G>?>(
        valueListenable: drag.slot,
        builder: (context, slot, child) {
          final here = slot != null && slot.group == group;
          return _DropMarker(
            axis: axis,
            before: here && slot.index == index,
            after: here && slot.index == count && index == count - 1,
            child: child!,
          );
        },
        child: KeyedSubtree(
          key: drag.keyOf(item),
          child: _ArrangeDraggable<I>(
            data: item,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _DragPreview(icon: icon, label: label),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: IgnorePointer(child: child),
            ),
            onDragStarted: () => drag.dragging.value = item,
            // Called even if the item's group has gone from the screen,
            // unlike onDragEnd.
            onDragCompleted: drag.end,
            onDraggableCanceled: (_, _) => drag.end(),
            child: child,
          ),
        ),
      );
}

/// A group items can be dropped into: [items], laid out along [axis].
class ArrangementDropTarget<G, I extends Object> extends StatelessWidget {
  const ArrangementDropTarget({
    required this.drag,
    required this.group,
    required this.items,
    required this.axis,
    required this.onDrop,
    required this.builder,
    super.key,
  });

  final ArrangementDrag<G, I> drag;
  final G group;
  final List<I> items;
  final Axis axis;

  /// Moves [item] into [group], in front of the item now at [index].
  final void Function(I item, G group, int index) onDrop;

  /// Builds the group, highlighted while an item is held over it.
  final Widget Function(BuildContext context, bool highlighted) builder;

  @override
  Widget build(BuildContext context) => DragTarget<I>(
    onWillAcceptWithDetails: (_) => true,
    onMove: (details) => drag.slot.value = (
      group: group,
      index: drag.indexAt(items, details.offset, axis),
    ),
    onLeave: (_) {
      if (drag.slot.value?.group == group) drag.slot.value = null;
    },
    onAcceptWithDetails: (details) {
      onDrop(details.data, group, drag.indexAt(items, details.offset, axis));
      drag.end();
    },
    builder: (context, candidates, _) =>
        builder(context, candidates.isNotEmpty),
  );
}

/// An emptied group, while an item is dragged: somewhere to drop it.
class ArrangementEmptyGroup extends StatelessWidget {
  const ArrangementEmptyGroup({
    required this.highlighted,
    this.width = 52,
    this.height,
    super.key,
  });

  final bool highlighted;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.add_rounded, size: 16, color: scheme.outline),
    );
  }
}

/// Marks where a dragged item would go: a line along the edge of the item
/// beside that place.
class _DropMarker extends StatelessWidget {
  const _DropMarker({
    required this.axis,
    required this.before,
    required this.after,
    required this.child,
  });

  final Axis axis;
  final bool before;
  final bool after;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: before || after
        ? _DropMarkerPainter(
            axis: axis,
            atStart: before,
            color: Theme.of(context).colorScheme.primary,
          )
        : null,
    child: child,
  );
}

class _DropMarkerPainter extends CustomPainter {
  _DropMarkerPainter({
    required this.axis,
    required this.atStart,
    required this.color,
  });

  final Axis axis;
  final bool atStart;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    if (axis == Axis.horizontal) {
      final x = atStart ? 1.0 : size.width - 1;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), paint);
    } else {
      final y = atStart ? 1.0 : size.height - 1;
      canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DropMarkerPainter oldDelegate) =>
      oldDelegate.axis != axis ||
      oldDelegate.atStart != atStart ||
      oldDelegate.color != color;
}

/// What follows the pointer while an item is dragged.
class _DragPreview extends StatelessWidget {
  const _DragPreview({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: Material(
        elevation: 6,
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icon,
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrangeDraggable<I extends Object> extends Draggable<I> {
  const _ArrangeDraggable({
    required super.child,
    required super.feedback,
    required super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragCompleted,
    super.onDraggableCanceled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _ArrangeDragRecognizer(allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}

/// Picks an item up once a mouse has moved it a few pixels, or once a finger
/// has held it.
class _ArrangeDragRecognizer extends MultiDragGestureRecognizer {
  _ArrangeDragRecognizer({super.debugOwner, super.allowedButtonsFilter});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.touch
      ? _HoldToDrag(event.position, event.kind, gestureSettings)
      : _MoveToDrag(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'arrange drag';
}

class _MoveToDrag extends MultiDragPointerState {
  _MoveToDrag(super.initialPosition, super.kind, super.gestureSettings);

  /// Far enough that a click with a slight wobble is still a click.
  static const double _slop = 6;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _slop) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

class _HoldToDrag extends MultiDragPointerState {
  _HoldToDrag(super.initialPosition, super.kind, super.gestureSettings) {
    _timer = Timer(_delay, _held);
  }

  /// A little shorter than a long press, so the drag wins over the tooltip.
  static const Duration _delay = Duration(milliseconds: 400);

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _held() {
    _timer = null;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      starter(initialPosition);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (_timer == null) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.rejected);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
