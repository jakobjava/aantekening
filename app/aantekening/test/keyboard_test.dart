import 'dart:io';

import 'package:aantekening/src/commands/app_command.dart';
import 'package:aantekening/src/commands/command_palette.dart';
import 'package:aantekening/src/commands/key_chord.dart';
import 'package:aantekening/src/commands/shortcuts.dart';
import 'package:aantekening/src/look/appearance.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/settings/settings_view.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/sidebar_state.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart' show press;

/// Moving about the window from the keyboard: every shortcut runs its
/// command wherever the keyboard is, and can be changed.
void main() {
  late AantekeningStore store;
  late Directory assets;
  late Preferences preferences;
  late List<PageRef> pages;
  late Section mechanics;
  late Section optics;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_keys_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    preferences = Preferences.inMemory();
    final physics = await store.library.createNotebook(title: 'Physics');
    mechanics = await store.library.createSection(
      notebookId: physics.id,
      title: 'Mechanics',
    );
    optics = await store.library.createSection(
      notebookId: physics.id,
      title: 'Optics',
    );
    pages = <PageRef>[
      for (final title in <String>['Forces', 'Momentum', 'Energy'])
        await store.pages.createPage(sectionId: mechanics.id, title: title),
    ];
    await store.pages.createPage(sectionId: optics.id, title: 'Lenses');
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  /// The window, on the first page of Mechanics.
  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          preferencesProvider.overrideWith((ref) async => preferences),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    await container.read(libraryActionsProvider).openPageId(pages.first.id);
    await tester.pumpAndSettle();
    return container;
  }

  String? pageOpen(ProviderContainer container) =>
      container.read(selectedPageProvider);

  testWidgets('Go to opens a page by a few letters of its name', (
    tester,
  ) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'lns');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(CommandPalette), findsNothing);
    expect(container.read(selectedSectionProvider), optics.id);
    expect(find.text('Lenses'), findsWidgets);
  });

  testWidgets('Commands runs a command by name', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.keyP, control: true, shift: true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '>new tab');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).tabs, hasLength(2));
  });

  testWidgets('Alt and the arrows go from page to page, and back', (
    tester,
  ) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown, alt: true);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown, alt: true);
    await tester.pumpAndSettle();
    expect(pageOpen(container), pages[2].id);
    await press(tester, LogicalKeyboardKey.arrowDown, alt: true);
    await tester.pumpAndSettle();
    expect(pageOpen(container), pages[2].id, reason: 'stops at the end');

    await press(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    await tester.pumpAndSettle();
    expect(pageOpen(container), pages[1].id, reason: 'back');
    await press(tester, LogicalKeyboardKey.arrowRight, alt: true);
    await tester.pumpAndSettle();
    expect(pageOpen(container), pages[2].id, reason: 'forward');

    await press(tester, LogicalKeyboardKey.arrowDown, alt: true, shift: true);
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), optics.id);
  });

  testWidgets('a closed tab opens again, and Alt and a digit shows a tab', (
    tester,
  ) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.keyT, control: true);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.digit1, alt: true);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).active, 0);

    await press(tester, LogicalKeyboardKey.keyW, control: true);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, hasLength(1));
    await press(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, hasLength(2));
    expect(container.read(tabsProvider).current.pageId, pages.first.id);
  });

  testWidgets('the search panel takes the keyboard from its shortcut', (
    tester,
  ) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.keyF, control: true);
    await tester.pumpAndSettle();
    expect(container.read(sidebarProvider).open, SidebarTab.search);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('the settings open, and close with Escape', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.comma, control: true);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsNothing);
  });

  testWidgets('a shortcut changed works at once, and is remembered', (
    tester,
  ) async {
    final container = await open(tester);
    const ctrlK = KeyChord(LogicalKeyboardKey.keyK, control: true);
    container.read(shortcutsProvider.notifier).bind(
      AppCommand.newTab,
      <KeyChord>[ctrlK],
    );
    await press(tester, LogicalKeyboardKey.keyT, control: true);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, hasLength(1), reason: 'not now');
    await press(tester, LogicalKeyboardKey.keyK, control: true);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, hasLength(2));
    expect((preferences['shortcuts']! as Map)[AppCommand.newTab.name], <String>[
      ctrlK.encode(),
    ]);
  });

  testWidgets('light and dark switch from the keyboard', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.keyD, control: true, shift: true);
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).mode, ThemeMode.dark);
    expect(preferences['appearance'], isNotNull);
  });
}
