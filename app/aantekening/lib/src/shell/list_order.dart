/// How the pages of a section, and the notebooks, are listed: as the person
/// arranged them, or by when they were made, when they last changed, or
/// their names, either way round.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../look/controls.dart';
import '../preferences.dart';

/// The lists that can be ordered.
enum OrderedList { pages, notebooks }

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

  /// [items], which come as they were arranged, in this order; items that
  /// tie stay as they were arranged. When each last changed is its own date,
  /// or [changedAt]'s where given — a notebook's, the latest of its pages'.
  List<T> sort<T extends TreeNode>(
    List<T> items, {
    int Function(T item)? changedAt,
  }) {
    final changed = changedAt ?? (T item) => item.updatedAt;
    final int Function(T a, T b)? compare = switch (this) {
      arranged => null,
      createdNewest => (a, b) => b.createdAt.compareTo(a.createdAt),
      createdOldest => (a, b) => a.createdAt.compareTo(b.createdAt),
      changedNewest => (a, b) => changed(b).compareTo(changed(a)),
      changedOldest => (a, b) => changed(a).compareTo(changed(b)),
      nameAscending => (a, b) => compareNames(a.title, b.title),
      nameDescending => (a, b) => compareNames(b.title, a.title),
    };
    if (compare == null) return items;
    final indexed =
        <(int, T)>[for (var i = 0; i < items.length; i++) (i, items[i])]
          ..sort((a, b) {
            final order = compare(a.$2, b.$2);
            return order != 0 ? order : a.$1.compareTo(b.$1);
          });
    return <T>[for (final (_, item) in indexed) item];
  }
}

/// [a] before [b] by name, as a person reads a list of names: letters
/// whatever their case and accents — Ä with A — and numbers by their value,
/// so "5.3 Waves" comes before "10.1 Optics".
int compareNames(String a, String b) {
  final left = _nameKey(a);
  final right = _nameKey(b);
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final x = left.codeUnitAt(i);
    final y = right.codeUnitAt(j);
    if (_isDigit(x) && _isDigit(y)) {
      final startX = i;
      final startY = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      final order = BigInt.parse(left.substring(startX, i))
          .compareTo(BigInt.parse(right.substring(startY, j)));
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
class ListOrderSetting extends Notifier<ListOrder> {
  ListOrderSetting(this.list);

  final OrderedList list;

  String get _key => 'library.order.${list.name}';

  @override
  ListOrder build() => switch (ref.preference(_key)) {
    final String name =>
      ListOrder.values.asNameMap()[name] ?? ListOrder.arranged,
    _ => ListOrder.arranged,
  };

  void choose(ListOrder order) {
    state = order;
    ref.savePreference(_key, order == ListOrder.arranged ? null : order.name);
  }
}

final listOrderProvider =
    NotifierProvider.family<ListOrderSetting, ListOrder, OrderedList>(
      ListOrderSetting.new,
    );

/// The pane header's button choosing how [list] is ordered, from a menu of
/// the orders with the one in use ticked.
class ListOrderButton extends ConsumerWidget {
  const ListOrderButton(this.list, {super.key});

  final OrderedList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(listOrderProvider(list));
    MenuCommand item(ListOrder choice) => MenuCommand(
      choice.label,
      () => ref.read(listOrderProvider(list).notifier).choose(choice),
      checked: choice == order,
    );
    return Builder(
      builder: (context) => SmallButton(
        'Sort',
        tooltip: order == ListOrder.arranged
            ? 'As arranged: drag ${list.name} to arrange them'
            : order.label,
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          unawaited(
            showCommandMenu(
              context,
              box.localToGlobal(box.size.bottomLeft(Offset.zero)),
              <List<MenuCommand>>[
                <MenuCommand>[item(ListOrder.arranged)],
                <MenuCommand>[
                  item(ListOrder.createdNewest),
                  item(ListOrder.createdOldest),
                ],
                <MenuCommand>[
                  item(ListOrder.changedNewest),
                  item(ListOrder.changedOldest),
                ],
                <MenuCommand>[
                  item(ListOrder.nameAscending),
                  item(ListOrder.nameDescending),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
