import 'dart:io';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// What could not be saved is kept, and put back the next time the notes
/// are opened — over nothing newer, and never lost.
void main() {
  late Directory root;
  late String notes;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aantekening_rescue_');
    notes = p.join(root.path, 'Notes');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<AantekeningStore> open() => AantekeningStore.open(
    notesFolder: notes,
    indexFolder: p.join(root.path, 'index'),
    automatic: false,
  );

  Future<(String, String)> seed(AantekeningStore store) async {
    final notebook = await store.library.createNotebook(title: 'Physics');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Mechanics',
    );
    final page = await store.pages.createPage(
      sectionId: section.id,
      title: 'Forces',
    );
    await store.pages.saveDocument(page.id, documentWithText(page.id, 'old'));
    return (section.id, page.id);
  }

  Future<String> textOf(AantekeningStore store, String pageId) async =>
      (await store.pages.loadDocument(pageId))!.extractSearchText();

  test('puts a rescued page back into its page, untouched since', () async {
    var store = await open();
    final (_, pageId) = await seed(store);
    await store.rescuePage(documentWithText(pageId, 'unsaved words'));
    await store.close();

    store = await open();
    addTearDown(store.close);
    expect(store.rescued.map((page) => page.id), <String>[pageId]);
    expect(await textOf(store, pageId), 'unsaved words');
    expect(store.rescue.waiting, isEmpty, reason: 'put back, then let go');
  });

  test('keeps it beside a page saved since, never over it', () async {
    var store = await open();
    final (sectionId, pageId) = await seed(store);
    await store.rescuePage(documentWithText(pageId, 'rescued words'));
    // Saved afterwards — on another computer, say.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.pages.saveDocument(pageId, documentWithText(pageId, 'newer'));
    await store.close();

    store = await open();
    addTearDown(store.close);
    expect(await textOf(store, pageId), 'newer');
    final copy = store.rescued.single;
    expect(copy.id, isNot(pageId));
    expect(copy.sectionId, sectionId);
    expect(copy.title, 'Forces (rescued)');
    expect(await textOf(store, copy.id), 'rescued words');
  });

  test('keeps a page deleted for good, in a notebook of its own', () async {
    var store = await open();
    final (sectionId, pageId) = await seed(store);
    await store.rescuePage(documentWithText(pageId, 'last words'));
    store.bin.purgeSection(sectionId);
    await store.close();

    store = await open();
    addTearDown(store.close);
    final copy = store.rescued.single;
    final section = (await store.library.findSection(copy.sectionId))!;
    expect(section.title, 'Rescued');
    expect(copy.title, 'Forces (rescued)');
    expect(await textOf(store, copy.id), 'last words');
  });

  test('leaves a file it cannot read where it is', () async {
    var store = await open();
    await seed(store);
    final rescued = File(p.join(store.rescue.path, 'X.rescued.json.gz'))
      ..createSync(recursive: true);
    rescued.writeAsStringSync('not gzip');
    await store.close();

    store = await open();
    addTearDown(store.close);
    expect(store.rescued, isEmpty);
    expect(rescued.existsSync(), isTrue);
  });

  test('keeps one rescue of a page, the latest, until it is saved', () async {
    var store = await open();
    final (_, pageId) = await seed(store);
    await store.rescuePage(documentWithText(pageId, 'first try'));
    await store.rescuePage(documentWithText(pageId, 'second try'));
    expect(store.rescue.waiting, hasLength(1));
    store.rescue.release(pageId);
    expect(store.rescue.waiting, isEmpty);
    await store.rescuePage(documentWithText(pageId, 'third try'));
    await store.close();

    store = await open();
    addTearDown(store.close);
    expect(store.rescued, hasLength(1));
    expect(await textOf(store, pageId), 'third try');
  });
}
