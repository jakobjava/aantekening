import 'package:aantekening/src/editor/page_minimap.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  /// A page with text boxes down to 3000 units.
  Future<void> saveLongPage(WidgetTester tester) => tester.runAsync(
    () => store.pages.saveDocument(
      pageId,
      PageDocument(
        id: pageId,
        elements: <NoteElement>[
          for (var i = 0; i < 10; i++)
            TextElement(
              id: 'box$i',
              frame: Frame(x: 40, y: 200 + i * 300.0, width: 300, height: 60),
              createdAt: 0,
              updatedAt: 0,
              blocks: <TextBlock>[TextBlock.plain('Box $i')],
            ),
        ],
      ),
    ),
  );

  CanvasController canvasOf(WidgetTester tester) =>
      tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

  testWidgets('the page has a scrollbar down its side and along its foot', (
    tester,
  ) async {
    await saveLongPage(tester);
    await openEditor(tester, store, pageId);

    expect(find.byType(PageScrollbar), findsNWidgets(2));
    expect(find.byType(PageMinimap), findsNothing);
  });

  testWidgets('the page preview takes the vertical scrollbar\'s place, and '
      'a press on it brings that part of the page into view', (tester) async {
    await saveLongPage(tester);
    final preferences = Preferences.inMemory();
    await openEditor(tester, store, pageId, preferences: preferences);

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'zp');

    expect(find.byType(PageMinimap), findsOneWidget);
    expect(find.byType(PageScrollbar), findsOneWidget, reason: 'across only');
    expect(preferences['view.minimap'], isTrue);
    // Every box is drawn on it, small.
    expect(
      find.descendant(
        of: find.byType(PageMinimap),
        matching: find.text('Box 9', findRichText: true),
      ),
      findsOneWidget,
    );

    final map = tester.getRect(find.byType(PageMinimap));
    await tester.tapAt(
      map.bottomCenter - const Offset(0, 4),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final canvas = canvasOf(tester);
    final view = canvas.viewport.visibleBounds(canvas.viewSize);
    expect(view.top, greaterThan(1000), reason: 'far down the page');
  });
}
