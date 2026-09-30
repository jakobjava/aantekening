/// Arranging the rows of a list by dragging one above or below another.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../look/tones.dart';
import 'library_menu.dart';

/// A row that, while [enabled], can be dragged above or below another of its
/// kind, and that others can be dropped above or below — the line where it
/// would go drawn as it is dragged over.
///
/// It is dragged with a mouse, a pen or a touchpad; a finger drags the list
/// along, as it does any list.
class ArrangeableRow<T extends TreeNode> extends StatefulWidget {
  const ArrangeableRow({
    required this.item,
    required this.enabled,
    required this.onArrange,
    required this.child,
    this.accepts,
    super.key,
  });

  final T item;
  final bool enabled;

  /// Puts [moved] just above [item], or just below it.
  final void Function(T moved, {required bool above}) onArrange;

  /// Whether [moved] may go beside [item]: not a page among its own
  /// subpages, say. Anything but [item] itself may, if null.
  final bool Function(T moved)? accepts;
  final Widget child;

  @override
  State<ArrangeableRow<T>> createState() => _ArrangeableRowState<T>();
}

class _ArrangeableRowState<T extends TreeNode>
    extends State<ArrangeableRow<T>> {
  /// Whether what is dragged over the row would go above it, or below; null
  /// while nothing is.
  bool? _above;

  void _over(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final above = box.globalToLocal(global).dy < box.size.height / 2;
    if (above != _above) setState(() => _above = above);
  }

  void _left() {
    if (_above != null) setState(() => _above = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final line = context.tones.paperEmphasis;
    final target = DragTarget<T>(
      onWillAcceptWithDetails: (details) =>
          details.data.id != widget.item.id &&
          (widget.accepts?.call(details.data) ?? true),
      onMove: (details) => _over(details.offset),
      onLeave: (_) => _left(),
      onAcceptWithDetails: (details) {
        final above = _above ?? true;
        _left();
        widget.onArrange(details.data, above: above);
      },
      builder: (context, candidates, _) {
        final above = _above;
        return Stack(
          children: <Widget>[
            widget.child,
            if (candidates.isNotEmpty && above != null)
              Positioned(
                left: 0,
                right: 0,
                top: above ? 0 : null,
                bottom: above ? null : 0,
                child: IgnorePointer(child: Container(height: 2, color: line)),
              ),
          ],
        );
      },
    );
    return _PointerDraggable<T>(
      data: widget.item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _Carried(title: displayTitle(widget.item)),
      childWhenDragging: Opacity(opacity: 0.4, child: widget.child),
      child: target,
    );
  }
}

/// A [Draggable] that a mouse, a pen or a touchpad drags up or down, and a
/// finger does not.
class _PointerDraggable<T extends Object> extends Draggable<T> {
  const _PointerDraggable({
    required super.data,
    required super.child,
    required super.feedback,
    super.childWhenDragging,
    super.dragAnchorStrategy,
  }) : super(affinity: Axis.vertical);

  static const Set<PointerDeviceKind> _devices = <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      VerticalMultiDragGestureRecognizer(supportedDevices: _devices)
        ..onStart = onStart;
}

/// What is dragged, under the pointer: the name of the row's page or
/// notebook.
class _Carried extends StatelessWidget {
  const _Carried({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(4),
    color: context.tones.pane,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}
