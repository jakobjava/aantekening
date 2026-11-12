/// Measures how smoothly, and at what cost, a heavy page scrolls and zooms,
/// and the AI floats over it on glass, opened, moved and sized: the time
/// each frame takes to build and to draw, and the processor time spent,
/// thread by thread, while a wheel, a touchpad, a pinch and the mouse move
/// them — and while nothing does.
///
/// Built and run in profile mode, on the desktop it is to measure:
///
/// ```sh
/// cd app/aantekening
/// flutter build linux --profile -t benchmark/canvas_benchmark.dart
/// build/linux/x64/profile/bundle/aantekening
/// ```
///
/// The page is made up — printouts with handwriting over them, and some
/// text — unless `AANTEKENING_BENCH_NOTES` names a OneNote package
/// (`.onepkg`) or a notes folder, whose heaviest page is used instead, or
/// the page whose title holds `AANTEKENING_BENCH_PAGE`. A notes folder is
/// copied first, and the copy opened. Nothing is read from or written to the
/// notes, the settings or the keychain: the page is kept in memory, its
/// files in a temporary folder. With `AANTEKENING_BENCH_LAYOUT=pages` the
/// page is shown as pages, cut into sheets.
///
/// `AANTEKENING_BENCH_ONLY=AI` measures only what its name holds;
/// `AANTEKENING_BENCH_TRACE=1` puts each widget's building, laying out and
/// drawing in the timeline, and `AANTEKENING_BENCH_HOLD=30` keeps the app
/// open that many seconds at the end, for the timeline to be read.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:aantekening/src/ai/ai_state.dart';
import 'package:aantekening/src/ai/ai_view.dart';
import 'package:aantekening/src/app.dart';
import 'package:aantekening/src/editor/trackpad.dart';
import 'package:aantekening/src/files/notes_location.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening/src/spelling/dictionaries.dart';
import 'package:aantekening/src/spelling/spelling.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'input.dart';
import 'made_up_notes.dart';
import 'measuring.dart';

