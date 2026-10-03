import 'package:aantekening/src/editor/media_views.dart';
import 'package:aantekening/src/editor/ribbon/mini_toolbar.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/look/marks.dart';
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
    await tester.tap(menuItem('Set picture as background'));
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
      tester
          .widget<Mark>(
            find.descendant(
              of: find.ancestor(
                of: find.text('Set picture as background'),
                matching: find.byType(Row),
              ),
              matching: find.byType(Mark),
            ),
          )
          .shape,
      MarkShape.check,
      reason: 'ticked, as it is set',
    );
    await tester.tap(menuItem('Set picture as background'));
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
        of: find.widgetWithText(AlertDialog, 'TikZ picture'),
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

  testWidgets('everything picked stays picked under a right-click, and the '
      'toolbar formats every box in it', (tester) async {
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
    await tester.tap(
      find
          .descendant(
            of: find.byType(MiniToolbar),
            matching: find.byTooltip('Bold  (Ctrl+B)'),
          )
          .first,
    );
    await tester.pumpAndSettle();

    for (final element in elementsOf(tester)) {
      expect(
        (element as TextElement).blocks.single.runs.single.marks.bold,
        isTrue,
      );
    }
  });
}
