import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/shell/list_order.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show shellWith, showPanes, useSurface, wideWindow;

PageRef _page(String title, {int created = 0, int changed = 0}) => PageRef(
  id: title,
  sectionId: 'section',
  title: title,
  position: 0,
  createdAt: created,
  updatedAt: changed,
);

/// The titles among [titles] in the order they are shown, top to bottom.
List<String> _shown(WidgetTester tester, List<String> titles) =>
    <String>[...titles]..sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );

void main() {
  group('names', () {
    test('compare as a person reads them', () {
      final names = <String>[
        '10.1 Optik',
        'übung',
        '5.3 Stehende Wellen',
        'Zusammenfassung',
        'Aufgaben',
        '5.10 Interferenz',
      ]..sort(compareNames);
      expect(names, <String>[
        '5.3 Stehende Wellen',
        '5.10 Interferenz',
        '10.1 Optik',
        'Aufgaben',
        'übung',
        'Zusammenfassung',
      ]);
    });
  });

  group('orders', () {
    final pages = <PageRef>[
      _page('B', created: 2, changed: 30),
      _page('C', created: 3, changed: 10),
      _page('A', created: 1, changed: 20),
    ];
    List<String> titles(ListOrder order) => <String>[
      for (final page in order.sort(pages)) page.title,
    ];

    test('each way round', () {
      expect(titles(ListOrder.arranged), <String>['B', 'C', 'A']);
      expect(titles(ListOrder.createdNewest), <String>['C', 'B', 'A']);
      expect(titles(ListOrder.createdOldest), <String>['A', 'B', 'C']);
      expect(titles(ListOrder.changedNewest), <String>['B', 'A', 'C']);
      expect(titles(ListOrder.changedOldest), <String>['C', 'A', 'B']);
      expect(titles(ListOrder.nameAscending), <String>['A', 'B', 'C']);
      expect(titles(ListOrder.nameDescending), <String>['C', 'B', 'A']);
    });

    test('ties keep the order they were arranged in', () {
      final same = <PageRef>[_page('B'), _page('A'), _page('C')];
      expect(
        ListOrder.createdNewest.sort(same).map((page) => page.title),
        <String>['B', 'A', 'C'],
      );
    });
  });

  group('the panes', () {
    late AantekeningStore store;
    late String sectionId;
    const titles = <String>['Beta', 'Alpha', 'Gamma'];

    setUp(() async {
      store = AantekeningStore.inMemory();
      final notebook = await store.library.createNotebook(title: 'Physik');
      sectionId = (await store.library.createSection(
        notebookId: notebook.id,
        title: 'Wellen',
      )).id;
      for (final title in titles) {
        await store.pages.createPage(sectionId: sectionId, title: title);
      }
    });

    tearDown(() => store.close());

    Future<void> openSection(
      WidgetTester tester,
      Preferences preferences,
    ) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store, preferences: preferences));
      await tester.pumpAndSettle();
      await showPanes(tester);
      await tester.tap(find.text('Physik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wellen'));
      await tester.pumpAndSettle();
    }

    Future<List<String>> stored() async => <String>[
      for (final page in await store.pages.listPages(sectionId)) page.title,
    ];

    testWidgets('sort the pages by name, and back as arranged', (tester) async {
      final preferences = Preferences.inMemory();
      await openSection(tester, preferences);
      expect(_shown(tester, titles), titles);

      // Over to the pages, to order them with o.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      Future<void> choose(String order) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
        await tester.pumpAndSettle();
        await tester.tap(find.text(order).last);
        await tester.pumpAndSettle();
      }

      await choose('Name, Z to A');
      expect(_shown(tester, titles), <String>['Gamma', 'Beta', 'Alpha']);
      expect(preferences['library.order.pages'], 'nameDescending');
      await choose('Name, A to Z');
      expect(_shown(tester, titles), <String>['Alpha', 'Beta', 'Gamma']);
      await choose('As arranged');
      expect(_shown(tester, titles), titles);
    });

    testWidgets('drag a page above another to arrange them', (tester) async {
      await openSection(tester, Preferences.inMemory());

      final from = tester.getCenter(find.text('Gamma'));
      final to = tester.getTopLeft(find.text('Beta')) + const Offset(10, 1);
      await tester.dragFrom(from, to - from, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(await stored(), <String>['Gamma', 'Beta', 'Alpha']);
      expect(_shown(tester, titles), <String>['Gamma', 'Beta', 'Alpha']);
    });

    testWidgets('pages sorted are not arranged by dragging', (tester) async {
      final preferences = Preferences.inMemory(<String, Object?>{
        'library.order.pages': 'nameAscending',
      });
      await openSection(tester, preferences);

      final from = tester.getCenter(find.text('Gamma'));
      final to = tester.getTopLeft(find.text('Alpha'));
      await tester.dragFrom(from, to - from, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(await stored(), titles);
    });

    testWidgets('drag a notebook below another', (tester) async {
      await store.library.createNotebook(title: 'Chemie');
      await openSection(tester, Preferences.inMemory());

      final from = tester.getCenter(find.text('Physik'));
      final to =
          tester.getBottomLeft(find.text('Chemie')) - const Offset(-10, 1);
      await tester.dragFrom(from, to - from, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(
        (await store.library.listNotebooks()).map((book) => book.title),
        <String>['Chemie', 'Physik'],
      );
    });
  });
}
