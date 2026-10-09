import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Pictures and files are shared by every computer the notes folder is on,
/// and named by what is in them: none is lost because one computer has not
/// yet seen the page that shows it, and no name read from the folder leads
/// out of it.
void main() {
  late Directory root;
  late String notes;
  var now = DateTime(2026, 10);

  setUp(() {
    root = Directory.systemTemp.createTempSync('aantekening_assets_');
    notes = p.join(root.path, 'Notes');
    now = DateTime(2026, 10);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<AantekeningStore> open() => AantekeningStore.open(
    notesFolder: notes,
    indexFolder: p.join(root.path, 'index'),
    automatic: false,
  );

  AssetStore assetsOf(AantekeningStore store) =>
      AssetStore(store.database, store.assets.rootDirectory, clock: () => now);

  final picture = Uint8List.fromList(utf8.encode('a picture'));

  test(
    'a picture no page shows is set aside, and comes back when read',
    () async {
      final store = await open();
      addTearDown(store.close);
      final assets = assetsOf(store);
      final asset = await assets.importBytes(picture, mimeType: 'image/png');
      final file = assets.fileFor(asset);
      expect(file.existsSync(), isTrue);

      expect(await assets.collectGarbage(), 1);
      expect(file.existsSync(), isFalse, reason: 'set aside');

      // A page another computer added shows it still.
      expect(assets.fileForHash(asset.sha256).readAsBytesSync(), picture);
    },
  );

  test('what is set aside goes for good only after a while, unshown', () async {
    final store = await open();
    addTearDown(store.close);
    final assets = assetsOf(store);
    final asset = await assets.importBytes(picture, mimeType: 'image/png');
    await assets.collectGarbage();
    final aside = File(
      p.join(assets.rootDirectory.path, '.removed', asset.sha256),
    );
    expect(aside.existsSync(), isTrue);

    now = now.add(const Duration(days: 29));
    await assets.collectGarbage();
    expect(aside.existsSync(), isTrue, reason: 'not yet');

    now = now.add(const Duration(days: 2));
    await assets.collectGarbage();
    expect(aside.existsSync(), isFalse);
  });

  test('a name that is not a SHA-256 leads nowhere', () async {
    final store = await open();
    addTearDown(store.close);
    final outside = File(p.join(root.path, 'secret.txt'))
      ..writeAsStringSync('not the notes');
    expect(
      () => store.assets.fileForHash('../../secret.txt'),
      throwsArgumentError,
    );

    // A page in the folder naming a file out of it.
    final sectionId = (await store.library.createSection(
      notebookId: (await store.library.createNotebook(title: 'N')).id,
      title: 'S',
    )).id;
    store.pages.putPage(
      PageFile(
        page: PageRef(
          id: Ulid.generate(),
          sectionId: sectionId,
          title: 'Crafted',
          position: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
        document: PageDocument.empty(),
        assets: <AssetRef>[
          const AssetRef(
            id: 'evil',
            sha256: '../../../secret.txt',
            mimeType: 'text/plain',
            byteSize: 13,
            createdAt: 0,
          ),
        ],
      ),
    );
    expect(await store.assets.find('evil'), isNull);
    await store.assets.collectGarbage();
    expect(outside.existsSync(), isTrue);
  });

  test('a backup is restored inside the folder it is restored to', () async {
    final store = await open();
    await seedPage(store);
    await store.close();
    final backup = Backups.create(notes, p.join(root.path, 'Backups'));

    // The backup, with a file named to land outside.
    final input = InputFileStream(backup);
    final archive = ZipDecoder().decodeStream(input);
    archive.addFile(ArchiveFile.string('../escaped.txt', 'out'));
    final crafted = p.join(root.path, 'crafted.zip');
    final encoded = ZipEncoder().encodeBytes(archive);
    input.closeSync();
    File(crafted).writeAsBytesSync(encoded);

    final restored = p.join(root.path, 'Restored', 'Notes');
    await Backups.restore(crafted, restored);
    expect(
      File(p.join(root.path, 'Restored', 'escaped.txt')).existsSync(),
      isFalse,
    );
    expect(NotesFolder(restored).readIdentity(), isNotNull);
  });
}

Future<void> seedPage(AantekeningStore store) async {
  final notebook = await store.library.createNotebook(title: 'Physics');
  final section = await store.library.createSection(
    notebookId: notebook.id,
    title: 'Mechanics',
  );
  final page = await store.pages.createPage(sectionId: section.id);
  await store.pages.saveDocument(page.id, documentWithText(page.id, 'F = ma'));
  await store.mirror!.flush();
}
