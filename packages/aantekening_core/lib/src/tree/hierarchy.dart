/// Items arranged in a tree by the parent each one names: sections within
/// sections, pages beneath pages.
library;

/// An item as [Hierarchy.walk] reaches it.
typedef HierarchyEntry<T> = ({T item, String id, int depth, bool last});

/// A tree assembled from a flat list of items, each naming its parent.
///
/// The store lists sections and pages flat, in order; this puts them back in
/// their tree once, for everything that shows or reasons about the nesting.
/// Every item is always reachable from the top: one whose parent is not in
/// the list — filtered out, or missing — is a root, and so is the item at
/// which a loop of parents, which the store never writes, would close.
class Hierarchy<T> {
  Hierarchy._(this._items, this._parents, this._children);

  /// The tree of [items], identified by [idOf] and nested under the item
  /// [parentOf] names, if any. Siblings keep the order they have in [items].
  factory Hierarchy.of(
    Iterable<T> items, {
    required String Function(T item) idOf,
    required String? Function(T item) parentOf,
  }) {
    final byId = <String, T>{for (final item in items) idOf(item): item};
    final parents = <String, String?>{
      for (final MapEntry(key: id, value: item) in byId.entries)
        id: byId.containsKey(parentOf(item)) ? parentOf(item) : null,
    };
    // A loop of parents is broken where it is found, making that item a root.
    for (final id in byId.keys) {
      final chain = <String>{id};
      for (var at = parents[id]; at != null; at = parents[at]) {
        if (!chain.add(at)) {
          parents[id] = null;
          break;
        }
      }
    }
    final children = <String?, List<String>>{};
    for (final id in byId.keys) {
      (children[parents[id]] ??= <String>[]).add(id);
    }
    return Hierarchy._(byId, parents, children);
  }

  final Map<String, T> _items;
  final Map<String, String?> _parents;
  final Map<String?, List<String>> _children;

  /// The items at the top, in order.
  List<T> get roots => _itemsOf(null);

  /// Whether the tree holds nothing.
  bool get isEmpty => _items.isEmpty;

  /// The item [id] names, if it is in the tree.
  T? operator [](String id) => _items[id];

  /// The items directly beneath [id], in order.
  List<T> childrenOf(String id) => _itemsOf(id);

  /// Whether anything lies beneath [id].
  bool hasChildren(String id) => _children[id]?.isNotEmpty ?? false;

  /// The id of the item [id] lies directly beneath, or null for a root.
  String? parentOf(String id) => _parents[id];

  /// The ids of the items [id] lies beneath, its parent first.
  Iterable<String> ancestorsOf(String id) sync* {
    for (var at = _parents[id]; at != null; at = _parents[at]) {
      yield at;
    }
  }

  /// Whether [id] is [ancestor] or lies anywhere beneath it.
  bool isWithin(String id, String ancestor) =>
      id == ancestor || ancestorsOf(id).contains(ancestor);

  /// Every item in reading order — each followed by what lies beneath it —
  /// with its id, how deeply it is nested, and whether it is the last of its
  /// siblings. What lies beneath an item whose id [expanded] says no to is
  /// left out.
  Iterable<HierarchyEntry<T>> walk({
    bool Function(String id)? expanded,
  }) sync* {
    Iterable<HierarchyEntry<T>> visit(String? parent, int depth) sync* {
      final ids = _children[parent] ?? const <String>[];
      for (final (index, id) in ids.indexed) {
        yield (
          item: _items[id] as T,
          id: id,
          depth: depth,
          last: index == ids.length - 1,
        );
        if (expanded == null || expanded(id)) yield* visit(id, depth + 1);
      }
    }

    yield* visit(null, 0);
  }

  List<T> _itemsOf(String? parent) => <T>[
    for (final id in _children[parent] ?? const <String>[]) _items[id] as T,
  ];
}
