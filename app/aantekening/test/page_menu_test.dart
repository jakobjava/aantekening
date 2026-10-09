import 'dart:math' as math;

import 'package:aantekening/src/editor/media_views.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/look/glass.dart';
import 'package:aantekening/src/modes/key_guide.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart' show TikzView;
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
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

  KeyGuideRow row(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(KeyGuideRow)),
  );

  Finder menuItem(String label) =>
      find.descendant(of: find.byType(KeyGuideRow), matching: find.text(label));

  bool enabled(WidgetTester tester, String label) =>
      row(tester, label).action.enabled;

  testWidgets('Shift+F10, or the Menu key, opens for the text picked the '
      'menu a right-click opens, leaving it picked', (tester) async {
    mockClipboard(tester);
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'keep cut');
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);

    await press(tester, LogicalKeyboardKey.f10, shift: true);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KeyGuideRow, 'Cut'), findsOneWidget);
    await tester.tap(find.widgetWithText(KeyGuideRow, 'Cut'));
    await tester.pumpAndSettle();
    expect(textOf(tester), 'keep ');

    await press(tester, LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(KeyGuideRow, 'Paste'), findsOneWidget);
  });

  testWidgets('a right-click on the paper opens the menu there, with '
      'nothing picked to cut, copy or delete', (tester) async {
    mockClipboard(tester);
    await openEditor(tester, store, pageId);
    await rightClick(tester, const Offset(600, 500));

    expect(menuItem('Text'), findsOneWidget);
    expect(enabled(tester, 'Cut'), isFalse);
    expect(enabled(tester, 'Copy'), isFalse);
    expect(enabled(tester, 'Paste'), isTrue);
    expect(enabled(tester, 'Delete'), isFalse);
    final rows = find
        .byType(KeyGuideRow)
        .evaluate()
        .map((row) => tester.getRect(find.byWidget(row.widget)));
    expect(
      rows.map((row) => row.left).reduce(math.min),
      lessThanOrEqualTo(600),
      reason: 'over where it was clicked',
    );
    expect(rows.map((row) => row.right).reduce(math.max), greaterThan(600));
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
    await tester.tap(menuItem('Set as background'));
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
    expect(menuItem('Set as background'), findsNothing, reason: 'it is');
    await tester.tap(menuItem('Take out of the background'));
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

    testWidgets('cut, is pasted onto the paper as a picture of its own', (
      tester,
    ) async {
      mockClipboard(tester);
      await savePage(tester, (asset) => <NoteElement>[boxWith(asset)]);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyX, control: true);
      await tester.pumpAndSettle();

      // A click on the paper leaves a bare caret there; pasted at it, the
      // picture lies on the page by itself.
      await tester.tapAt(const Offset(560, 520), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();

      final pictures = elementsOf(tester).whereType<ImageElement>().toList();
      expect(pictures, hasLength(1));
      expect(pictures.single.frame.width, 120);
      expect(pictures.single.frame.height, 60);
      final boxes = elementsOf(tester).whereType<TextElement>();
      expect(boxes.single.id, 'box', reason: 'no box made for it');
      expect(boxes.single.blocks.any((block) => block.isEmbed), isFalse);

      // Pasted again with nothing being typed, it goes on the page too.
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();
      expect(elementsOf(tester).whereType<ImageElement>(), hasLength(2));
      expect(elementsOf(tester).whereType<TextElement>(), hasLength(1));
    });

    testWidgets('a TikZ picture cut out goes on the page as itself, and '
        'its source is edited there', (tester) async {
      mockClipboard(tester);
      const source = r'\tikz \draw (0,0) -- (2,1);';
      await tester.runAsync(
        () => store.pages.saveDocument(
          pageId,
          PageDocument(
            id: pageId,
            elements: const <NoteElement>[
              TextElement(
                id: 'box',
                frame: Frame(x: 100, y: 100, width: 320, height: 160),
                createdAt: 0,
                updatedAt: 0,
                blocks: <TextBlock>[
                  TextBlock(runs: <TextRun>[TextRun('above')]),
                  TextBlock.embedded(BlockEmbed.tikz(source)),
                ],
              ),
            ],
          ),
        ),
      );
      await openEditor(tester, store, pageId);
      final drawn = tester.getRect(find.byType(TikzView));
      await tester.tapAt(drawn.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyX, control: true);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(560, 520), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();

      final picture = elementsOf(tester).whereType<TikzElement>().single;
      expect(picture.source, source);
      expect(picture.frame.width, closeTo(drawn.width, 1), reason: 'as drawn');
      expect(picture.frame.height, closeTo(drawn.height, 1));
      expect(elementsOf(tester).whereType<TextElement>().single.id, 'box');
      expect(
        tester.getRect(find.byType(TikzView)).width,
        closeTo(drawn.width, 1),
      );

      // Its source is edited from its menu, as one step.
      final on = tester.getCenter(find.byType(TikzView));
      await rightClick(tester, on);
      await tester.tap(menuItem('Edit TikZ source'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.widgetWithText(GlassDialog, 'TikZ picture'),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, r'\tikz \draw (0,0) -- (2,2);');
      await tester.pumpAndSettle();
      await tester.enterText(field, r'\tikz \draw (0,0) -- (2,3);');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter, control: true);
      await tester.pumpAndSettle();
      final edited = elementsOf(tester).whereType<TikzElement>().single;
      expect(edited.source, r'\tikz \draw (0,0) -- (2,3);');
      expect(
        edited.frame.height / edited.frame.width,
        greaterThan(picture.frame.height / picture.frame.width),
        reason: 'as tall as its drawing makes it',
      );
      canvasOf(tester).undo();
      await tester.pumpAndSettle();
      expect(elementsOf(tester).whereType<TikzElement>().single.source, source);
    });

    testWidgets('a TikZ picture is stretched by a side, and stays '
        'stretched as its source changes', (tester) async {
      mockClipboard(tester);
      await savePage(
        tester,
        (_) => const <NoteElement>[
          TikzElement(
            id: 'tikz',
            frame: Frame(x: 100, y: 100, width: 200, height: 100),
            createdAt: 0,
            updatedAt: 0,
            source: r'\tikz \draw (0,0) -- (2,1);',
          ),
        ],
      );
      await openEditor(tester, store, pageId);
      TikzElement tikz() => elementsOf(tester).whereType<TikzElement>().single;
      double drawnAspect() {
        final drawn = tester.getSize(find.byType(TikzView));
        return drawn.height / drawn.width;
      }

      // Its lower side dragged down, it is stretched, and fills its frame.
      final canvas = tester.getTopLeft(find.byType(InfiniteCanvas));
      await tester.tapAt(
        canvas + const Offset(200, 150),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final before = tikz().frame;
      final gesture = await tester.startGesture(
        canvas +
            Offset(200, 100 + before.height + SelectionHandles.outlineInset),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 30));
      await gesture.up();
      await tester.pumpAndSettle();
      final stretched = tikz().frame;
      expect(stretched.width, closeTo(before.width, 0.01));
      expect(stretched.height, closeTo(before.height + 60, 0.5));
      final shown = tester.getRect(find.byType(TikzView));
      expect(shown.height, closeTo(stretched.height, 0.5));
      expect(shown.width, closeTo(stretched.width, 0.5));
      final stretch = stretched.height / stretched.width / drawnAspect();

      // Its source changed, it keeps its width and its stretch.
      await rightClick(tester, shown.center);
      await tester.tap(menuItem('Edit TikZ source'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(GlassDialog, 'TikZ picture'),
          matching: find.byType(TextField),
        ),
        r'\tikz \draw (0,0) -- (2,3);',
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter, control: true);
      await tester.pumpAndSettle();
      final edited = tikz().frame;
      expect(edited.width, closeTo(stretched.width, 0.01));
      expect(
        edited.height / edited.width / drawnAspect(),
        closeTo(stretch, 0.01),
      );

      // Undone, it is as it was before, and stays so.
      canvasOf(tester).undo();
      await tester.pumpAndSettle();
      expect(tikz().frame.height, closeTo(stretched.height, 0.01));
    });

    testWidgets('is set as the background where it lies, in one step', (
      tester,
    ) async {
      mockClipboard(tester);
      await savePage(tester, (asset) => <NoteElement>[boxWith(asset)]);
      await openEditor(tester, store, pageId);
      final drawn = tester.getRect(find.byType(AssetImageView));

      await rightClick(tester, drawn.center);
      await tester.tap(menuItem('Set picture as background'));
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

  testWidgets('the menu formats the box a right-click picked', (tester) async {
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
    await tester.tap(menuItem('Text'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Bold'));
    await tester.pumpAndSettle();

    expect(blocksOf(tester).single.runs.single.marks.bold, isTrue);
  });

  testWidgets('everything picked stays picked under a right-click, and the '
      'menu formats every box in it', (tester) async {
    mockClipboard(tester);
    TextElement box(String id, double y) => TextElement(
      id: id,
      frame: Frame(x: 120, y: y, width: 200, height: 50),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[
        TextBlock(runs: <TextRun>[TextRun(id)]),
      ],
    );
    await savePage(
      tester,
      (_) => <NoteElement>[box('one', 160), box('two', 300)],
    );
    await openEditor(tester, store, pageId);

    await press(tester, LogicalKeyboardKey.keyA, control: true);
    await tester.pumpAndSettle();
    expect(canvasOf(tester).selection, <String>{'one', 'two'});

    // In the text of one of them, not on its band.
    await rightClick(
      tester,
      tester.getCenter(find.byType(TextBoxEditor).first) + const Offset(0, 8),
    );
    expect(canvasOf(tester).selection, <String>{'one', 'two'});
    // From the keys, as from the pointer.
    await press(tester, LogicalKeyboardKey.keyF);
    await press(tester, LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();

    for (final element in elementsOf(tester)) {
      expect(
        (element as TextElement).blocks.single.runs.single.marks.bold,
        isTrue,
      );
    }
  });
}
