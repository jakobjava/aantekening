import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory folder;
  late AantekeningStore store;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('archive_');
    store = AantekeningStore.inMemory(
      assetDirectory: Directory(p.join(folder.path, 'assets'))..createSync(),
    );
  });

  tearDown(() async {
    await store.close();
    folder.deleteSync(recursive: true);
  });

  test('an export read back is what was exported, down to its pages\' '
      'identities', () async {
    final notebook = await store.library.createNotebook(title: 'Physics');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Optics',
    );
    final inner = await store.library.createSection(
      notebookId: notebook.id,
      parentId: section.id,
      title: 'Lenses',
    );
    final page = await store.pages.createPage(
      sectionId: inner.id,
      title: 'Convex',
    );
    await store.pages.createPage(
      sectionId: inner.id,
      parentId: page.id,
      title: 'Focal length',
    );
    final picture = await store.assets.importBytes(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      mimeType: 'image/png',
      originalName: 'ray.png',
    );
    await store.pages.saveDocument(
      page.id,
      PageDocument.empty(id: page.id).withElementAdded(
        ImageElement(
          id: Ulid.generate(),
          frame: const Frame(x: 1, y: 2, width: 3, height: 4),
          createdAt: 1,
          updatedAt: 1,
          assetId: picture.id,
        ),
      ),
    );
    final deleted = await store.pages.createPage(
      sectionId: inner.id,
      title: 'Gone',
    );
    await store.pages.deletePage(deleted.id);

    final path = p.join(folder.path, 'Physics.aantekening');
    await store.exports.write(path, notebooks: <String>[notebook.id]);

    final work = Directory(p.join(folder.path, 'work'))..createSync();
    final draft = const AantekeningImporter().read(<String>[
      path,
    ], ImportWork(work));
    final book = draft.notebooks.single;
    expect(book.title, 'Physics');
    final lenses = book.sections.single.sections.single;
    expect(lenses.title, 'Lenses');
    expect(lenses.pages.single.title, 'Convex', reason: 'the bin stays');
    expect(lenses.pages.single.id, page.id);
    expect(lenses.pages.single.subpages.single.title, 'Focal length');
    final shown = lenses.pages.single.document.elements.single as ImageElement;
    final asset = draft.assets[shown.assetId]!;
    expect(File(asset.path).readAsBytesSync(), <int>[1, 2, 3, 4]);
    expect(asset.name, 'ray.png');

    // Stored again elsewhere, it is the same.
    final other = AantekeningStore.inMemory(
      assetDirectory: Directory(p.join(folder.path, 'other'))..createSync(),
    );
    addTearDown(other.close);
    final stored = await other.drafts.store(draft);
    expect(stored.firstPage!.pageId, page.id);
    final back =
        (await other.pages.loadDocument(page.id))!.elements.single
            as ImageElement;
    expect(await other.assets.readBytes(back.assetId), <int>[1, 2, 3, 4]);
  });

  test('reads an export whose section and page are each their own '
      'parent, not within themselves for ever', () async {
    final notebook = await store.library.createNotebook(title: 'N');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Loop',
    );
    final page = await store.pages.createPage(
      sectionId: section.id,
      title: 'Itself',
    );
    final path = p.join(folder.path, 'loop.aantekening');
    await store.exports.write(
      path,
      sections: <String>[section.id],
      pages: <String>[page.id],
    );

    // Each made its own parent.
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final looped = Archive();
    for (final file in archive.files) {
      var bytes = file.readBytes()!;
      if (file.name.startsWith('sections/') || file.name.startsWith('pages/')) {
        if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
          bytes = Uint8List.fromList(gzip.decode(bytes));
        }
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        final entity =
            (json['section'] ?? json['page'])! as Map<String, Object?>;
        entity['parentId'] = entity['id'];
        bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      }
      looped.addFile(ArchiveFile.bytes(file.name, bytes));
    }
    File(path).writeAsBytesSync(ZipEncoder().encode(looped));

    final draft = const AantekeningImporter().read(<String>[
      path,
    ], ImportWork(Directory(p.join(folder.path, 'work'))..createSync()));
    expect(draft.sections.single.title, 'Loop');
    expect(draft.sections.single.sections, isEmpty);
    expect(draft.pages.single.title, 'Itself');
    expect(draft.pages.single.subpages, isEmpty);
  });

  test('exports a page by itself, to go into a section', () async {
    final notebook = await store.library.createNotebook(title: 'N');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'S',
    );
    final page = await store.pages.createPage(
      sectionId: section.id,
      title: 'Alone',
    );
    final path = p.join(folder.path, 'page.aantekening');
    await store.exports.write(path, pages: <String>[page.id]);
    final draft = const AantekeningImporter().read(<String>[
      path,
    ], ImportWork(Directory(p.join(folder.path, 'work'))..createSync()));
    expect(draft.notebooks, isEmpty);
    expect(draft.pages.single.title, 'Alone');
  });
}