Future<void> main() async {
  AantekeningBinding.ensureInitialized();
  // Each widget's building and drawing in the timeline, to be read with
  // DevTools or the VM service: what a frame spent its time on.
  if (Platform.environment['AANTEKENING_BENCH_TRACE'] != null) {
    debugProfileBuildsEnabled = true;
    debugProfileBuildsEnabledUserWidgets = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
  }
  final folder = Directory.systemTemp.createTempSync('aantekening_bench_');
  final notes = Platform.environment['AANTEKENING_BENCH_NOTES'] ?? '';
  final title = Platform.environment['AANTEKENING_BENCH_PAGE'];
  final AantekeningStore store;
  final String pageId;
  if (notes.isNotEmpty && FileSystemEntity.isDirectorySync(notes)) {
    store = await _copiedNotes(folder, notes);
    pageId = await _heaviestOf(store, notes, title);
  } else {
    store = AantekeningStore.inMemory(
      assetDirectory: Directory('${folder.path}/assets')..createSync(),
    );
    pageId = notes.isEmpty
        ? await madeUpPage(store, folder)
        : await _heaviestPage(store, folder, notes, title);
  }

  final timings = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  Battery.start();
  // The whole window, as it is used: sidebar, tabs and ribbon about the
  // page. Settings are kept in memory, this computer's folder for the app
  // is the temporary one, and no keychain is read.
  final container = ProviderContainer(
    overrides: [
      storeProvider.overrideWith((ref) async => store),
      preferencesProvider.overrideWith((ref) async => Preferences.inMemory()),
      supportFolderProvider.overrideWith((ref) async => folder.path),
      dictionaryFolderProvider.overrideWith(
        (ref) async => DictionaryFolder(Directory('${folder.path}/words')),
      ),
      aiSecretsProvider.overrideWithValue(MemorySecrets()),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AantekeningApp(),
    ),
  );
  await wait(const Duration(seconds: 1));
  await container.read(libraryActionsProvider).openPageId(pageId);
  // The page across the window, as it is read.
  // Shown as pages, if asked: the same page, cut into sheets.
  if (Platform.environment['AANTEKENING_BENCH_LAYOUT'] == 'pages') {
    await wait(const Duration(milliseconds: 300));
    (_canvas().widget as InfiniteCanvas).controller.setLayout(NoteLayout.pages);
  }

  // Opened, and its PDF pages drawn.
  await wait(const Duration(seconds: 4));
  final input = Input(_canvasRect());
  final runs = <Run>[];
  // Only the measures whose names hold AANTEKENING_BENCH_ONLY, if set — the
  // AI pane's, say — what comes before them done but not measured.
  final only = Platform.environment['AANTEKENING_BENCH_ONLY'] ?? '';
  Future<void> measure(String name, Future<void> Function() action) async {
    if (!name.contains(only)) {
      if (name.startsWith('AI')) await action();
      return;
    }
    final run = Run.begin(name);
    await action();
    // Coasting, gliding and rendering what the move uncovered.
    await wait(const Duration(milliseconds: 1500));
    runs.add(run..end());
  }

  await measure('idle', () => wait(const Duration(seconds: 4)));
  // What a frame costs with nothing in it changed: the least any frame
  // costs, however little it moves.
  await measure('frames, nothing moving', () async {
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(end)) {
      SchedulerBinding.instance.scheduleForcedFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
  });
  await measure('wheel scroll', () async {
    for (final direction in <double>[1, -1]) {
      for (var notch = 0; notch < 24; notch++) {
        input.wheel(Offset(0, 100 * direction));
        await wait(const Duration(milliseconds: 60));
      }
    }
  });
  // Read down the page and back: a few notches, and a pause to read.
  await measure('wheel scroll, reading', () async {
    for (final direction in <double>[1, -1]) {
      for (var pause = 0; pause < 6; pause++) {
        for (var notch = 0; notch < 3; notch++) {
          input.wheel(Offset(0, 100 * direction));
          await wait(const Duration(milliseconds: 60));
        }
        await wait(const Duration(milliseconds: 700));
      }
    }
  });
  await measure('touchpad scroll', () async {
    await input.swipe(
      const Offset(0, -2400),
      const Duration(milliseconds: 900),
    );
    await input.swipe(const Offset(0, 1800), const Duration(milliseconds: 700));
    await input.swipe(const Offset(0, -600), const Duration(milliseconds: 500));
  });
  // Reading on for a while: what scrolling costs the battery.
  await measure('touchpad scroll, sustained', () async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    var direction = 1.0;
    while (DateTime.now().isBefore(end)) {
      await input.swipe(
        Offset(0, -500 * direction),
        const Duration(milliseconds: 600),
      );
      await wait(const Duration(milliseconds: 250));
      direction = -direction;
    }
  });
  await measure('touchpad pinch', () async {
    await input.pinch(const <double>[
      1,
      2.5,
      2.5,
      0.4,
      1,
    ], const Duration(seconds: 3));
  });
  await measure('ctrl+wheel zoom', () async {
    input.holdControl(down: true);
    for (final direction in <double>[-1, 1]) {
      for (var notch = 0; notch < 8; notch++) {
        input.wheel(Offset(0, 100 * direction));
        await wait(const Duration(milliseconds: 90));
      }
    }
    input.holdControl(down: false);
  });
  await input.pinch(const <double>[1, 4], const Duration(milliseconds: 800));
  await wait(const Duration(seconds: 3));
  await measure('touchpad scroll, zoomed in', () async {
    await input.swipe(
      const Offset(0, -1500),
      const Duration(milliseconds: 900),
    );
    await input.swipe(
      const Offset(-600, 900),
      const Duration(milliseconds: 700),
    );
  });
  await measure('idle, zoomed in', () => wait(const Duration(seconds: 3)));

  // The AI, floating over the page on glass: opened, moved by its head and
  // sized by its edge, and left open.
  await measure('AI pane opening', () async {
    container.read(tabsProvider.notifier).toggleAi();
    await wait(const Duration(milliseconds: 600));
  });
  // Closed, and opened again: what of opening is paid each time, and what
  // only the first.
  container.read(tabsProvider.notifier).toggleAi();
  await wait(const Duration(seconds: 1));
  await measure('AI pane opening again', () async {
    container.read(tabsProvider.notifier).toggleAi();
    await wait(const Duration(milliseconds: 600));
  });
  final pane = rectOf<AiView>();
  await measure('AI pane moved', () async {
    await input.drag(
      Offset(pane.center.dx, pane.top + 20),
      const Offset(-400, 60),
      const Duration(seconds: 2),
    );
  });
  await measure('AI pane sized', () async {
    final moved = rectOf<AiView>();
    await input.drag(
      Offset(moved.left + 2, moved.center.dy),
      const Offset(-300, 0),
      const Duration(seconds: 2),
    );
  });
  await measure('idle, AI pane open', () => wait(const Duration(seconds: 4)));

  // The last timings are handed over once a frame is drawn after a while.
  await wait(const Duration(milliseconds: 1100));
  SchedulerBinding.instance.scheduleForcedFrame();
  await wait(const Duration(milliseconds: 300));

  final out = StringBuffer()
    ..writeln()
    ..writeln(
      'Canvas benchmark — page ${_canvasRect().width.round()}×'
      '${_canvasRect().height.round()}, '
      '${PlatformDispatcher.instance.views.first.devicePixelRatio}× pixels, '
      'shown as ${(_canvas().widget as InfiniteCanvas).controller.document.canvas.layout.label.toLowerCase()}',
    );
  for (final run in runs) {
    run.report(out, timings);
  }
  out.writeln('Memory: ${(ProcessInfo.maxRss / 1e6).round()} MB at most');
  stdout.write(out);
  await stdout.flush();
  // Held open a while, if asked, for the timeline to be read.
  final hold = int.tryParse(
    Platform.environment['AANTEKENING_BENCH_HOLD'] ?? '',
  );
  if (hold != null) await wait(Duration(seconds: hold));
  await store.close();
  folder.deleteSync(recursive: true);
  exit(0);
}

