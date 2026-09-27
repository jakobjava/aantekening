import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestWorkspace workspace;
  late AantekeningStore store;

  setUp(() {
    workspace = TestWorkspace.create();
    store = workspace.store;
  });

  tearDown(() => workspace.dispose());

  group('the bin', () {
    test('holds what was deleted, each by itself, newest first', () async {
      final sectionId = await workspace.seedSection();
      final kept = await store.pages.createPage(sectionId: sectionId);
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Gone',
      );
      await store.pages.createPage(
        sectionId: sectionId,
        parentId: page.id,
        title: 'Went with it',
      );
      await store.pages.deletePage(page.id);
      final notebook = await store.library.createNotebook(title: 'Old');

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.library.deleteNotebook(notebook.id);

      final bin = await store.bin.list();
      expect(bin.map((entry) => entry.title), <String>['Old', 'Gone']);
      final gone = bin.last;
      expect(gone.kind, BinKind.page);
      expect(gone.pages, 2, reason: 'its subpage went with it');
      expect(gone.place, <String>['Maths', 'Analysis']);
      expect(bin.map((entry) => entry.id), isNot(contains(kept.id)));
    });

    test('restores a page, with the section it was in when that has gone '
        'since', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Back',
      );
      await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'restored words'),
      );
      await store.pages.deletePage(page.id);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.library.deleteSection(sectionId);

      final entry = (await store.bin.list()).firstWhere(
        (entry) => entry.kind == BinKind.page,
      );
      await store.bin.restore(entry);

      expect((await store.library.findSection(sectionId))!.isDeleted, isFalse);
      expect((await store.pages.findPage(page.id))!.isDeleted, isFalse);
      expect((await store.search.search('restored')).single.pageId, page.id);
    });

    test(
      'deletes for good what it holds, and the pictures only it showed',
      () async {
        final sectionId = await workspace.seedSection();
        final page = await store.pages.createPage(sectionId: sectionId);
        final picture = await store.assets.importBytes(
          Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: 'image/png',
        );
        await store.pages.saveDocument(
          page.id,
          PageDocument.empty(id: page.id).withElementAdded(
            ImageElement(
              id: Ulid.generate(),
              frame: const Frame(x: 0, y: 0, width: 10, height: 10),
              createdAt: 1,
              updatedAt: 1,
              assetId: picture.id,
            ),
          ),
        );
        await store.pages.deletePage(page.id);
        expect(
          await store.assets.collectGarbage(),
          0,
          reason: 'a page in the bin may yet come back',
        );

        expect(await store.bin.empty(), 1);
        expect(await store.bin.list(), isEmpty);
        expect(await store.pages.findPage(page.id), isNull);
        expect(await store.assets.collectGarbage(), 1);
      },
    );

    test('takes the conversations about what goes with it', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      await store.ai.createThread(NoteLink.page(page.id), title: 'About it');
      await store.pages.deletePage(page.id);
      await store.bin.empty();
      expect(await store.ai.threadsAbout(NoteLink.page(page.id)), isEmpty);
    });
  });

  group('storing drafts', () {
    test(
      'stores a notebook whole, with subpages, pictures and dates',
      () async {
        final assets = Directory.systemTemp.createTempSync('drafts_');
        addTearDown(() => assets.deleteSync(recursive: true));
        final picture = File(p.join(assets.path, 'picture'))
          ..writeAsBytesSync(<int>[9, 9, 9]);
        final document = PageDocument.empty().withElementAdded(
          ImageElement(
            id: Ulid.generate(),
            frame: const Frame(x: 0, y: 0, width: 10, height: 10),
            createdAt: 1,
            updatedAt: 1,
            assetId: 'picture-1',
          ),
        );
        final stored = await store.drafts.store(
          NotesDraft(
            notebooks: <NotebookDraft>[
              NotebookDraft(
                title: 'Imported',
                sections: <SectionDraft>[
                  SectionDraft(
                    title: 'Group',
                    sections: <SectionDraft>[
                      SectionDraft(
                        title: 'Section',
                        pages: <PageDraft>[
                          PageDraft(
                            title: 'Top',
                            createdAt: DateTime.utc(
                              2025,
                              9,
                              17,
                              12,
                            ).millisecondsSinceEpoch,
                            document: document,
                            subpages: <PageDraft>[
                              PageDraft(
                                title: 'Beneath',
                                createdAt: 2,
                                document: PageDocument.empty(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
            assets: <String, AssetDraft>{
              'picture-1': AssetDraft(
                path: picture.path,
                mimeType: 'image/png',
              ),
            },
          ),
        );

        final first = stored.firstPage!;
        final top = (await store.pages.findPage(first.pageId))!;
        expect(top.title, 'Top');
        expect(
          top.createdAt,
          DateTime.utc(2025, 9, 17, 12).millisecondsSinceEpoch,
        );
        final beneath = (await store.pages.listPages(
          first.sectionId,
        )).firstWhere((page) => page.parentId == top.id);
        expect(beneath.title, 'Beneath');
        final shown =
            (await store.pages.loadDocument(top.id))!.elements.single
                as ImageElement;
        expect(await store.assets.readBytes(shown.assetId), <int>[9, 9, 9]);
        final sections = await store.library.listAllSections(first.notebookId);
        expect(sections.map((section) => section.title), <String>[
          'Group',
          'Section',
        ]);
      },
    );

    test('keeps a page\'s own identity unless it is taken', () async {
      final sectionId = await workspace.seedSection();
      final existing = await store.pages.createPage(sectionId: sectionId);
      final fresh = Ulid.generate();
      await store.drafts.store(
        NotesDraft(
          pages: <PageDraft>[
            PageDraft(
              title: 'Kept id',
              createdAt: 1,
              document: PageDocument.empty(),
              id: fresh,
            ),
            PageDraft(
              title: 'Taken id',
              createdAt: 1,
              document: PageDocument.empty(),
              id: existing.id,
            ),
          ],
        ),
        sectionId: sectionId,
      );
      final pages = await store.pages.listPages(sectionId);
      expect(pages.map((page) => page.id), contains(fresh));
      expect(pages, hasLength(3));
    });
  });
}
