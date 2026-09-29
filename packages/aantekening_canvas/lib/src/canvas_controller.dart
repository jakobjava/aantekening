/// Mutable editing state for one open page.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'canvas_viewport.dart';
import 'spatial_index.dart';
import 'tools.dart';

/// Holds the page being edited, the viewport onto it, and the current
/// selection and tool.
///
/// The document itself stays immutable: every edit swaps in a new
/// [PageDocument]. That makes undo a matter of keeping references rather than
/// replaying inverse operations, and lets the renderer decide what to repaint
/// by comparing identity instead of diffing contents.
///
/// The page has a top-left corner, which the view never scrolls past and
/// content is kept within: see [PageDocument.shiftOntoPage].
class CanvasController extends ChangeNotifier {
  CanvasController({PageDocument? document})
    : _document = document ?? PageDocument.empty() {
    _reindex();
  }

  /// How many edits can be undone before the oldest is dropped.
  static const int undoLimit = 200;

  /// How close, in page units, a pointer must come to an element to hit it.
  static const double hitSlop = 4;

  PageDocument _document;
  final ValueNotifier<CanvasViewport> _view = ValueNotifier<CanvasViewport>(
    const CanvasViewport(),
  );
  final _Signal _contents = _Signal();
  final _Signal _wetInk = _Signal();

  /// The size of the view the canvas was last laid out in.
  ///
  /// Set by the canvas during layout, which is why assigning it does not
  /// notify: it describes the window, not the page, and nothing needs to
  /// rebuild because it changed.
  Size viewSize = Size.zero;
  CanvasTool _tool = CanvasTool.select;
  PenSettings _pen = PenSettings.defaultPen;
  PenSettings _highlighter = PenSettings.defaultHighlighter;

  final SpatialIndex _index = SpatialIndex();
  final Map<String, NoteElement> _byId = <String, NoteElement>{};
  final Set<String> _selection = <String>{};

  final List<PageDocument> _undoStack = <PageDocument>[];
  final List<PageDocument> _redoStack = <PageDocument>[];

  /// Samples of the stroke currently being drawn, as `[x, y, pressure, tilt]`.
  final List<double> _wetPoints = <double>[];

  /// The shape the stroke in progress became, or is being dragged out as,
  /// while the pointer drawing it is down.
  _ShapeDraft? _draft;

  /// How far, in screen pixels, the line being drawn trails the pointer,
  /// to steady a shaking hand: none at 0.
  ///
  /// The line is pulled along behind the pointer as if on a string that
  /// long, so a tremor shorter than the string moves nothing, and the
  /// line takes the way the hand meant. Where the pen lifts, or holds
  /// still to make a shape, it catches up.
  double inkSmoothing = 0;

  /// Where the line being drawn has got to, trailing the pointer, and the
  /// last sample the pointer gave.
  Offset _lineEnd = Offset.zero;
  ({Offset page, double pressure, double tilt})? _pointer;

  ShapeKind _shapeKind = ShapeKind.rectangle;

  /// The ink element new strokes are appended to.
  ///
  /// Consecutive strokes join one element instead of each becoming their own,
  /// so a page of handwriting stays a handful of elements. Without this, a
  /// densely written page would carry thousands, and every culling query and
  /// save would pay for them.
  String? _activeInkElementId;

  /// When the last stroke was committed; a pause longer than [inkJoinPause]
  /// starts a new ink element.
  DateTime _lastStrokeEnd = DateTime.fromMillisecondsSinceEpoch(0);

  bool _drawing = false;
  bool _dirty = false;

  /// How close, in page units, a new stroke must be to the ink written just
  /// before it to join the same element. Handwriting a paragraph stays one
  /// element; writing somewhere else on the page starts another, which can
  /// then be selected and moved on its own.
  static const double inkJoinDistance = 48;

  /// How long a pause between strokes still counts as the same writing.
  static const Duration inkJoinPause = Duration(seconds: 8);

  // ------------------------------------------------------------------- state

  PageDocument get document => _document;

  CanvasViewport get viewport => _view.value;