/// Where the page is on screen.
Rect _canvasRect() => rectOf<InfiniteCanvas>();

/// The page, as the window shows it.
Element _canvas() => find<InfiniteCanvas>();

/// Imports the OneNote package at [path], and picks its page whose title
/// holds [title], or else the one with the most on it.
Future<String> _heaviestPage(
  AantekeningStore store,
  Directory folder,
  String path,
  String? title,
) async {
  final work = Directory('${folder.path}/import')..createSync();
  final draft = await Isolate.run(
    () => const OneNoteImporter().read(<String>[path], ImportWork(work)),
  );
  await store.drafts.store(draft);
  return _heaviestOf(store, path, title);
}

/// A copy of the notes folder at [path], opened with an index of its own:
/// the notes themselves are neither read by the index nor written to.
Future<AantekeningStore> _copiedNotes(Directory folder, String path) async {
  final copy = Directory('${folder.path}/notes');
  final source = Directory(path);
  for (final entity in source.listSync(recursive: true)) {
    final relative = entity.path.substring(source.path.length);
    if (entity is Directory) {
      Directory('${copy.path}$relative').createSync(recursive: true);
    } else if (entity is File) {
      File('${copy.path}$relative').parent.createSync(recursive: true);
      entity.copySync('${copy.path}$relative');
    }
  }
  return AantekeningStore.open(
    notesFolder: copy.path,
    indexFolder: '${folder.path}/index',
    automatic: false,
  );
}

/// The page of [store] whose title holds [title], or else its heaviest.
Future<String> _heaviestOf(
  AantekeningStore store,
  String path,
  String? title,
) async {
  String? heaviest;
  var most = -1;
  for (final page in await store.pages.listAllPages()) {
    if (title != null && title.isNotEmpty) {
      if (page.title.contains(title)) return page.id;
      continue;
    }
    final document = await store.pages.loadDocument(page.id);
    if (document == null) continue;
    var weight = 0;
    for (final element in document.elements) {
      weight += switch (element) {
        InkElement(:final strokes) => strokes.fold(
          0,
          (sum, stroke) => sum + stroke.pointCount,
        ),
        PdfElement() => 20000,
        _ => 500,
      };
    }
    if (weight > most) {
      most = weight;
      heaviest = page.id;
    }
  }
  if (heaviest == null) throw StateError('No page in $path');
  return heaviest;
}
