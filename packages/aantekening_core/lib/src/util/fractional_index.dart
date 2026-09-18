/// Ordering keys that allow inserting between two siblings without rewriting
/// the rest of the list.
library;

/// Computes sort keys for reorderable lists (pages in a section, sections in a
/// notebook, and so on).
///
/// Sibling order is stored as a `REAL` column rather than a contiguous integer
/// rank. Dragging one page between two others then touches a single row instead
/// of renumbering every following sibling, which keeps reordering O(1) no
/// matter how large the notebook grows.
abstract final class FractionalIndex {
  /// The gap between consecutive appended items.
  static const double step = 1024;

  /// Returns a key that sorts before [first].
  static double before(double first) => first - step;

  /// Returns a key that sorts after [last].
  static double after(double last) => last + step;

  /// Returns a key that sorts strictly between [a] and [b].
  ///
  /// Repeated subdivision eventually exhausts double precision; callers should
  /// treat [needsRebalance] as a signal to renumber the affected sibling list.
  static double between(double a, double b) {
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    return low + (high - low) / 2;
  }

  /// Computes the key for an item dropped between [previous] and [next], either
  /// of which may be null at the ends of the list.
  static double insert({double? previous, double? next}) {
    if (previous == null && next == null) return 0;
    if (previous == null) return before(next!);
    if (next == null) return after(previous);
    return between(previous, next);
  }

  /// Whether [a] and [b] have converged closely enough that the sibling list
  /// should be renumbered with evenly spaced keys.
  static bool needsRebalance(double a, double b) => (a - b).abs() < 1e-9;

  /// Produces evenly spaced keys for [count] items, used when rebalancing.
  static List<double> rebalanced(int count) => <double>[
    for (var i = 0; i < count; i++) i * step,
  ];
}
