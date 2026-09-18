/// The graph view: every notebook, section and page, and how they nest.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/trackpad.dart';
import '../providers.dart';
import '../shell/library_actions.dart';
import '../shell/library_pane.dart';
import '../theme.dart';
import 'force_layout.dart';
import 'note_graph.dart';

/// The graph view in the sidebar, as Obsidian draws a vault: notebooks,
/// sections and pages as dots, each joined to what it is in, laid out as a
/// system of forces that moves as it settles and as things are dragged.
///
/// Scrolling zooms, dragging the background moves the view, and dragging a
/// dot pulls it and what hangs from it along; clicking a dot opens it.
/// Pointing at one names it and lights what it is joined to.
class GraphPanel extends ConsumerStatefulWidget {
  const GraphPanel({super.key});

  @override
  ConsumerState<GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends ConsumerState<GraphPanel>
    with SingleTickerProviderStateMixin {
  /// Zoom change per logical pixel scrolled, applied exponentially.
  static const double _scrollZoomRate = 0.002;
  static const double _minZoom = 0.1;
  static const double _maxZoom = 6;

  late final Ticker _ticker = createTicker(_tick);
  final double _trackpadPanScale = trackpadPanScale();

  /// Repaints the graph without rebuilding anything around it.
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  ForceLayout? _layout;
  NoteGraph? _graph;

  /// Where the middle of the layout is drawn, from the middle of the view.
  Offset _pan = Offset.zero;
  double _zoom = 1;
  Size _size = Size.zero;

  int? _hovered;

  /// The node being dragged, if any.
  int? _held;

  /// Where the pointer went down, which a drag picks a node up from.
  Offset? _pressedAt;
  PointerDeviceKind? _gestureKind;
  double _lastScale = 1;

  /// Names laid out once and drawn every frame, by node, name and whether
  /// faded, in [_labelStyle].
  final Map<(String, String, bool), TextPainter> _labels =
      <(String, String, bool), TextPainter>{};
  TextStyle? _labelStyle;

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _clearLabels();
    super.dispose();
  }

  void _clearLabels() {
    for (final label in _labels.values) {
      label.dispose();
    }
    _labels.clear();
  }

  /// [node]'s name, laid out in [style].
  TextPainter _label(
    GraphNode node, {
    required bool faded,
    required TextStyle style,
    required ColorScheme scheme,
  }) {
    if (style != _labelStyle) {
      _clearLabels();
      _labelStyle = style;
    }
    return _labels[(node.id, node.label, faded)] ??= TextPainter(
      text: TextSpan(
        text: node.label,
        style: style.copyWith(
          color: scheme.onSurface.withValues(alpha: faded ? 0.3 : 0.9),
          fontWeight: node.kind == GraphNodeKind.page
              ? FontWeight.w400
              : FontWeight.w600,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
  }

  /// Takes in [graph], keeping the layout if only names have changed.
  void _show(NoteGraph graph) {
    final layout = _layout;
    _graph = graph;
    // Names laid out for nodes since renamed or gone are not kept.
    if (_labels.length > 2 * graph.nodes.length) _clearLabels();
    if (layout != null && layout.graph.sameShape(graph)) {
      _frame.value++;
      return;
    }
    _layout = ForceLayout(
      graph,
      previous: layout?.positionsById ?? const <String, Offset>{},
    );
    _hovered = null;
    _held = null;
    _run();
  }

  void _run() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final layout = _layout;
    if (layout == null || layout.isSettled) {
      _ticker.stop();
      return;
    }
    layout.step();
    _frame.value++;
  }

  Offset _toLayout(Offset view) =>
      (view - _size.center(Offset.zero) - _pan) / _zoom;

  int? _nodeAt(Offset view) =>
      _layout?.nodeAt(_toLayout(view), slop: 4 / _zoom);

  void _zoomAbout(double factor, Offset view) {
    final before = _toLayout(view);
    _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom);
    // The point under the pointer stays under it.
    _pan = view - _size.center(Offset.zero) - before * _zoom;
    _frame.value++;
  }

  /// Zooms and moves the view so the whole graph fits in it.
  void _fit() {
    final layout = _layout;
    if (layout == null || layout.positions.isEmpty || _size.isEmpty) return;
    var bounds = Rect.fromCenter(
      center: layout.positions.first,
      width: 0,
      height: 0,
    );
    for (final position in layout.positions) {
      bounds = bounds.expandToInclude(
        Rect.fromCircle(center: position, radius: 12),
      );
    }
    _zoom = math
        .min(
          (_size.width - 48) / math.max(bounds.width, 1),
          (_size.height - 48) / math.max(bounds.height, 1),
        )
        .clamp(_minZoom, 2.0);
    _pan = -bounds.center * _zoom;
    _frame.value++;
  }

  void _open(int node) {
    final target = _graph?.nodes[node];
    if (target == null) return;
    final actions = ref.read(libraryActionsProvider);
    final sectionId = target.sectionId;
    switch (target.kind) {
      case GraphNodeKind.notebook:
        actions.openNotebook(target.notebookId);
      case GraphNodeKind.section:
        actions.openSection(target.notebookId, target.id);
      case GraphNodeKind.page:
        if (sectionId == null) return;
        actions.openPage(
          notebookId: target.notebookId,
          sectionId: sectionId,
          pageId: target.id,
        );
    }
  }

  // ------------------------------------------------------------- gestures

  void _onScaleStart(ScaleStartDetails details) {
    _gestureKind = details.kind;
    // One finger or the mouse on a node drags it; anything else moves or
    // zooms the view.
    final single =
        details.pointerCount == 1 && details.kind != PointerDeviceKind.trackpad;
    final node = single ? _nodeAt(_pressedAt ?? details.localFocalPoint) : null;
    _held = node;
    if (node != null) {
      _layout?.hold(node, _toLayout(details.localFocalPoint));
      _run();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final held = _held;
    if (held != null) {
      _layout?.hold(held, _toLayout(details.localFocalPoint));
      _run();
      return;
    }
    if (details.scale != 1) {
      _zoomAbout(details.scale / _lastScale, details.localFocalPoint);
    }
    _lastScale = details.scale;
    // Linux reports touchpad movement several times over; see
    // trackpadPanScale.
    final scale = _gestureKind == PointerDeviceKind.trackpad
        ? _trackpadPanScale
        : 1.0;
    _pan += details.focalPointDelta * scale;
    _frame.value++;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastScale = 1;
    if (_held != null) {
      _layout?.release();
      _held = null;
      _run();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        _zoomAbout(
          math.exp(-event.scrollDelta.dy * _scrollZoomRate),
          event.localPosition,
        );
      });
    }
  }

