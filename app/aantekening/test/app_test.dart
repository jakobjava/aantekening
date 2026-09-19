import 'dart:io';

import 'package:aantekening/src/editor/page_title.dart';
import 'package:aantekening/src/editor/ribbon/ribbon.dart';
import 'package:aantekening/src/editor/text/block_paragraph.dart';
import 'package:aantekening/src/graph/graph_panel.dart';
import 'package:aantekening/src/graph/note_graph.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/search/search_panel.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/library_pane.dart';
import 'package:aantekening/src/shell/page_list_pane.dart';
import 'package:aantekening/src/shell/sidebar.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/sidebar_state.dart';
import 'package:aantekening/src/shell/tree_rows.dart';
import 'package:aantekening/src/theme.dart';
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
    await tester.tap(find.text('Physics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mechanics'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PageListPane),
        matching: find.text(title),
      ),
    );
    await tester.pumpAndSettle();
    return created;
  }

  group('the window', () {
    testWidgets('shows an empty library on first run', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      expect(find.text('NOTEBOOKS'), findsOneWidget);
      expect(find.text('No notebooks yet'), findsOneWidget);
      expect(find.text('Select a page, or create one'), findsOneWidget);
    });

    testWidgets('has the ribbon across it, over the sidebar and the page', (
      tester,
    ) async {
      await openPage(tester);

      final ribbon = tester.getRect(find.byType(Ribbon));
      expect(ribbon.left, 0);
      expect(ribbon.width, wideWindow.width);
      expect(tester.getTopLeft(find.byType(Sidebar)).dy, ribbon.bottom);
      expect(tester.getTopLeft(find.byType(LibraryPane)).dy, ribbon.bottom);
      expect(find.text('Search all notes'), findsNothing, reason: 'no bar');
    });

    testWidgets('opens the editor when a page is selected', (tester) async {
      await openPage(tester);

      // The ribbon's commands are there, and the text is on the canvas
      // itself, not merely echoed in the page list's preview line.
      expect(find.byTooltip('Undo  (Ctrl+Z)'), findsOneWidget);
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

      await tester.tap(find.text('Analysis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Convergence tests'), findsOneWidget);
    });

    testWidgets('creates a notebook from the header button', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New notebook'));
      await tester.pumpAndSettle();
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
      expect(find.text('Algebra'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  group('the sidebar', () {
    testWidgets('closes a panel when its button is pressed again', (
      tester,
    ) async {
      final preferences = Preferences.inMemory();
      await openPage(tester, preferences: preferences);
      final pageLeft = tester.getTopLeft(find.byType(InfiniteCanvas)).dx;

      await tester.tap(find.byTooltip('Notebooks'));
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPane), findsNothing);
      expect(
        tester.getTopLeft(find.byType(InfiniteCanvas)).dx,
        lessThan(pageLeft - 400),
      );
      expect(preferences['sidebar.open'], 'none');
    });

    testWidgets('columns are made wider by their edges, and remembered', (
      tester,
    ) async {
      final preferences = Preferences.inMemory();
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store, preferences: preferences));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(LibraryPane));
      expect(before.width, SidebarColumn.notebooks.initialWidth);

      await tester.dragFrom(
        before.centerRight - const Offset(2, 0),
        const Offset(60, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(LibraryPane)).width,
        closeTo(before.width + 60, 1),
      );
      expect(
        tester.getSize(find.byType(PageListPane)).width,
        SidebarColumn.pages.initialWidth,
      );
      expect(
        (preferences['sidebar.widths']! as Map)['notebooks'],
        closeTo(before.width + 60, 1),
      );
    });

    testWidgets('its buttons can be moved, as the ribbon\'s can', (
      tester,
    ) async {
      final preferences = Preferences.inMemory();
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store, preferences: preferences));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Local AI')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
      await gesture.moveTo(
        tester.getRect(find.byTooltip('Notebooks')).topCenter +
            const Offset(0, 3),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final buttons = <String>['Local AI', 'Notebooks', 'Search', 'Graph'];
      final heights = <double>[
        for (final label in buttons) tester.getCenter(find.byTooltip(label)).dy,
      ];
      expect(heights, orderedEquals(List<double>.of(heights)..sort()));
      expect(preferences['sidebar.layout'], isNotNull, reason: 'saved');
    });

    testWidgets('in a narrow window a panel lies over the page', (
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

      expect(find.text('NOTEBOOKS'), findsOneWidget);
      await tester.tap(find.text('Pocket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      // Picking a page puts it away, showing the page.
      expect(find.byType(LibraryPane), findsNothing);
      expect(find.byType(InfiniteCanvas), findsOneWidget);
    });

    testWidgets('opens the local AI\'s settings', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Local AI'));
      await tester.pumpAndSettle();

      expect(find.text('Enable local AI features'), findsOneWidget);
      expect(find.byType(LibraryPane), findsNothing);
    });

    testWidgets('shows the graph of notebooks, sections and pages', (
      tester,
    ) async {
      await openPage(tester);

      await tester.tap(find.byTooltip('Graph'));
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

      await rightClick(
        tester,
        find.descendant(
          of: find.byType(PageListPane),
          matching: find.text('Lecture 1'),
        ),
      );
      await tester.tap(find.text('Rename'));
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
      expect(
        find.descendant(
          of: find.byType(PageListPane),
          matching: find.text('Dynamics'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('keys typed in the title are not the page\'s shortcuts', (
      tester,
    ) async {
      await openPage(tester);
      final commands = tester.widget<Ribbon>(find.byType(Ribbon)).commands;
      commands.canvas.selectEverything();
      await tester.pump();

      await tester.showKeyboard(titleField);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(commands.canvas.tool, CanvasTool.select, reason: 'P is a pen');
      expect(commands.canvas.document.elements, hasLength(1));
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
      final commands = tester.widget<Ribbon>(find.byType(Ribbon)).commands;

      await tester.showKeyboard(titleField);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();

      expect(
        tester.widget<EditableText>(titleField).focusNode.hasFocus,
        isFalse,
      );
      expect(commands.canvas.tool, CanvasTool.pen, reason: 'the page has it');
    });

    testWidgets('a new page is named first', (tester) async {
      await openPage(tester);

      await tester.tap(find.byTooltip('New page'));
      await tester.pumpAndSettle();

      final title = tester.widget<EditableText>(titleField);
      expect(title.controller.text, isEmpty);
      expect(title.focusNode.hasFocus, isTrue);
      expect(find.text('Untitled page'), findsOneWidget);
    });
  });

  group('menus', () {
    testWidgets('a page\'s commands come in order', (tester) async {
      await openPage(tester);

      await rightClick(
        tester,
        find.descendant(
          of: find.byType(PageListPane),
          matching: find.text('Lecture 1'),
        ),
      );

      final labels = <String>[
        'New page',
        'New subpage',
        'Cut',
        'Copy',
        'Paste',
        'Rename',
        'Delete',
      ];
      final tops = <double>[
        for (final label in labels)
          tester
              .getTopLeft(
                find.widgetWithText(PopupMenuItem<VoidCallback>, label),
              )
              .dy,
      ];
      expect(tops, orderedEquals(List<double>.of(tops)..sort()));
    });

    testWidgets('a page is copied and pasted after itself', (tester) async {
      await openPage(tester);
      Finder listed(String title) => find.descendant(
        of: find.byType(PageListPane),
        matching: find.text(title),
      );

      await rightClick(tester, listed('Lecture 1'));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      await rightClick(tester, listed('Lecture 1'));
      await tester.tap(find.text('Paste page'));
      await tester.pumpAndSettle();

      expect(listed('Lecture 1'), findsNWidgets(2));
      expect(await store.search.search('newtons'), hasLength(2));
    });

    testWidgets('deleting a section asks first', (tester) async {
      await openPage(tester);

      await rightClick(tester, find.text('Mechanics'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the section “Mechanics”?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mechanics'), findsNothing);
      expect(find.text('Select a section'), findsOneWidget);
      expect(find.text('Select a page, or create one'), findsOneWidget);
    });
  });

  group('search', () {
    Future<void> search(WidgetTester tester, String query) async {
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchPanel),
          matching: find.byType(TextField),
        ),
        query,
      );
      await tester.pump(SearchPanel.typingPause);
      await tester.pumpAndSettle();
    }

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
      await tester.tap(find.text('Elsewhere'));
      await tester.pumpAndSettle();

      await search(tester, 'resid');

      expect(find.text('1 PAGE'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InfiniteCanvas),
          matching: find.text('the residue theorem', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(marked(tester), isTrue);

      // Closing the panel takes the marks away.
      await tester.tap(find.byTooltip('Search'));
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
      expect(find.text('1 OF 2 PAGES'), findsOneWidget);
      final opened = container.read(selectedPageProvider);

      await tester.tap(find.byTooltip('Next page  (Enter)'));
      await tester.pumpAndSettle();
      expect(find.text('2 OF 2 PAGES'), findsOneWidget);
      expect(container.read(selectedPageProvider), isNot(opened));
      expect(marked(tester), isTrue);

      // Enter in the search field steps on too, wrapping round to the first.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(selectedPageProvider), opened, reason: 'wraps');
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
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      expect(find.text('Waves'), findsOneWidget);

      // Waves is the second level down: the second line beside it comes
      // down from Mechanics.
      final row = tester.getRect(
        find.ancestor(of: find.text('Waves'), matching: find.byType(TreeRow)),
      );
      await tester.tapAt(
        Offset(row.left + TreeRow.indent * 1.5, row.center.dy),
      );
      await tester.pumpAndSettle();
      expect(find.text('Waves'), findsNothing);
      expect(preferences['library.collapsed'], <String>[mechanics.id]);

      // Opening it from elsewhere, as search does, shows it again.
      ProviderScope.containerOf(tester.element(find.byType(HomeShell)))
          .read(libraryActionsProvider)
          .openSection(notebook.id, waves.id);
      await tester.pumpAndSettle();
      expect(find.text('Waves'), findsOneWidget);
      expect(preferences['library.collapsed'], isNull);
    });
  });

  group('fitting columns', () {
    test('keeps widths that fit and shrinks together those that do not', () {
      expect(fitWidths(<double>[200, 300], 600), <double>[200, 300]);
      expect(fitWidths(<double>[200, 300], 250), <double>[100, 150]);
      expect(fitWidths(<double>[200, 300], -10), <double>[0, 0]);
    });
  });

  group('snippet highlighting', () {
    const scheme = ColorScheme.light();

    test('marks the matched terms', () {
      final span = highlightedSnippet(
        'the ${SnippetMarkers.start}residue${SnippetMarkers.end} theorem',
        scheme,
      );
      final children = span.children!.cast<TextSpan>();

      expect(children.map((c) => c.text).join(), 'the residue theorem');
      expect(
        children.firstWhere((c) => c.text == 'residue').style?.fontWeight,
        FontWeight.w700,
      );
    });

    test('passes through text with no markers', () {
      final span = highlightedSnippet('plain text', scheme);
      expect(
        span.children!.cast<TextSpan>().map((c) => c.text).join(),
        'plain text',
      );
    });

    test('tolerates an unterminated marker', () {
      final span = highlightedSnippet(
        'a ${SnippetMarkers.start}broken',
        scheme,
      );
      expect(
        span.children!.cast<TextSpan>().map((c) => c.text).join(),
        'a broken',
      );
    });
  });
}
