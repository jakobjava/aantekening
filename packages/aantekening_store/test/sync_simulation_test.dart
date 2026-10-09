import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening_store/aantekening_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Two computers sharing one notes folder, as a sync service shares it,
/// doing what people do — writing, adding pages, renaming, deleting,
/// putting back — in every order, writing to and reading from the folder
/// at random moments. However it goes, once both have caught up they hold
/// the same notes, and the last words each wrote on each page are in them.
///
/// `AANTEKENING_SEEDS=2000 dart test test/sync_simulation_test.dart` tries
/// more ways it can go.
void main() {
  final seeds =
      int.tryParse(Platform.environment['AANTEKENING_SEEDS'] ?? '') ?? 40;
  for (var seed = 0; seed < seeds; seed++) {
    test('seed $seed', () => _simulate(seed), timeout: const Timeout.factor(4));
  }
}

Future<void> _simulate(int seed) async {
  final random = math.Random(seed);
  final root = Directory.systemTemp.createTempSync('aantekening_sync_');
  addTearDown(() => root.deleteSync(recursive: true));
  final notes = p.join(root.path, 'Notes');

  Future<AantekeningStore> open(String name) => AantekeningStore.open(
    notesFolder: notes,
    indexFolder: p.join(root.path, 'index-$name'),
    automatic: false,
  );

  final first = await open('a');
  final notebook = await first.library.createNotebook(title: 'Notes');
  final section = await first.library.createSection(
    notebookId: notebook.id,
    title: 'Section',
  );
  for (var i = 0; i < 3; i++) {
    await first.pages.createPage(sectionId: section.id, title: 'Page $i');
  }
  await first.mirror!.flush();
  final second = await open('b');
  final computers = <AantekeningStore>[first, second];
  addTearDown(() async {
    for (final computer in computers) {
      await computer.close();
    }
  });

  // The last words each computer wrote on each page.
  final last = <int, Map<String, String>>{0: {}, 1: {}};
  var words = 0;
  final log = <String>[];

  for (var step = 0; step < 60; step++) {
    final who = random.nextInt(2);
    final store = computers[who];
    final pages = await store.pages.listPages(section.id);
    final live = pages.where((page) => page.deletedAt == null).toList();
    final roll = random.nextInt(100);
    if (roll < 40 && live.isNotEmpty) {
      final page = live[random.nextInt(live.length)];
      final text = 'words${words++}';
      // Writing over words seen here, whoever wrote them, is meant: they
      // go.
      final seen = (await store.pages.loadDocument(
        page.id,
      ))?.extractSearchText();
      for (final written in last.values) {
        written.removeWhere((_, words) => words == seen);
      }
      await store.pages.saveDocument(page.id, documentWithText(page.id, text));
      last[who]![page.id] = text;
      log.add('$who writes $text on ${page.title}');
    } else if (roll < 48) {
      final page = await store.pages.createPage(
        sectionId: section.id,
        title: 'New ${words++}',
      );
      log.add('$who adds ${page.title}');
    } else if (roll < 54 && live.isNotEmpty) {
      final page = live[random.nextInt(live.length)];
      await store.pages.renamePage(page.id, 'Renamed ${words++}');
      log.add('$who renames ${page.title}');
    } else if (roll < 58 && live.length > 1) {
      final page = live[random.nextInt(live.length)];
      await store.pages.deletePage(page.id);
      log.add('$who deletes ${page.title}');
    } else if (roll < 62) {
      final deleted = (await store.bin.list())
          .where((entry) => entry.kind == BinKind.page)
          .toList();
      if (deleted.isNotEmpty) {
        final entry = deleted[random.nextInt(deleted.length)];
        await store.bin.restore(entry);
        log.add('$who restores ${entry.title}');
      }
    } else if (roll < 66) {
      final deleted = (await store.bin.list())
          .where((entry) => entry.kind == BinKind.page)
          .toList();
      if (deleted.isNotEmpty) {
        final entry = deleted[random.nextInt(deleted.length)];
        // Deleting for good what is seen here is meant: it goes.
        final seen = (await store.pages.loadDocument(
          entry.id,
        ))?.extractSearchText();
        for (final written in last.values) {
          written.removeWhere((_, words) => words == seen);
        }
        store.bin.purgePage(entry.id);
        log.add('$who deletes ${entry.title} for good');
      }
    } else if (roll < 69) {
      // Stopped at once — the power cut — and started again: nothing it
      // had not written to the folder is written, until it starts.
      store.database.close();
      computers[who] = await open(who == 0 ? 'a' : 'b');
      log.add('$who stops and starts again');
    } else if (roll < 82) {
      await store.mirror!.flush();
      log.add('$who writes to the folder');
    } else {
      await store.mirror!.scan();
      log.add('$who reads the folder');
    }
  }

  // Both catch up, until nothing changes any more.
  for (var round = 0; round < 6; round++) {
    for (final computer in computers) {
      await computer.mirror!.flush();
      await computer.mirror!.scan();
    }
  }
  for (final computer in computers) {
    expect(
      computer.mirror!.status.pending,
      0,
      reason: 'all written\n${log.join('\n')}',
    );
  }

  Future<Map<String, String>> contents(AantekeningStore store) async => {
    for (final page in await store.pages.listAllPages())
      if (page.deletedAt == null)
        '${page.title} ${page.id}':
            (await store.pages.loadDocument(page.id))?.extractSearchText() ??
            '',
  };

  final mine = await contents(computers[0]);
  final theirs = await contents(computers[1]);
  expect(theirs, mine, reason: 'both hold the same notes\n${log.join('\n')}');

  // Words written on a page one computer then deleted are in the bin, not
  // lost: look there too.
  final kept = <String>{
    ...mine.values,
    for (final computer in computers)
      for (final row in computer.database.select('SELECT id FROM pages'))
        (await computer.pages.loadDocument(
              row['id']! as String,
            ))?.extractSearchText() ??
            '',
  };
  for (final MapEntry(key: who, value: written) in last.entries) {
    for (final text in written.values) {
      expect(
        kept,
        contains(text),
        reason: 'what computer $who wrote last is kept\n${log.join('\n')}',
      );
    }
  }
}
