import 'dart:io';

import 'package:aantekening/src/ai/workspace_reader.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AantekeningStore store;
  late Directory assets;
  late Notebook notebook;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_reader_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    notebook = await store.library.createNotebook(title: 'Physics');
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  Future<void> save(String pageId, String text) => store.pages.saveDocument(
    pageId,
    PageDocument.empty(id: pageId).withElementAdded(
      TextElement(
        id: 'text',
        frame: const Frame(x: 40, y: 40, width: 300, height: 60),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock.plain(text)],
      ),
    ),
  );

  /// A page titled [title] in section [sectionId], saying [text].
  Future<PageRef> pageSaying(
    String sectionId,
    String title,
    String text,
  ) async {
    final page = await store.pages.createPage(
      sectionId: sectionId,
      title: title,
    );
    await save(page.id, text);
    return page;
  }

  test('a notebook’s pages are listed under the sections they are in, '
      'nested as they are', () async {
    final mechanics = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Mechanics',
    );
    final forces = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Forces',
      parentId: mechanics.id,
    );
    final optics = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Optics',
    );
    await pageSaying(mechanics.id, 'Motion', 'Things move.');
    await pageSaying(forces.id, 'Newton', 'Force is mass times acceleration.');
    await pageSaying(optics.id, 'Lenses', 'Light bends.');
    final reader = WorkspaceReader(store);

    final pages = await reader.pagesIn(NoteLink.notebook(notebook.id));
    expect(
      <String, List<String>>{for (final page in pages) page.title: page.path},
      <String, List<String>>{
        'Motion': <String>['Physics', 'Mechanics'],
        'Newton': <String>['Physics', 'Mechanics', 'Forces'],
        'Lenses': <String>['Physics', 'Optics'],
      },
    );
    final within = await reader.pagesIn(NoteLink.section(mechanics.id));
    expect(within.map((page) => page.title), <String>['Motion', 'Newton']);
    expect(
      (await reader.pagesIn(NoteLink.section(forces.id))).single.path,
      <String>['Physics', 'Mechanics', 'Forces'],
    );
  });

  test('every page asked about is taken apart once for each version of it, '
      'though only a few are kept whole', () async {
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Mechanics',
    );
    final pages = <PageRef>[
      for (var i = 0; i < WorkspaceReader.documentsKept * 2; i++)
        await pageSaying(section.id, 'Page $i', 'Fact number $i.'),
    ];
    final reader = WorkspaceReader(store);
    final first = <PageDigest>[
      for (final page in pages) (await reader.digest(page.id))!,
    ];

    // Read again, each is what it was.
    for (final (i, page) in pages.indexed) {
      expect(identical(await reader.digest(page.id), first[i]), isTrue);
    }

    // Changed, it is read again as it is now.
    final before = (await store.pages.loadDocument(pages.first.id))!;
    await store.pages.saveDocument(
      pages.first.id,
      before.withElementAdded(
        TextElement(
          id: 'more',
          frame: const Frame(x: 40, y: 140, width: 300, height: 60),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[TextBlock.plain('A fact changed.')],
        ),
      ),
    );
    final changed = (await reader.digest(pages.first.id))!;
    expect(identical(changed, first.first), isFalse);
    expect(
      changed.items
          .expand((item) => item.passages)
          .map((passage) => passage.text)
          .join(),
      contains('A fact changed.'),
    );

    // Gone, it is read as nothing.
    await store.pages.deletePage(pages.last.id);
    expect(await reader.digest(pages.last.id), isNull);
  });
}
