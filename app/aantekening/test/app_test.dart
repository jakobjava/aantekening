import 'dart:io';

import 'package:aantekening/src/editor/rich_text_view.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/search/search_results_pane.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/page_list_pane.dart';
import 'package:aantekening/src/theme.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the shell over an in-memory workspace.
Widget shellWith(AantekeningStore store) => ProviderScope(
  overrides: [storeProvider.overrideWith((ref) async => store)],
  child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
);

/// Fixes the surface size so a test targets a known layout.
///
/// The shell switches to a drawer below 900 logical pixels, and the default
/// test window is 800 wide — so every layout-sensitive test states which of the
/// two it means.
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

  group('HomeShell', () {
    testWidgets('shows an empty library on first run', (tester) async {
      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      expect(find.text('NOTEBOOKS'), findsOneWidget);
      expect(find.text('No notebooks yet'), findsOneWidget);
      expect(find.text('Select a page, or create one'), findsOneWidget);
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

      expect(find.text('Analysis'), findsOneWidget);

      await tester.tap(find.text('Analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Series'), findsOneWidget);

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Convergence tests'), findsOneWidget);
    });

    testWidgets('opens the editor when a page is selected', (tester) async {
      final notebook = await store.library.createNotebook(title: 'Physics');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Mechanics',
      );
      final created = await store.pages.createPage(
        sectionId: section.id,
        title: 'Lecture 1',
      );
      await store.pages.saveDocument(
        created.id,
        PageDocument.empty(id: created.id).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 40, y: 40, width: 300, height: 80),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('Newtons second law')],
          ),
        ),
        title: 'Lecture 1',
      );

      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mechanics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lecture 1').last);
      await tester.pumpAndSettle();

      // The toolbar is up and the element is rendered on the canvas itself,
      // not merely echoed in the page list's preview line.
      expect(find.byTooltip('Fit page'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InfiniteCanvas),
          matching: find.text('Newtons second law'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing a query swaps the page list for results', (
      tester,
    ) async {
      final notebook = await store.library.createNotebook(title: 'Maths');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'Analysis',
      );
      final created = await store.pages.createPage(sectionId: section.id);
      await store.pages.saveDocument(
        created.id,
        PageDocument.empty(id: created.id).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 0, y: 0, width: 300, height: 60),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('the residue theorem')],
          ),
        ),
      );

      useSurface(tester, wideWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'residue');
      await tester.pumpAndSettle();

      expect(find.text('1 MATCH'), findsOneWidget);
    });

    testWidgets('moves navigation into a drawer on a narrow window', (
      tester,
    ) async {
      await store.library.createNotebook(title: 'Pocket notes');

      useSurface(tester, phoneWindow);
      await tester.pumpWidget(shellWith(store));
      await tester.pumpAndSettle();

      // The panes are not on screen, but are one tap away.
      expect(find.text('NOTEBOOKS'), findsNothing);

      await tester.tap(find.byTooltip('Notebooks'));
      await tester.pumpAndSettle();

      expect(find.text('NOTEBOOKS'), findsOneWidget);
      expect(find.text('Pocket notes'), findsOneWidget);
    });
  });

  group('page ordering', () {
    test('places each subpage under its parent', () {
      final ordered = orderPagesWithSubpages(<PageRef>[
        page('child', 'Child', parentId: 'parent'),
        page('parent', 'Parent'),
        page('other', 'Other'),
      ]);

      expect(
        ordered.map((e) => (e.page.title, e.depth)).toList(),
        <(String, int)>[('Parent', 0), ('Child', 1), ('Other', 0)],
      );
    });

    test('promotes a page whose parent is missing', () {
      final ordered = orderPagesWithSubpages(<PageRef>[
        page('orphan', 'Orphan', parentId: 'gone'),
      ]);

      expect(ordered.single.depth, 0, reason: 'no page may become unreachable');
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

  group('plain-text editing', () {
    test("keeps each line's kind, indent and formatting", () {
      final existing = <TextBlock>[
        const TextBlock(
          kind: TextBlockKind.heading1,
          runs: <TextRun>[TextRun('Title', TextMarks(bold: true))],
        ),
        const TextBlock(
          kind: TextBlockKind.bulleted,
          indent: 2,
          runs: <TextRun>[TextRun('point')],
        ),
      ];

      final updated = applyPlainText(existing, 'New title\nnew point');

      expect(updated[0].kind, TextBlockKind.heading1);
      expect(updated[0].runs.single.marks.bold, isTrue);
      expect(updated[0].plainText, 'New title');
      expect(updated[1].kind, TextBlockKind.bulleted);
      expect(updated[1].indent, 2);
    });

    test('new trailing lines inherit the last block', () {
      final existing = <TextBlock>[
        const TextBlock(
          kind: TextBlockKind.bulleted,
          runs: <TextRun>[TextRun('first')],
        ),
      ];

      final updated = applyPlainText(existing, 'first\nsecond\nthird');

      expect(updated, hasLength(3));
      expect(updated.last.kind, TextBlockKind.bulleted);
    });

    test('round-trips through plain text', () {
      final blocks = <TextBlock>[
        TextBlock.plain('one'),
        TextBlock.plain('two'),
      ];
      expect(plainTextOf(applyPlainText(blocks, 'one\ntwo')), 'one\ntwo');
    });
  });
}
