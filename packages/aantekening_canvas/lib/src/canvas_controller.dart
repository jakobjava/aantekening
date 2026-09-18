/// Mutable editing state for one open page.
library;

import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
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
  CanvasViewport _viewport = const CanvasViewport();

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

  CanvasViewport get viewport => _viewport;

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

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  /// Replaces the open page, discarding history and selection.
  void loadDocument(PageDocument document) {
    _document = document;
    _undoStack.clear();
    _redoStack.clear();
    _selection.clear();
    _wetPoints.clear();
    _activeInkElementId = null;
    _drawing = false;
    _dirty = false;
    _reindex();
    notifyListeners();
  }

  /// Marks the current document as persisted.
  void markSaved() {
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- viewport

  set viewport(CanvasViewport value) {
    if (_viewport == value) return;
    _viewport = value;
    notifyListeners();
  }

  /// The page-space point at the centre of the view.
  Offset get viewCenter =>
      _viewport.toPage(Offset(viewSize.width / 2, viewSize.height / 2));

  /// Pans by a screen-space delta.
  void panBy(Offset delta) => viewport = _viewport.panBy(delta);

  /// Zooms by [factor] about a screen point.
  void zoomBy(double factor, Offset screenFocus) =>
      viewport = _viewport.zoomAround(_viewport.zoom * factor, screenFocus);

  /// Zooms by [factor] about the centre of the view, for keyboard and toolbar
  /// zooming where there is no pointer to anchor on.
  void zoomAtCenter(double factor) =>
      zoomBy(factor, Offset(viewSize.width / 2, viewSize.height / 2));

  /// Frames the whole page within a view of [size].
  void zoomToFit(Size size) {
    final bounds = _document.contentBounds;
    viewport = bounds.isEmpty
        ? const CanvasViewport()
        : _viewport.fit(bounds, size);
  }

  /// Resets to 100% zoom around the centre of the view.
  void resetZoom(Size size) {
    final center = _viewport.toPage(Offset(size.width / 2, size.height / 2));
    viewport = _viewport.zoomAround(1, Offset.zero).centeredOn(center, size);
  }

  // ------------------------------------------------------------------- tools

  void setTool(CanvasTool value) {
    if (_tool == value) return;
    _tool = value;
    // Switching tools ends the current run of ink, so the next stroke starts a
    // fresh element rather than joining strokes made with a different pen.
    _activeInkElementId = null;
    if (value != CanvasTool.select) _selection.clear();
    notifyListeners();
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
    notifyListeners();
  }

  // --------------------------------------------------------------- selection

  /// The elements intersecting the visible region, in paint order.
  List<NoteElement> visibleElements(Size size) {
    final ids = _index.query(_viewport.visibleBounds(size));
    final elements = <NoteElement>[for (final id in ids) ?_byId[id]];
    elements.sort((a, b) => a.z.compareTo(b.z));
    return elements;
  }

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

  /// Selects [id], replacing the selection unless [additive] is set.
  void select(String id, {bool additive = false}) {
    if (!additive) _selection.clear();
    if (additive && _selection.contains(id)) {
      _selection.remove(id);
    } else {
      _selection.add(id);
    }
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// The selected elements, in paint order.
  List<NoteElement> get selectedElements => <NoteElement>[
    for (final element in _document.elements)
      if (_selection.contains(element.id)) element,
  ];

  /// The bounding box of the selection, or null when nothing is selected.
  Aabb? get selectionBounds {
    final elements = selectedElements;
    if (elements.isEmpty) return null;
    var bounds = elements.first.bounds;
    for (var i = 1; i < elements.length; i++) {
      bounds = bounds.union(elements[i].bounds);
    }
    return bounds;
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
      _document.withElementAdded(element),
      recordUndo: recordUndo,
      markDirty: markDirty,
    );
  }

  /// Adds several elements as one undoable step, in order, each on top of the
  /// last — the pages of an imported PDF, say.
  void addElements(List<NoteElement> elements) {
    if (elements.isEmpty) return;
    var next = _document;
    for (final element in elements) {
      next = next.withElementAdded(element);
    }
    _apply(next);
  }

  /// Replaces several elements at once, as one change — a group being moved,
  /// resized or turned.
  void replaceElements(
    Iterable<NoteElement> elements, {
    bool recordUndo = true,
  }) {
    final replacements = <String, NoteElement>{
      for (final element in elements) element.id: element,
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

  /// Removes the elements named in [ids].
  void removeElements(Set<String> ids, {bool recordUndo = true}) {
    _selection.removeAll(ids);
    _apply(_document.withElementsRemoved(ids), recordUndo: recordUndo);
  }

  /// Replaces the selection with [ids].
  void selectAll(Iterable<String> ids) {
    _selection
      ..clear()
      ..addAll(ids.where(_byId.containsKey));
    notifyListeners();
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
      _document.withElementReplaced(element),
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

  /// Moves the selection by a page-space delta.
  void translateSelection(Offset delta, {bool recordUndo = true}) {
    if (_selection.isEmpty || delta == Offset.zero) return;
    var next = _document;
    for (final element in selectedElements) {
      next = next.withElementReplaced(
        element.withFrame(element.frame.translate(delta.dx, delta.dy)),
      );
    }
    _apply(next, recordUndo: recordUndo);
  }

  /// Brings the selection to the front of the paint order.
  void bringSelectionToFront() {
    if (_selection.isEmpty) return;
    var next = _document;
    var z = next.topZ;
    for (final element in selectedElements) {
      next = next.withElementReplaced(element.withZ(++z));
    }
    _apply(next);
  }

  // ------------------------------------------------------------ ink capture

  /// Begins a stroke at a page-space point.
  void beginStroke(Offset page, {double pressure = 1, double tilt = 0}) {
    _drawing = true;
    _wetPoints
      ..clear()
      ..addAll(<double>[page.dx, page.dy, _pressure(pressure), tilt]);
    notifyListeners();
  }

  /// Adds a sample to the stroke in progress.
  ///
  /// Samples closer together than a fraction of a page unit are dropped: a
  /// stylus can report faster than the display refreshes, and keeping every
  /// sample would inflate the stored page without changing what is drawn.
  void extendStroke(Offset page, {double pressure = 1, double tilt = 0}) {
    if (!_drawing) return;
    final length = _wetPoints.length;
    if (length >= 4) {
      final dx = page.dx - _wetPoints[length - 4];
      final dy = page.dy - _wetPoints[length - 3];
      if (dx * dx + dy * dy < _minSampleDistanceSquared) return;
    }
    _wetPoints.addAll(<double>[page.dx, page.dy, _pressure(pressure), tilt]);
    notifyListeners();
  }

  /// Ends the stroke and commits it to the page.
  ///
  /// Returns the ink element the stroke was added to, or null when the stroke
  /// held too few samples to be worth keeping.
  InkElement? endStroke() {
    if (!_drawing) return null;
    _drawing = false;

    if (_wetPoints.length < 4) {
      _wetPoints.clear();
      notifyListeners();
      return null;
    }

    final settings = pen;
    final stroke = InkStroke(
      tool: settings.tool,
      color: settings.strokeColor,
      width: settings.width,
      points: Float32List.fromList(_wetPoints),
    );
    _wetPoints.clear();

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

    final element = InkElement(
      id: Ulid.generate(),
      frame: const Frame(x: 0, y: 0, width: 0, height: 0),
      createdAt: now,
      updatedAt: now,
    ).withStrokes(<InkStroke>[stroke]);
    _activeInkElementId = element.id;
    _apply(_document.withElementAdded(element));
    return element;
  }

  /// Discards the stroke in progress.
  void cancelStroke() {
    if (!_drawing && _wetPoints.isEmpty) return;
    _drawing = false;
    _wetPoints.clear();
    notifyListeners();
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
    notifyListeners();
  }

  // ----------------------------------------------------------------- helpers

  /// Minimum squared distance between kept samples, in page units.
  static const double _minSampleDistanceSquared = 0.5 * 0.5;

  double _pressure(double reported) =>
      pen.pressureSensitive ? reported.clamp(0.0, 1.0) : 1.0;

  /// Commits [next] as the current document.
  void _apply(
    PageDocument next, {
    bool recordUndo = true,
    bool markDirty = true,
  }) {
    if (identical(next, _document)) return;

    if (recordUndo) {
      _undoStack.add(_document);
      if (_undoStack.length > undoLimit) _undoStack.removeAt(0);
      _redoStack.clear();
    }
    _document = next;
    if (markDirty) _dirty = true;
    _reindex();
    _selection.removeWhere((id) => !_byId.containsKey(id));
    notifyListeners();
  }

  void _reindex() {
    _byId
      ..clear()
      ..addEntries(
        _document.elements.map(
          (element) => MapEntry<String, NoteElement>(element.id, element),
        ),
      );
    _index.rebuild(_document.elements);
  }
}
