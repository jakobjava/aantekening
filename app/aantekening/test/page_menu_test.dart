import 'dart:io';

import 'package:aantekening/src/editor/media_views.dart';
import 'package:aantekening/src/editor/ribbon/mini_toolbar.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  late AantekeningStore store;
  late Directory assets;
  late String pageId;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_menu_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    final notebook = await store.library.createNotebook(title: 'Notes');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Section',
    );
    pageId = (await store.pages.createPage(sectionId: section.id)).id;
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  /// Saves the page holding [elements], each picture's asset stored first.
  Future<void> savePage(
    WidgetTester tester,
    List<NoteElement> Function(String assetId) elements,
  ) => tester.runAsync(() async {
    final asset = await store.assets.importBytes(
      pngBytes,
      mimeType: 'image/png',
    );
    await store.pages.saveDocument(
      pageId,
      PageDocument(id: pageId, elements: elements(asset.id)),
    );
  });

  ImageElement picture(String assetId) => ImageElement(
    id: 'picture',
    frame: const Frame(x: 120, y: 160, width: 160, height: 80),
    createdAt: 0,
    updatedAt: 0,
    assetId: assetId,
  );

  CanvasController canvasOf(WidgetTester tester) =>
      tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

  List<NoteElement> elementsOf(WidgetTester tester) =>
      canvasOf(tester).document.elements;

  Finder menuItem(String label) => find.descendant(
    of: find.byType(PopupMenuItem<VoidCallback>),
    matching: find.text(label),
  );

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PopupMenuItem<VoidCallback>>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(PopupMenuItem<VoidCallback>),
        ),
      )
      .enabled;

  testWidgets('a right-click on the paper offers pasting, under the toolbar', (
    tester,
  ) async {
    mockClipboard(tester);
    await openEditor(tester, store, pageId);
    await rightClick(tester, const Offset(600, 500));

    expect(find.byType(MiniToolbar), findsOneWidget);
    expect(enabled(tester, 'Cut'), isFalse);
    expect(enabled(tester, 'Copy'), isFalse);
    expect(enabled(tester, 'Paste'), isFalse, reason: 'nothing copied yet');
    expect(menuItem('Delete'), findsNothing);
  });

  testWidgets('a picture is copied and pasted, a step on each time', (
    tester,
  ) async {
    mockClipboard(tester);
    await savePage(tester, (asset) => <NoteElement>[picture(asset)]);
    await openEditor(tester, store, pageId);
    await tester.tapAt(
      tester.getCenter(find.byType(AssetImageView)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyC, control: true);
    await press(tester, LogicalKeyboardKey.keyV, control: true);
    await press(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pumpAndSettle();

    final pictures = elementsOf(tester).whereType<ImageElement>().toList();
    expect(pictures, hasLength(3));
    expect(pictures.map((p) => p.id).toSet(), hasLength(3));
    expect(pictures.map((p) => p.frame.x), <double>[120, 144, 168]);
    expect(canvasOf(tester).selection, <String>{pictures.last.id});

    // Cut takes it away, and pasting brings it back.
    await press(tester, LogicalKeyboardKey.keyX, control: true);
    expect(elementsOf(tester), hasLength(2));
    await press(tester, LogicalKeyboardKey.keyV, control: true);
    expect(elementsOf(tester), hasLength(3));
  });

  for (final cut in <bool>[false, true]) {
    testWidgets(
      'a picture ${cut ? 'cut' : 'copied'} and pasted at a caret on the '
      'paper lands there as itself',
      (tester) async {
        mockClipboard(tester);
        await savePage(tester, (asset) => <NoteElement>[picture(asset)]);
        await openEditor(tester, store, pageId);
        await tester.tapAt(
          tester.getCenter(find.byType(AssetImageView)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await press(
          tester,
          cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC,
          control: true,
        );

        // A click on empty paper, a caret there, and paste.
        const caret = Offset(700, 550);
        await tester.tapAt(caret, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(textBox(tester).isEditing, isTrue);
        await press(tester, LogicalKeyboardKey.keyV, control: true);
        await tester.pumpAndSettle();

        expect(find.byType(TextBoxEditor), findsNothing, reason: 'no box');
        final pictures = elementsOf(tester).whereType<ImageElement>();
        expect(pictures, hasLength(cut ? 1 : 2));
        final pasted = pictures.last;
        final topLeft =
            tester.getTopLeft(find.byType(InfiniteCanvas)) +
            canvasOf(tester).viewport
                .toScreen(Offset(pasted.frame.x, pasted.frame.y));
        expect(topLeft.dx, closeTo(caret.dx, 0.5));
        expect(topLeft.dy, closeTo(caret.dy, 0.5));
        expect(canvasOf(tester).selection, <String>{pasted.id});
      },
    );
  }

  testWidgets('a right-clicked picture is set as the background, and back', (
    tester,
  ) async {
    mockClipboard(tester);
    await savePage(tester, (asset) => <NoteElement>[picture(asset)]);
    await openEditor(tester, store, pageId);
    final at = tester.getCenter(find.byType(AssetImageView));

    await rightClick(tester, at);
    expect(canvasOf(tester).selection, <String>{'picture'});
    await tester.tap(menuItem('Set Picture As Background'));
    await tester.pumpAndSettle();

    final background = canvasOf(tester).document.elementById('picture')!;
    expect(background.locked, isTrue);
    expect(canvasOf(tester).selection, isEmpty);
    // Out of reach: a click there places a caret on the paper instead.
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(canvasOf(tester).selection, isEmpty);
    expect(find.byType(TextBoxEditor), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await rightClick(tester, at);
    expect(
      tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Set Picture As Background'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.check_rounded),
        ),
      ),
      isNotNull,
      reason: 'ticked, as it is set',
    );
    await tester.tap(menuItem('Set Picture As Background'));
    await tester.pumpAndSettle();
    expect(canvasOf(tester).document.elementById('picture')!.locked, isFalse);
  });

  group('a picture in a text box', () {
    TextElement boxWith(String assetId) => TextElement(
      id: 'box',
      frame: const Frame(x: 100, y: 100, width: 320, height: 160),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[
        TextBlock.plain('above'),
        TextBlock.embedded(
          BlockEmbed(
            kind: EmbedKind.image,
            assetId: assetId,
            width: 120,
            height: 60,
          ),
        ),
      ],
    );

    testWidgets('is copied and pasted within the box', (tester) async {
      mockClipboard(tester);
      await savePage(tester, (asset) => <NoteElement>[boxWith(asset)]);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.keyC, control: true);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();

      expect(blocksOf(tester).where((block) => block.isEmbed), hasLength(2));
    });

    testWidgets('is set as the background where it lies, in one step', (
      tester,
    ) async {
      mockClipboard(tester);
      await savePage(tester, (asset) => <NoteElement>[boxWith(asset)]);
      await openEditor(tester, store, pageId);
      final drawn = tester.getRect(find.byType(AssetImageView));

      await rightClick(tester, drawn.center);
      await tester.tap(menuItem('Set Picture As Background'));
      await tester.pumpAndSettle();

      final background = elementsOf(tester).whereType<ImageElement>().single;
      expect(background.locked, isTrue);
      final viewport = canvasOf(tester).viewport;
      final topLeft =
          tester.getTopLeft(find.byType(InfiniteCanvas)) +
          viewport.toScreen(Offset(background.frame.x, background.frame.y));
      expect(topLeft.dx, closeTo(drawn.left, 0.5));
      expect(topLeft.dy, closeTo(drawn.top, 0.5));
      final box = elementsOf(tester).whereType<TextElement>().single;
      expect(box.blocks.where((block) => block.isEmbed), isEmpty);

      canvasOf(tester).undo();
      await tester.pumpAndSettle();
      expect(elementsOf(tester).whereType<ImageElement>(), isEmpty);
      expect(
        elementsOf(tester).whereType<TextElement>().single.blocks,
        hasLength(2),
      );
    });

    testWidgets('things from the page go into the text', (tester) async {
      mockClipboard(tester);
      await savePage(
        tester,
        (asset) => <NoteElement>[
          picture(asset),
          TextElement(
            id: 'box',
            frame: const Frame(x: 400, y: 400, width: 200, height: 40),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('text')],
          ),
        ],
      );
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyC, control: true);

      final box = tester.getRect(find.byType(TextBoxEditor));
      await tester.tapAt(
        Offset(box.right - 4, box.top + TextBoxEditor.grabBand + 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();

      final blocks = tester
          .widget<TextBoxEditor>(find.byType(TextBoxEditor))
          .element
          .blocks;
      expect(blocks.where((block) => block.isEmbed), hasLength(1));
      expect(elementsOf(tester).whereType<ImageElement>(), hasLength(1));
    });
  });

  testWidgets("the toolbar formats the box a right-click picked", (
    tester,
  ) async {
    mockClipboard(tester);
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'words');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byType(TextBoxEditor));
    await rightClick(
      tester,
      Offset(box.center.dx, box.top + TextBoxEditor.grabBand / 2),
    );
    await tester.tap(
      find
          .descendant(
            of: find.byType(MiniToolbar),
            matching: find.byTooltip('Bold  (Ctrl+B)'),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(blocksOf(tester).single.runs.single.marks.bold, isTrue);
  });
}
