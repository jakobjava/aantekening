/// A list stepped through by the keys, which keeps the row the keys are on
/// in view.
library;

import 'package:flutter/widgets.dart';

/// A list of rows each [itemExtent] tall, one of them the [cursor]'s: as the
/// cursor moves — by the keys, or as the list changes under it — the list
/// scrolls just far enough to show its row whole, as it does when it first
/// shows.
class CursorList extends StatefulWidget {
  const CursorList({
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    required this.cursor,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    super.key,
  });

  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  /// The row the keys are on, or null for none.
  final int? cursor;

  final EdgeInsets padding;
  final bool shrinkWrap;

  @override
  State<CursorList> createState() => _CursorListState();
}

class _CursorListState extends State<CursorList> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _revealAfterLayout();
  }

  @override
  void didUpdateWidget(CursorList old) {
    super.didUpdateWidget(old);
    if (old.cursor != widget.cursor ||
        old.itemCount != widget.itemCount ||
        old.itemExtent != widget.itemExtent) {
      _revealAfterLayout();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Shows the cursor's row once the list is laid out, and knows how far
  /// it reaches.
  void _revealAfterLayout() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());

  void _reveal() {
    final cursor = widget.cursor;
    if (!mounted || cursor == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return;
    }
    // From the edge of the list for the first and last rows, so its padding
    // shows with them.
    final top = cursor == 0
        ? 0.0
        : widget.padding.top + cursor * widget.itemExtent;
    final bottom = cursor == widget.itemCount - 1
        ? position.maxScrollExtent + position.viewportDimension
        : widget.padding.top + (cursor + 1) * widget.itemExtent;
    final double to;
    if (top < position.pixels) {
      to = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      to = bottom - position.viewportDimension;
    } else {
      return;
    }
    _scroll.jumpTo(
      to.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _scroll,
    shrinkWrap: widget.shrinkWrap,
    padding: widget.padding,
    itemCount: widget.itemCount,
    itemExtent: widget.itemExtent,
    itemBuilder: widget.itemBuilder,
  );
}
