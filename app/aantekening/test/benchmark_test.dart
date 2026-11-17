import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../benchmark/input.dart';
import '../benchmark/made_up_notes.dart';
import '../benchmark/measuring.dart' hide find;
import '../benchmark/profile.dart';
import 'editor_harness.dart' show openEditor, useTestPage;

/// The parts of the app benchmark that need no window to be held to what
/// they say: the notes it makes up, what a run makes of the frames, the
/// table and the comparison of two profiles — and the keys, the pen and
/// the typing it drives the window with, which must reach the page as a
/// person's do.
void main() {
  group('The notes made up', () {
    test('hold what was asked for, in a folder they open from again', () async {
      final folder = Directory.systemTemp.createTempSync(
        'aantekening_bench_test_',
      );
      AantekeningStore? store;
      // Closed first, whatever became of the test: Windows deletes no file
      // still open.
      addTearDown(() async {
        await store?.close();
        folder.deleteSync(recursive: true);
      });
      Future<AantekeningStore> open() => AantekeningStore.open(
        notesFolder: '${folder.path}/notes',
        indexFolder: '${folder.path}/index',
        automatic: false,
      );
      const size = NotesSize(
        notebooks: 2,
        sections: 7,
        pages: 60,
        strokes: 200,
        paragraphs: 30,
        boxes: 6,
        pictures: 3,
        printout: 2,
      );

      store = await open();
      final made = await makeUpNotes(
        store,
        Directory('${folder.path}/made')..createSync(),
        size,
      );
      await store.mirror!.flush();

      expect(made.holds['notebooks'], 2);
      expect(made.holds['sections'], 7);
      expect(made.holds['pages'], 60);
      expect(made.holds['strokes'], greaterThanOrEqualTo(200));
      // A fifth of the pages, and the heavy ones, in one section.
      expect(made.holds['pagesInFullestSection'], greaterThan(60 ~/ 5));

      final ink = (await store.pages.loadDocument(made.ink))!;
      expect(ink.elements.whereType<PdfElement>(), hasLength(2));
      expect(
        ink.elements.whereType<InkElement>().fold(
          0,
          (sum, element) => sum + element.strokes.length,
        ),
        made.holds['strokes'],
      );
      final again = (await store.pages.loadDocument(made.inkAgain))!;
      expect(again.elements, hasLength(ink.elements.length));

      final text = (await store.pages.loadDocument(made.longText))!;
      expect(
        text.elements.whereType<TextElement>().map((box) => box.blocks.length),
        unorderedEquals(<int>[30, 3]),
      );

      final formulas = (await store.pages.loadDocument(made.formulas))!;
      final boxes = formulas.elements.whereType<TextElement>().toList();
      expect(boxes, hasLength(6));
      expect(
        boxes.every(
          (box) => box.blocks.every(
            (block) => block.runs.any((run) => run.math == MathMode.latex),
          ),
        ),
        isTrue,
      );
      expect(formulas.elements.whereType<ImageElement>(), hasLength(3));

      expect((await store.pages.loadDocument(made.blank))!.elements, isEmpty);
      expect(
        (await store.pages.findPage(made.ordinary))!.sectionId,
        made.section,
      );
      expect(
        (await store.library.findSection(made.section))!.notebookId,
        made.notebook,
      );
      // Found by what is searched for, and gone to by name.
      expect(await store.search.search('schwingung'), isNotEmpty);
      expect(
        (await store.pages.findPage(made.ink))!.title,
        MadeUpNotes.inkTitle,
      );
      await store.close();

      // As the app finds them when it is started on them.
      store = await open();
      expect(await store.pages.listAllPages(), hasLength(60));
      expect((await store.pages.loadDocument(made.ink))!.elements, isNotEmpty);
      await store.close();

      // And told to the window that measures on them.
      final told = MadeUpNotes.fromJson(
        jsonDecode(jsonEncode(made.toJson())) as Map<String, Object?>,
      );
      expect(told.ink, made.ink);
      expect(told.holds, made.holds);
      // Hundreds of files written and read again: a second on Linux, but
      // past half a minute on a busy Windows runner.
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('are as large as the environment says', () {
      expect(
        NotesSize.from(const <String, String>{}).toJson(),
        NotesSize.quick.toJson(),
      );
      final set = NotesSize.from(const <String, String>{
        'AANTEKENING_BENCH_SIZE': 'large',
        'AANTEKENING_BENCH_PAGES': '500',
        'AANTEKENING_BENCH_STROKES': 'many',
      });
      expect(set.pages, 500);
      expect(set.sections, NotesSize.large.sections);
      expect(set.strokes, NotesSize.large.strokes);
    });

    testWidgets('have pictures the engine reads', (tester) async {
      final image = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(picture(64, 40, seed: 2));
        return (await codec.getNextFrame()).image;
      });
      expect(image!.width, 64);
      expect(image.height, 40);
      image.dispose();
    });
  });

  group('A run', () {
    /// A frame begun at [at], built and then drawn for so many
    /// microseconds.
    ui.FrameTiming frame(int at, {required int build, required int raster}) =>
        ui.FrameTiming(
          vsyncStart: at,
          buildStart: at,
          buildFinish: at + build,
          rasterStart: at + build,
          rasterFinish: at + build + raster,
          rasterFinishWallTime: at + build + raster,
        );

    test('tells its frames, the late ones, and what was shown when', () {
      final timings = <ui.FrameTiming>[
        frame(1000, build: 2000, raster: 3000),
        frame(20000, build: 12000, raster: 10000),
        frame(60000, build: 30000, raster: 10000),
        // After the run: not one of its frames.
        frame(300000, build: 90000, raster: 90000),
      ];
      final run = Run.between('typing', 0, 200000)
        ..took('key handled in', 1.5)
        ..took('key handled in', 2.5)
        // A key pressed half a millisecond in, shown by the first frame;
        // and one never shown, which is no time at all.
        ..shown('key to pixels', 500, 1500)
        ..shown('key to pixels', 500, null)
        ..told('frame after a key', 25000)
        ..counts['things picked'] = 12;
      final json = run.toJson(timings);

      expect(json['frames'], 3);
      expect(json['over16'], 2);
      expect(json['over33'], 1);
      expect((json['build']! as Map)['p50'], 12.0);
      expect((json['build']! as Map)['worst'], 30.0);
      expect((json['raster']! as Map)['worst'], 10.0);
      expect((json['total']! as Map)['worst'], 40.0);
      expect(json.containsKey('cpu'), isFalse);
      final times = json['times']! as Map<String, Object?>;
      expect((times['key handled in']! as Map)['count'], 2);
      expect((times['key handled in']! as Map)['worst'], 2.5);
      // Until the frame was drawn, not only built.
      expect((times['key to pixels']! as Map)['count'], 1);
      expect((times['key to pixels']! as Map)['p50'], 5.5);
      expect((times['frame after a key, build']! as Map)['p50'], 12.0);
      expect((times['frame after a key, raster']! as Map)['p50'], 10.0);
      expect(json['counts'], <String, num>{'things picked': 12});
      // What a file keeps of it is what was measured.
      expect(jsonDecode(jsonEncode(json)), json);
    });

    test('measured as it happens spends some time, and ends', () async {
      final run = Run.begin('idle', stalls: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      run.end();
      final json = run.toJson(const <ui.FrameTiming>[]);
      expect(json['frames'], 0);
      expect(json['build'], isNull);
      expect(json['seconds']! as double, greaterThan(0.02));
      expect(json['stall'], isNotNull);
    });

    test('knows how the computer is powered, or that it does not', () {
      final power = powerState();
      expect(
        power.keys,
        containsAll(<String>[
          'profile',
          'pluggedIn',
          'governor',
          'energyPreference',
        ]),
      );
      expect(powerWarning(const <String, Object?>{'pluggedIn': true}), isNull);
      expect(
        powerWarning(const <String, Object?>{
          'pluggedIn': false,
          'profile': 'balanced',
        }),
        allOf(contains('on battery'), contains('balanced')),
      );
      expect(buildOf().keys, containsAll(<String>['commit', 'flutter']));
    });
  });

  group('A profile', () {
    /// A profile of one measure, typing, whose keys took [key]
    /// milliseconds to show, and whose frames were late [late] times.
    Map<String, Object?> profile(
      double key, {
      int late = 0,
      bool plugged = true,
      String measure = 'typing: in a short box',
    }) => <String, Object?>{
      'benchmark': 'app',
      'build': <String, Object?>{'commit': 'abcdef0123456789', 'flutter': '3'},
      'power': <String, Object?>{
        'pluggedIn': plugged,
        'profile': plugged ? 'performance' : 'balanced',
        'governor': null,
        'energyPreference': null,
      },
      'notes': <String, Object?>{'pages': 2000},
      'window': <String, Object?>{'width': 1280, 'height': 720},
      'measures': <Object?>[
        <String, Object?>{
          'name': measure,
          'seconds': 9.5,
          'frames': 120,
          'build': <String, Object?>{
            'count': 120,
            'p50': 2.0,
            'p90': 3.0,
            'p99': 4.0,
            'worst': 5.0,
          },
          'raster': null,
          'over16': late,
          'over33': 0,
          'cpu': <String, Object?>{'ui': 300.0, 'raster': 100.0},
          'times': <String, Object?>{
            'key to pixels': <String, Object?>{
              'count': 60,
              'p50': key,
              'p90': key,
              'p99': key,
              'worst': key,
            },
            'Enter to settled': <String, Object?>{'count': 1, 'p50': 400.0},
          },
          'counts': <String, Object?>{'paragraphs in the box': 3},
        },
      ],
      'unmeasured': <Object?>['pen: d did not take up the pen'],
    };

    test('is kept in a file, and read from it', () {
      final folder = Directory.systemTemp.createTempSync(
        'aantekening_bench_test_',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      final path = '${folder.path}/kept/profile.json';
      writeProfile(path, profile(10));
      expect(readProfile(path), profile(10));
      File(path).writeAsStringSync('{"something": "else"}');
      expect(() => readProfile(path), throwsFormatException);
    });

    test('is written out as a table, with what was not measured', () {
      final head = headOf(profile(10, plugged: false));
      expect(head, contains('abcdef0123'));
      expect(head, contains('on battery, profile balanced'));
      final table = tableOf(profile(10, late: 7));
      expect(table, contains('typing: in a short box'));
      expect(table, contains('key to pixels'));
      expect(table, contains('(60 times)'));
      expect(table, contains('400 ms'));
      expect(table, contains('paragraphs in the box'));
      expect(table, contains('! pen: d did not take up the pen'));
    });

    test('compared with another, says what got slower and faster', () {
      final slower = changesBetween(
        <Map<String, Object?>>[profile(10)],
        <Map<String, Object?>>[profile(20, late: 9)],
      );
      Change of(String compared) =>
          slower.singleWhere((change) => change.compared == compared);
      expect(of('key to pixels p50').isBeyond(0.2), isTrue);
      expect(of('key to pixels p50').share, 1.0);
      expect(of('frames over 16.7 ms').isBeyond(0.2), isTrue);
      // Not by more than it is allowed to vary; nor what did not change.
      expect(of('key to pixels p50').isBeyond(1.5), isFalse);
      expect(of('frame build p50').isBeyond(0.2), isFalse);
      expect(of('Enter to settled').isBeyond(0.2), isFalse);

      final said = comparisonOf(
        <Map<String, Object?>>[profile(20)],
        <Map<String, Object?>>[profile(10)],
      );
      expect(said, contains('faster  key to pixels p50'));
      expect(said, isNot(contains('SLOWER')));
      expect(said, contains('0 slower, 3 faster'));
      expect(said, isNot(contains('Enter to settled')));
      expect(
        comparisonOf(
          <Map<String, Object?>>[profile(20)],
          <Map<String, Object?>>[profile(10)],
          all: true,
        ),
        contains('Enter to settled'),
      );
    });

    test('compared over several runs, marks only what is past their noise', () {
      Change key(List<double> before, List<double> after) => changesBetween(
        before.map(profile).toList(),
        after.map(profile).toList(),
      ).singleWhere((change) => change.compared == 'key to pixels p50');
      // Slower on average, but a run before was as slow as one after.
      expect(key(<double>[10, 21], <double>[20, 22]).isBeyond(0.2), isFalse);
      // Every run after slower than every run before.
      expect(key(<double>[10, 12], <double>[20, 22]).isBeyond(0.2), isTrue);
      expect(key(<double>[20, 22], <double>[10, 12]).isBeyond(0.2), isTrue);
      // A millisecond is not felt, however many percent it is.
      expect(key(<double>[0.5], <double>[1.2]).isBeyond(0.2), isFalse);
    });

    test('compared with one made otherwise, says so', () {
      final said = comparisonOf(
        <Map<String, Object?>>[profile(10, plugged: false)],
        <Map<String, Object?>>[profile(10, measure: 'typing: in a long box')],
      );
      expect(said, contains('! The computer was not powered alike'));
      expect(said, contains('on battery'));
      expect(said, contains('Only before: typing: in a short box'));
      expect(said, contains('Only after: typing: in a long box'));
      expect(
        unlikeBetween(
          <Map<String, Object?>>[profile(10)],
          <Map<String, Object?>>[profile(12)],
        ),
        isEmpty,
      );
    });
  });

  group('What drives the window', () {
    late AantekeningStore store;
    late String pageId;
    useTestPage((made, page) {
      store = made;
      pageId = page;
    });

    /// Hands the window what the engine would, as a test must: at once,
    /// on the test's own clock.
    Deliver deliverIn(WidgetTester tester) =>
        (channel, message, answered) => unawaited(
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel,
            message,
            answered,
          ),
        );

    /// What is typed in this test, told of what the app tells the input
    /// method — as the benchmark's binding tells it.
    TypedText overhear(WidgetTester tester) {
      final typed = TypedText(deliver: deliverIn(tester));
      final messenger = tester.binding.defaultBinaryMessenger;
      final channel = SystemChannels.textInput.name;
      messenger.setMockMessageHandler(channel, (message) async {
        typed.sent(message);
        return const JSONMethodCodec().encodeSuccessEnvelope(null);
      });
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      return typed;
    }

    CanvasController pageOf(WidgetTester tester) =>
        tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

    testWidgets('its keys are the modes’, and its pen writes', (tester) async {
      await openEditor(tester, store, pageId);
      final keys = Keys(deliver: deliverIn(tester));
      final page = pageOf(tester);
      expect(page.tool, CanvasTool.select);

      // d, in normal mode: the pen.
      expect(await keys.press('d'), isTrue);
      await tester.pump();
      expect(page.tool, CanvasTool.pen);

      final input = Input(tester.getRect(find.byType(InfiniteCanvas)));
      const from = Offset(300, 400);
      var at = from;
      input.penDown(at, 0.5);
      for (var i = 1; i <= 12; i++) {
        final next = from + Offset(i * 4.0, i.isEven ? 6 : -6);
        input.penMove(next, next - at, 0.6);
        at = next;
      }
      input.penUp(at);
      await tester.pump();
      final ink = page.document.elements.whereType<InkElement>().toList();
      expect(ink, hasLength(1));
      expect(ink.single.strokes, hasLength(1));
      expect(ink.single.strokes.single.pointCount, greaterThan(6));

      // Esc: back to normal. A capital is typed with Shift, and let go.
      expect(await keys.press('Esc'), isTrue);
      await tester.pump();
      expect(page.tool, CanvasTool.select);
      expect(await keys.press('G'), isTrue);
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      // A key that is no command of the mode is left alone.
      expect(await keys.press('q'), isFalse);
      // The page saved, a pause after the stroke.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    testWidgets('what it types reaches a text box as the input method’s', (
      tester,
    ) async {
      await store.pages.saveDocument(
        pageId,
        PageDocument.empty(id: pageId).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 60, y: 160, width: 400, height: 120),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('one'), TextBlock.plain('two')],
          ),
        ),
      );
      final typed = overhear(tester);
      await openEditor(tester, store, pageId);
      final keys = Keys(deliver: deliverIn(tester));
      final page = pageOf(tester);
      List<TextBlock> blocks() =>
          page.document.elements.whereType<TextElement>().single.blocks;
      String textOf(TextBlock block) =>
          block.runs.map((run) => run.text).join();

      // A click on the first line, with the mouse: the caret is there.
      final input = Input(tester.getRect(find.byType(InfiniteCanvas)));
      final click = input.click(
        tester.getRect(find.byType(InfiniteCanvas)).topLeft +
            page.viewport.toScreen(
              const Offset(60 + 20, 160 + TextElement.grabBand + 8),
            ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await click;
      await tester.pumpAndSettle();
      expect(typed.client, isNotNull);
      expect(typed.deltas, isTrue);
      expect(typed.multiline, isTrue);
      expect(typed.text, 'one');

      // A letter: the window leaves the key to the input method, whose
      // edit the box takes.
      for (final letter in 'xY'.split('')) {
        expect(await keys.down(letter), isFalse);
        expect(await typed.type(letter), isTrue);
        await keys.up(letter);
        await tester.pump();
      }
      expect(textOf(blocks().first), allOf(contains('xY'), hasLength(5)));
      expect(typed.text, textOf(blocks().first));

      // Enter is the box's own: a new paragraph, the input method told
      // nothing.
      expect(await keys.press('Enter'), isTrue);
      await tester.pump();
      expect(blocks(), hasLength(3));

      // Esc: typing ends, and nothing has the keyboard to type into.
      expect(await keys.press('Esc'), isTrue);
      await tester.pump();
      expect(typed.client, isNull);
      expect(await typed.type('z'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    testWidgets('and a field of one line, where Enter is the input method’s', (
      tester,
    ) async {
      final typed = overhear(tester);
      final keys = Keys(deliver: deliverIn(tester));
      String? submitted;
      final field = TextEditingController(text: 'Old name')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 8);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TextField(
              controller: field,
              autofocus: true,
              onSubmitted: (value) => submitted = value,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(typed.client, isNotNull);
      expect(typed.deltas, isFalse);
      expect(typed.multiline, isFalse);
      expect(typed.text, 'Old name');

      // Typed over what is picked, a key at a time.
      for (final letter in 'New page 2'.split('')) {
        expect(await keys.down(letter), isFalse);
        expect(await typed.type(letter), isTrue);
        await keys.up(letter);
        await tester.pump();
      }
      expect(field.text, 'New page 2');

      expect(await keys.down('Enter'), isFalse);
      expect(await typed.perform(), isTrue);
      await keys.up('Enter');
      await tester.pump();
      expect(submitted, 'New page 2');
    });
  });
}
