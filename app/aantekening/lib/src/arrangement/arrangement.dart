/// Buttons the person using the app can arrange: which group each is in, and
/// in what order. The ribbon's buttons and the sidebar's are both arranged
/// this way.
library;

import 'package:flutter/foundation.dart';

/// A group of an [Arrangement], implemented by an enum whose values are the
/// groups in order.
abstract interface class ArrangementGroup<I extends Enum> implements Enum {
  /// The items this group holds before anything is moved.
  List<I> get defaults;
}

/// Which items each group holds, in order.
///
/// Every item is in exactly one group, so moving items around can never lose
/// one or show one twice.
@immutable
class Arrangement<G extends ArrangementGroup<I>, I extends Enum> {
  Arrangement._(this._groups, Map<G, List<I>> items)
    : _items = Map<G, List<I>>.unmodifiable(<G, List<I>>{
        for (final group in _groups)
          group: List<I>.unmodifiable(items[group] ?? <I>[]),
      });

  /// Every item where it starts out, in [groups]: the values of the enum
  /// implementing [ArrangementGroup].
  factory Arrangement.defaults(List<G> groups) => Arrangement._(groups, {
    for (final group in groups) group: group.defaults,
  });

  /// The arrangement saved by [toJson], or the defaults if [json] is not one.
  ///
  /// Unknown names are skipped and an item named twice keeps its first place.
  /// Items the saved arrangement does not mention — added in a later version
  /// — appear where they start out.
  factory Arrangement.fromJson(List<G> groups, Object? json) {
    if (json is! Map || json['groups'] is! Map) {
      return Arrangement.defaults(groups);
    }
    final stored = json['groups'] as Map;
    final names = <String, I>{
      for (final group in groups)
        for (final item in group.defaults) item.name: item,
    };
    final placed = <I>{};
    final items = <G, List<I>>{for (final group in groups) group: <I>[]};
    for (final group in groups) {
      final saved = stored[group.name];
      if (saved is! List) continue;
      for (final name in saved) {
        final item = names[name];
        if (item != null && placed.add(item)) items[group]!.add(item);
      }
    }
    for (final group in groups) {
      for (final item in group.defaults) {
        if (placed.add(item)) items[group]!.add(item);
      }
    }
    return Arrangement._(groups, items);
  }

  final List<G> _groups;
  final Map<G, List<I>> _items;

  /// The items in [group], in order.
  List<I> itemsIn(G group) => _items[group]!;

  /// The group holding [item].
  G groupOf(I item) => _groups.firstWhere((g) => itemsIn(g).contains(item));

  bool get isDefault =>
      _groups.every((group) => listEquals(itemsIn(group), group.defaults));

  /// [item] moved into [group], in front of the item now at [index] there,
  /// or at the end for an index past the last.
  Arrangement<G, I> move(I item, G group, int index) {
    final from = groupOf(item);
    final items = <G, List<I>>{
      for (final entry in _items.entries) entry.key: List<I>.of(entry.value),
    };
    var at = index.clamp(0, items[group]!.length);
    // Taking the item out first shifts everything after it along by one.
    if (from == group && items[from]!.indexOf(item) < at) at--;
    items[from]!.remove(item);
    items[group]!.insert(at, item);
    return Arrangement._(_groups, items);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'groups': <String, Object?>{
      for (final group in _groups)
        group.name: <String>[for (final item in itemsIn(group)) item.name],
    },
  };

  @override
  bool operator ==(Object other) =>
      other is Arrangement<G, I> &&
      _groups.every(
        (group) => listEquals(other.itemsIn(group), itemsIn(group)),
      );

  @override
  int get hashCode => Object.hashAll(<Object>[
    for (final group in _groups) Object.hashAll(itemsIn(group)),
  ]);
}
