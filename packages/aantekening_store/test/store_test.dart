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

  group('on-disk workspace', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aantekening_disk_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('creates its files and survives being reopened', () async {
      final first = await AantekeningStore.open(directory.path);
      final notebook = await first.library.createNotebook(title: 'Persisted');
      final section = await first.library.createSection(
        notebookId: notebook.id,
        title: 'Section',
      );
      final page = await first.pages.createPage(sectionId: section.id);
      await first.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'written to disk'),
      );
      await first.close();

      expect(
        File(
          p.join(directory.path, AantekeningStore.databaseFileName),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          p.join(directory.path, AantekeningStore.assetsDirectoryName),
        ).existsSync(),
        isTrue,
      );

      final second = await AantekeningStore.open(directory.path);
      addTearDown(second.close);

      expect((await second.library.listNotebooks()).single.title, 'Persisted');
      expect(
        (await second.pages.loadDocument(page.id))!.extractSearchText(),
        contains('written to disk'),
      );
      expect((await second.search.search('disk')).single.pageId, page.id);
    });

    test('uses write-ahead logging for the persistent database', () async {
      final store = await AantekeningStore.open(directory.path);
      addTearDown(store.close);

      final mode = store.database
          .select('PRAGMA journal_mode')
          .first
          .values
          .first;

      // WAL is what lets a read proceed while an autosave is in flight.
      expect('$mode'.toLowerCase(), 'wal');
    });
  });

  group('schema', () {
    test('migrates a fresh database to the current version', () {
      expect(store.database.raw.userVersion, Schema.version);
    });

    test('refuses a database written by a newer build', () {
      store.database.raw.userVersion = Schema.version + 1;
      expect(() => Schema.migrate(store.database.raw), throwsStateError);
    });

    test('is idempotent on an already-current database', () {
      expect(() => Schema.migrate(store.database.raw), returnsNormally);
    });
  });

  group('notebooks and sections', () {
    test('creates notebooks in insertion order', () async {
      await store.library.createNotebook(title: 'First');
      await store.library.createNotebook(title: 'Second');

      final notebooks = await store.library.listNotebooks();

      expect(notebooks.map((n) => n.title), <String>['First', 'Second']);
      expect(notebooks[0].position, lessThan(notebooks[1].position));
    });

    test('nests sections to arbitrary depth', () async {
      final book = await store.library.createNotebook(title: 'Physics');
      final top = await store.library.createSection(
        notebookId: book.id,
        title: 'Mechanics',
      );
      final sub = await store.library.createSection(
        notebookId: book.id,
        title: 'Kinematics',
        parentId: top.id,
      );
      await store.library.createSection(
        notebookId: book.id,
        title: 'Projectiles',
        parentId: sub.id,
      );

      expect(
        (await store.library.listSections(book.id)).map((s) => s.title),
        <String>['Mechanics'],
      );
      expect(
        (await store.library.listSections(
          book.id,
          parentId: top.id,
        )).map((s) => s.title),
        <String>['Kinematics'],
      );
      expect((await store.library.listAllSections(book.id)).length, 3);
    });

    test('refuses to move a section inside its own subtree', () async {
      final book = await store.library.createNotebook(title: 'Physics');
      final parent = await store.library.createSection(
        notebookId: book.id,
        title: 'Mechanics',
      );
      final child = await store.library.createSection(
        notebookId: book.id,
        title: 'Kinematics',
        parentId: parent.id,
      );

      expect(
        () => store.library.moveSection(
          parent.id,
          notebookId: book.id,
          parentId: child.id,
        ),
        throwsArgumentError,
      );
      expect(
        () => store.library.moveSection(
          parent.id,
          notebookId: book.id,
          parentId: parent.id,
        ),
        throwsArgumentError,
      );
    });

    test('moving a section carries its subtree to the new notebook', () async {
      final from = await store.library.createNotebook(title: 'From');
      final to = await store.library.createNotebook(title: 'To');
      final parent = await store.library.createSection(
        notebookId: from.id,
        title: 'Parent',
      );
      final child = await store.library.createSection(
        notebookId: from.id,
        title: 'Child',
        parentId: parent.id,
      );

      await store.library.moveSection(parent.id, notebookId: to.id);

      expect((await store.library.findSection(child.id))!.notebookId, to.id);
      expect((await store.library.listAllSections(from.id)), isEmpty);
    });

    test('renames notebooks and sections', () async {
      final book = await store.library.createNotebook(title: 'Draft');
      final section = await store.library.createSection(
        notebookId: book.id,
        title: 'Untitled',
      );

      await store.library.renameNotebook(book.id, 'Physics');
      await store.library.renameSection(section.id, 'Optics');

      expect((await store.library.findNotebook(book.id))!.title, 'Physics');
      expect((await store.library.findSection(section.id))!.title, 'Optics');
    });

    test(
      'deleting a section takes its subsections and pages with it',
      () async {
        final book = await store.library.createNotebook(title: 'Maths');
        final parent = await store.library.createSection(
          notebookId: book.id,
          title: 'Analysis',
        );
        final child = await store.library.createSection(
          notebookId: book.id,
          title: 'Series',
          parentId: parent.id,
        );
        final page = await store.pages.createPage(sectionId: child.id);
        await store.pages.saveDocument(
          page.id,
          documentWithText(page.id, 'ratio test'),
        );

        final deleted = await store.library.deleteSection(parent.id);

        expect(deleted, unorderedEquals(<String>[parent.id, child.id]));
        expect(await store.library.listAllSections(book.id), isEmpty);
        expect(await store.search.search('ratio'), isEmpty);
        expect(await store.pages.listAllPages(), isEmpty);

        await store.library.restoreSection(parent.id);
        expect(await store.library.listAllSections(book.id), hasLength(2));
        expect(await store.search.search('ratio'), hasLength(1));
      },
    );

    test('restoring a section leaves what was deleted before it', () async {
      final book = await store.library.createNotebook(title: 'Maths');
      final parent = await store.library.createSection(
        notebookId: book.id,
        title: 'Analysis',
      );
      final gone = await store.library.createSection(
        notebookId: book.id,
        title: 'Old',
        parentId: parent.id,
      );
      await store.library.deleteSection(gone.id);
      // Deletions are told apart by when they were made.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.library.deleteSection(parent.id);

      await store.library.restoreSection(parent.id);

      expect(
        (await store.library.listAllSections(book.id)).map((s) => s.title),
        <String>['Analysis'],
      );
    });

    test('copies a section with its subsections and pages', () async {
      final book = await store.library.createNotebook(title: 'Maths');
      final other = await store.library.createNotebook(title: 'Archive');
      final parent = await store.library.createSection(
        notebookId: book.id,
        title: 'Analysis',
      );
      final child = await store.library.createSection(
        notebookId: book.id,
        title: 'Series',
        parentId: parent.id,
      );
      final page = await store.pages.createPage(
        sectionId: child.id,
        title: 'Tests',
      );
      await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'ratio test'),
      );

      final copy = await store.library.copySection(
        parent.id,
        notebookId: other.id,
      );

      final copied = await store.library.listAllSections(other.id);
      expect(copied.map((s) => s.title), <String>['Analysis', 'Series']);
      expect(copied.last.parentId, copy.id);
      final pages = await store.pages.listPages(copied.last.id);
      expect(pages.single.title, 'Tests');
      expect(pages.single.id, isNot(page.id));
      expect(
        (await store.pages.loadDocument(pages.single.id))!.id,
        pages.single.id,
      );
      expect(await store.search.search('ratio'), hasLength(2));
      // The original is untouched.
      expect(await store.library.listAllSections(book.id), hasLength(2));
    });

    test('refuses to copy a section into itself', () async {
      final book = await store.library.createNotebook(title: 'Maths');
      final parent = await store.library.createSection(
        notebookId: book.id,
        title: 'Analysis',
      );

      expect(
        () => store.library.copySection(
          parent.id,
          notebookId: book.id,
          parentId: parent.id,
        ),
        throwsArgumentError,
      );
    });

    test('soft deletion hides a notebook but keeps it recoverable', () async {
      final book = await store.library.createNotebook(title: 'Temp');

      await store.library.deleteNotebook(book.id);
      expect(await store.library.listNotebooks(), isEmpty);
      expect((await store.library.findNotebook(book.id))!.isDeleted, isTrue);

      await store.library.restoreNotebook(book.id);
      expect((await store.library.listNotebooks()).length, 1);
    });
  });

  group('pages', () {
    test('round-trips a document through the database', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);

      final document = documentWithText(page.id, 'The chain rule');
      await store.pages.saveDocument(page.id, document);

      final loaded = await store.pages.loadDocument(page.id);
      expect(loaded, isNotNull);
      expect(loaded!.extractSearchText(), contains('The chain rule'));
      expect(loaded.revision, document.revision);
    });

    test('compresses large bodies and reads them back identically', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);

      final long = List<String>.generate(
        400,
        (i) => 'line $i of the proof',
      ).join('\n');
      await store.pages.saveDocument(page.id, documentWithText(page.id, long));

      final encoding = store.database.select(
        'SELECT encoding FROM page_bodies WHERE page_id = ?',
        <Object?>[page.id],
      ).first['encoding'];
      expect(encoding, BodyEncoding.gzippedJson);

      final loaded = await store.pages.loadDocument(page.id);
      expect(loaded!.extractSearchText(), contains('line 399 of the proof'));
    });

    test('stores small bodies uncompressed', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      await store.pages.saveDocument(page.id, documentWithText(page.id, 'hi'));

      final encoding = store.database.select(
        'SELECT encoding FROM page_bodies WHERE page_id = ?',
        <Object?>[page.id],
      ).first['encoding'];
      expect(encoding, BodyEncoding.json);
    });

    test('never takes a title from the text', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);

      final saved = await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'Taylor series\nremainder term'),
      );

      expect(saved.title, isEmpty);
      expect(saved.preview, contains('remainder term'));
    });

    test('keeps a title the user set', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: 'My title',
      );

      final saved = await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'something else entirely'),
      );

      expect(saved.title, 'My title');
    });

    test('rejects saving to a page that does not exist', () async {
      expect(
        () => store.pages.saveDocument('nope', documentWithText('nope', 'x')),
        throwsStateError,
      );
    });

    test('supports subpages under a parent page', () async {
      final sectionId = await workspace.seedSection();
      final parent = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Lecture 1',
      );
      await store.pages.createPage(
        sectionId: sectionId,
        title: 'Exercises',
        parentId: parent.id,
      );

      expect(
        (await store.pages.listPages(
          sectionId,
          topLevelOnly: true,
        )).map((p) => p.title),
        <String>['Lecture 1'],
      );
      expect(
        (await store.pages.listPages(
          sectionId,
          parentId: parent.id,
        )).map((p) => p.title),
        <String>['Exercises'],
      );
    });

    test('refuses to make a page its own subpage', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      final subpage = await store.pages.createPage(
        sectionId: sectionId,
        parentId: page.id,
      );

      for (final parentId in <String>[page.id, subpage.id]) {
        expect(
          () => store.pages.movePage(
            page.id,
            sectionId: sectionId,
            parentId: parentId,
          ),
          throwsArgumentError,
        );
      }
    });

    test('moves a page with its subpages to another section', () async {
      final from = await workspace.seedSection();
      final to = await workspace.seedSection(notebook: 'Other');
      final page = await store.pages.createPage(sectionId: from);
      final subpage = await store.pages.createPage(
        sectionId: from,
        parentId: page.id,
      );

      await store.pages.movePage(page.id, sectionId: to);

      expect(await store.pages.listPages(from), isEmpty);
      expect((await store.pages.findPage(subpage.id))!.sectionId, to);
      expect((await store.pages.findPage(subpage.id))!.parentId, page.id);
    });

    test('places a page after another, before the one that followed', () async {
      final sectionId = await workspace.seedSection();
      final first = await store.pages.createPage(
        sectionId: sectionId,
        title: 'First',
      );
      await store.pages.createPage(sectionId: sectionId, title: 'Second');
      final moved = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Moved',
      );

      await store.pages.movePage(
        moved.id,
        sectionId: sectionId,
        after: first.id,
      );

      expect(
        (await store.pages.listPages(sectionId)).map((p) => p.title),
        <String>['First', 'Moved', 'Second'],
      );
    });

    test('copies a page with its subpages under a new identity', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Lecture',
      );
      await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'Green theorem'),
      );
      await store.pages.createPage(
        sectionId: sectionId,
        title: 'Exercises',
        parentId: page.id,
      );

      final copy = await store.pages.copyPage(
        page.id,
        sectionId: sectionId,
        after: page.id,
      );

      final topLevel = await store.pages.listPages(
        sectionId,
        topLevelOnly: true,
      );
      expect(topLevel.map((p) => p.id), <String>[page.id, copy.id]);
      expect(copy.title, 'Lecture');
      expect(copy.createdAt, page.createdAt);
      expect(
        (await store.pages.listPages(
          sectionId,
          parentId: copy.id,
        )).single.title,
        'Exercises',
      );
      final document = await store.pages.loadDocument(copy.id);
      expect(document!.id, copy.id);
      expect(document.extractSearchText(), 'Green theorem');
      expect(await store.search.search('green'), hasLength(2));
    });

    test('copies a page beneath one of its own subpages', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      final subpage = await store.pages.createPage(
        sectionId: sectionId,
        parentId: page.id,
      );

      final copy = await store.pages.copyPage(
        page.id,
        sectionId: sectionId,
        parentId: page.id,
        after: subpage.id,
      );

      expect(copy.parentId, page.id);
      // The page, its subpage, the copy and the copy of the subpage.
      expect(await store.pages.listPages(sectionId), hasLength(4));
    });

    test('deleting a page takes its subpages with it', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      final subpage = await store.pages.createPage(
        sectionId: sectionId,
        parentId: page.id,
      );

      final deleted = await store.pages.deletePage(page.id);

      expect(deleted, <String>[page.id, subpage.id]);
      expect(await store.pages.listPages(sectionId), isEmpty);

      await store.pages.restorePage(page.id);
      expect(await store.pages.listPages(sectionId), hasLength(2));
    });

    test('changes the date shown under the title', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      final date = DateTime(2026, 3, 14, 9, 26).millisecondsSinceEpoch;

      await store.pages.setPageDate(page.id, date);

      expect((await store.pages.findPage(page.id))!.createdAt, date);
    });

    test('lists every live page in the workspace', () async {
      final sectionId = await workspace.seedSection();
      final kept = await store.pages.createPage(sectionId: sectionId);
      final gone = await store.pages.createPage(sectionId: sectionId);
      final hidden = await store.pages.createPage(
        sectionId: await workspace.seedSection(notebook: 'Deleted'),
      );
      await store.pages.deletePage(gone.id);
      final section = await store.library.findSection(hidden.sectionId);
      await store.library.deleteNotebook(section!.notebookId);

      expect((await store.pages.listAllPages()).map((p) => p.id), <String>[
        kept.id,
      ]);
    });

    test('lists recently edited pages first', () async {
      final sectionId = await workspace.seedSection();
      final older = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Older',
      );
      final newer = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Newer',
      );

      await store.pages.saveDocument(older.id, documentWithText(older.id, 'a'));
      await store.pages.saveDocument(newer.id, documentWithText(newer.id, 'b'));

      final recent = await store.pages.recentPages(limit: 2);
      expect(recent.first.id, newer.id);
    });
  });

  group('search', () {
    late String sectionId;

    setUp(() async {
      sectionId = await workspace.seedSection();
    });

    Future<PageRef> addPage(String title, String body) async {
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: title,
      );
      return store.pages.saveDocument(page.id, documentWithText(page.id, body));
    }

    test('finds pages by a word in the body', () async {
      await addPage('Lecture 3', 'the residue theorem and contour integration');
      await addPage('Lecture 4', 'uniform convergence');

      final hits = await store.search.search('residue');

      expect(hits.map((h) => h.title), <String>['Lecture 3']);
      expect(hits.single.snippet, contains('residue'));
    });

    test('matches a prefix so results appear while typing', () async {
      await addPage('Lecture 3', 'the residue theorem');

      expect((await store.search.search('resi')).length, 1);
      expect(
        (await store.search.search('resi', prefixLastTerm: false)),
        isEmpty,
      );
    });

    test('ranks a title match above a passing mention', () async {
      await addPage('Fourier transform', 'a short note');
      await addPage('Lecture 9', 'we mention the fourier transform once here');

      final hits = await store.search.search('fourier');

      expect(hits.first.title, 'Fourier transform');
      expect(hits.first.score, greaterThan(hits.last.score));
    });

    test('requires every term to match', () async {
      await addPage('A', 'alpha beta');
      await addPage('B', 'alpha gamma');

      final hits = await store.search.search('alpha gamma');

      expect(hits.map((h) => h.title), <String>['B']);
    });

    test('reflects edits immediately', () async {
      final page = await addPage('Notes', 'original wording');
      expect(await store.search.search('original'), isNotEmpty);

      await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'replaced wording'),
      );

      expect(await store.search.search('original'), isEmpty);
      expect(await store.search.search('replaced'), isNotEmpty);
    });

    test('excludes deleted pages and restores them on undelete', () async {
      final page = await addPage('Notes', 'ephemeral content');

      await store.pages.deletePage(page.id);
      expect(await store.search.search('ephemeral'), isEmpty);

      await store.pages.restorePage(page.id);
      expect(await store.search.search('ephemeral'), isNotEmpty);
    });

    test('excludes pages whose notebook is deleted', () async {
      final page = await addPage('Notes', 'hidden by its notebook');
      final section = await store.library.findSection(page.sectionId);
      await store.library.deleteNotebook(section!.notebookId);

      expect(await store.search.search('hidden'), isEmpty);
    });

    test('filters by notebook', () async {
      await addPage('In scope', 'shared term');
      final other = await store.library.createNotebook(title: 'Other');
      final otherSection = await store.library.createSection(
        notebookId: other.id,
        title: 'Elsewhere',
      );
      final page = await store.pages.createPage(sectionId: otherSection.id);
      await store.pages.saveDocument(
        page.id,
        documentWithText(page.id, 'shared term'),
      );

      expect((await store.search.search('shared')).length, 2);

      final section = await store.library.findSection(sectionId);
      final scoped = await store.search.search(
        'shared',
        notebookId: section!.notebookId,
      );
      expect(scoped.map((h) => h.title), <String>['In scope']);
    });

    test('finds a page renamed after it was written', () async {
      final page = await addPage('Old name', 'body text');

      await store.pages.renamePage(page.id, 'Bessel functions');

      expect((await store.search.search('bessel')).single.pageId, page.id);
      expect(
        await store.search.search('body'),
        isNotEmpty,
        reason: 'renaming must not drop the indexed body',
      );
    });

    test('indexes maths source so formulas are findable', () async {
      final page = await store.pages.createPage(
        sectionId: sectionId,
        title: 'Formula',
      );
      final document = PageDocument.empty(id: page.id).withElementAdded(
        MathElement(
          id: Ulid.generate(),
          frame: const Frame(x: 0, y: 0, width: 100, height: 40),
          createdAt: 0,
          updatedAt: 0,
          source: r'\int_0^\infty e^{-x^2} dx',
          mode: MathMode.latex,
        ),
      );
      await store.pages.saveDocument(page.id, document);

      expect(await store.search.search('infty'), isNotEmpty);
    });

    test('returns nothing for an empty query', () async {
      await addPage('Notes', 'content');
      expect(await store.search.search('  '), isEmpty);
      expect(await store.search.count('  '), 0);
    });

    test('rebuilding the index reproduces the same results', () async {
      await addPage('Notes', 'reindexed content');
      store.database.run('DELETE FROM page_search');
      expect(await store.search.search('reindexed'), isEmpty);

      final rebuilt = await store.pages.rebuildSearchIndex();

      expect(rebuilt, 1);
      expect(await store.search.search('reindexed'), isNotEmpty);
    });
  });

  group('assets', () {
    test('deduplicates identical content', () async {
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

      final first = await store.assets.importBytes(
        bytes,
        mimeType: 'image/png',
      );
      final second = await store.assets.importBytes(
        bytes,
        mimeType: 'image/png',
      );

      expect(second.id, first.id);
      expect(await store.assets.totalBytes(), 64);
    });

    test('reads back what was imported', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final asset = await store.assets.importBytes(
        bytes,
        mimeType: 'application/pdf',
        originalName: 'lecture.pdf',
      );

      expect(await store.assets.readBytes(asset.id), bytes);
      expect((await store.assets.find(asset.id))!.originalName, 'lecture.pdf');
    });

    test('collects assets no live page references', () async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      final asset = await store.assets.importBytes(
        Uint8List.fromList(<int>[9, 9, 9]),
        mimeType: 'image/png',
      );

      final document = PageDocument.empty(id: page.id).withElementAdded(
        ImageElement(
          id: Ulid.generate(),
          frame: const Frame(x: 0, y: 0, width: 100, height: 100),
          createdAt: 0,
          updatedAt: 0,
          assetId: asset.id,
        ),
      );
      await store.pages.saveDocument(page.id, document);

      expect(
        await store.assets.collectGarbage(),
        0,
        reason: 'the asset is still referenced',
      );

      await store.pages.purgePage(page.id);

      expect(await store.assets.collectGarbage(), 1);
      expect(await store.assets.find(asset.id), isNull);
    });

    test('guesses media types from the file extension', () {
      expect(AssetStore.mimeTypeForPath('/tmp/a.PDF'), 'application/pdf');
      expect(AssetStore.mimeTypeForPath('/tmp/a.jpeg'), 'image/jpeg');
      expect(
        AssetStore.mimeTypeForPath('/tmp/a.xyz'),
        'application/octet-stream',
      );
    });
  });

  group('embeddings', () {
    Future<String> seedPage() async {
      final sectionId = await workspace.seedSection();
      final page = await store.pages.createPage(sectionId: sectionId);
      return page.id;
    }

    test('ranks chunks by cosine similarity', () async {
      final pageId = await seedPage();
      await store.embeddings.replacePageChunks(
        pageId,
        'test-model',
        <EmbeddedChunk>[
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 0,
            text: 'aligned',
            vector: Float32List.fromList(<double>[1, 0, 0]),
          ),
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 1,
            text: 'orthogonal',
            vector: Float32List.fromList(<double>[0, 1, 0]),
          ),
        ],
      );

      final hits = await store.embeddings.nearest(
        Float32List.fromList(<double>[1, 0, 0]),
        model: 'test-model',
        minSimilarity: -1,
      );

      expect(hits.first.text, 'aligned');
      expect(hits.first.similarity, closeTo(1, 1e-6));
      expect(hits.last.similarity, closeTo(0, 1e-6));
    });

    test('drops matches below the similarity floor', () async {
      final pageId = await seedPage();
      await store.embeddings.replacePageChunks(
        pageId,
        'test-model',
        <EmbeddedChunk>[
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 0,
            text: 'orthogonal',
            vector: Float32List.fromList(<double>[0, 1, 0]),
          ),
        ],
      );

      final hits = await store.embeddings.nearest(
        Float32List.fromList(<double>[1, 0, 0]),
        model: 'test-model',
      );

      expect(hits, isEmpty);
    });

    test('ignores models and dimensions that do not match the query', () async {
      final pageId = await seedPage();
      await store.embeddings.replacePageChunks(
        pageId,
        'other-model',
        <EmbeddedChunk>[
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 0,
            text: 'wrong model',
            vector: Float32List.fromList(<double>[1, 0, 0]),
          ),
        ],
      );

      final hits = await store.embeddings.nearest(
        Float32List.fromList(<double>[1, 0, 0]),
        model: 'test-model',
        minSimilarity: -1,
      );

      expect(hits, isEmpty);
      expect(await store.embeddings.chunkCount(), 1);
    });

    test('replacing chunks removes the previous generation', () async {
      final pageId = await seedPage();
      Future<void> write(String text) => store.embeddings.replacePageChunks(
        pageId,
        'test-model',
        <EmbeddedChunk>[
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 0,
            text: text,
            vector: Float32List.fromList(<double>[1, 0, 0]),
          ),
        ],
      );

      await write('first');
      await write('second');

      expect(await store.embeddings.chunkCount(model: 'test-model'), 1);
      final hits = await store.embeddings.nearest(
        Float32List.fromList(<double>[1, 0, 0]),
        model: 'test-model',
        minSimilarity: -1,
      );
      expect(hits.single.text, 'second');
    });

    test('deleting a page cascades to its embeddings', () async {
      final pageId = await seedPage();
      await store.embeddings.replacePageChunks(
        pageId,
        'test-model',
        <EmbeddedChunk>[
          EmbeddedChunk(
            pageId: pageId,
            chunkIndex: 0,
            text: 'gone',
            vector: Float32List.fromList(<double>[1, 0, 0]),
          ),
        ],
      );

      await store.pages.purgePage(pageId);

      expect(await store.embeddings.chunkCount(), 0);
    });
  });
}
