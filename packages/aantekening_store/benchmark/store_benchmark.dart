// How long the store takes over many notes, where the window would wait on
// it: saving, searching, listing, opening, and looking at the notes folder.
//
//   dart run benchmark/store_benchmark.dart [pages]
//
// The notes are made up, in a temporary folder that goes afterwards.

import 'dart:async';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final count = arguments.isEmpty ? 3000 : int.parse(arguments.first);
  final root = Directory.systemTemp.createTempSync('aantekening_bench_');
  final notes = p.join(root.path, 'Notes');
  final index = p.join(root.path, 'index');
  try {
    var store = await AantekeningStore.open(
      notesFolder: notes,
      indexFolder: index,
      automatic: false,
    );
    final notebook = await store.library.createNotebook(title: 'Physics');
    final sections = <String>[
      for (var i = 0; i < 30; i++)
        (await store.library.createSection(
          notebookId: notebook.id,
          title: 'Section $i',
        )).id,
    ];
    final pages = <String>[];
    var watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      final page = await store.pages.createPage(
        sectionId: sections[i % sections.length],
        title: 'Lecture $i',
      );
      await store.pages.saveDocument(page.id, _page(page.id, i));
      pages.add(page.id);
    }
    _say('made $count pages', watch, count);

    watch = Stopwatch()..start();
    await store.mirror!.flush();
    _say('wrote them all to the folder', watch);

    for (var run = 0; run < 3; run++) {
      watch = Stopwatch()..start();
      final stalled = await _longestStall(store.mirror!.scan);
      _say('looked at the folder, nothing changed', watch);
      _stall(stalled);
    }

    watch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await store.pages.saveDocument(pages[i % count], _page(pages[i], -i));
    }
    _say('saved a page', watch, 200);

    watch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await store.pages.loadDocument(pages[(i * 7) % count]);
    }
    _say('opened a page', watch, 200);

    watch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      await store.search.search(i.isEven ? 'momentum energy' : 'wav');
    }
    _say('searched', watch, 100);

    watch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      await store.pages.listPages(sections[i % sections.length]);
    }
    _say('listed a section', watch, 100);

    watch = Stopwatch()..start();
    await store.pages.listAllPages();
    _say('listed every page', watch);

    await store.close();
    watch = Stopwatch()..start();
    store = await AantekeningStore.open(
      notesFolder: notes,
      indexFolder: index,
      automatic: false,
    );
    _say('opened the notes again', watch);
    await store.close();
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// The longest the isolate asking — the window's, in the app — went
/// without being able to do anything else while [work] ran.
Future<Duration> _longestStall(Future<Object?> Function() work) async {
  var longest = Duration.zero;
  final since = Stopwatch()..start();
  final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
    if (since.elapsed > longest) longest = since.elapsed;
    since.reset();
  });
  await work();
  ticker.cancel();
  if (since.elapsed > longest) longest = since.elapsed;
  return longest;
}

void _stall(Duration stalled) => stdout.writeln(
  '${'  the window waited at most'.padRight(42)} '
  '${(stalled.inMicroseconds / 1000).toStringAsFixed(2).padLeft(9)} ms',
);

void _say(String what, Stopwatch watch, [int times = 1]) {
  final each = watch.elapsedMicroseconds / times / 1000;
  stdout.writeln(
    '${what.padRight(42)} ${each.toStringAsFixed(2).padLeft(9)} ms'
    '${times > 1 ? ' each' : ''}',
  );
}

PageDocument _page(String id, int n) =>
    PageDocument.empty(id: id).withElementAdded(
      TextElement(
        id: Ulid.generate(),
        frame: const Frame(x: 0, y: 0, width: 600, height: 800),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          for (var line = 0; line < 40; line++)
            TextBlock.plain(
              'Line $line of lecture $n: momentum, energy and waves, '
              'conserved where the laws are symmetric.',
            ),
        ],
      ),
    );
