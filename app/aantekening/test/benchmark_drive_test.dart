import 'dart:io';

import 'package:aantekening/src/app.dart';
import 'package:aantekening/src/editor/media_views.dart'
    show pdfDocumentProvider;
import 'package:aantekening/src/files/notes_keeper.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../benchmark/app_measures.dart';
import '../benchmark/input.dart';
import '../benchmark/made_up_notes.dart';
import '../benchmark/measuring.dart' hide find;

/// Goes through every measure of the app benchmark without a window on
/// the desktop — the whole app, on notes made up small, in the test's own
/// window that nobody sees, in real time — to say that each is driven as
/// it is meant to be: the keys taken, the pen writing, the pages opening.
///
///   AANTEKENING_BENCH_DRIVE=1 flutter test test/benchmark_drive_test.dart
///
/// It takes a couple of minutes, so it is run when asked; and it times
/// nothing worth keeping — the test's window draws in the test font, and
/// its printouts not at all. `AANTEKENING_BENCH_ONLY=pen` goes through
/// only what its name holds, as it does for the benchmark.
void main() {
  if (Platform.environment['AANTEKENING_BENCH_DRIVE'] != '1') {
    test(
      'the measures driven through the window, when asked',
      () {},
      skip: 'not asked',
    );
    return;
  }
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every measure is driven through the window', (tester) async {
    // Every frame the app asks for drawn, and the pointers the benchmark
    // sends taken as a device's.
    binding
      ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
      ..shouldPropagateDevicePointerEvents = true;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    final folder = Directory.systemTemp.createTempSync(
      'aantekening_bench_drive_',
    );
    final messenger = tester.binding.defaultBinaryMessenger;
    final typed = TypedText();
    messenger.setMockMessageHandler(SystemChannels.textInput.name, (
      message,
    ) async {
      typed.sent(message);
      return const JSONMethodCodec().encodeSuccessEnvelope(null);
    });
    final only = Platform.environment['AANTEKENING_BENCH_ONLY'] ?? '';
    try {
      final made = await _notesIn(folder);
      leaveOpen(folder.path, made, made.ordinary);
      final reloads = Reloads();
      final container = measuredContainer(
        folder.path,
        reloads,
        // No PDF engine in a test.
        more: [pdfDocumentProvider.overrideWith((ref, id) async => null)],
      );
      // The test's window draws a frame every sixtieth of a second, asked
      // for or not.
      Frames.drawsUnasked = true;
      Frames.start();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AantekeningApp(),
        ),
      );
      final shown = await Frames.shows(
        () =>
            tester
                .widgetList<InfiniteCanvas>(find.byType(InfiniteCanvas))
                .firstOrNull
                ?.controller
                .document
                .id ==
            made.ordinary,
        walks: true,
        within: const Duration(seconds: 30),
      );
      expect(shown, isNotNull, reason: 'the app opened on its page');

      final measures = Measures(
        container: container,
        notes: made,
        reloads: reloads,
        only: only,
        penStrokes: 6,
        idle: const Duration(milliseconds: 500),
        typed: typed,
      );
      await measures.all();

      expect(measures.unmeasured, isEmpty);
      // Each gives numbers a profile keeps.
      final names = <String>[
        for (final run in measures.runs)
          run.toJson(Frames.timings)['name']! as String,
      ];
      for (final scenario in const <String>[
        'open',
        'idle',
        'pen',
        'select',
        'typing',
        'search',
        'goto',
        'picker',
        'library',
      ]) {
        if (!scenario.contains(only)) continue;
        expect(
          names.where((name) => name.startsWith('$scenario: ')),
          isNotEmpty,
          reason: '$scenario was measured',
        );
      }
      for (final run in measures.runs) {
        final json = run.toJson(Frames.timings);
        debugPrint(
          '${json['name']}: ${json['frames']} frames; '
          '${(json['times']! as Map<String, Object?>).keys.join(', ')}; '
          '${json['counts'] ?? ''}',
        );
      }

      // Closed as the app closes.
      await container.read(openSavesProvider).saveAll();
      await tester.pumpWidget(const SizedBox());
      await (await container.read(storeProvider.future)).close();
      container.dispose();
    } finally {
      binding.shouldPropagateDevicePointerEvents = false;
      messenger.setMockMessageHandler(SystemChannels.textInput.name, null);
      tester.view.reset();
      folder.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// Makes up small notes in [folder], and closes them.
Future<MadeUpNotes> _notesIn(Directory folder) async {
  final store = await AantekeningStore.open(
    notesFolder: '${folder.path}/notes',
    indexFolder: '${folder.path}/index',
    automatic: false,
  );
  try {
    final made = await makeUpNotes(
      store,
      Directory('${folder.path}/made')..createSync(),
      const NotesSize(
        notebooks: 2,
        sections: 8,
        pages: 150,
        strokes: 400,
        paragraphs: 60,
        boxes: 6,
        pictures: 2,
        printout: 2,
      ),
    );
    await store.mirror!.flush();
    return made;
  } finally {
    await store.close();
  }
}
