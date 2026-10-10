part of 'infinite_canvas.dart';

/// A page drawn as the canvas draws it, seen from [view], only to be
/// looked at: nothing on it can be pressed, picked or typed in. A map of the
/// page, say, drawn small.
///
/// What each element looks like comes from [elementBuilder], as on the
/// canvas; ink and pictures set as the background are drawn as there.
class CanvasPreview extends StatelessWidget {
  const CanvasPreview({
    required this.controller,
    required this.view,
    this.elementBuilder,
    super.key,
  });

  /// The page, as the canvas has it.
  final CanvasController controller;

  /// Where the page is seen from, which the preview follows by itself.
  final ValueListenable<CanvasViewport> view;
  final CanvasElementBuilder? elementBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => IgnorePointer(
      child: ClipRect(
        child: _PageContent(
          controller: controller,
          view: view,
          size: constraints.biggest,
          builder: elementBuilder,
          header: null,
          headerInteractive: false,
          still: true,
        ),
      ),
    ),
  );
}

/// The page's own layers, from the bottom up: the pictures and PDF pages
/// set as its background, highlighter, the element widgets, pen ink, ink
/// inverting what is beneath it, and the stroke in progress; laid out in
/// page units over the part of the page around what [view] sees in a view
/// of [size], and shown as it sees it.
///
/// It follows the view without being built again until the view moves out
/// of what was laid out, or zooms — and while it is being zoomed
/// ([zooming]), it is scaled as it was laid out, and laid out for the zoom
/// it comes to once that is done. Built again as the view moves on, an
/// element already placed keeps the very widget it had. Each layer repaints
/// by itself, so a new ink sample repaints only the stroke in progress, and
/// a caret blinking only the element layer.
class _PageContent extends StatefulWidget {
  const _PageContent({
    required this.controller,
    required this.view,
    required this.size,
    required this.builder,
    required this.header,
    required this.headerInteractive,
    this.zooming,
    this.still = false,
  });

  final CanvasController controller;
  final ValueListenable<CanvasViewport> view;

  /// Whether the view is being zoomed; never, if null.
  final ValueListenable<bool>? zooming;
  final Size size;
  final CanvasElementBuilder? builder;
  final CanvasHeader? header;
  final bool headerInteractive;

  /// Whether the page is only looked at, never zoomed: the stroke in
  /// progress is left out, and ink is kept as pixels.
  final bool still;

  @override
  State<_PageContent> createState() => _PageContentState();
}

class _PageContentState extends State<_PageContent> {
  /// The part of the page laid out.
  Aabb _region = Aabb.empty;

  /// The zoom it was laid out for, which what is drawn in pixels is drawn
  /// for: the view's, but for while it is being zoomed.
  double _zoom = 0;

  /// Whether it was laid out while the view was being zoomed, to be laid
  /// out again once it is not, for the zoom it came to.
  bool _laidOutZooming = false;

  /// Each element's widget as it was last placed, and the element it was
  /// placed for: an element placed again as the view moves on is given the
  /// very widget it had, which the framework leaves as it is.
  Map<String, (NoteElement, Widget?)> _placed =
      <String, (NoteElement, Widget?)>{};

  /// The ink over the elements, kept as pixels while the view is not being
  /// zoomed.
  final Map<InkLayer, InkTiles> _inkTiles = <InkLayer, InkTiles>{
    for (final layer in const <InkLayer>[InkLayer.marking, InkLayer.above])
      layer: InkTiles(layer),
  };

