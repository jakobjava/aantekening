import 'dart:async';

import 'package:aantekening/src/files/notes_location.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

/// What is written on a page is kept, however the page is left: for
/// another page, or by the editor closing, straight after the last key.
void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  Future<String> stored(String id) async =>
      (await store.pages.loadDocument(id))?.extractSearchText() ?? '';

  Future<String> anotherPage() async => (await store.pages.createPage(
    sectionId: (await store.pages.findPage(pageId))!.sectionId,
  )).id;

  testWidgets('every letter typed is kept when another page opens at once', (
    tester,
  ) async {
    final other = await anotherPage();
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Hello');
    await openEditor(tester, store, other);
    await tester.pumpAndSettle();
    expect(await stored(pageId), contains('Hello'));
  });

  testWidgets('a formula still being typed is kept when another page opens', (
    tester,
  ) async {
    final other = await anotherPage();
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Energy ');
    await press(tester, LogicalKeyboardKey.keyM, control: true);
    await type(tester, 'mc^2');
    await openEditor(tester, store, other);
    await tester.pumpAndSettle();
    final text = await stored(pageId);
    expect(text, contains('Energy'));
    expect(text, contains('c^2'));
  });

  testWidgets('a formula still being typed is kept when the editor closes', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Energy ');
    await press(tester, LogicalKeyboardKey.keyM, control: true);
    await type(tester, 'mc^2');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final text = await stored(pageId);
    expect(text, contains('Energy'));
    expect(text, contains('c^2'));
  });

  testWidgets('a page that cannot be saved is rescued, not lost', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    // Deleted for good from under it — on another computer, say.
    store.bin.purgePage(pageId);
    await startTextBox(tester);
    await type(tester, 'Last words');
    await tester.pump(const Duration(seconds: 1));
    // The rescue is written to a file a step at a time, each step waiting
    // on the disk, which the fake clock does not.
    final said = find.textContaining('is put back');
    for (var step = 0; step < 40 && said.evaluate().isEmpty; step++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final rescued = RescuedPage.decode(
      store.rescue.waiting.single.readAsBytesSync(),
    );
    expect(rescued.document.extractSearchText(), contains('Last words'));
    expect(said, findsOneWidget);
  });

  group('a change from another computer', () {
    late StreamController<FolderChanges> changes;
    setUp(() => changes = StreamController<FolderChanges>.broadcast());
    tearDown(() => changes.close());

    Future<void> open(WidgetTester tester) => openEditor(
      tester,
      store,
      pageId,
      overrides: [folderChangesProvider.overrideWith((ref) => changes.stream)],
    );

    Future<void> arrive(WidgetTester tester, String text) async {
      // As the mirror puts it in: into the index, then said.
      await store.pages.saveDocument(pageId, documentWithText(pageId, text));
      changes.add(FolderChanges(pages: <String>{pageId}));
      await tester.pumpAndSettle();
    }

    testWidgets('shows in place on a page not changed here', (tester) async {
      await open(tester);
      await arrive(tester, 'Their words');
      expect(
        find.textContaining('Their words', findRichText: true),
        findsWidgets,
      );
      expect(await store.pages.listAllPages(), hasLength(1));
    });

    testWidgets('is kept beside a page being changed here', (tester) async {
      await open(tester);
      await startTextBox(tester);
      await type(tester, 'Our words');
      await arrive(tester, 'Their words');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(await stored(pageId), contains('Our words'));
      final pages = await store.pages.listAllPages();
      final theirs = pages.singleWhere((page) => page.id != pageId);
      expect(theirs.title, contains('changed elsewhere'));
      expect(await stored(theirs.id), 'Their words');
    });
  });
}

/// A page holding one text box with [text].
PageDocument documentWithText(String pageId, String text) =>
    PageDocument.empty(id: pageId).withElementAdded(
      TextElement(
        id: Ulid.generate(),
        frame: const Frame(x: 40, y: 40, width: 400, height: 40),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock.plain(text)],
      ),
    );