  void _onHover(PointerHoverEvent event) =>
      _hover(_nodeAt(event.localPosition));

  /// Points at [node], or at nothing: the cursor shows it can be clicked, and
  /// the graph lights it and what it is joined to.
  void _hover(int? node) {
    if (node == _hovered) return;
    setState(() => _hovered = node);
    _frame.value++;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ref.listen<AsyncValue<NoteGraph>>(noteGraphProvider, (_, next) {
      final value = next.value;
      if (value != null) _show(value);
    });
    final loaded = ref.watch(noteGraphProvider);
    if (_graph == null && loaded.value != null) _show(loaded.value!);
    final graph = _graph;
    final current = ref.watch(selectedPageProvider);

    final Widget body;
    if (graph == null) {
      body = loaded.hasError
          ? PaneMessage('${loaded.error}', error: true)
          : const Center(child: CircularProgressIndicator());
    } else if (graph.nodes.isEmpty) {
      body = const PaneMessage('No notebooks yet');
    } else {
      body = ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            return Listener(
              onPointerDown: (event) => _pressedAt = event.localPosition,
              onPointerSignal: _onPointerSignal,
              child: MouseRegion(
                onHover: _onHover,
                onExit: (_) => _hover(null),
                cursor: _hovered == null
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapUp: (details) {
                    final node = _nodeAt(details.localPosition);
                    if (node != null) _open(node);
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _GraphPainter(
                      state: this,
                      current: current,
                      scheme: scheme,
                      labelStyle: Theme.of(context).textTheme.labelSmall!,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Material(
      color: AppTheme.paneColor(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Graph',
            actionIcon: Icons.fit_screen_outlined,
            actionTooltip: 'Fit the graph in view',
            onAction: graph == null ? null : _fit,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Draws the graph as [state] lays it out and views it.
class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.state,
    required this.current,
    required this.scheme,
    required this.labelStyle,
  }) : super(repaint: state._frame);

  final _GraphPanelState state;

  /// The page open in the editor, which is ringed.
  final String? current;
  final ColorScheme scheme;
  final TextStyle labelStyle;

  /// Names are shown for notebooks and sections from this zoom, and for
  /// pages from [_pageLabelZoom].
  static const double _labelZoom = 0.6;
  static const double _pageLabelZoom = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = state._layout;
    final graph = state._graph;
    if (layout == null || graph == null) return;
    final zoom = state._zoom;
    final origin = size.center(Offset.zero) + state._pan;
    Offset toView(int node) => origin + layout.positions[node] * zoom;

    // What the pointer is on, and what that is joined to, stand out; the
    // rest steps back.
    final hovered = state._hovered;
    final lit = <int>{
      ?hovered,
      if (hovered != null)
        for (final (parent, child) in graph.links)
          if (parent == hovered) child else if (child == hovered) parent,
    };
    final dimmed = hovered != null;

    final link = Paint()
      ..strokeWidth = math.max(0.6, zoom * 0.9)
      ..color = scheme.outlineVariant.withValues(alpha: dimmed ? 0.35 : 0.9);
    final litLink = Paint()
      ..strokeWidth = math.max(1, zoom * 1.4)
      ..color = scheme.primary;
    for (final (parent, child) in graph.links) {
      final isLit = hovered != null && (parent == hovered || child == hovered);
      canvas.drawLine(toView(parent), toView(child), isLit ? litLink : link);
    }

    for (var i = 0; i < graph.nodes.length; i++) {
      final node = graph.nodes[i];
      final center = toView(i);
      final radius = math.max(2.0, ForceLayout.radiusOf(node) * zoom);
      final base = node.color != null
          ? Color(node.color!)
          : switch (node.kind) {
              GraphNodeKind.notebook => scheme.primary,
              GraphNodeKind.section => scheme.tertiary,
              GraphNodeKind.page => scheme.onSurfaceVariant,
            };
      final faded = dimmed && !lit.contains(i);
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = base.withValues(alpha: faded ? 0.25 : 1),
      );
      if (node.id == current) {
        canvas.drawCircle(
          center,
          radius + 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = scheme.primary,
        );
      }

      final named =
          lit.contains(i) ||
          node.id == current ||
          zoom >=
              (node.kind == GraphNodeKind.page ? _pageLabelZoom : _labelZoom);
      if (!named) continue;
      final label = state._label(
        node,
        faded: faded,
        style: labelStyle,
        scheme: scheme,
      );
      label.paint(canvas, center + Offset(-label.width / 2, radius + 3));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.current != current ||
      oldDelegate.scheme != scheme ||
      oldDelegate.labelStyle != labelStyle;
}
