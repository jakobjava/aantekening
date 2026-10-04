import 'package:aantekening/src/editor/text/formula_window.dart';
import 'package:aantekening/src/look/controls.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/settings/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the formulas settings set how long a source grows before it '
      'gets a window', (tester) async {
    final preferences = Preferences.inMemory();
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWith((ref) async => preferences),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SettingsView(initial: SettingsPage.formulas),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('${FormulaWindow.usual} characters'), findsOneWidget);

    final slider = tester.getRect(find.byType(LevelSlider));
    await tester.tapAt(slider.centerRight - const Offset(1, 0));
    await tester.pumpAndSettle();
    expect(find.text('${FormulaWindow.most} characters'), findsOneWidget);
    expect(preferences['math.windowPast'], FormulaWindow.most);

    await tester.tapAt(slider.centerLeft + const Offset(1, 0));
    await tester.pumpAndSettle();
    expect(find.text('${FormulaWindow.least} characters'), findsOneWidget);
  });
}