  /// The view, by itself. Listeners are told of every change to the view,
  /// scrolling among them, and of nothing else.
  ValueListenable<CanvasViewport> get view => _view;

  /// Told of every change but those to the view and to the stroke in
  /// progress: what the page holds, what is selected, the tools. What shows
  /// the page rebuilds for these, and follows the view without rebuilding.
  Listenable get contents => _contents;

  /// Told of each sample added to the stroke in progress, and of its start
  /// and end.
  Listenable get wetInk => _wetInk;

  CanvasTool get tool => _tool;

  /// The settings of whichever inking tool is active — the highlighter's
  /// while it is selected, the pen's otherwise.
  PenSettings get pen => _tool == CanvasTool.highlighter ? _highlighter : _pen;

  /// The pen's settings, whether or not it is the active tool.
  PenSettings get penSettings => _pen;

  /// The highlighter's settings, whether or not it is the active tool.
  PenSettings get highlighterSettings => _highlighter;

  /// Identifiers of the selected elements.
  Set<String> get selection => Set<String>.unmodifiable(_selection);

  /// Whether there are unsaved edits.
  bool get isDirty => _dirty;

  /// Whether a stroke is currently being drawn.
  bool get isDrawing => _drawing;

  /// The in-progress stroke's samples, for the wet-ink overlay.
  List<double> get wetPoints => List<double>.unmodifiable(_wetPoints);

  /// The stroke in progress as it would be kept now: as it is being drawn,
  /// or as the shape it became.
  List<InkStroke> get wetStrokes {
    final settings = pen;
    final draft = _draft;
    if (draft != null) {
      return draft.shape.strokes(
        tool: settings.tool,
        color: settings.strokeColor,
        width: settings.width,
      );
    }
    if (_wetPoints.length < InkStroke.stride) return const <InkStroke>[];
    return <InkStroke>[
      InkStroke(
        tool: settings.tool,
        color: settings.strokeColor,
        width: settings.width,
        points: Float32List.fromList(_wetPoints),
      ),
    ];
  }

  /// Whether the stroke in progress is a shape now, reshaped as the
  /// pointer moves rather than drawn on.
  bool get isShaping => _draft != null;

  /// The shape the shape tool drags out.
  ShapeKind get shapeKind => _shapeKind;

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  /// Replaces the open page, discarding history and selection, and shows it
  /// from its top-left corner at the zoom in use.
  void loadDocument(PageDocument document) {
    _document = document;
    _view.value = CanvasViewport(zoom: viewport.zoom);
    _undoStack.clear();
    _redoStack.clear();
    _selection.clear();
    _wetPoints.clear();
    _draft = null;
    _wetInk.signal();
    _activeInkElementId = null;
    _drawing = false;
    _dirty = false;
    _reindex();
    _changed();
  }

  /// Marks the page as persisted, if [saved] — what was written — is still
  /// what it holds: a change made while it was being written is not.
  void markSaved(PageDocument saved) {
    if (!_dirty || !identical(saved, _document)) return;
    _dirty = false;
    _changed();
  }

  /// Tells what listens that the page, the selection or the tools changed.
  void _changed() {
    _contents.signal();
    notifyListeners();
  }

