import 'dart:io';

import 'package:aantekening/src/editor/note_clipboard.dart';
import 'package:aantekening/src/editor/system_clipboard.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  late AantekeningStore store;
  late String pageId;
  late Directory files;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });
  setUp(
    () => files = Directory.systemTemp.createTempSync('aantekening_paste_'),
  );
  tearDown(() {
    SystemClipboard.debugRead = null;
    files.deleteSync(recursive: true);
  });

  /// Puts [clip] on the system clipboard, as the runner reads it.
  void copied(SystemClip? clip) => SystemClipboard.debugRead = () async => clip;

  CanvasController canvasOf(WidgetTester tester) =>
      tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

  /// Presses Ctrl+V and waits until what it pastes is on the page: read
  /// and stored, away from the test's clock.
  Future<void> paste(WidgetTester tester) async {
    final before = canvasOf(tester).document;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.runAsync(() async {
      var still = 0;
      var last = before;
      for (var i = 0; i < 500; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        final now = canvasOf(tester).document;
        still = identical(now, last) ? still + 1 : 0;
        last = now;
        if (!identical(now, before) && still >= 10) break;
      }
    });
    await tester.pumpAndSettle();
  }

  String fileAt(String name, List<int> bytes) =>
      (File('${files.path}/$name')..writeAsBytesSync(bytes)).path;

  group('The clipboard', () {
    test('pastes a screenshot, not a picture copied here before it', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? text;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return text == null ? null : <String, Object?>{'text': text};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      const picture = ImageElement(
        id: 'p',
        frame: Frame(x: 0, y: 0, width: 10, height: 10),
        createdAt: 0,
        updatedAt: 0,
        assetId: 'a',
      );
      await NoteClipboard.copy(ElementsClip(<NoteElement>[picture]));
      expect(await NoteClipboard.read(), isA<ElementsClip>());

      copied(CopiedPicture(pngBytes, 'image/png'));
      expect(await NoteClipboard.read(), isA<CopiedClip>());

      // A spreadsheet's cells, copied with a picture of them, are text.
      text = 'a\tb';
      copied(CopiedPicture(pngBytes, 'image/png', withText: true));
      expect(await NoteClipboard.read(), isA<PlainClip>());

      // Files copied come with their paths as text, and are files.
      copied(const CopiedFiles(<String>['/tmp/x.pdf'], withText: true));
      expect(await NoteClipboard.read(), isA<CopiedClip>());

      // Text copied here pastes as what it was.
      copied(null);
      await NoteClipboard.copy(const PlainClip('hier'));
      expect((await NoteClipboard.read())?.plain, 'hier');
    });
  });

  group('On the page', () {
    testWidgets('a screenshot pasted lies in the middle of the view', (
      tester,
    ) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      copied(CopiedPicture(pngBytes, 'image/png'));
      await paste(tester);

      final canvas = canvasOf(tester);
      final picture = canvas.document.elements.whereType<ImageElement>().single;
      expect(picture.bounds.centerX, closeTo(canvas.viewCenter.dx, 1));
      final asset = await tester.runAsync(
        () => store.assets.find(picture.assetId),
      );
      expect(asset!.mimeType, 'image/png');
    });

    testWidgets('files copied in a file manager are brought in as dropped '
        'ones are: LaTeX typeset, text as text', (tester) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      copied(
        CopiedFiles(<String>[
          fileAt('notes.tex', r'Energy is $E = mc^2$.'.codeUnits),
          fileAt('list.txt', 'first\nsecond'.codeUnits),
        ], withText: true),
      );
      await paste(tester);

      final boxes = canvasOf(tester).document.elements
          .whereType<TextElement>()
          .toList();
      expect(boxes, hasLength(2));
      final runs = boxes
          .expand((box) => box.blocks)
          .expand((block) => block.runs)
          .toList();
      expect(runs.any((run) => run.math != null), isTrue, reason: 'typeset');
      expect(runs.map((run) => run.text), contains('second'));
    });

    testWidgets('a screenshot pasted while typing goes into the text', (
      tester,
    ) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'Zie:');
      copied(CopiedPicture(pngBytes, 'image/png'));
      await paste(tester);

      final box = canvasOf(tester).document.elements
          .whereType<TextElement>()
          .single;
      expect(box.blocks.first.runs.single.text, 'Zie:');
      expect(
        box.blocks.where((block) => block.embed?.kind == EmbedKind.image),
        hasLength(1),
      );
      expect(canvasOf(tester).document.elements, hasLength(1));
    });

    testWidgets('a screenshot pasted at a bare caret lies there, on the page', (
      tester,
    ) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      copied(CopiedPicture(pngBytes, 'image/png'));
      await paste(tester);

      final elements = canvasOf(tester).document.elements;
      expect(elements.whereType<ImageElement>(), hasLength(1));
      expect(elements.whereType<TextElement>(), isEmpty);
    });

    testWidgets('text copied elsewhere still pastes as text', (tester) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      await Clipboard.setData(const ClipboardData(text: 'gewone tekst'));
      copied(null);
      await paste(tester);

      final box = canvasOf(tester).document.elements
          .whereType<TextElement>()
          .single;
      expect(box.blocks.single.runs.single.text, 'gewone tekst');
    });
  });
}
