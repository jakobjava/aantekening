/// The sections and pages as trees, as the picker lists them: each row's
/// place, and the rows folded away beneath others.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The ids of some rows, remembered between sessions.
class RememberedRows extends Notifier<Set<String>> {
  RememberedRows(this._key);

  final String _key;

  @override
  Set<String> build() => <String>{
    if (ref.preference(_key) case final List<Object?> ids)
      ...ids.whereType<String>(),
  };

  /// Takes [id] out if it is in, and puts it in if it is not.
  void toggle(String id) => _set(
    state.contains(id)
        ? state.difference(<String>{id})
        : <String>{...state, id},
  );

  /// Takes [ids] out.
  void remove(Iterable<String> ids) {
    final fewer = state.difference(ids.toSet());
    if (fewer.length != state.length) _set(fewer);
  }

  void _set(Set<String> ids) {
    state = ids;
    ref.savePreference(_key, ids.isEmpty ? null : ids.toList());
  }
}

/// The rows folded to hide what lies beneath them: sections and pages,
/// which show it otherwise.
final collapsedRowsProvider = NotifierProvider<RememberedRows, Set<String>>(
  () => RememberedRows('library.collapsed'),
);

/// A row above another in a tree, and whether its line goes on down past
/// that row, to a later child.
typedef TreeAncestor = ({String id, bool continues});

/// Where a row stands in a tree: beneath which rows, and whether its own
/// children show.
@immutable
class TreePlace {
  const TreePlace({
    required this.id,
    this.ancestors = const <TreeAncestor>[],
    this.expanded,
  });

  /// The id of the row's item.
  final String id;

  /// The rows this one lies beneath, from the top down.
  final List<TreeAncestor> ancestors;

  /// Whether the row's children show beneath it, or null for a row without
  /// any.
  final bool? expanded;

  int get depth => ancestors.length;
}

/// The rows of [tree] that show, in order, each with its place: what lies
/// beneath a [collapsed] row is left out. Every row lies beneath [root], a
/// row of another tree, if one is given.
List<({T item, TreePlace place})> treeRows<T>(
  Hierarchy<T> tree,
  Set<String> collapsed, {
  String? root,
}) {
  final rows = <({T item, TreePlace place})>[];
  final above = root == null ? 0 : 1;
  final path = <TreeAncestor>[if (root != null) (id: root, continues: false)];
  bool expanded(String id) => !collapsed.contains(id);

  for (final entry in tree.walk(expanded: expanded)) {
    path.removeRange(entry.depth + above, path.length);
    if (path.isNotEmpty) path.last = (id: path.last.id, continues: !entry.last);
    rows.add((
      item: entry.item,
      place: TreePlace(
        id: entry.id,
        ancestors: List<TreeAncestor>.unmodifiable(path),
        expanded: tree.hasChildren(entry.id) ? expanded(entry.id) : null,
      ),
    ));
    path.add((id: entry.id, continues: false));
  }
  return rows;
}