  @override
  void dispose() {
    _view.dispose();
    _contents.dispose();
    _wetInk.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- viewport

  /// Moves the view, stopping it at the page's top and left edges.
  set viewport(CanvasViewport value) {
    final origin = value.origin;
    stretchTo(
      origin.dx >= 0 && origin.dy >= 0
          ? value
          : CanvasViewport(
              origin: Offset(math.max(0, origin.dx), math.max(0, origin.dy)),
              zoom: value.zoom,
            ),
    );
  }

  /// Moves the view to [value] as it is, even past the page's top and left
  /// edges: a scroll stretched beyond them, on its way back.
  void stretchTo(CanvasViewport value) {
    if (viewport == value) return;
    _view.value = value;
    notifyListeners();
  }

  /// The page-space point at the centre of the view.
  Offset get viewCenter =>
      viewport.toPage(Offset(viewSize.width / 2, viewSize.height / 2));

  /// Pans by a screen-space delta.
  void panBy(Offset delta) => viewport = viewport.panBy(delta);

  /// Zooms by [factor] about a screen point.
  void zoomBy(double factor, Offset screenFocus) =>
      viewport = viewport.zoomAround(viewport.zoom * factor, screenFocus);

  /// Zooms by [factor] about the centre of the view, for keyboard and toolbar
  /// zooming where there is no pointer to anchor on.
  void zoomAtCenter(double factor) =>
      zoomBy(factor, Offset(viewSize.width / 2, viewSize.height / 2));

  /// Frames the whole page within a view of [size].
  void zoomToFit(Size size) {
    final bounds = contentBounds;
    viewport = bounds.isEmpty
        ? const CanvasViewport()
        : viewport.fit(bounds, size);
  }

  /// Resets to 100% zoom around the centre of the view.
  void resetZoom(Size size) {
    final center = viewport.toPage(Offset(size.width / 2, size.height / 2));
    viewport = viewport.zoomAround(1, Offset.zero).centeredOn(center, size);
  }

  /// Scrolls just far enough to show [bounds] with [margin] screen pixels
  /// around it, or, if it does not fit, to show its top-left part.
  void reveal(Aabb bounds, {double margin = 48}) {
    final visible = viewport.visibleBounds(viewSize);
    final pad = viewport.toPageDistance(margin);
    double along(double start, double end, double viewStart, double viewEnd) {
      if (start - pad >= viewStart && end + pad <= viewEnd) return viewStart;
      final length = viewEnd - viewStart;
      // The far edge in view if the whole of it fits, else its start.
      return end - start + 2 * pad <= length && start - pad >= viewStart
          ? end + pad - length
          : start - pad;
    }

    viewport = CanvasViewport(
      origin: Offset(
        along(bounds.left, bounds.right, visible.left, visible.right),
        along(bounds.top, bounds.bottom, visible.top, visible.bottom),
      ),
      zoom: viewport.zoom,
    );
  }

  // ------------------------------------------------------------------- tools

  void setTool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    // Switching tools ends the current run of ink, so the next stroke starts a
    // fresh element rather than joining strokes made with a different pen.
    _activeInkElementId = null;
    if (value != CanvasTool.select) _selection.clear();
    _changed();
  }

  /// Chooses the shape the shape tool drags out.
  void setShapeKind(ShapeKind value) {
    if (_shapeKind == value) return;
    _shapeKind = value;
    _changed();
  }

  /// Changes the pen's settings, or the highlighter's when [value] is a
  /// highlighter.
  void setPen(PenSettings value) {
    if (value.tool == InkTool.highlighter) {
      if (_highlighter == value) return;
      _highlighter = value;
    } else {
      if (_pen == value) return;
      _pen = value;
    }
    _activeInkElementId = null;
    _changed();
  }

  // --------------------------------------------------------------- selection

  /// The elements intersecting the visible region, in paint order.
  List<NoteElement> visibleElements(Size size) =>
      elementsIn(viewport.visibleBounds(size));

  /// The elements intersecting [region] of the page, in paint order.
  List<NoteElement> elementsIn(Aabb region) {
    final ids = _index.query(region);
    final elements = <NoteElement>[for (final id in ids) ?_byId[id]];
    elements.sort((a, b) => a.z.compareTo(b.z));
    return elements;
  }

  /// What the page's content spans, worked out once for each version of it.
  Aabb get contentBounds => _contentBounds ??= _document.contentBounds;
  Aabb? _contentBounds;

  /// The topmost unlocked element at a page-space point.
  ///
  /// Turned elements are tested against their turned shape, and ink only near
  /// its strokes: a page of handwriting has a large bounding box that is
  /// mostly empty paper, and should not swallow clicks meant for what lies
  /// beneath it.
  NoteElement? hitTest(Offset page) {
    final probe = Aabb(
      page.dx - hitSlop,
      page.dy - hitSlop,
      page.dx + hitSlop,
      page.dy + hitSlop,
    );
    NoteElement? best;
    for (final id in _index.query(probe)) {
      final element = _byId[id];
      if (element == null || element.locked) continue;
      final hit = element is InkElement
          ? element.hitsStroke(page.dx, page.dy, hitSlop + 2)
          : element.frame.containsPoint(page.dx, page.dy, slop: hitSlop);
      if (!hit) continue;
      if (best == null || element.z >= best.z) best = element;
    }
    return best;
  }

