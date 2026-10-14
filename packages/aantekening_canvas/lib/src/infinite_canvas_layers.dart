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

  /// The text boxes kept built though they are out of the part of the page
  /// laid out, the one out of it longest first: shown again, they are there
  /// at once. Built anew as it came into view, a box of formulas took tens
  /// of milliseconds, a stutter in the scroll.
  final List<String> _kept = <String>[];

  /// How many text boxes are kept built out of view at most.
  static const int _keptAtMost = 64;

  /// Builds the text boxes about the view ahead of it, once it rests.
  Timer? _ahead;

  /// The ink over the elements, kept as pixels while the view is not being
  /// zoomed.
  final Map<InkLayer, InkTiles> _inkTiles = <InkLayer, InkTiles>{
    for (final layer in const <InkLayer>[InkLayer.marking, InkLayer.above])
      layer: InkTiles(layer),
  };

  bool get _isZooming => widget.zooming?.value ?? false;

  /// Where the elements that can be pressed are placed.
  final GlobalKey _placement = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_onViewChanged);
    widget.zooming?.addListener(_onViewChanged);
    if (!widget.still) widget.controller.showsAt = _showsAt;
    _buildAheadLater();
  }

  /// Whether the element [id] shows something at [page], as it is placed:
  /// [CanvasController.showsAt].
  bool? _showsAt(String id, Offset page) {
    final placement = _placement.currentContext?.findRenderObject();
    final space = context.findRenderObject();
    if (placement is! RenderPagePlacement || space is! RenderBox) return null;
    return placement.showsAt(
      id,
      space.localToGlobal(widget.view.value.toView(page)),
    );
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
    if (!identical(oldWidget.controller, widget.controller)) {
      if (oldWidget.controller.showsAt == _showsAt) {
        oldWidget.controller.showsAt = null;
      }
      if (!widget.still) widget.controller.showsAt = _showsAt;
    }
    // Built again from above, what the page holds, or what builds it, has
    // changed: every element is built anew — those kept out of view too,
    // which stay kept.
    _placed = <String, (NoteElement, Widget?)>{};
    _buildAheadLater();
  }

  @override
  void dispose() {
    _ahead?.cancel();
    widget.view.removeListener(_onViewChanged);
    widget.zooming?.removeListener(_onViewChanged);
    if (widget.controller.showsAt == _showsAt) {
      widget.controller.showsAt = null;
    }
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
    // One timer waits for the view to rest, rather than one set and called
    // off at every step of a scroll.
    _movedMeanwhile = true;
    if (_ahead == null) _buildAheadLater();
  }

  /// How long the view rests before the text boxes about it are built.
  static const Duration _aheadRest = Duration(milliseconds: 300);

  /// Whether the view has moved since the wait for it to rest began.
  bool _movedMeanwhile = false;

  /// Builds the text boxes about the view ahead of it once it has rested
  /// [after], and [_aheadRest] since it last moved — one a frame, the
  /// nearest first — so that a box of formulas scrolled to is there already
  /// rather than built as it comes into view.
  void _buildAheadLater([Duration after = _aheadRest]) {
    _ahead?.cancel();
    _ahead = null;
    _movedMeanwhile = false;
    if (widget.still) return;
    _ahead = Timer(after, _buildAhead);
  }

  void _buildAhead() {
    _ahead = null;
    if (!mounted) return;
    // Moved while it waited: it waits as long again from now, which is at
    // least as long as the view has rested since.
    if (_movedMeanwhile) {
      _buildAheadLater();
      return;
    }
    if (_isZooming) return;
    final next = _nearestNotBuilt();
    if (next == null) return;
    setState(() => _kept.add(next));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buildAheadLater(Duration.zero);
    });
  }

  /// The text box nearest the view, within a view or two of it, that is not
  /// built yet; or null, if there is none or enough are kept.
  String? _nearestNotBuilt() {
    if (_kept.length >= _keptAtMost) return null;
    final view = widget.view.value.visibleBounds(widget.size);
    final about = Aabb(
      view.left - view.width,
      view.top - 2 * view.height,
      view.right + view.width,
      view.bottom + 2 * view.height,
    );
    String? nearest;
    var nearestDistance = double.infinity;
    for (final element in widget.controller.elementsIn(about)) {
      if (!_keepsBuilt(element) || _placed.containsKey(element.id)) continue;
      final bounds = element.bounds;
      final distance =
          (bounds.centerX - view.centerX).abs() +
          (bounds.centerY - view.centerY).abs();
      if (distance < nearestDistance) {
        nearest = element.id;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// Whether [element] is kept built while out of view: a text box, whose
  /// formulas are slow to build, never a picture or PDF page, which would
  /// keep what it has drawn.
  static bool _keepsBuilt(NoteElement element) =>
      element is TextElement && !element.locked;

  /// The widget [element] is shown by, placed at its frame: the one it was
  /// given before, in [before], if it is the same element. Only what is
  /// shown is kept for the next time.
  Widget? _place(
    Map<String, (NoteElement, Widget?)> before,
    NoteElement element, {
    bool shown = true,
  }) {
    final kept = before[element.id];
    final Widget? content;
    if (kept != null && identical(kept.$1, element)) {
      content = kept.$2;
    } else {
      final built = widget.builder?.call(context, element);
      // Painted once, and kept: the page painted again as what comes into
      // view is placed paints only that, not every formula of every box
      // already there, glyph by glyph.
      content = built == null ? null : RepaintBoundary(child: built);
    }
    _placed[element.id] = (element, content);
    if (content == null) return null;
    return PlacedOnPage(
      // Keyed by identity so an element keeps its widget state — a text box
      // its caret, a PDF page its rendered image — while others are added,
      // removed or scrolled out of view around it.
      key: ValueKey<String>(element.id),
      id: element.id,
      frame: widget.view.value.frameInView(element.frame),
      shown: shown,
      child: content,
    );
  }

  /// The text boxes kept built out of view, as they now are, [shown] being
  /// the elements in view: those that have just left it among them.
  List<NoteElement> _keptOutOf(
    List<NoteElement> shown,
    Map<String, (NoteElement, Widget?)> before,
  ) {
    if (widget.still) return const <NoteElement>[];
    final inView = <String>{for (final element in shown) element.id};
    _kept.removeWhere(inView.contains);
    for (final MapEntry(key: id, value: (element, _)) in before.entries) {
      if (!inView.contains(id) && _keepsBuilt(element) && !_kept.contains(id)) {
        _kept.add(id);
      }
    }
    while (_kept.length > _keptAtMost) {
      _kept.removeAt(0);
    }
    final kept = <NoteElement>[];
    _kept.removeWhere((id) {
      final element = widget.controller.elementById(id);
      if (element == null || !_keepsBuilt(element)) return true;
      kept.add(element);
      return false;
    });
    return kept;
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
    final kept = _keptOutOf(shown, before);
    Widget layer(bool locked, {CanvasHeader? header}) => _ElementLayer(
      placement: locked ? null : _placement,
      placed: <Widget>[
        for (final element in shown)
          if (element.locked == locked && element is! InkElement)
            ?_place(before, element),
        if (!locked)
          for (final element in kept) ?_place(before, element, shown: false),
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
      view: widget.view,
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
    this.placement,
    required this.origin,
    required this.header,
    required this.headerFrame,
    required this.headerInteractive,
  });

  /// The elements' widgets, each a [PlacedOnPage].
  final List<Widget> placed;

  /// The key of the [PagePlacement] they are placed by.
  final GlobalKey? placement;

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
      key: placement,
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
