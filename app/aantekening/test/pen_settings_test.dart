import 'dart:io';

import 'package:aantekening/src/editor/pen_preferences.dart';
import 'package:aantekening/src/editor/ribbon/ribbon.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/settings/pen_settings.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  testWidgets('the page draws as the pen was set to', (tester) async {
    final assets = Directory.systemTemp.createTempSync('aantekening_pen_');
    final store = AantekeningStore.inMemory(assetDirectory: assets);
    addTearDown(() async {
      await store.close();
      assets.deleteSync(recursive: true);
    });
    final pageId = (await tester.runAsync(() async {
      final notebook = await store.library.createNotebook(title: 'Notes');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Section',
      );
      return (await store.pages.createPage(sectionId: section.id)).id;
    }))!;

    await openEditor(
      tester,
      store,
      pageId,
      preferences: Preferences.inMemory(<String, Object?>{
        'pen.smoothing': 'strong',
        'pen.firstButton': 'scroll',
        'pen.shapesOnHold': false,
      }),
    );

    final canvas = tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas));
    expect(canvas.penButtons.first, PenButtonAction.scroll);
    expect(canvas.penButtons.second, PenButtonAction.select);
    expect(canvas.shapesOnHold, isFalse);
    expect(
      tester.widget<Ribbon>(find.byType(Ribbon)).commands.canvas.inkSmoothing,
      PenSmoothing.strong.pixels,
    );
  });

  testWidgets('the settings set the pen, and tell its buttons apart', (
    tester,
  ) async {
    final preferences = Preferences.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith((ref) async => preferences),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PenSettingsPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Medium'));
    await tester.tap(find.text('Scroll').last);
    await tester.tap(find.text('Hold the pen still to make a shape'));
    await tester.pumpAndSettle();
    expect(preferences['pen.smoothing'], 'medium');
    expect(preferences['pen.secondButton'], 'scroll');
    expect(preferences['pen.shapesOnHold'], false);

    // A pen pressed with its first button held over the page says so.
    final pen = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.stylus,
      buttons: kPrimaryButton | kPrimaryStylusButton,
    );
    await pen.up();
    await tester.pumpAndSettle();
    expect(find.text('Just pressed'), findsOneWidget);
  });
}