  bool get _isZooming => widget.zooming?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_onViewChanged);
    widget.zooming?.addListener(_onViewChanged);
  }

  @override
  void didUpdateWidget(_PageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      oldWidget.view.removeListener(_onViewChanged);
      widget.view.addListener(_onViewChanged);
    }
    if (!identical(oldWidget.zooming, widget.zooming)) {
      oldWidget.zooming?.removeListener(_onViewChanged);
      widget.zooming?.addListener(_onViewChanged);
    }
    // Built again from above, what the page holds, or what builds it, has
    // changed: every element is built anew.
    _placed = <String, (NoteElement, Widget?)>{};
  }

  @override
  void dispose() {
    widget.view.removeListener(_onViewChanged);
    widget.zooming?.removeListener(_onViewChanged);
    for (final tiles in _inkTiles.values) {
      tiles.dispose();
    }
    super.dispose();
  }

  void _onViewChanged() {
    final viewport = widget.view.value;
    // Laid out once more as a zoom begins, for the ink to follow it by
    // itself, and then only where it uncovers what was not laid out.
    final laidOut = _isZooming
        ? _laidOutZooming &&
              _region.containsBox(viewport.visibleBounds(widget.size))
        : !_laidOutZooming &&
              viewport.zoom == _zoom &&
              pageRegion(viewport, widget.size) == _region;
    if (!laidOut) setState(() {});
  }

  /// The widget [element] is shown by, placed at its frame: the one it was
  /// given before, in [before], if it is the same element. Only what is
  /// shown is kept for the next time.
  Widget? _place(
    Map<String, (NoteElement, Widget?)> before,
    NoteElement element,
  ) {
    final kept = before[element.id];
    if (kept != null && identical(kept.$1, element)) {
      _placed[element.id] = kept;
      return kept.$2;
    }
    final content = widget.builder?.call(context, element);
    final placed = content == null
        ? null
        : PlacedOnPage(
            // Keyed by identity so an element keeps its widget state — a
            // text box its caret, a PDF page its rendered image — while
            // others are added, removed or scrolled out of view around it.
            key: ValueKey<String>(element.id),
            frame: widget.view.value.frameInView(element.frame),
            child: content,
          );
    _placed[element.id] = (element, placed);
    return placed;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final viewport = widget.view.value;
    final region = _region = pageRegion(viewport, widget.size);
    _laidOutZooming = _isZooming;
    if (!_isZooming || _zoom == 0) _zoom = viewport.zoom;
    final shown = controller.elementsIn(region);
    final origin = Offset(region.left, region.top);
    // The painters draw in page space moved to the region's corner; on
    // sheets, each sheet's part moved down by the gaps above it, and across
    // to lie in the middle under the widest.
    final fromOrigin = CanvasViewport(origin: origin);
    final fold = viewport.fold;
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final devicePixelsPerUnit = _zoom * pixelRatio;
    final pixelsPerUnit = widget.still ? _zoom * pixelRatio : null;
    Aabb seen() => widget.view.value.visibleBounds(widget.size);
    InkTiles? tilesOf(InkLayer layer) => widget.still ? null : _inkTiles[layer];
    // While the view zooms, the ink stays as tiles, scaled with the page:
    // zooming out, drawn again for the zoom it has come to each time it
    // outgrows them; zooming in, drawn sharp again once the zoom rests, as
    // PDF pages are. Drawn as strokes at every step of a zoom in, dense
    // handwriting took three times a frame to draw.
    final tileScale =
        (_laidOutZooming ? math.min(_zoom, viewport.zoom) : _zoom) * pixelRatio;
    final ink = <InkElement>[
      for (final element in shown)
        if (element is InkElement && !element.locked) element,
    ];
    final before = _placed;
    _placed = <String, (NoteElement, Widget?)>{};
    Widget layer(bool locked, {CanvasHeader? header}) => _ElementLayer(
      placed: <Widget>[
        for (final element in shown)
          if (element.locked == locked && element is! InkElement)
            ?_place(before, element),
      ],
      // The elements are placed where the view lays them out.
      origin: viewport.toView(origin),
      header: header,
      headerFrame: header == null ? null : viewport.frameInView(header.frame),
      headerInteractive: widget.headerInteractive,
    );

    Widget paint(CustomPainter painter) => IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: painter)),
    );

    return CanvasScope(
      zoom: _zoom,
      region: region,
      zooming: _laidOutZooming,
      child: PageSpace(
        view: widget.view,
        region: region,
        devicePixelRatio: pixelRatio,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            // The pictures and PDF pages set as the background, beneath all
            // ink, and never pressed.
            IgnorePointer(child: RepaintBoundary(child: layer(true))),
            RepaintBoundary(child: layer(false, header: widget.header)),
            // Over the pictures, PDF pages and text alike, the highlighter
            // as the pen: multiplied with them, it marks what it covers.
            for (final inkLayer in InkLayer.values)
              paint(
                InkPainter(
                  elements: ink,
                  viewport: fromOrigin,
                  layer: inkLayer,
                  pixelsPerUnit: pixelsPerUnit,
                  tiles: tilesOf(inkLayer),
                  tileScale: tileScale,
                  fold: fold,
                  devicePixelsPerUnit: devicePixelsPerUnit,
                  seen: seen,
                ),
              ),
            if (!widget.still)
              paint(
                WetInkPainter(
                  controller: controller,
                  viewport: fromOrigin,
                  fold: fold,
                  devicePixelsPerUnit: devicePixelsPerUnit,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Places the element widgets on the page, with the header beneath them.
///
/// Each is laid out at its frame's size in page units, and the whole layer
/// is scaled with the page, so text lays out the same at every zoom.
class _ElementLayer extends StatelessWidget {
  const _ElementLayer({
    required this.placed,
    required this.origin,
    required this.header,
    required this.headerFrame,
    required this.headerInteractive,
  });

  /// The elements' widgets, each a [PlacedOnPage].
  final List<Widget> placed;

  /// The point of the view's space at the layer's top-left corner.
  final Offset origin;
  final CanvasHeader? header;

  /// Where the header lies in the view's space.
  final Frame? headerFrame;

  /// Whether the header takes presses: only with the select tool, so a pen
  /// can write over it.
  final bool headerInteractive;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    return PagePlacement(
      origin: origin,
      children: <Widget>[
        // Placed whether or not it is in view: scrolling it out of sight
        // must not take the keyboard from someone typing a title.
        if (header != null)
          PlacedOnPage(
            key: const ValueKey<String>('header'),
            frame: headerFrame ?? header.frame,
            child: IgnorePointer(
              ignoring: !headerInteractive,
              child: header.child,
            ),
          ),
        ...placed,
      ],
    );
  }
}

/// Lays out [InfiniteCanvas.afterSheets] below the last sheet, in the
/// middle of it, following the view by itself.
class _AfterSheets extends SingleChildLayoutDelegate {
  _AfterSheets(this.view) : super(relayout: view);

  final ValueListenable<CanvasViewport> view;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final viewport = view.value;
    final fold = viewport.fold;
    if (fold == null) return Offset(0, size.height);
    final zoom = viewport.zoom;
    final middle = (fold.width / 2 - viewport.origin.dx) * zoom;
    final bottom = (fold.extent - viewport.origin.dy) * zoom;
    return Offset(
      middle - childSize.width / 2,
      bottom + (CanvasController.deskFoot - childSize.height) / 2,
    );
  }

  @override
  bool shouldRelayout(_AfterSheets old) => old.view != view;
}

/// Takes pointer presses on the selection's handles and sides, so that they
/// reach only the canvas and not the element under the edge.
///
/// Its own parent's listener still sees the press, since it is an ancestor
/// of this; what it keeps out are the element widgets beneath in the stack.
class _HandleTargets extends LeafRenderObjectWidget {
  const _HandleTargets({required this.hits});

  final bool Function(Offset position) hits;

  @override
  _RenderHandleTargets createRenderObject(BuildContext context) =>
      _RenderHandleTargets(hits);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHandleTargets renderObject,
  ) {
    renderObject.hits = hits;
  }
}

class _RenderHandleTargets extends RenderBox {
  _RenderHandleTargets(this.hits);

  bool Function(Offset position) hits;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => hits(position);
}
