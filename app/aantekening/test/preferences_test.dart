import 'package:aantekening/src/look/floating_pane.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/shell/list_order.dart';
import 'package:aantekening/src/shell/recent_pages.dart';
import 'package:aantekening/src/shell/status_line.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening/src/shell/tree_rows.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A container over [preferences], read already.
  Future<ProviderContainer> over(Preferences preferences) async {
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWith((ref) async => preferences)],
    );
    addTearDown(container.dispose);
    await container.read(preferencesProvider.future);
    return container;
  }

  test('reads what an earlier version saved, as it saved it', () async {
    final container = await over(
      Preferences.inMemory(<String, Object?>{
        'statusLine.place': 'bottom',
        'library.order.pages': 'nameDescending',
        'tabs.share': 0.3,
        'recent.pages': <Object?>['b', 'a'],
        'library.collapsed': <Object?>['s1'],
        'pane.picker': <String, Object?>{'x': 10, 'y': 20},
      }),
    );

    expect(container.read(statusLinePlaceProvider), StatusLinePlace.bottom);
    expect(
      container.read(listOrderProvider(OrderedList.pages)),
      ListOrder.nameDescending,
    );
    expect(
      container.read(listOrderProvider(OrderedList.sections)),
      ListOrder.arranged,
    );
    expect(container.read(splitShareProvider), 0.3);
    expect(container.read(recentPagesProvider), <String>['b', 'a']);
    expect(container.read(collapsedRowsProvider), <String>{'s1'});
    expect(container.read(panePlacementProvider(Pane.picker)), (
      at: const Offset(10, 20),
      size: null,
    ));
  });

  test('saves as an earlier version did, keeping nothing for what each '
      'starts at', () async {
    final preferences = Preferences.inMemory();
    final container = await over(preferences);

    container
        .read(statusLinePlaceProvider.notifier)
        .place(StatusLinePlace.bottom);
    container
        .read(listOrderProvider(OrderedList.notebooks).notifier)
        .choose(ListOrder.changedNewest);
    container.read(splitShareProvider.notifier).set(0.25);
    container.read(recentPagesProvider.notifier).visit('p');
    container.read(collapsedRowsProvider.notifier).toggle('s');
    container.read(panePlacementProvider(Pane.picker).notifier).place((
      at: const Offset(1, 2),
      size: const Size(3, 4),
    ));

    expect(preferences['statusLine.place'], 'bottom');
    expect(preferences['library.order.notebooks'], 'changedNewest');
    expect(preferences['tabs.share'], 0.25);
    expect(preferences['recent.pages'], <String>['p']);
    expect(preferences['library.collapsed'], <String>['s']);
    expect(preferences['pane.picker'], <String, Object?>{
      'x': 1.0,
      'y': 2.0,
      'width': 3.0,
      'height': 4.0,
    });

    container.read(statusLinePlaceProvider.notifier).place(StatusLinePlace.top);
    container
        .read(listOrderProvider(OrderedList.notebooks).notifier)
        .choose(ListOrder.arranged);
    container.read(splitShareProvider.notifier).set(SplitShare.even);
    container.read(collapsedRowsProvider.notifier).toggle('s');
    container.read(panePlacementProvider(Pane.picker).notifier).reset();
    for (final key in <String>[
      'statusLine.place',
      'library.order.notebooks',
      'tabs.share',
      'library.collapsed',
      'pane.picker',
    ]) {
      expect(preferences[key], isNull, reason: key);
    }
  });
}
