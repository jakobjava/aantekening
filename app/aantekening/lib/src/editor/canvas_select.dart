/// Rebuilding on one value read from the page, rather than on every change
/// to it.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds when one value read from the page changes, rather than on every
/// change — the page notifies on every frame of scrolling.
class CanvasSelect<T> extends StatefulWidget {
  const CanvasSelect({
    required this.canvas,
    required this.select,
    required this.builder,
    super.key,
  });

  final CanvasController canvas;
  final ValueGetter<T> select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<CanvasSelect<T>> createState() => _CanvasSelectState<T>();
}

class _CanvasSelectState<T> extends State<CanvasSelect<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.canvas.addListener(_changed);
  }

  @override
  void didUpdateWidget(CanvasSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.canvas, widget.canvas)) {
      oldWidget.canvas.removeListener(_changed);
      widget.canvas.addListener(_changed);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.canvas.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.select();
    if (value != _value) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