  /// The topmost part of the background at a page-space point: what a
  /// right-click there can take out of the background again.
  NoteElement? backgroundAt(Offset page) {
    NoteElement? best;
    for (final id in _index.query(Aabb(page.dx, page.dy, page.dx, page.dy))) {
      final element = _byId[id];
      if (element == null ||
          !element.locked ||
          !element.frame.containsPoint(page.dx, page.dy)) {
        continue;
      }
      if (best == null || element.z >= best.z) best = element;
    }
    return best;
  }

  /// Makes the element [id] part of the page's background, beneath the rest
  /// of it, or takes it out of the background again.
  ///
  /// A background is drawn beneath all ink and cannot be picked, so it is
  /// let go of from the selection. With [recordUndo] false the change is
  /// part of the undo step before it — the picture being taken out of a text
  /// box, say.
  void setBackground(
    String id, {
    required bool background,
    bool recordUndo = true,
  }) {
    final element = _byId[id];
    if (element == null || element.locked == background) return;
    var lowest = element.z;
    for (final other in _document.elements) {
      if (other.z < lowest) lowest = other.z;
    }
    _selection.remove(id);
    _apply(
      _document.withElementReplaced(
        background
            ? element.withLocked(true).withZ(lowest - 1)
            : element.withLocked(false),
      ),
      recordUndo: recordUndo,
    );
  }

  /// Selects [id], replacing the selection unless [additive] is set.
  void select(String id, {bool additive = false}) {
    if (!additive) _selection.clear();
    if (additive && _selection.contains(id)) {
      _selection.remove(id);
    } else {
      _selection.add(id);
    }
    _changed();
  }

  /// Selects everything the marquee [region] takes in.
  ///
  /// Objects are taken whole when the marquee touches them. Handwriting is
  /// taken stroke by stroke: strokes mostly inside the marquee are split off
  /// into an element of their own and selected, so one word can be picked out
  /// of a page of notes, as with OneNote's lasso.
  void selectIn(Aabb region, {bool additive = false}) {
    if (!additive) _selection.clear();
    var next = _document;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final id in _index.query(region)) {
      final element = _byId[id];
      if (element == null || element.locked) continue;
      if (element is! InkElement) {
        _selection.add(id);
        continue;
      }
      final inside = <InkStroke>[];
      final outside = <InkStroke>[];
      for (final stroke in element.strokes) {
        final taken =
            stroke.bounds.intersects(region) &&
            stroke.fractionInside(region) >= 0.5;
        (taken ? inside : outside).add(stroke);
      }
      if (inside.isEmpty) continue;
      if (outside.isEmpty) {
        _selection.add(id);
        continue;
      }
      final split = InkElement(
        id: Ulid.generate(),
        frame: element.frame,
        createdAt: element.createdAt,
        updatedAt: now,
      ).withStrokes(inside);
      next = next
          .withElementReplaced(element.withStrokes(outside, updatedAt: now))
          .withElementAdded(split);
      _selection.add(split.id);
      if (_activeInkElementId == id) _activeInkElementId = null;
    }

