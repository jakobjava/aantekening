import 'dart:io';

import 'package:aantekening/src/editor/page_title.dart';
import 'package:aantekening/src/editor/text/block_paragraph.dart';
import 'package:aantekening/src/files/bin_view.dart';
import 'package:aantekening/src/graph/graph_panel.dart';
import 'package:aantekening/src/graph/note_graph.dart';
import 'package:aantekening/src/look/appearance.dart';
import 'package:aantekening/src/look/glass.dart';
import 'package:aantekening/src/look/marks.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/look/tones.dart';
import 'package:aantekening/src/modes/key_guide.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/search/search_line.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/new_page_dialog.dart';
import 'package:aantekening/src/shell/picker.dart';
import 'package:aantekening/src/shell/status_line.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening/src/shell/tree_rows.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the shell over an in-memory workspace.
Widget shellWith(AantekeningStore store, {Preferences? preferences}) =>
    ProviderScope(
      overrides: [
        storeProvider.overrideWith((ref) async => store),
        preferencesProvider.overrideWith(
          (ref) async => preferences ?? Preferences.inMemory(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
    );

/// Fixes the surface size so a test targets a known layout.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const Size wideWindow = Size(1500, 950);
const Size phoneWindow = Size(420, 900);

PageRef page(String id, String title, {String? parentId}) => PageRef(
  id: id,
  sectionId: 'sec',
  title: title,
  position: 0,
  createdAt: 0,
  updatedAt: 0,
  parentId: parentId,
);

PageDocument withText(String pageId, String text) =>
    PageDocument.empty(id: pageId).withElementAdded(
      TextElement(
        id: Ulid.generate(),
        frame: const Frame(x: 40, y: 400, width: 300, height: 60),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock.plain(text)],
      ),
    );

/// The title field on the page.
Finder get titleField => find.descendant(
  of: find.byType(PageTitle),
  matching: find.byType(EditableText),
);

/// What [finder] finds in the picker, leaving out the tabs, which show
/// the names of what they have open too.
Finder inPanes(Finder finder) =>
    find.descendant(of: find.byType(Picker), matching: finder);

/// The row of the menu showing named [label].
Finder inMenu(String label) => find.widgetWithText(KeyGuideRow, label);

/// The tab on the status line named [title].
Finder tabNamed(String title) =>
    find.descendant(of: find.byType(StatusLine), matching: find.text(title));

/// Opens the picker on the notebooks and pages, unless it is open.
Future<void> showPanes(WidgetTester tester) async {
  if (find.byType(Picker).evaluate().isNotEmpty) return;
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens the search line with Ctrl+F — / with a page open — and types
/// [query] into it.
Future<void> searchFor(WidgetTester tester, String query) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(SearchLine),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump(SearchLine.typingPause);
  await tester.pumpAndSettle();
}

/// Right-clicks [target].
Future<void> rightClick(WidgetTester tester, Finder target) async {
  await tester.tap(
    target,
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

void main() {
  late AantekeningStore store;
  late Directory assets;

  setUp(() {
    assets = Directory.systemTemp.createTempSync('aantekening_app_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  /// A notebook, a section and a page with [text] on it, opened in the
  /// shell.
  Future<PageRef> openPage(
    WidgetTester tester, {
    String title = 'Lecture 1',
    String text = 'Newtons second law',
    Preferences? preferences,
  }) async {
    final notebook = await store.library.createNotebook(title: 'Physics');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Mechanics',
    );
    final created = await store.pages.createPage(
      sectionId: section.id,
      title: title,
    );
    await store.pages.saveDocument(created.id, withText(created.id, text));

    useSurface(tester, wideWindow);
    await tester.pumpWidget(shellWith(store, preferences: preferences));
    await tester.pumpAndSettle();
    await showPanes(tester);
    await tester.tap(inPanes(find.text('Physics')));
    await tester.pumpAndSettle();
    await tester.tap(inPanes(find.text('Mechanics')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Picker), matching: find.text(title)),
    );
    await tester.pumpAndSettle();
    return created;
  }

  group('the window', () {
    testWidgets('shows an empty library on first run', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      expect(find.text('Notebooks and pages'), findsOneWidget);

      await showPanes(tester);
      expect(find.text('NOTEBOOKS'), findsOneWidget);
      expect(find.text('No notebooks yet — n makes one'), findsOneWidget);
    });

    testWidgets('is the page, the status line floating over its top', (
      tester,
    ) async {
      await openPage(tester);

      final line = tester.getRect(find.byType(StatusLine));
      expect(line.top, StatusLine.margin, reason: 'floating clear of it');
      expect(line.width, wideWindow.width - 2 * StatusLine.margin);
      final page = tester.getRect(find.byType(InfiniteCanvas));
      expect(page.top, 0, reason: 'beneath the status line');
      expect(page.left, 0);
      expect(find.byType(Picker), findsNothing, reason: 'put away');
      // The title is out from under it.
      expect(tester.getTopLeft(titleField).dy, greaterThan(line.bottom));
    });

    testWidgets('has the status line at its foot, if chosen', (tester) async {
      await openPage(
        tester,
        preferences: Preferences.inMemory(<String, Object?>{
          'statusLine.place': 'bottom',
        }),
      );
      expect(
        tester.getRect(find.byType(StatusLine)).bottom,
        wideWindow.height - StatusLine.margin,
      );
    });

    testWidgets('opens the editor when a page is selected', (tester) async {
      await openPage(tester);

      // The page takes the keys, and the text is on the canvas itself,
      // not merely echoed in the page list's preview line.
      expect(find.text('NORMAL'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InfiniteCanvas),
          matching: find.text('Newtons second law', findRichText: true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('lists notebooks, sections and pages', (tester) async {
      final notebook = await store.library.createNotebook(title: 'Analysis');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Series',
      );
      await store.pages.createPage(
        sectionId: section.id,
        title: 'Convergence tests',
      );

      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await showPanes(tester);

      await tester.tap(find.text('Analysis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Convergence tests'), findsOneWidget);
    });

    testWidgets('creates a notebook with n', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await showPanes(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      // Typed in the dialog, n is the name's, not the picker's again.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Algebra',
      );
      // Settling runs the dialog's exit animation to the end, which is where a
      // controller disposed too early would be caught being used again.
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Picker), findsNothing, reason: 'its page is open');
      await showPanes(tester);
      expect(inPanes(find.text('Algebra')), findsOneWidget);
      expect(inPanes(find.text('Notes')), findsOneWidget);
    });
  });

  group('the picker', () {
    testWidgets('holds still as notebooks of more or fewer sections are '
        'gone through', (tester) async {
      for (final (title, sections) in <(String, int)>[
        ('Long', 12),
        ('Short', 1),
      ]) {
        final notebook = await store.library.createNotebook(title: title);
        for (var i = 0; i < sections; i++) {
          await store.library.createSection(
            notebookId: notebook.id,
            title: '$title $i',
          );
        }
      }
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await showPanes(tester);
      Rect picker() => tester.getRect(
        find.descendant(of: find.byType(Picker), matching: find.byType(Glass)),
      );

      await tester.tap(inPanes(find.text('Long')));
      await tester.pumpAndSettle();
      final long = picker();
      await tester.tap(inPanes(find.text('Short')));
      await tester.pumpAndSettle();
      expect(picker(), long, reason: 'not shrunk, nor moved');
    });

    testWidgets('fits a narrow window, and goes once a page is picked', (
      tester,
    ) async {
      final notebook = await store.library.createNotebook(title: 'Pocket');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Notes',
      );
      await store.pages.createPage(sectionId: section.id, title: 'Shopping');

      useSurface(tester, phoneWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await showPanes(tester);

      expect(find.text('NOTEBOOKS'), findsOneWidget);
      await tester.tap(find.text('Pocket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      expect(find.byType(Picker), findsNothing);
      expect(find.byType(InfiniteCanvas), findsOneWidget);
    });

    testWidgets('shows the graph of notebooks, sections and pages', (
      tester,
    ) async {
      await openPage(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(GraphPanel), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GraphPanel)),
      );
      expect(
        container.read(noteGraphProvider).value!.nodes.map((n) => n.label),
        <String>['Physics', 'Mechanics', 'Lecture 1'],
      );
    });
  });

  group('titles', () {
    testWidgets('the page\'s title is its name in the list, both ways', (
      tester,
    ) async {
      await openPage(tester);
      expect(
        tester.widget<EditableText>(titleField).controller.text,
        'Lecture 1',
      );

      await showPanes(tester);
      await rightClick(tester, inPanes(find.text('Lecture 1')));
      await tester.tap(inMenu('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Kinematics',
      );
      expect(find.text('Rename the page'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(titleField).controller.text,
        'Kinematics',
      );

      await tester.enterText(titleField, 'Dynamics');
      await tester.pump(PageTitle.typingPause);
      await tester.pumpAndSettle();
      expect(inPanes(find.text('Dynamics')), findsOneWidget);
    });

    testWidgets('keys typed in the title are not the page\'s shortcuts', (
      tester,
    ) async {
      await openPage(tester);
      final canvas = tester
          .widget<InfiniteCanvas>(find.byType(InfiniteCanvas))
          .controller;
      canvas.selectEverything();
      await tester.pump();

      await tester.showKeyboard(titleField);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(canvas.tool, CanvasTool.select, reason: 'd draws');
      expect(canvas.document.elements, hasLength(1));
    });

    testWidgets('shows the date and time the page was made', (tester) async {
      await openPage(tester);
      final made = DateTime.fromMillisecondsSinceEpoch(
        (await store.pages.listAllPages()).single.createdAt,
      );
      final localizations = MaterialLocalizations.of(
        tester.element(find.byType(PageTitle)),
      );

      expect(find.text(localizations.formatFullDate(made)), findsOneWidget);
    });

    testWidgets('Enter in the title hands the keyboard back to the page', (
      tester,
    ) async {
      await openPage(tester);
      final canvas = tester
          .widget<InfiniteCanvas>(find.byType(InfiniteCanvas))
          .controller;

      await tester.showKeyboard(titleField);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();

      expect(
        tester.widget<EditableText>(titleField).focusNode.hasFocus,
        isFalse,
      );
      expect(canvas.tool, CanvasTool.pen, reason: 'the page has it');
    });

    testWidgets('a new page is named first', (tester) async {
      await openPage(tester);
      await showPanes(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      // As the last page was made: one canvas, unless chosen otherwise.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final title = tester.widget<EditableText>(titleField);
      expect(title.controller.text, isEmpty);
      expect(title.focusNode.hasFocus, isTrue);
      expect(find.byType(Picker), findsNothing, reason: 'its page is open');
      expect(tabNamed('Untitled page'), findsOneWidget);
    });
  });

  group('a new page', () {
    CanvasController canvasShown(WidgetTester tester) =>
        tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

    testWidgets('starts as pages on the paper chosen, and the next is '
        'offered the same', (tester) async {
      await openPage(tester);
      await showPanes(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('Squared'), findsNothing, reason: 'a canvas has none');
      await tester.tap(
        find.descendant(
          of: find.byType(NewPageDialog),
          matching: find.text('Pages'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squared'));
      await tester.tap(find.text('Letter'));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final sheets = canvasShown(tester).document.canvas.sheetsShown!;
      expect(sheets.templates, <SheetTemplate>[SheetTemplate.grid]);
      expect(sheets.size, SheetSize.letter);
      expect(tabNamed('Untitled page'), findsOneWidget);

      await showPanes(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('Squared'), findsOneWidget, reason: 'pages, as before');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        inPanes(find.text('Untitled page')),
        findsOneWidget,
        reason: 'one',
      );
    });
  });

  group('menus', () {
    testWidgets('a page\'s commands come in order', (tester) async {
      await openPage(tester);
      await showPanes(tester);

      await rightClick(tester, inPanes(find.text('Lecture 1')));

      final labels = <String>[
        'New page',
        'New subpage',
        'Cut',
        'Copy',
        'Paste',
        'Rename',
        'Delete',
      ];
      // As read: down each column, the columns left to right.
      final places = <Offset>[
        for (final label in labels) tester.getTopLeft(inMenu(label)),
      ];
      int reading(Offset a, Offset b) =>
          a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx);
      expect(places, orderedEquals(List<Offset>.of(places)..sort(reading)));
    });

    testWidgets('a page is copied and pasted after itself', (tester) async {
      await openPage(tester);
      Finder listed(String title) => inPanes(find.text(title));

      await showPanes(tester);
      await rightClick(tester, listed('Lecture 1'));
      await tester.tap(inMenu('Copy'));
      await tester.pumpAndSettle();
      await rightClick(tester, listed('Lecture 1'));
      await tester.tap(inMenu('Paste page'));
      await tester.pumpAndSettle();

      await showPanes(tester);
      expect(listed('Lecture 1'), findsNWidgets(2));
      expect(await store.search.search('newtons'), hasLength(2));
    });

    testWidgets('deleting a section moves it to the bin, and Undo brings '
        'it back', (tester) async {
      await openPage(tester);
      await showPanes(tester);

      await rightClick(tester, find.text('Mechanics'));
      await tester.tap(inMenu('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Mechanics'), findsNothing);
      expect(find.text('No sections yet — n makes one'), findsOneWidget);
      expect(find.text('“Mechanics” is in the bin.'), findsOneWidget);
      expect((await store.bin.list()).single.title, 'Mechanics');

      // Its message lies beneath the picker, put away to reach it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Undo')),
      );
      await tester.pumpAndSettle();
      await showPanes(tester);
      expect(inPanes(find.text('Mechanics')), findsOneWidget);
      expect(await store.bin.list(), isEmpty);
    });

    testWidgets('the message that something is in the bin goes by itself', (
      tester,
    ) async {
      await openPage(tester);
      await showPanes(tester);

      await rightClick(tester, find.text('Mechanics'));
      await tester.tap(inMenu('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('“Mechanics” is in the bin.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('“Mechanics” is in the bin.'), findsNothing);
    });

    testWidgets('the bin restores what was deleted, and deletes it for good '
        'once asked', (tester) async {
      Future<void> deleteMechanics() async {
        await showPanes(tester);
        await rightClick(tester, find.text('Mechanics'));
        await tester.tap(inMenu('Delete'));
        await tester.pumpAndSettle();
      }

      await openPage(tester);
      await deleteMechanics();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      expect(find.byType(BinView), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.text('The bin is empty.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close  (Esc)'));
      await tester.pumpAndSettle();
      expect(inPanes(find.text('Mechanics')), findsOneWidget);

      await deleteMechanics();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty the bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for good'));
      await tester.pumpAndSettle();
      expect(find.text('The bin is empty.'), findsOneWidget);
      expect(await store.pages.listAllPages(), isEmpty);
      expect(await store.bin.list(), isEmpty);
    });
  });

  group('search', () {
    Future<void> search(WidgetTester tester, String query) =>
        searchFor(tester, query);

    bool marked(WidgetTester tester) => tester
        .renderObjectList<RenderBlockParagraph>(find.byType(BlockParagraph))
        .any((paragraph) => paragraph.decoration.matches.isNotEmpty);

    testWidgets('opens the best match with what was found marked', (
      tester,
    ) async {
      await openPage(tester, text: 'the residue theorem');
      final other = await store.pages.createPage(
        sectionId: (await store.pages.listAllPages()).single.sectionId,
        title: 'Elsewhere',
      );
      await store.pages.saveDocument(other.id, withText(other.id, 'nothing'));
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)))
          .read(libraryRevisionProvider.notifier)
          .bump();
      await tester.pumpAndSettle();
      await showPanes(tester);
      await tester.tap(inPanes(find.text('Elsewhere')));
      await tester.pumpAndSettle();

      await search(tester, 'resid');

      expect(find.text('1 page'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InfiniteCanvas),
          matching: find.text('the residue theorem', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(marked(tester), isTrue);

      // Kept with Enter, they stay marked, until Esc on the page.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SearchLine), findsNothing);
      expect(marked(tester), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(marked(tester), isFalse);
    });

    testWidgets('steps through the pages that match', (tester) async {
      final first = await openPage(tester, text: 'contour integral');
      final second = await store.pages.createPage(
        sectionId: first.sectionId,
        title: 'Lecture 2',
      );
      await store.pages.saveDocument(
        second.id,
        withText(second.id, 'another contour'),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeShell)),
      );

      await search(tester, 'contour');
      expect(find.text('1 of 2'), findsOneWidget);
      final opened = container.read(selectedPageProvider);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(container.read(selectedPageProvider), isNot(opened));
      expect(marked(tester), isTrue);

      // Tab steps on too, wrapping round to the first.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(container.read(selectedPageProvider), opened, reason: 'wraps');

      // And a page listed opens with a click.
      await tester.tap(
        find.descendant(
          of: find.byType(SearchLine),
          matching: find.text('Lecture 2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(selectedPageProvider), second.id);
    });
  });

  group('trees', () {
    List<({String title, TreePlace place})> rowsOf(
      List<PageRef> pages, {
      Set<String> collapsed = const <String>{},
    }) => <({String title, TreePlace place})>[
      for (final (:item, :place) in treeRows(
        PageRef.hierarchy(pages),
        collapsed,
      ))
        (title: item.title, place: place),
    ];

    final pages = <PageRef>[
      page('child', 'Child', parentId: 'parent'),
      page('parent', 'Parent'),
      page('grandchild', 'Grandchild', parentId: 'child'),
      page('sibling', 'Sibling', parentId: 'parent'),
      page('other', 'Other'),
    ];

    test('places each row under its parent, with the lines beside it', () {
      final rows = rowsOf(pages);

      expect(rows.map((row) => row.title), <String>[
        'Parent',
        'Child',
        'Grandchild',
        'Sibling',
        'Other',
      ]);
      expect(rows.map((row) => row.place.expanded), <bool?>[
        true,
        true,
        null,
        null,
        null,
      ]);
      // The parent's line goes on past the child's subtree to the sibling,
      // and ends there.
      expect(rows[2].place.ancestors, <TreeAncestor>[
        (id: 'parent', continues: true),
        (id: 'child', continues: false),
      ]);
      expect(rows[3].place.ancestors, <TreeAncestor>[
        (id: 'parent', continues: false),
      ]);
      expect(rows[4].place.ancestors, isEmpty);
    });

    test('leaves out what lies beneath a collapsed row', () {
      final rows = rowsOf(pages, collapsed: <String>{'child'});

      expect(rows.map((row) => row.title), <String>[
        'Parent',
        'Child',
        'Sibling',
        'Other',
      ]);
      expect(rows[1].place.expanded, isFalse);
    });

    testWidgets('picking a section moves none of the rows', (tester) async {
      final notebook = await store.library.createNotebook(title: 'Physics');
      for (final title in <String>['Mechanics', 'Waves', 'Optics']) {
        await store.library.createSection(
          notebookId: notebook.id,
          title: title,
        );
      }
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await showPanes(tester);
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      Rect optics() => tester.getRect(inPanes(find.text('Optics')));
      final before = optics();

      await tester.tap(inPanes(find.text('Mechanics')));
      await tester.pumpAndSettle();
      expect(optics(), before);
    });

    testWidgets('a section collapses by its line, and opens out again', (
      tester,
    ) async {
      final preferences = Preferences.inMemory();
      final notebook = await store.library.createNotebook(title: 'Physics');
      final mechanics = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Mechanics',
      );
      final waves = await store.library.createSection(
        notebookId: notebook.id,
        parentId: mechanics.id,
        title: 'Waves',
      );
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store, preferences: preferences));
      await tester.pumpAndSettle();
      await showPanes(tester);
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      expect(find.text('Waves'), findsOneWidget);

      // Folded by the chevron before Mechanics.
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Mechanics'),
                matching: find.byType(InkWell),
              ),
              matching: find.byType(Mark),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Waves'), findsNothing);
      expect(preferences['library.collapsed'], <String>[mechanics.id]);

      // Opening it from elsewhere, as search does, shows it again.
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)))
          .read(libraryActionsProvider)
          .openSection(notebook.id, waves.id);
      await tester.pumpAndSettle();
      expect(inPanes(find.text('Waves')), findsOneWidget);
      expect(preferences['library.collapsed'], isNull);
    });
  });

  group('tabs', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));

    TabsState tabsOf(WidgetTester tester) =>
        containerOf(tester).read(tabsProvider);

    /// [text] on the page showing.
    Finder onPage(String text) => find.descendant(
      of: find.byType(InfiniteCanvas),
      matching: find.text(text, findRichText: true),
    );

    Future<void> pressWithControl(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    /// A second page beside the one [openPage] made, opened in a new tab
    /// from its menu.
    Future<PageRef> openSecondInNewTab(
      WidgetTester tester,
      PageRef first,
    ) async {
      final second = await store.pages.createPage(
        sectionId: first.sectionId,
        title: 'Lecture 2',
      );
      await store.pages.saveDocument(
        second.id,
        withText(second.id, 'Energy is conserved'),
      );
      containerOf(tester).read(libraryRevisionProvider.notifier).bump();
      await tester.pumpAndSettle();
      await showPanes(tester);
      await rightClick(tester, inPanes(find.text('Lecture 2')));
      await tester.tap(inMenu('Open in new tab'));
      await tester.pumpAndSettle();
      return second;
    }

    testWidgets('a page opens in a tab of its own, and each tab shows its '
        'own page', (tester) async {
      final first = await openPage(tester);
      final second = await openSecondInNewTab(tester, first);

      expect(tabsOf(tester).tabs, hasLength(2));
      expect(tabsOf(tester).active, 1);
      expect(onPage('Energy is conserved'), findsOneWidget);
      expect(tabNamed('Lecture 1'), findsOneWidget);
      expect(tabNamed('Lecture 2'), findsOneWidget);

      await tester.tap(tabNamed('Lecture 1'));
      await tester.pumpAndSettle();
      expect(onPage('Newtons second law'), findsOneWidget);
      expect(containerOf(tester).read(selectedPageProvider), first.id);

      // The picker picks for the tab showing, and for no other.
      await showPanes(tester);
      await tester.tap(inPanes(find.text('Lecture 2')));
      await tester.pumpAndSettle();
      expect(tabsOf(tester).tabs.map((tab) => tab.pageId), <String>[
        second.id,
        second.id,
      ]);
    });

    testWidgets('each tab has a search of its own', (tester) async {
      await openPage(tester);

      await pressWithControl(tester, LogicalKeyboardKey.keyT);
      expect(tabsOf(tester).tabs, hasLength(2));
      expect(tabNamed('New tab'), findsNothing, reason: 'named by its section');
      expect(find.text('Notebooks and pages'), findsOneWidget);

      await searchFor(tester, 'Newtons');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SearchLine), findsNothing);

      await pressWithControl(tester, LogicalKeyboardKey.tab);
      expect(tabsOf(tester).active, 0);
      expect(containerOf(tester).read(searchQueryProvider), isEmpty);

      await pressWithControl(tester, LogicalKeyboardKey.tab, shift: true);
      expect(tabsOf(tester).active, 1);
      expect(
        containerOf(tester).read(searchQueryProvider),
        'Newtons',
        reason: 'its search kept',
      );
    });

    testWidgets('Ctrl+W closes the tab showing; the last makes way for a new '
        'one', (tester) async {
      final first = await openPage(tester);
      await openSecondInNewTab(tester, first);

      await pressWithControl(tester, LogicalKeyboardKey.keyW);
      expect(tabsOf(tester).tabs.single.pageId, first.id);
      expect(onPage('Newtons second law'), findsOneWidget);

      await pressWithControl(tester, LogicalKeyboardKey.keyW);
      expect(tabsOf(tester).tabs.single.pageId, isNull);
      expect(tabNamed('New tab'), findsOneWidget);
    });

    testWidgets('tabs are remembered, and forget what is deleted', (
      tester,
    ) async {
      final preferences = Preferences.inMemory();
      final first = await openPage(tester, preferences: preferences);
      final second = await openSecondInNewTab(tester, first);
      expect(preferences['tabs'], <Object?>[
        containsPair('page', first.id),
        containsPair('page', second.id),
      ]);

      // Opened again, the window shows the same tabs.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(shellWith(store, preferences: preferences));
      await tester.pumpAndSettle();
      expect(tabsOf(tester).tabs.map((tab) => tab.pageId), <String>[
        first.id,
        second.id,
      ]);
      expect(onPage('Energy is conserved'), findsOneWidget);

      await containerOf(tester).read(libraryActionsProvider).delete(second);
      await tester.pumpAndSettle();
      expect(tabsOf(tester).tabs.map((tab) => tab.pageId), <String?>[
        first.id,
        null,
      ]);
    });

    testWidgets('going back to a tab finds its page where it was left', (
      tester,
    ) async {
      final first = await openPage(tester);
      final canvas = containerOf(tester);
      CanvasController view() =>
          tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;
      view().viewport = const CanvasViewport(origin: Offset(0, 300), zoom: 1.5);
      await tester.pumpAndSettle();

      await openSecondInNewTab(tester, first);
      // From its top, out from under the status line.
      expect(view().viewport.origin, const Offset(0, -StatusLine.reach / 1.5));
      canvas.read(tabsProvider.notifier).activate(0);
      await tester.pumpAndSettle();
      expect(
        view().viewport,
        const CanvasViewport(origin: Offset(0, 300), zoom: 1.5),
      );
    });

    test('closing and moving tabs keeps the one showing, or its neighbour', () {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(
            (ref) async => Preferences.inMemory(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final tabs = container.read(tabsProvider.notifier)
        ..open()
        ..open();
      expect(container.read(tabsProvider).active, 2);

      tabs.move(2, 0);
      expect(container.read(tabsProvider).active, 0);
      tabs.close(1);
      expect(container.read(tabsProvider).active, 0);
      tabs.close(0);
      expect(container.read(tabsProvider).tabs, hasLength(1));
      expect(container.read(tabsProvider).active, 0);
      tabs
        ..open()
        ..closeOthers(0);
      expect(container.read(tabsProvider).tabs, hasLength(1));
    });
  });

  group('snippet highlighting', () {
    final tones = Tones.of(const Appearance(), Brightness.light);

    test('marks the matched terms', () {
      final span = highlightedSnippet(
        'the ${SnippetMarkers.start}residue${SnippetMarkers.end} theorem',
        tones,
      );
      final children = span.children!.cast<TextSpan>();

      expect(children.map((c) => c.text).join(), 'the residue theorem');
      expect(
        children.firstWhere((c) => c.text == 'residue').style?.fontWeight,
        FontWeight.w700,
      );
    });

    test('passes through text with no markers', () {
      final span = highlightedSnippet('plain text', tones);
      expect(
        span.children!.cast<TextSpan>().map((c) => c.text).join(),
        'plain text',
      );
    });

    test('tolerates an unterminated marker', () {
      final span = highlightedSnippet('a ${SnippetMarkers.start}broken', tones);
      expect(
        span.children!.cast<TextSpan>().map((c) => c.text).join(),
        'a broken',
      );
    });
  });
}
