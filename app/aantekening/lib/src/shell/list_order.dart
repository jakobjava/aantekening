/// How the notebooks, the sections of a notebook and the pages of a
/// section are listed: as the person arranged them, or by when they were made, when they last changed, or
/// their names, either way round.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The lists that can be ordered.
enum OrderedList { pages, sections, notebooks }

enum ListOrder {
  /// As the person arranged them, by dragging them where they belong.
  arranged('As arranged'),
  createdNewest('Created, newest first'),
  createdOldest('Created, oldest first'),
  changedNewest('Changed, newest first'),
  changedOldest('Changed, oldest first'),
  nameAscending('Name, A to Z'),
  nameDescending('Name, Z to A');

  const ListOrder(this.label);

  final String label;

  /// Whether it orders by when each last changed, which is worked out from
  /// what lies within each.
  bool get byChange => this == changedNewest || this == changedOldest;

  /// [items], which come as they were arranged, in this order; items that
  /// tie stay as they were arranged. When each last changed is its own date,
  /// or [changedAt]'s where given — a notebook's, the latest of its pages'.
  List<T> sort<T extends TreeNode>(
    List<T> items, {
    int Function(T item)? changedAt,
  }) {
    // Each item's date or name is worked out once, not at every comparison,
    // and the items compared by where they were.
    List<int> dates(int Function(T item) of) => <int>[
      for (final item in items) of(item),
    ];
    late final created = dates((item) => item.createdAt);
    late final changed = dates(changedAt ?? (item) => item.updatedAt);
    late final names = <String>[for (final item in items) _nameKey(item.title)];
    final int Function(int a, int b)? compare = switch (this) {
      arranged => null,
      createdNewest => (a, b) => created[b].compareTo(created[a]),
      createdOldest => (a, b) => created[a].compareTo(created[b]),
      changedNewest => (a, b) => changed[b].compareTo(changed[a]),
      changedOldest => (a, b) => changed[a].compareTo(changed[b]),
      nameAscending => (a, b) => _compareKeys(names[a], names[b]),
      nameDescending => (a, b) => _compareKeys(names[b], names[a]),
    };
    if (compare == null) return items;
    final order = List<int>.generate(items.length, (i) => i)
      ..sort((a, b) {
        final by = compare(a, b);
        return by != 0 ? by : a.compareTo(b);
      });
    return <T>[for (final i in order) items[i]];
  }
}

/// [a] before [b] by name, as a person reads a list of names: letters
/// whatever their case and accents — Ä with A — and numbers by their value,
/// so "5.3 Waves" comes before "10.1 Optics".
int compareNames(String a, String b) => _compareKeys(_nameKey(a), _nameKey(b));

/// Names as they are compared, [_nameKey]s, compared.
int _compareKeys(String left, String right) {
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final x = left.codeUnitAt(i);
    final y = right.codeUnitAt(j);
    if (_isDigit(x) && _isDigit(y)) {
      // Numbers by their value: of their digits past any zeros before
      // them, the more the greater, and as many, the first that differs.
      while (i < left.length - 1 &&
          left.codeUnitAt(i) == 0x30 &&
          _isDigit(left.codeUnitAt(i + 1))) {
        i++;
      }
      while (j < right.length - 1 &&
          right.codeUnitAt(j) == 0x30 &&
          _isDigit(right.codeUnitAt(j + 1))) {
        j++;
      }
      final startX = i;
      final startY = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      var order = (i - startX).compareTo(j - startY);
      for (var k = 0; order == 0 && k < i - startX; k++) {
        order = left
            .codeUnitAt(startX + k)
            .compareTo(right.codeUnitAt(startY + k));
      }
      if (order != 0) return order;
      continue;
    }
    if (x != y) return x.compareTo(y);
    i++;
    j++;
  }
  return (left.length - i).compareTo(right.length - j);
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// [name] as it is compared: in small letters, its accents left off.
String _nameKey(String name) {
  final lower = name.trim().toLowerCase();
  final key = StringBuffer();
  for (final rune in lower.runes) {
    key.write(_unaccented[rune] ?? String.fromCharCode(rune));
  }
  return key.toString();
}

const Map<int, String> _unaccented = <int, String>{
  0xE0: 'a',
  0xE1: 'a',
  0xE2: 'a',
  0xE3: 'a',
  0xE4: 'a',
  0xE5: 'a',
  0xE7: 'c',
  0xE8: 'e',
  0xE9: 'e',
  0xEA: 'e',
  0xEB: 'e',
  0xEC: 'i',
  0xED: 'i',
  0xEE: 'i',
  0xEF: 'i',
  0xF1: 'n',
  0xF2: 'o',
  0xF3: 'o',
  0xF4: 'o',
  0xF5: 'o',
  0xF6: 'o',
  0xF8: 'o',
  0xF9: 'u',
  0xFA: 'u',
  0xFB: 'u',
  0xFC: 'u',
  0xFD: 'y',
  0xFF: 'y',
  0xDF: 'ss',
};

/// How the list [OrderedList] names is ordered, remembered between
/// sessions.
class ListOrderSetting extends EnumPreference<ListOrder> {
  ListOrderSetting(this.list);

  final OrderedList list;

  @override
  String get key => 'library.order.${list.name}';

  @override
  List<ListOrder> get values => ListOrder.values;

  @override
  ListOrder get initial => ListOrder.arranged;

  void choose(ListOrder order) => save(order);
}

final listOrderProvider =
    NotifierProvider.family<ListOrderSetting, ListOrder, OrderedList>(
      ListOrderSetting.new,
    );
