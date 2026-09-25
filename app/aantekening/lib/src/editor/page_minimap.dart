/// The page drawn small down its right-hand side, as code editors draw
/// theirs.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/tones.dart';
import '../preferences.dart';
import 'element_views.dart';
import 'text/text_box_editor.dart';

/// Whether the page is shown small beside it in place of its vertical
/// scrollbar, remembered between sessions.
class MinimapController extends Notifier<bool> {
  static const String _key = 'view.minimap';

  @override
  bool build() => ref.preference(_key) == true;

  void toggle() {
    state = !state;
    ref.savePreference(_key, state ? true : null);
  }
}

final minimapProvider = NotifierProvider<MinimapController, bool>(
  MinimapController.new,
);

/// The page drawn small, the whole of its width across [width], with the
/// part in view marked.
///
/// A page longer than the map fits scrolls through it as the view does, as
/// Kate's map of a file does. A press on the map brings that part of the
/// page into view, and dragging goes on moving it there; the wheel over the
/// map scrolls the page.
class PageMinimap extends StatefulWidget {
  const PageMinimap({required this.controller, super.key});

  final CanvasController controller;

  static const double width = 120;

  /// The largest the page is drawn, so a narrow page is not drawn larger
  /// than a map of it needs.
  static const double maxScale = 0.2;

  @override
  State<PageMinimap> createState() => _PageMinimapState();
}

class _PageMinimapState extends State<PageMinimap> {
  /// Each element's small drawing, kept while the element is the same, so a
  /// change to one box draws that box again and no other.
  final Map<String, (NoteElement, Widget)> _drawn =
      <String, (NoteElement, Widget)>{};

  /// How the map was laid over the page when a drag of it began, which
  /// holds for the whole drag so the page follows the pointer steadily.
  _MapPlacement? _dragging;

  CanvasController get _controller => widget.controller;

  Widget? _draw(BuildContext context, NoteElement element) {
    final kept = _drawn[element.id];
    if (kept != null && identical(kept.$1, element)) return kept.$2;
    final drawn = element is TextElement
        ? TextBoxEditor(element: element, isEditing: false, interactive: false)
        : CanvasElementView(element: element);
    _drawn[element.id] = (element, drawn);
    return drawn;
  }

  void _forgetRemoved() {
    if (_drawn.length <= _controller.document.elements.length + 64) return;
    _drawn.removeWhere((id, _) => _controller.document.elementById(id) == null);
  }

  /// Brings the page point under [local] to the middle of the view.
  void _centreOn(Offset local, _MapPlacement placement) {
    final page = placement.toPage(local);
    final view = _controller.viewport.visibleBounds(_controller.viewSize);
    _controller.viewport = CanvasViewport(
      origin: Offset(page.dx - view.width / 2, page.dy - view.height / 2),
      zoom: _controller.viewport.zoom,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        _forgetRemoved();
        final placement = _MapPlacement.of(_controller, constraints.biggest);
        final mark = context.tones.paperEmphasis;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _dragging = placement;
            _centreOn(event.localPosition, placement);
          },
          onPointerMove: (event) {
            final dragging = _dragging;
            if (dragging != null) _centreOn(event.localPosition, dragging);
          },
          onPointerUp: (_) => _dragging = null,
          onPointerCancel: (_) => _dragging = null,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _controller.panBy(-event.scrollDelta);
            }
          },
          child: ColoredBox(
            color: Color(_controller.document.canvas.background.paperColor),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                RepaintBoundary(
                  child: CanvasPreview(
                    controller: _controller,
                    viewport: placement.viewport,
                    elementBuilder: _draw,
                  ),
                ),
                CustomPaint(
                  painter: _ViewPainter(view: placement.viewOnMap, color: mark),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// How the map lies over the page: how small the page is drawn, how far
/// down the page the map has scrolled, and where the view is on it.
class _MapPlacement {
  const _MapPlacement(this.viewport, this.viewOnMap);

  factory _MapPlacement.of(CanvasController controller, Size size) {
    final across = ScrollSpan.of(controller, Axis.horizontal);
    final down = ScrollSpan.of(controller, Axis.vertical);
    final scale = math.min(
      PageMinimap.maxScale,
      size.width / math.max(1, across.extent),
    );
    // The map scrolls through a page longer than itself in step with the
    // view: at the top of the page with the view there, at the foot of it
    // with the view at the foot.
    final overflow = math.max(0.0, down.extent * scale - size.height);
    final travel = down.extent - down.length;
    final offset = travel > 0 ? overflow * (down.start / travel) : 0.0;
    final viewport = CanvasViewport(
      origin: Offset(0, offset / scale),
      zoom: scale,
    );
    final view = controller.viewport.visibleBounds(controller.viewSize);
    return _MapPlacement(
      viewport,
      Rect.fromPoints(
        viewport.toScreen(Offset(view.left, view.top)),
        viewport.toScreen(Offset(view.right, view.bottom)),
      ),
    );
  }

  /// The page as the map draws it.
  final CanvasViewport viewport;

  /// Where the view is on the map.
  final Rect viewOnMap;

  Offset toPage(Offset local) => viewport.toPage(local);
}

/// The part of the page in view, marked on the map.
class _ViewPainter extends CustomPainter {
  const _ViewPainter({required this.view, required this.color});

  final Rect view;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = view.intersect(Offset.zero & size);
    if (rect.isEmpty) return;
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.10))
      ..drawRect(
        rect.deflate(0.5),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke,
      );
  }

  @override
  bool shouldRepaint(_ViewPainter old) =>
      old.view != view || old.color != color;
}
