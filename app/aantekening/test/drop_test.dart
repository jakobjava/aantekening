import 'dart:io';

import 'package:aantekening/src/spelling/spelling.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'editor_harness.dart';

/// A GIF of two frames, red then blue, two pixels square.
final Uint8List _gif = Uint8List.fromList(<int>[
  71, 73, 70, 56, 57, 97, 2, 0, 2, 0, 129, 0, 0, 255, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 33, 255, 11, 78, 69, 84, 83, 67, 65, 80, 69, 50, 46, 48, //
  3, 1, 0, 0, 0, 33, 249, 4, 0, 10, 0, 0, 0, 44, 0, 0, 0, 0, 2, 0, 2, 0, //
  0, 8, 6, 0, 1, 8, 4, 16, 16, 0, 33, 249, 4, 1, 10, 0, 1, 0, 44, 0, 0, //
  0, 0, 2, 0, 2, 0, 129, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 6, 0, //
  1, 8, 4, 16, 16, 0, 59, //
]);

void main() {
  late AantekeningStore store;
  late String pageId;
  late Directory files;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });
  setUp(() => files = Directory.systemTemp.createTempSync('aantekening_drop_'));
  tearDown(() => files.deleteSync(recursive: true));

  CanvasController canvasOf(WidgetTester tester) =>
      tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

  /// Drops [payload] at [at] in the window, as GTK hands it over: one
  /// address a line, or text. It is held over the window first, as a drag
  /// is, for a drop to be taken on any platform.
  Future<void> drop(WidgetTester tester, String payload, Offset at) async {
    Future<void> send(String method, Object arguments) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
    await tester.runAsync(() async {
      await send('entered', <double>[at.dx, at.dy]);
      await send('performOperation_linux', <Object>[
        payload,
        <double>[at.dx, at.dy],
      ]);
      // Read and stored away from the test's clock.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  String fileAt(String name, List<int> bytes) {
    final file = File('${files.path}/$name')..writeAsBytesSync(bytes);
    return file.uri.toString();
  }

  testWidgets('a GIF dropped on the page lies where it was let go', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    const at = Offset(500, 400);
    await drop(tester, fileAt('wave.gif', _gif), at);

    final canvas = canvasOf(tester);
    final picture = canvas.document.elements.whereType<ImageElement>().single;
    final where = canvas.viewport.toPage(at);
    expect(picture.bounds.centerX, closeTo(where.dx, 1));
    expect(picture.bounds.centerY, closeTo(where.dy, 1));
    final asset = await tester.runAsync(
      () => store.assets.find(picture.assetId),
    );
    expect(asset!.mimeType, 'image/gif');
    expect(asset.originalName, 'wave.gif');
  });

  testWidgets('a GIF plays with the desktop\'s animations turned off', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openEditor(tester, store, pageId);
    await drop(tester, fileAt('wave.gif', _gif), const Offset(500, 400));

    // The picture shown, as Flutter hands one over for each frame.
    final shown = <int>{};
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      shown.add(
        identityHashCode(tester.widget<RawImage>(find.byType(RawImage)).image),
      );
    }
    expect(shown.length, greaterThan(1), reason: 'its frames shown in turn');
  });

  testWidgets('LaTeX, text and other files dropped together lie one under '
      'another', (tester) async {
    await openEditor(tester, store, pageId);
    final payload = <String>[
      fileAt('notes.tex', r'Energy is $E = mc^2$.'.codeUnits),
      fileAt('list.txt', 'first\nsecond'.codeUnits),
      fileAt('marks.csv', 'a,b\n1,2'.codeUnits),
    ].join('\r\n');
    await drop(tester, payload, const Offset(300, 300));

    final boxes =
        canvasOf(tester).document.elements.whereType<TextElement>().toList()
          ..sort((a, b) => a.frame.y.compareTo(b.frame.y));
    expect(boxes, hasLength(3));
    final latex = boxes[0].blocks.single;
    expect(
      latex.runs.any((run) => run.math != null && run.imported),
      isTrue,
      reason: 'typeset as LaTeX brought in is',
    );
    expect(RichTextEditing.plainTextOf(boxes[1].blocks), 'first\nsecond');
    final file = boxes[2].blocks.single.embed!;
    expect(file.kind, EmbedKind.file);
    expect(file.name, 'marks.csv');
    for (var i = 1; i < boxes.length; i++) {
      expect(
        boxes[i].frame.y,
        greaterThanOrEqualTo(boxes[i - 1].bounds.bottom),
        reason: 'each under the last',
      );
    }
  });

  testWidgets('text dragged by itself is put in a box, a line naming a '
      'website and all', (tester) async {
    await openEditor(tester, store, pageId);
    await drop(tester, 'See\nhttps://example.org', const Offset(300, 300));
    final box = canvasOf(tester).document.elements
        .whereType<TextElement>()
        .single;
    expect(RichTextEditing.plainTextOf(box.blocks), 'See\nhttps://example.org');
  });

  testWidgets('a drop that brings nothing readable says so', (tester) async {
    await openEditor(tester, store, pageId);
    await drop(tester, '', const Offset(300, 300));
    expect(find.text('What was dropped could not be read.'), findsOneWidget);
    expect(canvasOf(tester).document.elements, isEmpty);
  });

  testWidgets('a picture dragged out of a browser is fetched', (tester) async {
    final asked = <Uri>[];
    await openEditor(
      tester,
      store,
      pageId,
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            asked.add(request.url);
            return http.Response.bytes(_gif, 200);
          }),
        ),
      ],
    );
    await drop(tester, 'https://example.org/funny.gif', const Offset(400, 300));
    expect(asked, <Uri>[Uri.parse('https://example.org/funny.gif')]);
    expect(
      canvasOf(tester).document.elements.whereType<ImageElement>(),
      hasLength(1),
    );
  });
}
