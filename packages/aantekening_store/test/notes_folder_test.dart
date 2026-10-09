import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The notes folder: every change written to it as a file, every change
/// another copy of the notes made to it read back, and nothing lost either
/// way.
void main() {
  late Directory root;
  late String notes;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aantekening_folder_');
    notes = p.join(root.path, 'Notes');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The notes as one computer has them: its own index, the shared folder.
  Future<AantekeningStore> computer(String name) => AantekeningStore.open(
    notesFolder: notes,
    indexFolder: p.join(root.path, 'index-$name'),
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
    await store.pages.saveDocument(
      page.id,
      documentWithText(page.id, 'F = ma'),
    );
    return (section.id, page.id);
  }

  Future<String> textOf(AantekeningStore store, String pageId) async =>
      (await store.pages.loadDocument(pageId))!.extractSearchText();

  test('writes each notebook, section and page as a file of its own', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (sectionId, pageId) = await seed(store);
    await store.mirror!.flush();

    final page = File(p.join(notes, 'pages', '$pageId.json.gz'));
    final file = EntityFile.decode(page.readAsBytesSync())! as PageFile;
    expect(file.page.title, 'Forces');
    expect(file.document.extractSearchText(), 'F = ma');
    expect(
      File(p.join(notes, 'sections', '$sectionId.json')).existsSync(),
      isTrue,
    );
    expect(store.mirror!.status.pending, 0);
    // Nothing is left of the writes but the files.
    expect(
      Directory(
        notes,
      ).listSync(recursive: true).where((file) => file.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('writes a page of handwriting as it is kept', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (_, pageId) = await seed(store);
    final ink =
        InkElement(
          id: 'ink',
          frame: const Frame(x: 0, y: 0, width: 800, height: 800),
          createdAt: 1,
          updatedAt: 1,
        ).withStrokes(<InkStroke>[
          InkStroke(
            tool: InkTool.pen,
            color: 0xFF000000,
            width: 2,
            points: Float32List.fromList(<double>[
              for (var i = 0; i < 60000; i++) i * 0.37 % 800,
            ]),
          ),
        ]);
    final document = documentWithText(pageId, 'Heavy').withElementAdded(ink);
    await store.pages.saveDocument(pageId, document);
    await store.mirror!.flush();

    final file =
        EntityFile.decode(
              File(p.join(notes, 'pages', '$pageId.json.gz')).readAsBytesSync(),
            )!
            as PageFile;
    expect(file.document.encode(), document.encode());
    expect(file.page.title, 'Forces');
  });

  test('writes by itself what changes, after a quiet spell too', () async {
    final store = await AantekeningStore.open(
      notesFolder: notes,
      indexFolder: p.join(root.path, 'index-a'),
    );
    addTearDown(store.close);
    final (_, pageId) = await seed(store);
    final page = File(p.join(notes, 'pages', '$pageId.json.gz'));
    // On Windows a file being moved over cannot be opened for a moment:
    // nothing to be read yet.
    String? written() {
      try {
        return (EntityFile.decode(page.readAsBytesSync())! as PageFile).document
            .extractSearchText();
      } on FileSystemException {
        return null;
      }
    }

    Future<void> until(bool Function() done) async {
      for (var waited = 0; !done(); waited++) {
        if (waited > 100) fail('Not written');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    await until(() => page.existsSync() && store.mirror!.status.pending == 0);
    expect(written(), 'F = ma');
    // Nothing waits now, so nothing is being checked; a change wakes it.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await store.pages.saveDocument(pageId, documentWithText(pageId, 'p = mv'));
    await until(() => written() == 'p = mv');
  });

  test('sees at once what another computer writes to the folder', () async {
    final watching = await AantekeningStore.open(
      notesFolder: notes,
      indexFolder: p.join(root.path, 'index-a'),
    );
    addTearDown(watching.close);
    final (_, pageId) = await seed(watching);
    await watching.mirror!.flush();
    final other = await computer('b');
    addTearDown(other.close);

    final arrived = watching.mirror!.changes.first;
    await other.pages.saveDocument(pageId, documentWithText(pageId, 'p = mv'));
    await other.mirror!.flush();

    // Read as the file is moved into place, long before the folder is next
    // looked at by the minute.
    expect(
      (await arrived.timeout(const Duration(seconds: 10))).pages,
      contains(pageId),
    );
    expect(await textOf(watching, pageId), 'p = mv');
  });

  test('another computer sharing the folder sees the notes, and its '
      'changes come back', () async {
    final first = await computer('a');
    addTearDown(first.close);
    final (_, pageId) = await seed(first);
    await first.mirror!.flush();

    final second = await computer('b');
    addTearDown(second.close);
    expect(await textOf(second, pageId), 'F = ma');
    expect((await second.library.listNotebooks()).single.title, 'Physics');

    await second.pages.saveDocument(
      pageId,
      documentWithText(pageId, 'F = dp/dt'),
    );
    await second.pages.renamePage(pageId, "Newton's second law");
    await second.mirror!.flush();

    final changes = await first.mirror!.scan();
    expect(changes.pages, contains(pageId));
    expect(await textOf(first, pageId), 'F = dp/dt');
    expect((await first.pages.findPage(pageId))!.title, "Newton's second law");
    expect((await first.search.search('dp')).single.pageId, pageId);
  });

  test('a page changed on two computers at once keeps both versions', () async {
    final first = await computer('a');
    addTearDown(first.close);
    final (sectionId, pageId) = await seed(first);
    await first.mirror!.flush();
    final second = await computer('b');
    addTearDown(second.close);

    await first.pages.saveDocument(pageId, documentWithText(pageId, 'mine'));
    await second.pages.saveDocument(pageId, documentWithText(pageId, 'theirs'));
    await first.mirror!.flush();
    // The second writes over a file it did not write: it keeps the first
    // one's version as a page of its own before it does.
    await second.mirror!.flush();

    final pages = await second.pages.listPages(sectionId);
    expect(pages, hasLength(2));
    final other = pages.firstWhere((page) => page.id != pageId);
    expect(other.title, contains('other version'));
    expect(await textOf(second, other.id), 'mine');
    expect(await textOf(second, pageId), 'theirs');

    await second.mirror!.flush();
    await first.mirror!.scan();
    expect(await first.pages.listPages(sectionId), hasLength(2));
    expect(await textOf(first, pageId), 'theirs');
  });

  test("a sync service's conflicting copy becomes a page of its own", () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (sectionId, pageId) = await seed(store);
    await store.mirror!.flush();

    final file = store.pages.pageFile(pageId)!;
    final copy = PageFile(
      page: file.page,
      document: documentWithText(pageId, 'written on the laptop'),
    );
    File(
      p.join(notes, 'pages', '$pageId-LAPTOP.json.gz'),
    ).writeAsBytesSync(copy.encode());

    await store.mirror!.scan();
    final pages = await store.pages.listPages(sectionId);
    expect(pages, hasLength(2));
    final kept = pages.firstWhere((page) => page.id != pageId);
    expect(await textOf(store, kept.id), 'written on the laptop');
    expect(await textOf(store, pageId), 'F = ma');
    expect(
      File(p.join(notes, 'pages', '$pageId-LAPTOP.json.gz')).existsSync(),
      isFalse,
    );
    await store.mirror!.flush();
    expect(
      File(p.join(notes, 'pages', '${kept.id}.json.gz')).existsSync(),
      isTrue,
    );
  });

  test('a file deleted from the folder is written again', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (_, pageId) = await seed(store);
    await store.mirror!.flush();
    final page = File(p.join(notes, 'pages', '$pageId.json.gz'))..deleteSync();

    await store.mirror!.scan();
    expect(await textOf(store, pageId), 'F = ma', reason: 'not taken away');
    await store.mirror!.flush();
    expect(page.existsSync(), isTrue);
  });

  test('a damaged file is left alone, and the page kept', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (_, pageId) = await seed(store);
    await store.mirror!.flush();
    final page = File(p.join(notes, 'pages', '$pageId.json.gz'))
      ..writeAsStringSync('half a page');

    final changes = await store.mirror!.scan();
    expect(changes.damaged, <String>[page.path]);
    expect(await textOf(store, pageId), 'F = ma');
  });

  test(
    'a change the app stopped before writing is written next time',
    () async {
      final indexFolder = p.join(root.path, 'index-a');
      final store = await computer('a');
      final (_, pageId) = await seed(store);
      await store.mirror!.flush();
      await store.pages.saveDocument(
        pageId,
        documentWithText(pageId, 'unwritten'),
      );
      // Stopped without closing: nothing flushed.
      store.database.close();

      final again = await AantekeningStore.open(
        notesFolder: notes,
        indexFolder: indexFolder,
        automatic: false,
      );
      addTearDown(again.close);
      final file =
          EntityFile.decode(
                File(
                  p.join(notes, 'pages', '$pageId.json.gz'),
                ).readAsBytesSync(),
              )!
              as PageFile;
      expect(file.document.extractSearchText(), 'unwritten');
    },
  );

  test('deleting for good leaves a note every copy follows', () async {
    final first = await computer('a');
    addTearDown(first.close);
    final (sectionId, pageId) = await seed(first);
    await first.mirror!.flush();
    final second = await computer('b');
    addTearDown(second.close);

    await first.pages.deletePage(pageId);
    await first.bin.empty();
    await first.mirror!.flush();
    final tombstone = EntityFile.decode(
      File(p.join(notes, 'pages', '$pageId.json.gz')).readAsBytesSync(),
    );
    expect(tombstone, isA<Tombstone>());

    await second.mirror!.scan();
    expect(await second.pages.findPage(pageId), isNull);
    expect(await second.pages.listPages(sectionId), isEmpty);
  });

  test('a page changed elsewhere after it was deleted here is kept', () async {
    final first = await computer('a');
    addTearDown(first.close);
    final (sectionId, pageId) = await seed(first);
    await first.mirror!.flush();
    final second = await computer('b');
    addTearDown(second.close);

    // Changed on the second computer, and synced...
    await second.pages.saveDocument(
      pageId,
      documentWithText(pageId, 'written later'),
    );
    await second.mirror!.flush();
    // ...while the first, not yet seeing it, deletes the page for good.
    await first.pages.deletePage(pageId);
    await first.bin.empty();
    await first.mirror!.flush();

    final kept = (await first.pages.listPages(sectionId)).single;
    expect(kept.title, contains('other version'));
    expect(await textOf(first, kept.id), 'written later');
    await first.mirror!.flush();
    await second.mirror!.scan();
    expect(await textOf(second, kept.id), 'written later');
  });

  test(
    'a page kept when its section is gone goes in a notebook of its own',
    () async {
      final first = await computer('a');
      addTearDown(first.close);
      final (sectionId, pageId) = await seed(first);
      await first.mirror!.flush();
      final second = await computer('b');
      addTearDown(second.close);

      await second.pages.saveDocument(
        pageId,
        documentWithText(pageId, 'written later'),
      );
      await second.mirror!.flush();
      first.bin.purgeSection(sectionId);
      await first.mirror!.flush();

      final pages = await first.pages.listAllPages();
      final kept = pages.single;
      expect(
        (await first.library.findSection(kept.sectionId))!.title,
        'Rescued',
      );
      expect(await textOf(first, kept.id), 'written later');
    },
  );

  test('what cannot be written waits until it changes, never let go', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (_, pageId) = await seed(store);
    await store.mirror!.flush();
    // A page whose contents cannot be read from the index.
    store.database.run(
      'UPDATE page_bodies SET body = ? WHERE page_id = ?',
      <Object?>[
        Uint8List.fromList(<int>[1, 2, 3]),
        pageId,
      ],
    );

    await store.mirror!.flush();
    expect(store.mirror!.status.pending, 1, reason: 'still waiting');
    expect(store.mirror!.status.problem, contains(pageId));
    await store.mirror!.flush();
    expect(store.mirror!.status.pending, 1);

    await store.pages.saveDocument(pageId, documentWithText(pageId, 'fixed'));
    await store.mirror!.flush();
    expect(store.mirror!.status.pending, 0);
    expect(store.mirror!.status.problem, isNull);
    final file =
        EntityFile.decode(
              File(p.join(notes, 'pages', '$pageId.json.gz')).readAsBytesSync(),
            )!
            as PageFile;
    expect(file.document.extractSearchText(), 'fixed');
  });

  test('notes from before notes folders are put in the folder', () async {
    Directory(notes).createSync(recursive: true);
    final legacy = AantekeningDatabase.open(
      p.join(notes, AantekeningStore.legacyDatabaseName),
    );
    final pages = PageRepository(legacy);
    final library = LibraryRepository(legacy, pages);
    final notebook = await library.createNotebook(title: 'Old notes');
    final section = await library.createSection(
      notebookId: notebook.id,
      title: 'Kept',
    );
    final page = await pages.createPage(sectionId: section.id, title: 'Still');
    legacy.close();

    final store = await computer('a');
    addTearDown(store.close);
    expect((await store.library.listNotebooks()).single.title, 'Old notes');
    expect(
      File(p.join(notes, 'pages', '${page.id}.json.gz')).existsSync(),
      isTrue,
    );
    expect(NotesFolder(notes).readIdentity(), isNotNull);
    expect(
      File(p.join(notes, AantekeningStore.legacyDatabaseName)).existsSync(),
      isFalse,
    );
    expect(
      File(
        p.join(
          notes,
          '${AantekeningStore.legacyDatabaseName}.before-notes-folder',
        ),
      ).existsSync(),
      isTrue,
      reason: 'kept, renamed, to be safe',
    );
  });

  // Damaged past its header, the index opens and fails its check; damaged
  // in its header too, it cannot even be set up — and must still be let go
  // of, or Windows will not let it be moved aside.
  for (final (damage, from) in const <(String, int)>[
    ('within', 100),
    ('past opening', 0),
  ]) {
    test(
      'an index damaged $damage is set aside and filled again from the folder',
      () async {
        final indexFolder = p.join(root.path, 'index-a');
        final store = await computer('a');
        final (_, pageId) = await seed(store);
        await store.mirror!.flush();
        // Stopped without closing, and the index damaged meanwhile.
        store.database.close();
        final index = Directory(indexFolder)
            .listSync()
            .whereType<File>()
            .firstWhere((file) => file.path.endsWith('.sqlite'));
        final bytes = index.readAsBytesSync();
        for (var i = from; i < bytes.length; i += 97) {
          bytes[i] = 0x55;
        }
        index.writeAsBytesSync(bytes);

        final again = await AantekeningStore.open(
          notesFolder: notes,
          indexFolder: indexFolder,
          automatic: false,
        );
        addTearDown(again.close);
        expect(await textOf(again, pageId), 'F = ma');
        expect(
          Directory(
            indexFolder,
          ).listSync().any((file) => file.path.contains('.damaged-')),
          isTrue,
        );
      },
    );
  }

  test(
    'backups hold the whole folder, and restore as notes of their own',
    () async {
      final store = await computer('a');
      final (_, pageId) = await seed(store);
      await store.close();
      final backups = p.join(root.path, 'Backups');

      final first = Backups.create(notes, backups, at: DateTime(2026, 9));
      Backups.create(notes, backups, at: DateTime(2026, 9, 2));
      Backups.create(notes, backups, at: DateTime(2026, 9, 3));
      expect(File(first).existsSync(), isTrue);
      Backups.prune(backups, keep: 2);
      final kept = Backups.list(backups);
      expect(kept.map((file) => p.basename(file.path)), <String>[
        'aantekening backup 2026-09-03 00.00.00.zip',
        'aantekening backup 2026-09-02 00.00.00.zip',
      ]);

      final restored = p.join(root.path, 'Restored');
      await Backups.restore(kept.first.path, restored);
      expect(
        NotesFolder(restored).readIdentity(),
        isNot(NotesFolder(notes).readIdentity()),
      );
      final opened = await AantekeningStore.open(
        notesFolder: restored,
        indexFolder: p.join(root.path, 'index-r'),
        automatic: false,
      );
      addTearDown(opened.close);
      expect(await textOf(opened, pageId), 'F = ma');
    },
  );

  test(
    'triggers are paused while a file read from the folder goes in',
    () async {
      final store = await computer('a');
      addTearDown(store.close);
      await seed(store);
      await store.mirror!.flush();
      final second = await computer('b');
      addTearDown(second.close);
      expect(second.mirror!.status.pending, 0, reason: 'nothing to write back');
      final control = second.database.select(
        "SELECT value FROM mirror_control WHERE key = 'paused'",
      );
      expect(control.single['value'], 0);
    },
  );

  test('a notebook deleted for good takes its sections and pages with it '
      'from every copy', () async {
    final store = await computer('a');
    addTearDown(store.close);
    final (sectionId, pageId) = await seed(store);
    final notebook = (await store.library.listNotebooks()).single;
    await store.mirror!.flush();
    await store.library.deleteNotebook(notebook.id);
    await store.bin.empty();
    await store.mirror!.flush();
    for (final path in <String>[
      p.join(notes, 'notebooks', '${notebook.id}.json'),
      p.join(notes, 'sections', '$sectionId.json'),
      p.join(notes, 'pages', '$pageId.json.gz'),
    ]) {
      expect(EntityFile.decode(File(path).readAsBytesSync()), isA<Tombstone>());
    }
  });

  test('closing does not wait for a screen that stopped listening', () async {
    final store = await computer('a');
    // As the app pauses what a screen no longer shows is listening to.
    store.mirror!.statuses.listen((_) {}).pause();
    store.mirror!.changes.listen((_) {}).pause();
    await store.close().timeout(const Duration(seconds: 5));
  });

  test('an index opens in write-ahead mode and syncs every commit', () async {
    final store = await computer('a');
    addTearDown(store.close);
    Row pragma(String name) => store.database.select('PRAGMA $name').first;
    expect(pragma('journal_mode').values.first, 'wal');
    expect(pragma('synchronous').values.first, 2);
  });
}