    if (identical(next, _document)) {
      _changed();
    } else {
      // Splitting changes nothing that can be seen, so it is not an undo step
      // of its own; it is kept with whatever the selection is used for next.
      _apply(next, recordUndo: false);
    }
  }

  /// Selects everything on the page.
  void selectEverything() {
    _selection
      ..clear()
      ..addAll(<String>[
        for (final element in _document.elements)
          if (!element.locked) element.id,
      ]);
    _changed();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    _changed();
  }

  /// The selected elements, in paint order.
  List<NoteElement> get selectedElements => <NoteElement>[
    for (final element in _document.elements)
      if (_selection.contains(element.id)) element,
  ];

  /// The bounding box of the selection, or null when nothing is selected.
  Aabb? get selectionBounds {
    final elements = selectedElements;
    return elements.isEmpty ? null : NoteElement.boundsOf(elements);
  }

  // ----------------------------------------------------------------- editing

  /// Adds [element] on top of the page.
  ///
  /// With [markDirty] false the addition does not by itself cause a save —
  /// right for a placeholder, such as the empty text box behind a caret, that
  /// only becomes content once something is typed into it.
  void addElement(
    NoteElement element, {
    bool recordUndo = true,
    bool markDirty = true,
  }) {
    _apply(
      _document.withElementAdded(_keptOnPage(<NoteElement>[element]).single),
      recordUndo: recordUndo,
      markDirty: markDirty,
    );
  }

  /// Adds several elements as one undoable step, in order, each on top of the
  /// last — the pages of an imported PDF, say.
  void addElements(List<NoteElement> elements) {
    if (elements.isEmpty) return;
    var next = _document;
    for (final element in _keptOnPage(elements)) {
      next = next.withElementAdded(element);
    }
    _apply(next);
  }

  /// Replaces several elements at once, as one change — a group being moved,
  /// resized or turned. Moved together if need be, they stay on the page.
  void replaceElements(
    Iterable<NoteElement> elements, {
    bool recordUndo = true,
  }) {
    final replacements = <String, NoteElement>{
      for (final element in _keptOnPage(elements.toList())) element.id: element,
    };
    if (replacements.isEmpty) return;
    var changed = false;
    final updated = <NoteElement>[];
    for (final element in _document.elements) {
      final replacement = replacements[element.id];
      if (replacement != null && !identical(replacement, element)) {
        changed = true;
        updated.add(replacement);
      } else {
        updated.add(element);
      }
    }
    if (!changed) return;
    _apply(
      _document.copyWith(revision: _document.revision + 1, elements: updated),
      recordUndo: recordUndo,
    );
  }

  /// Removes the elements named in [ids]. With [markDirty] false the
  /// removal does not by itself cause a save: of what was never saved.
  void removeElements(
    Set<String> ids, {
    bool recordUndo = true,
    bool markDirty = true,
  }) {
    _selection.removeAll(ids);
    _apply(
      _document.withElementsRemoved(ids),
      recordUndo: recordUndo,
      markDirty: markDirty,
    );
  }

  /// Replaces the element of [element]'s id with it, recorded in history as
  /// its arrival: undone, it is gone. For what was a placeholder until now,
  /// kept out of history — a caret on the paper, once something is written
  /// at it.
  void replacePlaceholder(NoteElement element) {
    _record(_document.withElementsRemoved(<String>{element.id}));
    _apply(_document.withElementReplaced(element), recordUndo: false);
  }

  /// Replaces the selection with [ids].
  void selectAll(Iterable<String> ids) {
    _selection
      ..clear()
      ..addAll(ids.where(_byId.containsKey));
    _changed();
  }

  /// Replaces the element sharing [element]'s identifier.
  ///
  /// With [markDirty] false the change is not treated as an edit: it is kept,
  /// and saved along with the next real edit, but does not on its own cause a
  /// save. That is right for layout the view derives from the content, such
  /// as a text box growing to fit text that has not changed.
  void replaceElement(
    NoteElement element, {
    bool recordUndo = true,
    bool markDirty = true,
  }) {
    _apply(
      _document.withElementReplaced(_keptOnPage(<NoteElement>[element]).single),
      recordUndo: recordUndo,
      markDirty: markDirty,
    );
  }

  /// Deletes the selected elements.
  void deleteSelection() {
    if (_selection.isEmpty) return;
    final removed = Set<String>.of(_selection);
    _selection.clear();
    _apply(_document.withElementsRemoved(removed));
  }

  /// Moves the selection by a page-space delta, or as far as it goes before
  /// reaching the page's top or left edge.
  void translateSelection(Offset delta, {bool recordUndo = true}) {
    final bounds = selectionBounds;
    if (bounds == null) return;
    final back = PageDocument.shiftOntoPage(
      bounds.translate(delta.dx, delta.dy),
    );
    // Content already past the edge, from before pages had edges, is kept
    // from going further rather than pushed back.
    final moved = Offset(
      delta.dx + math.min(back.x, math.max(0, -delta.dx)),
      delta.dy + math.min(back.y, math.max(0, -delta.dy)),
    );
    if (moved == Offset.zero) return;
    var next = _document;
    for (final element in selectedElements) {
      next = next.withElementReplaced(
        element.withFrame(element.frame.translate(moved.dx, moved.dy)),
      );
    }
    _apply(next, recordUndo: recordUndo);
  }

  // ------------------------------------------------------------ ink capture

  /// Begins a stroke at a page-space point, letting go of what was picked
  /// — with a pen's button, say.
  void beginStroke(Offset page, {double pressure = 1, double tilt = 0}) {
    _selection.clear();
    _drawing = true;
    _draft = null;
    _lineEnd = page;
    _pointer = (page: page, pressure: pressure, tilt: tilt);
    _wetPoints
      ..clear()
      ..addAll(<double>[page.dx, page.dy, _pressure(pressure), tilt]);
    _wetInk.signal();
    _changed();
  }

  /// Begins dragging out a [shapeKind] from a page-space point.
  void beginShape(Offset page) {
    final at = Vec2(page.dx, page.dy);
    final shape = InkShape.begin(_shapeKind, at);
    _selection.clear();
    _drawing = true;
    _wetPoints.clear();
    _draft = _ShapeDraft(shape, shape.draggedHandle, at, dragged: true);
    _wetInk.signal();
    _changed();
  }

  /// Makes the stroke in progress the shape it was drawn as, if it clearly
  /// is one — a highlighter's only a straight line — and returns whether
  /// it did. The shape is then held by its handle nearest the pointer,
  /// which reshapes it as it moves, until it lifts.
  ///
  /// The samples within [settled] page units of where the pen came to rest
  /// are its trembling there, and are left out of what is read.
  bool snapToShape({double settled = 0}) {
    if (!_drawing || _draft != null) return false;
    _catchUp();
    final points = <Vec2>[
      for (var i = 0; i < _wetPoints.length; i += InkStroke.stride)
        Vec2(_wetPoints[i], _wetPoints[i + 1]),
    ];
    if (points.isEmpty) return false;
    final shape = ShapeRecognizer.recognize(
      points,
      linesOnly: pen.tool == InkTool.highlighter,
      settled: settled,
    );
    if (shape == null) return false;
    final pointer = points.last;
    final handles = shape.handles;
    var nearest = 0;
    for (var i = 1; i < handles.length; i++) {
      if (handles[i].distanceTo(pointer) <
          handles[nearest].distanceTo(pointer)) {
        nearest = i;
      }
    }
    _draft = _ShapeDraft(shape, nearest, pointer);
    _wetInk.signal();
    notifyListeners();
    return true;
  }

  /// Adds a sample to the stroke in progress, trailing the pointer by
  /// [inkSmoothing], or, once it is a shape, reshapes it: [constrain] keeps
  /// a box square and a line on steps of 15°.
  void extendStroke(
    Offset page, {
    double pressure = 1,
    double tilt = 0,
    bool constrain = false,
  }) {
    if (!_drawing) return;
    final draft = _draft;
    if (draft != null) {
      draft.reach(Vec2(page.dx, page.dy), constrain: constrain);
      _wetInk.signal();
      notifyListeners();
      return;
    }
    _pointer = (page: page, pressure: pressure, tilt: tilt);
    final string = viewport.toPageDistance(inkSmoothing);
    if (string > 0) {
      final pull = page - _lineEnd;
      final distance = pull.distance;
      if (distance <= string) return;
      _lineEnd += pull * ((distance - string) / distance);
    } else {
      _lineEnd = page;
    }
    _addSample(_lineEnd, pressure, tilt);
  }

  /// Brings the line being drawn up to the pointer, where it trails it.
  void _catchUp() {
    final pointer = _pointer;
    if (pointer == null || pointer.page == _lineEnd) return;
    _lineEnd = pointer.page;
    _addSample(pointer.page, pointer.pressure, pointer.tilt);
  }

  /// Adds a sample at [page] to the stroke in progress.
  ///
  /// Samples closer together than a fraction of a page unit are dropped: a
  /// stylus can report faster than the display refreshes, and keeping every
  /// sample would inflate the stored page without changing what is drawn.
  void _addSample(Offset page, double pressure, double tilt) {
    final length = _wetPoints.length;
    if (length >= 4) {
      final dx = page.dx - _wetPoints[length - 4];
      final dy = page.dy - _wetPoints[length - 3];
      if (dx * dx + dy * dy < _minSampleDistanceSquared) return;
    }
    _wetPoints.addAll(<double>[page.dx, page.dy, _pressure(pressure), tilt]);
    _wetInk.signal();
    notifyListeners();
  }

  /// Ends the stroke and commits it to the page.
  ///
  /// Returns the ink element the stroke was added to, or null when the stroke
  /// held too few samples to be worth keeping.
  InkElement? endStroke() {
    if (!_drawing) return null;
    final draft = _draft;
    if (draft == null) _catchUp();
    _drawing = false;
    _pointer = null;
    final strokes = draft == null ? wetStrokes : const <InkStroke>[];
    // What was drawn goes with the stroke, the samples of one that became
    // a shape too, or the overlay goes on showing them.
    _draft = null;
    _wetPoints.clear();
    _wetInk.signal();
    if (draft != null) return _endShape(draft);
    if (strokes.isEmpty) {
      _changed();
      return null;
    }
    final stroke = strokes.single;

    final clock = DateTime.now();
    final now = clock.millisecondsSinceEpoch;
    final active = _activeInkElementId;
    final existing = active == null ? null : _byId[active];
    final joins =
        existing is InkElement &&
        clock.difference(_lastStrokeEnd) < inkJoinPause &&
        existing.bounds.inflate(inkJoinDistance).intersects(stroke.bounds);
    _lastStrokeEnd = clock;

    if (joins) {
      final merged = existing.withStrokes(<InkStroke>[
        ...existing.strokes,
        stroke,
      ], updatedAt: now);
      _apply(_document.withElementReplaced(merged));
      return merged;
    }
    final element = _newInk(<InkStroke>[stroke], now);
    _activeInkElementId = element.id;
    return element;
  }

  /// Commits the shape [draft] holds, as an element of its own, which
  /// the writing after it does not join: it is picked and moved by itself.
  /// A shape dragged out no further than a click is put down at its usual
  /// size.
  InkElement? _endShape(_ShapeDraft draft) {
    var shape = draft.shape;
    if (draft.dragged && shape.extent < _smallestShape) {
      shape = InkShape.placed(shape.kind, draft.grip);
    }
    if (shape.extent < _smallestShape) {
      _changed();
      return null;
    }
    final settings = pen;
    _activeInkElementId = null;
    return _newInk(
      shape.strokes(
        tool: settings.tool,
        color: settings.strokeColor,
        width: settings.width,
      ),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Adds an ink element of [strokes], made at [now].
  InkElement _newInk(List<InkStroke> strokes, int now) {
    final element = InkElement(
      id: Ulid.generate(),
      frame: const Frame(x: 0, y: 0, width: 0, height: 0),
      createdAt: now,
      updatedAt: now,
    ).withStrokes(strokes);
    _apply(_document.withElementAdded(element));
    return element;
  }

  /// Discards the stroke in progress.
  void cancelStroke() {
    if (!_drawing && _wetPoints.isEmpty && _draft == null) return;
    _drawing = false;
    _pointer = null;
    _wetPoints.clear();
    _draft = null;
    _wetInk.signal();
    _changed();
  }

  /// Erases whole strokes within [radius] of a page-space point.
  ///
  /// Strokes are removed entire rather than split, which is what makes erasing
  /// predictable: a light touch never leaves invisible fragments behind.
  bool eraseAt(Offset page, {double radius = 8}) {
    final probe = Aabb(
      page.dx - radius,
      page.dy - radius,
      page.dx + radius,
      page.dy + radius,
    );

    var next = _document;
    var changed = false;
    final emptied = <String>{};

    for (final id in _index.query(probe)) {
      final element = _byId[id];
      if (element is! InkElement || element.locked) continue;

      final kept = <InkStroke>[
        for (final stroke in element.strokes)
          if (!stroke.hitTest(page.dx, page.dy, radius)) stroke,
      ];
      if (kept.length == element.strokes.length) continue;

      changed = true;
      if (kept.isEmpty) {
        emptied.add(element.id);
      } else {
        next = next.withElementReplaced(element.withStrokes(kept));
      }
    }

    if (!changed) return false;
    if (emptied.isNotEmpty) {
      next = next.withElementsRemoved(emptied);
      if (emptied.contains(_activeInkElementId)) _activeInkElementId = null;
    }
    _apply(next);
    return true;
  }

  // -------------------------------------------------------------- undo/redo

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_document);
    _document = _undoStack.removeLast();
    _afterHistoryChange();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_document);
    _document = _redoStack.removeLast();
    _afterHistoryChange();
  }

  void _afterHistoryChange() {
    _activeInkElementId = null;
    _dirty = true;
    _reindex();
    _selection.removeWhere((id) => !_byId.containsKey(id));
    _changed();
  }

  // ----------------------------------------------------------------- helpers

  /// [elements] moved together, if need be, to lie on the page.
  static List<NoteElement> _keptOnPage(List<NoteElement> elements) {
    if (elements.isEmpty) return elements;
    final shift = PageDocument.shiftOntoPage(NoteElement.boundsOf(elements));
    if (shift.x == 0 && shift.y == 0) return elements;
    return <NoteElement>[
      for (final element in elements)
        element.withFrame(element.frame.translate(shift.x, shift.y)),
    ];
  }

  /// Minimum squared distance between kept samples, in page units.
  static const double _minSampleDistanceSquared = 0.5 * 0.5;

  /// How far across, in page units, a shape has to reach to be kept.
  static const double _smallestShape = 4;

  double _pressure(double reported) =>
      pen.pressureSensitive ? reported.clamp(0.0, 1.0) : 1.0;

  /// Commits [next] as the current document.
  void _apply(
    PageDocument next, {
    bool recordUndo = true,
    bool markDirty = true,
  }) {
    if (identical(next, _document)) return;

    if (recordUndo) _record(_document);
    _document = next;
    if (markDirty) _dirty = true;
    _reindex();
    _selection.removeWhere((id) => !_byId.containsKey(id));
    _changed();
  }

  /// Keeps [before] as what undo goes back to.
  void _record(PageDocument before) {
    _undoStack.add(before);
    if (_undoStack.length > undoLimit) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Brings the lookups up to date with the document: only the elements
  /// changed, added or removed, so a keystroke in one box of a page full
  /// of handwriting does not index all of it again.
  void _reindex() {
    _contentBounds = null;
    final gone = _byId.keys.toSet();
    for (final element in _document.elements) {
      final id = element.id;
      gone.remove(id);
      if (identical(_byId[id], element)) continue;
      _byId[id] = element;
      _index.insert(id, element.bounds);
    }
    for (final id in gone) {
      _byId.remove(id);
      _index.remove(id);
    }
  }
}

/// A shape being drawn: as it was when the pointer took hold of it, by
/// which handle, and where the pointer was then.
class _ShapeDraft {
  _ShapeDraft(this.held, this.handle, this.grip, {this.dragged = false})
    : shape = held;

  final InkShape held;
  final int handle;
  final Vec2 grip;

  /// Whether it is being dragged out with the shape tool, rather than a
  /// stroke that became it.
  final bool dragged;

  /// The shape as it is now.
  InkShape shape;

  /// Moves the handle held as far as the pointer, now at [pointer], has
  /// moved since it took hold: measured from there, so nothing drifts.
  void reach(Vec2 pointer, {required bool constrain}) {
    shape = held.withHandle(
      handle,
      held.handles[handle] + (pointer - grip),
      constrain: constrain,
    );
  }
}

/// A change with nothing to say but that it happened.
class _Signal extends ChangeNotifier {
  void signal() => notifyListeners();
}
