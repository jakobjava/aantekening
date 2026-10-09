import 'dart:io';

import 'package:aantekening/src/commands/app_command.dart';
import 'package:aantekening/src/commands/key_chord.dart';
import 'package:aantekening/src/commands/shortcuts.dart';
import 'package:aantekening/src/editor/page_editor.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/look/appearance.dart';
import 'package:aantekening/src/look/chooser.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/search/search_line.dart';
import 'package:aantekening/src/search/search_session.dart';
import 'package:aantekening/src/settings/settings_view.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/picker.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart' show press, typeKeys, typeKeysAtOnce;

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
    expect(find.byType(Chooser), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'lns');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(Chooser), findsNothing);
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

  testWidgets('/ opens the search line, the best match opening as it is '
      'typed; Enter keeps what is found, for n to step through', (
    tester,
  ) async {
    final container = await open(tester);
    for (final page in pages) {
      await tester.runAsync(
        () => store.pages.saveDocument(
          page.id,
          PageDocument.empty(id: page.id).withElementAdded(
            TextElement(
              id: 'text',
              frame: const Frame(x: 40, y: 200, width: 300, height: 40),
              createdAt: 0,
              updatedAt: 0,
              blocks: <TextBlock>[
                TextBlock.plain(page == pages.first ? 'nothing' : 'work done'),
              ],
            ),
          ),
        ),
      );
    }

    // What is typed straight after /, before the line is drawn, is in it.
    await typeKeysAtOnce(tester, '/work');
    await tester.pump();
    expect(container.read(searchLineProvider), isTrue);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(SearchLine),
        matching: find.byType(TextField),
      ),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'work');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => container.read(searchResultsProvider.future));
    await tester.pumpAndSettle();
    final first = container.read(selectedPageProvider);
    expect(first, isNot(pages.first.id), reason: 'the best match opened');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(searchLineProvider), isFalse);
    expect(container.read(searchHighlightProvider), isNotNull, reason: 'kept');

    await typeKeys(tester, 'n');
    expect(container.read(selectedPageProvider), isNot(first));
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(searchHighlightProvider), isNull);
  });

  testWidgets('the picker opens on the page open, j and k move through its '
      'rows, and a page picked closes it — however fast the keys come', (
    tester,
  ) async {
    final container = await open(tester);
    Future<void> key(LogicalKeyboardKey key, [String? character]) async {
      await tester.sendKeyDownEvent(key, character: character);
      await tester.sendKeyUpEvent(key);
    }

    // Not a frame between them: the picker is not yet drawn as they come.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await key(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await key(LogicalKeyboardKey.keyJ, 'j');
    await key(LogicalKeyboardKey.keyJ, 'j');
    await key(LogicalKeyboardKey.keyK, 'k');
    await key(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(Picker), findsNothing);
    expect(
      container.read(selectedPageProvider),
      pages[1].id,
      reason: 'from the page open, down two and up one',
    );

    // The page has the keys again, put away by Esc as by a pick.
    await typeKeys(tester, '/');
    expect(container.read(searchLineProvider), isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyE, control: true, shift: true);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Picker), findsNothing);
    await typeKeys(tester, '/');
    expect(container.read(searchLineProvider), isTrue);
  });

  testWidgets('the window splits between two tabs, Alt+l going between '
      'them and a click in the other giving it the keys', (tester) async {
    final container = await open(tester);
    await container.read(libraryActionsProvider).openIdInNewTab(pages[1].id);
    await tester.pumpAndSettle();
    TabsState tabs() => container.read(tabsProvider);
    expect(tabs().active, 1);

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'wv');
    expect(find.byType(PageEditor), findsNWidgets(2));
    expect(tabs().beside, 1, reason: 'the other tab, beside');
    expect(tabs().active, 0);
    final first = tester.getRect(find.byType(PageEditor).first);
    final second = tester.getRect(find.byType(PageEditor).last);
    expect(first.right, lessThanOrEqualTo(second.left), reason: 'side by side');

    await press(tester, LogicalKeyboardKey.keyL, alt: true);
    await tester.pumpAndSettle();
    expect(tabs().active, 1);
    expect(tabs().beside, 0);

    final editors = tester.stateList(find.byType(PageEditor)).toList();
    await tester.tapAt(first.center);
    await tester.pumpAndSettle();
    expect(tabs().active, 0, reason: 'clicked into');
    expect(
      tester.stateList(find.byType(PageEditor)),
      editors,
      reason: 'neither page opened again',
    );
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextBoxEditor>(),
      isNotNull,
      reason: 'the click went on to the page, placing a caret',
    );

    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'wq');
    expect(find.byType(PageEditor), findsOneWidget);
    expect(tabs().beside, isNull);
    expect(tabs().tabs, hasLength(2), reason: 'the other still a tab');
  });

  testWidgets('the line between split panes is dragged to share the window '
      'otherwise, and is remembered', (tester) async {
    final container = await open(tester);
    await container.read(libraryActionsProvider).openIdInNewTab(pages[1].id);
    await tester.pumpAndSettle();
    container.read(tabsProvider.notifier).split(stacked: false);
    await tester.pumpAndSettle();
    Rect first() => tester.getRect(find.byType(PageEditor).first);
    final before = first();

    final line = Offset(before.right + 0.5, before.center.dy);
    await tester.dragFrom(line, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(first().width, closeTo(before.width - 150, 1));
    expect(
      preferences['tabs.share'],
      closeTo((before.width - 150) / (before.width * 2), 0.01),
    );

    await tester.dragFrom(
      Offset(first().right + 0.5, before.center.dy),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();
    expect(
      first().width,
      closeTo(SplitShare.least * (before.width * 2), 1),
      reason: 'neither pane goes',
    );
  });

  testWidgets('the picker keeps the row the keys are on in view', (
    tester,
  ) async {
    for (var i = 1; i <= 40; i++) {
      await store.pages.createPage(sectionId: mechanics.id, title: 'Page $i');
    }
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyE, control: true, shift: true);
    await tester.pumpAndSettle();

    /// Whether [title]'s row shows whole in its column.
    bool shows(String title) {
      final row = find.descendant(
        of: find.byType(Picker),
        matching: find.text(title),
      );
      if (row.evaluate().isEmpty) return false;
      final list = tester.getRect(
        find.ancestor(of: row, matching: find.byType(Scrollable)).first,
      );
      final rect = tester.getRect(row);
      return rect.top >= list.top && rect.bottom <= list.bottom;
    }

    expect(shows('Page 40'), isFalse, reason: 'far down');
    await typeKeys(tester, 'G');
    expect(shows('Page 40'), isTrue, reason: 'the last, in view');
    await typeKeys(tester, 'g');
    expect(shows('Forces'), isTrue, reason: 'the first, in view again');
    for (var i = 0; i < 25; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(shows('Page 22'), isTrue, reason: 'followed down by the arrows');
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
