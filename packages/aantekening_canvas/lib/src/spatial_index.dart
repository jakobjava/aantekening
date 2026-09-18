/// A uniform-grid spatial index over the elements of a page.
library;

import 'package:aantekening_core/aantekening_core.dart';

/// Indexes element bounds so that a viewport query touches only nearby
/// elements.
///
/// A page can hold thousands of elements while only a handful are on screen.
/// Testing every element against the viewport on each frame would make paint
/// cost grow with the size of the note rather than with what is visible, so
/// elements are bucketed into fixed cells and only the cells the viewport
/// overlaps are examined.
///
/// A uniform grid is used rather than a quadtree because notes are spatially
/// even — text and ink cluster at a human writing scale — and a grid has no
/// rebalancing, no allocation per node, and integer-arithmetic lookups.
class SpatialIndex {
  SpatialIndex({this.cellSize = 512})
    : assert(cellSize > 0, 'cellSize must be positive');

  /// The width and height of one bucket, in page units.
  final double cellSize;

  final Map<int, Set<String>> _cells = <int, Set<String>>{};
  final Map<String, Aabb> _bounds = <String, Aabb>{};

  /// Number of indexed elements.
  int get length => _bounds.length;

  /// Number of occupied buckets, exposed for diagnostics and tests.
  int get cellCount => _cells.length;

  /// Adds or updates [id] with [bounds].
  void insert(String id, Aabb bounds) {
    if (_bounds.containsKey(id)) remove(id);
    if (bounds.isEmpty) return;

    _bounds[id] = bounds;
    _forEachCell(bounds, (key) {
      (_cells[key] ??= <String>{}).add(id);
    });
  }

  /// Removes [id] from the index.
  void remove(String id) {
    final bounds = _bounds.remove(id);
    if (bounds == null) return;
    _forEachCell(bounds, (key) {
      final cell = _cells[key];
      if (cell == null) return;
      cell.remove(id);
      if (cell.isEmpty) _cells.remove(key);
    });
  }

  /// Empties the index.
  void clear() {
    _cells.clear();
    _bounds.clear();
  }

  /// Replaces the whole index with [elements].
  void rebuild(Iterable<NoteElement> elements) {
    clear();
    for (final element in elements) {
      insert(element.id, element.bounds);
    }
  }

  /// Returns the identifiers whose bounds intersect [region].
  ///
  /// Bucketing is conservative, so results are filtered against the precise
  /// bounds before being returned; callers get no false positives.
  Set<String> query(Aabb region) {
    final matches = <String>{};
    _forEachCell(region, (key) {
      final cell = _cells[key];
      if (cell == null) return;
      for (final id in cell) {
        if (matches.contains(id)) continue;
        final bounds = _bounds[id];
        if (bounds != null && bounds.intersects(region)) {
          matches.add(id);
        }
      }
    });
    return matches;
  }

  /// The indexed bounds of [id], or null when it is not present.
  Aabb? boundsOf(String id) => _bounds[id];

  void _forEachCell(Aabb bounds, void Function(int key) visit) {
    final minX = (bounds.left / cellSize).floor();
    final maxX = (bounds.right / cellSize).floor();
    final minY = (bounds.top / cellSize).floor();
    final maxY = (bounds.bottom / cellSize).floor();

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        visit(_key(x, y));
      }
    }
  }

  /// Packs signed cell coordinates into one integer key.
  ///
  /// Dart integers are 64-bit on the platforms this app targets, so 32 bits per
  /// axis covers any coordinate a page can reach.
  static int _key(int x, int y) => (x << 32) ^ (y & 0xFFFFFFFF);
}
