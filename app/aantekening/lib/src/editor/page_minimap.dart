/// The page drawn small down its right-hand side, as code editors draw
/// theirs.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
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

  /// Where the map sees the page from.
  late final _MapView _mapView = _MapView(widget.controller);

  CanvasController get _controller => widget.controller;

  @override
  void didUpdateWidget(PageMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mapView.controller = widget.controller;
  }

  @override
  void dispose() {
    _mapView.dispose();
    super.dispose();
  }

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
    _drawn.removeWhere((id, _) => _controller.elementById(id) == null);
  }

  /// Brings the part of the page under [local] to the middle of the view.
  void _centreOn(Offset local, _MapPlacement placement) {
    final view = _controller.viewport;
    final middle = placement.toView(local);
    final size = _controller.viewSize / view.zoom;
    _controller.viewport = view.copyWith(
      origin: Offset(middle.dx - size.width / 2, middle.dy - size.height / 2),
    );
  }

  /// The map follows the view by itself: it is built again only when the
  /// page changes.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = _mapView.size = constraints.biggest;
      return ListenableBuilder(
        listenable: _controller.contents,
        builder: (context, _) {
          _forgetRemoved();
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              final placement = _MapPlacement.of(_controller, size);
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
                  // Sheets, drawn as the page shows them.
                  if (_controller.document.canvas.sheetsShown
                      case final sheets?)
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: BackgroundPainter(
                          background: _controller.document.canvas.background,
                          view: _mapView,
                          sheets: sheets,
                          desk: context.tones.pane,
                        ),
                      ),
                    ),
                  RepaintBoundary(
                    child: CanvasPreview(
                      controller: _controller,
                      view: _mapView,
                      elementBuilder: _draw,
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _ViewPainter(
                        controller: _controller,
                        color: context.tones.paperEmphasis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Where the map sees the page from, following the view.
class _MapView extends ChangeNotifier
    implements ValueListenable<CanvasViewport> {
  _MapView(this._controller) {
    _controller.addListener(_follow);
  }

  CanvasController _controller;
  set controller(CanvasController value) {
    if (identical(value, _controller)) return;
    _controller.removeListener(_follow);
    _controller = value..addListener(_follow);
    _follow();
  }

  /// The map's size, as it was last laid out.
  Size get size => _size;
  Size _size = Size.zero;
  set size(Size value) {
    _size = value;
    _value = _MapPlacement.of(_controller, value).viewport;
  }

  @override
  CanvasViewport get value => _value;
  CanvasViewport _value = const CanvasViewport();

  void _follow() {
    final next = _MapPlacement.of(_controller, _size).viewport;
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller.removeListener(_follow);
    super.dispose();
  }
}

/// How the map lies over the page: how small the page is drawn, how far
/// down the page the map has scrolled, and where the view is on it.
class _MapPlacement {
  const _MapPlacement(this.viewport, this.viewOnMap);

  factory _MapPlacement.of(CanvasController controller, Size size) {
    final across = ScrollSpan.of(controller, Axis.horizontal);
    final down = ScrollSpan.of(controller, Axis.vertical);
    final view = controller.viewport;
    // From as far back as the view goes: the page's corner, or the desk
    // about its sheets.
    final first = controller.originRange(view.zoom).min;
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
      origin: Offset(first.dx, first.dy + offset / scale),
      zoom: scale,
      fold: view.fold,
    );
    return _MapPlacement(
      viewport,
      Rect.fromLTWH(
        (view.origin.dx - viewport.origin.dx) * scale,
        (view.origin.dy - viewport.origin.dy) * scale,
        across.length * scale,
        down.length * scale,
      ),
    );
  }

  /// The page as the map draws it.
  final CanvasViewport viewport;

  /// Where the view is on the map.
  final Rect viewOnMap;

  /// The point of the view's space at [local] on the map.
  Offset toView(Offset local) => viewport.origin + local / viewport.zoom;
}

/// The part of the page in view, marked on the map; it follows the view
/// by itself.
class _ViewPainter extends CustomPainter {
  _ViewPainter({required this.controller, required this.color})
    : super(
        repaint: Listenable.merge(<Listenable>[
          controller.view,
          controller.contents,
        ]),
      );

  final CanvasController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final view = _MapPlacement.of(controller, size).viewOnMap;
    final rect = view.intersect(Offset.zero & size);
    if (rect.isEmpty) return;
    // What is in view, ringed in the accent.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.75), const Radius.circular(3)),
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_ViewPainter old) =>
      old.controller != controller || old.color != color;
}
