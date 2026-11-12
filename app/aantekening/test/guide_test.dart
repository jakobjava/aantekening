import 'package:aantekening/src/editor/jump_labels.dart';
import 'package:aantekening/src/editor/page_editor.dart';
import 'package:aantekening/src/editor/text/math_templates.dart';
import 'package:aantekening/src/editor/text/typefaces.dart';
import 'package:aantekening/src/look/chooser.dart';
import 'package:aantekening/src/look/glass.dart';
import 'package:aantekening/src/modes/editor_mode.dart';
import 'package:aantekening/src/modes/key_guide.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

CanvasController _canvas(WidgetTester tester) =>
    tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

EditorMode _mode(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PageEditor)))
        .read(editorModeProvider);

/// The guide's row for [label].
KeyGuideRow _row(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(KeyGuideRow)),
);

/// The guide's title, as it shows it.
Finder _guideTitled(String title) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is Semantics && (widget.properties.header ?? false),
  ),
  matching: find.text(title),
);

/// A page holding one text box, [runs] in it.
Future<void> _pageWithBox(
  WidgetTester tester,
  AantekeningStore store,
  String pageId, {
  List<TextRun> runs = const <TextRun>[TextRun('a few words')],
}) => tester.runAsync(
  () => store.pages.saveDocument(
    pageId,
    PageDocument.empty(id: pageId).withElementAdded(
      TextElement(
        id: 'note',
        frame: const Frame(x: 100, y: 100, width: 300, height: 60),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[TextBlock(runs: runs)],
      ),
    ),
  ),
);

void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  test('every structure and symbol offered typesets', () {
    void expectTypesets(String latex, String what) => expect(
      () => TexParser(latex, const TexParserSettings()).parse(),
      returnsNormally,
      reason: '$what: $latex',
    );

    for (final gallery in <MathGallery>[
      ...MathGalleries.structures,
      ...MathGalleries.symbols,
    ]) {
      expectTypesets(gallery.icon, gallery.name);
      for (final template in gallery.templates) {
        expectTypesets(template.preview, template.name);
        expectTypesets(
          template.latex.replaceAll(MathTemplate.caret, 'x'),
          template.name,
        );
      }
    }
  });

  testWidgets('d draws with the pen used last, v selects, Esc goes back, '
      'and typing in a box is insert mode', (tester) async {
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    expect(_mode(tester), EditorMode.normal);

    await typeKeys(tester, 'd');
    expect(canvas.tool, CanvasTool.pen);
    expect(_mode(tester), EditorMode.draw);

    await typeKeys(tester, 'h');
    expect(canvas.tool, CanvasTool.highlighter);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.select);
    expect(_mode(tester), EditorMode.normal);

    await typeKeys(tester, 'd');
    expect(canvas.tool, CanvasTool.highlighter, reason: 'the one used last');
    await press(tester, LogicalKeyboardKey.escape);
    await typeKeys(tester, 'v');
    expect(canvas.tool, CanvasTool.lasso);
    expect(_mode(tester), EditorMode.select);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await typeKeys(tester, 'i');
    expect(_mode(tester), EditorMode.insert);
    await type(tester, 'words');
    expect(textOf(tester), 'words', reason: 'the keys type');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_mode(tester), EditorMode.normal);
  });

  testWidgets('keys count however fast they come: none is lost to the menu '
      'opening, nor to a box on its way', (tester) async {
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);

    // Space held into d and e, not a frame between them: the eraser.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await typeKeysAtOnce(tester, 'de');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.eraser);
    expect(find.byType(KeyGuideRow), findsNothing, reason: 'closed');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // i, and the words straight after it, all in the new box.
    await typeKeysAtOnce(tester, 'iFast words');
    await tester.pumpAndSettle();
    expect(textOf(tester), 'Fast words');
    expect(_mode(tester), EditorMode.insert);
  });

  testWidgets('the menu opens in the middle, wherever the pointer is, and '
      'holds still as its layers open', (tester) async {
    await openEditor(tester, store, pageId);
    Rect guide() => tester.getRect(
      find
          .ancestor(
            of: find.byType(KeyGuideRow).first,
            matching: find.byType(Glass),
          )
          .first,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(100, 600));
    await press(tester, LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final menu = guide();
    expect(menu.center.dx, closeTo(600, 1), reason: 'the middle');

    // A smaller layer opened from it leaves it where it was, as large.
    await typeKeys(tester, 'w');
    expect(_guideTitled('Window'), findsOneWidget);
    expect(guide(), menu);
    await press(tester, LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(guide(), menu);
  });

  testWidgets('the menu is moved by its title and sized by its edge, opens '
      'again where it was left, and a double-click puts it back', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    Rect menu() => tester.getRect(
      find
          .ancestor(
            of: find.byType(KeyGuideRow).first,
            matching: find.byType(Glass),
          )
          .first,
    );
    Future<void> open() async {
      await press(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
    }

    await open();
    final before = menu();
    await tester.dragFrom(
      tester.getCenter(_guideTitled('Menu')),
      const Offset(-120, 80),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(menu().topLeft, before.topLeft + const Offset(-120, 80));

    final moved = menu();
    await tester.dragFrom(
      Offset(moved.right - 2, moved.center.dy),
      const Offset(-150, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    // Its edge lands on the grid panes are sized on, the nearest to where
    // it was let go.
    expect(menu().width, closeTo(moved.width - 150, 4.5));
    expect(find.byType(KeyGuideRow), findsWidgets, reason: 'still all there');
    final sized = menu();

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await open();
    expect(menu(), sized);

    final strip = Offset(menu().center.dx, menu().top + 9);
    await tester.tapAt(strip, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(strip, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(menu(), before);
  });

  testWidgets('Space opens the menu, whose keys open layers and run what '
      'they name; Backspace goes back a layer', (tester) async {
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);

    await press(tester, LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_guideTitled('Menu'), findsOneWidget);
    await typeKeys(tester, 'd');
    expect(_guideTitled('Draw'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_guideTitled('Menu'), findsOneWidget);

    await typeKeys(tester, 'de');
    expect(find.byType(KeyGuideRow), findsNothing, reason: 'closed');
    expect(canvas.tool, CanvasTool.eraser);

    // A key a layer has nothing for closes it, doing nothing.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'Q');
    expect(find.byType(KeyGuideRow), findsNothing);
    expect(canvas.tool, CanvasTool.eraser);
  });

  testWidgets('Space held moves the page with the pointer, and opens no '
      'menu as it is let go', (tester) async {
    await openEditor(tester, store, pageId);
    // Something far off, for the page to reach as far as.
    final canvas = _canvas(tester)
      ..addElement(
        const TextElement(
          id: 'far',
          frame: Frame(x: 4000, y: 4000, width: 200, height: 60),
          createdAt: 0,
          updatedAt: 0,
        ),
      );
    await tester.pump();
    final before = canvas.viewport.origin;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.dragFrom(
      const Offset(600, 500),
      const Offset(-120, -200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(canvas.viewport.origin, isNot(before));
    expect(find.byType(KeyGuideRow), findsNothing);
  });

  testWidgets('g waits before showing what comes after it', (tester) async {
    await openEditor(tester, store, pageId);
    await typeKey(tester, 'g');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KeyGuideRow), findsNothing, reason: 'not yet');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_guideTitled('Go'), findsOneWidget, reason: 'once the keys pause');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(KeyGuideRow), findsNothing);
  });

  testWidgets('Ctrl+Space opens the menu while typing, and the caret is '
      'back in the box after', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'loud');
    await press(tester, LogicalKeyboardKey.home);
    await press(tester, LogicalKeyboardKey.end, shift: true);

    await press(tester, LogicalKeyboardKey.space, control: true);
    await tester.pumpAndSettle();
    expect(_guideTitled('Menu'), findsOneWidget);
    await typeKeys(tester, 'fb');
    expect(blocksOf(tester).single.runs.single.marks.bold, isTrue);

    await type(tester, '!');
    expect(textOf(tester), '!', reason: 'typed over the selection');
  });

  testWidgets('a colour in Draw takes up that pen in it; in draw mode the '
      'digits pick the palette, and [ and ] the width', (tester) async {
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'dc');
    expect(_guideTitled('Pen'), findsOneWidget);
    await tester.tap(find.byTooltip('Blue'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.pen);
    expect(canvas.penSettings.color, 0xFF1A73E8);

    await typeKeys(tester, 'h3');
    expect(canvas.tool, CanvasTool.highlighter);
    expect(canvas.highlighterSettings.color, 0xFFD93025);
    expect(canvas.penSettings.color, 0xFF1A73E8, reason: 'the pen keeps its');

    final width = canvas.highlighterSettings.width;
    await typeKeys(tester, ']');
    expect(canvas.highlighterSettings.width, greaterThan(width));
    await typeKeys(tester, '[[');
    expect(canvas.highlighterSettings.width, lessThan(width));
  });

  testWidgets('in draw mode - draws the line dashed, dotted and whole '
      'again, f fills shapes and o more strongly; and the pen is kept so '
      'for the next page', (tester) async {
    final preferences = Preferences.inMemory();
    await openEditor(tester, store, pageId, preferences: preferences);
    final canvas = _canvas(tester);

    await typeKeys(tester, 'd-');
    expect(canvas.penSettings.line, InkLine.dashed);
    await typeKeys(tester, '-');
    expect(canvas.penSettings.line, InkLine.dotted);
    await typeKeys(tester, '--');
    expect(canvas.penSettings.line, InkLine.dashed);

    expect(canvas.penSettings.fill, isNull);
    await typeKeys(tester, 'f');
    expect(_guideTitled('Fill shapes'), findsOneWidget);
    await tester.tap(find.byTooltip('Green'));
    await tester.pumpAndSettle();
    expect(canvas.penSettings.fill, 0x8034A853, reason: 'half as strong');
    await typeKeys(tester, 'o');
    expect(canvas.penSettings.fill, 0xFF34A853);
    await typeKeys(tester, 'o');
    expect(canvas.penSettings.fill, 0x4034A853);

    // A shape dragged out now is dashed and filled.
    await typeKeys(tester, 's');
    await tester.tap(find.byTooltip('Rectangle'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(const Offset(500, 420));
    await gesture.up();
    await tester.pumpAndSettle();
    final shape = canvas.document.elements.whereType<InkElement>().single;
    expect(shape.strokes.single.line, InkLine.dashed);
    expect(shape.strokes.single.fill, 0x4034A853);

    expect(preferences['pen.ink'], <String, Object?>{
      'pen': <String, Object?>{
        'color': 0xFF000000,
        'width': 2.2,
        'line': 'dashed',
        'fill': 0x4034A853,
      },
      'highlighter': <String, Object?>{'color': 0xFFFFD60A, 'width': 22.0},
    });

    // No fill takes it away again.
    await typeKeys(tester, 'f');
    await tester.tap(find.byTooltip('No fill'));
    await tester.pumpAndSettle();
    expect(canvas.penSettings.fill, isNull);
  });

  testWidgets('a page is drawn on with the pen as it was last set', (
    tester,
  ) async {
    await openEditor(
      tester,
      store,
      pageId,
      preferences: Preferences.inMemory(<String, Object?>{
        'pen.ink': <String, Object?>{
          'pen': <String, Object?>{
            'color': 0xFF1A73E8,
            'width': 5.0,
            'line': 'dotted',
            'fill': 0x80D93025,
          },
          'highlighter': <String, Object?>{
            'color': 0xFF34A853,
            'width': 30.0,
            // A highlighter is never dashed nor filled, whatever is kept.
            'line': 'dashed',
            'fill': 0xFF000000,
          },
        },
      }),
    );
    final canvas = _canvas(tester);

    expect(
      canvas.penSettings,
      const PenSettings(
        color: 0xFF1A73E8,
        width: 5,
        line: InkLine.dotted,
        fill: 0x80D93025,
      ),
    );
    expect(
      canvas.highlighterSettings,
      PenSettings.defaultHighlighter.copyWith(color: 0xFF34A853, width: 30),
    );
  });

  testWidgets('in select mode s draws the ink picked another way: its '
      'colour, width and line, and what closes filled', (tester) async {
    InkStroke through(List<double> xs, List<double> ys) => InkStroke.fromPoints(
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 2.2,
      xs: xs,
      ys: ys,
    );
    await tester.runAsync(
      () => store.pages.saveDocument(
        pageId,
        PageDocument.empty(id: pageId).withElementAdded(
          InkElement(
            id: 'drawn',
            frame: const Frame(x: 0, y: 0, width: 0, height: 0),
            createdAt: 0,
            updatedAt: 0,
          ).withStrokes(<InkStroke>[
            through(
              <double>[100, 300, 300, 100, 100],
              <double>[100, 100, 200, 200, 100],
            ),
            through(<double>[100, 300], <double>[300, 300]),
          ]),
        ),
      ),
    );
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    List<InkStroke> strokes() =>
        (canvas.document.elements.single as InkElement).strokes;

    // With nothing picked there is none to draw another way.
    await typeKeys(tester, 'vs');
    expect(_guideTitled('Ink picked'), findsNothing);
    await typeKeys(tester, 'as');
    expect(_guideTitled('Ink picked'), findsOneWidget);

    await typeKeys(tester, '-');
    expect(strokes().map((stroke) => stroke.line), <InkLine>[
      InkLine.dashed,
      InkLine.dashed,
    ]);
    await typeKeys(tester, ']');
    expect(strokes().first.width, 3.5);

    await typeKeys(tester, 'f');
    await tester.tap(find.byTooltip('Yellow'));
    await tester.pumpAndSettle();
    expect(strokes().first.fill, 0x80FFD60A);
    expect(strokes().last.fill, isNull, reason: 'it goes round nothing');

    await typeKeys(tester, 'sc');
    await tester.tap(find.byTooltip('Red'));
    await tester.pumpAndSettle();
    expect(strokes().every((stroke) => stroke.color == 0xFFD93025), isTrue);
    expect(canvas.selection, <String>{'drawn'}, reason: 'still picked');

    // Each of those is a step undo takes back.
    canvas.undo();
    expect(strokes().first.color, 0xFF000000);

    // A right-click on it offers the same, in the menu.
    await rightClick(
      tester,
      tester.getTopLeft(find.byType(InfiniteCanvas)) + const Offset(200, 150),
    );
    expect(_guideTitled('Menu'), findsOneWidget);
    await typeKeys(tester, 'I');
    expect(_guideTitled('Ink picked'), findsOneWidget);
  });

  testWidgets('a sheet is added printed as chosen, and moved', (tester) async {
    await store.pages.saveDocument(
      pageId,
      PageDocument(
        id: pageId,
        canvas: CanvasSettings(
          layout: NoteLayout.pages,
          sheets: Sheets(templates: const <SheetTemplate>[SheetTemplate.lined]),
        ),
      ),
    );
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    List<SheetTemplate> templates() =>
        canvas.document.canvas.sheetsShown!.templates;

    // Asked, and Enter takes what the sheet in view is printed with.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sa');
    expect(find.text('Add a sheet after sheet 1'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(templates(), <SheetTemplate>[
      SheetTemplate.lined,
      SheetTemplate.lined,
    ]);

    // A click takes another; the new sheet is shown.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sa');
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    expect(templates(), hasLength(3));
    expect(templates()[canvas.currentSheet], SheetTemplate.music);

    final shown = canvas.currentSheet;
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sk');
    expect(templates()[shown - 1], SheetTemplate.music);
    expect(canvas.currentSheet, shown - 1, reason: 'followed');

    // What the sheet in view is printed with, from its tiles.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sp');
    await tester.tap(find.byTooltip('Squared'));
    await tester.pumpAndSettle();
    expect(templates()[canvas.currentSheet], SheetTemplate.grid);
  });

  testWidgets('a sheet deleted is put back by its message, and only it', (
    tester,
  ) async {
    await store.pages.saveDocument(
      pageId,
      PageDocument(
        id: pageId,
        canvas: CanvasSettings(
          layout: NoteLayout.pages,
          sheets: Sheets(
            templates: const <SheetTemplate>[
              SheetTemplate.lined,
              SheetTemplate.grid,
            ],
          ),
        ),
      ),
    );
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    int sheets() => canvas.document.canvas.sheetsShown!.count;

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sd');
    expect(sheets(), 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(sheets(), 2, reason: 'put back');

    // Something done after it is not what the message undoes.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sd');
    canvas.addElement(
      const TextElement(
        id: 'after',
        frame: Frame(x: 100, y: 100, width: 300, height: 60),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          TextBlock(runs: <TextRun>[TextRun('later')]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(canvas.elementById('after'), isNotNull);
    expect(sheets(), 1);
  });

  testWidgets('a sheet is added turned landscape among upright ones', (
    tester,
  ) async {
    await store.pages.saveDocument(
      pageId,
      PageDocument(
        id: pageId,
        canvas: CanvasSettings(
          layout: NoteLayout.pages,
          sheets: Sheets(templates: const <SheetTemplate>[SheetTemplate.lined]),
        ),
      ),
    );
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    List<SheetOrientation> turned() =>
        canvas.document.canvas.sheetsShown!.orientations;

    // L turns it, and Enter adds it so.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sa');
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(turned(), <SheetOrientation>[
      SheetOrientation.portrait,
      SheetOrientation.landscape,
    ]);
    expect(canvas.currentSheet, 1, reason: 'shown');

    // Offered as the sheet in view is; a click turns it upright again.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'sa');
    await tester.tap(find.text('Portrait'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squared'));
    await tester.pumpAndSettle();
    expect(turned(), <SheetOrientation>[
      SheetOrientation.portrait,
      SheetOrientation.landscape,
      SheetOrientation.portrait,
    ]);
    expect(
      canvas.document.canvas.sheetsShown!.templates.last,
      SheetTemplate.grid,
    );
  });

  testWidgets('a shape chosen in Draw is dragged out in the pen', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'ds');
    await tester.tap(find.byTooltip('Axes in 3D'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.shape);
    expect(canvas.shapeKind, ShapeKind.axes3d);
    expect(_mode(tester), EditorMode.draw);

    // A colour leaves the shape tool in hand: the inverse of what is
    // beneath among them.
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'dcv');
    expect(canvas.tool, CanvasTool.shape);
    expect(canvas.penSettings.color, NoteColors.inverse);

    await tester.dragFrom(
      const Offset(500, 400),
      const Offset(240, 200),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final axes = canvas.document.elements.whereType<InkElement>().single;
    expect(axes.bounds.width, greaterThan(200));
    expect(
      axes.strokes.every((stroke) => stroke.color == NoteColors.inverse),
      isTrue,
    );
  });

  testWidgets('a font chosen by name sets the text in it, and stays through '
      'other formatting', (tester) async {
    await _pageWithBox(tester, store, pageId);
    await openEditor(
      tester,
      store,
      pageId,
      overrides: [
        installedTypefacesProvider.overrideWith(
          (ref) async => <String>['DejaVu Sans'],
        ),
      ],
    );
    final canvas = _canvas(tester);
    TextMarks marks() => (canvas.document.elementById('note')! as TextElement)
        .blocks
        .single
        .runs
        .single
        .marks;
    canvas.select('note');
    await tester.pumpAndSettle();

    Future<void> choose(String typed) async {
      await press(tester, LogicalKeyboardKey.space);
      await typeKeys(tester, 'ff');
      expect(find.byType(Chooser), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, typed);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'ff');
    expect(find.text('DejaVu Sans'), findsOneWidget, reason: 'installed');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await choose('plexmono');
    expect(marks().font, 'IBM Plex Mono');

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'fb');
    expect(marks().bold, isTrue);
    expect(marks().font, 'IBM Plex Mono');
    // The marks stay offered, for another; Esc is done with them.
    expect(find.byType(KeyGuideRow), findsWidgets);
    await press(tester, LogicalKeyboardKey.escape);

    await choose('default');
    expect(marks().font, isNull);
  });

  testWidgets('text can be the inverse of what is beneath it', (tester) async {
    await _pageWithBox(tester, store, pageId);
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    canvas.select('note');
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'ftv');
    final box = canvas.document.elementById('note')! as TextElement;
    expect(box.blocks.single.runs.single.marks.color, NoteColors.inverse);
  });

  testWidgets('formatting a selected box formats all of it, undone at once', (
    tester,
  ) async {
    await _pageWithBox(
      tester,
      store,
      pageId,
      runs: const <TextRun>[
        TextRun('plain '),
        TextRun('strong', TextMarks(bold: true)),
      ],
    );
    await openEditor(tester, store, pageId);
    final canvas = _canvas(tester);
    TextElement box() => canvas.document.elementById('note')! as TextElement;

    canvas.select('note');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.space);
    await typeKeys(tester, 'f');
    expect(_row(tester, 'Bold').action.enabled, isTrue);
    expect(_row(tester, 'Bold').action.checked, isFalse, reason: 'mixed');

    await typeKeys(tester, 'b');
    expect(box().blocks.single.runs.every((run) => run.marks.bold), isTrue);
    expect(_row(tester, 'Bold').action.checked, isTrue, reason: 'it stays');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    canvas.undo();
    await tester.pumpAndSettle();
    expect(box().blocks.single.runs.first.marks.bold, isFalse);
  });

  testWidgets('? shows the keys of the mode the page is in', (tester) async {
    await openEditor(tester, store, pageId);
    await typeKeys(tester, '?');
    expect(_guideTitled('Normal mode'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await typeKeys(tester, 'd?');
    expect(_guideTitled('Draw mode'), findsOneWidget);
  });

  group('moving about the page', () {
    TextElement box(String id, double x, double y) => TextElement(
      id: id,
      frame: Frame(x: x, y: y, width: 200, height: 40),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[TextBlock.plain(id)],
    );

    Future<CanvasController> openBoxes(WidgetTester tester) async {
      await tester.runAsync(
        () => store.pages.saveDocument(
          pageId,
          PageDocument(
            id: pageId,
            elements: <NoteElement>[
              box('first', 100, 100),
              box('beside', 500, 110),
              box('below', 110, 300),
            ],
          ),
        ),
      );
      await openEditor(tester, store, pageId);
      return _canvas(tester);
    }

    testWidgets('h, j, k and l go from box to box, the nearest that way', (
      tester,
    ) async {
      final canvas = await openBoxes(tester);

      await typeKeys(tester, 'j');
      expect(canvas.selection, <String>{'first'}, reason: 'the first in view');
      await typeKeys(tester, 'l');
      expect(canvas.selection, <String>{'beside'});
      await typeKeys(tester, 'h');
      expect(canvas.selection, <String>{'first'});
      await typeKeys(tester, 'j');
      expect(canvas.selection, <String>{'below'});
      await typeKeys(tester, 'j');
      expect(canvas.selection, <String>{'below'}, reason: 'nothing further');

      // In select mode they pick what is that way as well.
      await typeKeys(tester, 'vk');
      expect(canvas.selection, <String>{'below', 'first'});
    });

    testWidgets('f puts a label over each box, and its letter goes there', (
      tester,
    ) async {
      final canvas = await openBoxes(tester);

      await typeKeys(tester, 'f');
      expect(find.byType(JumpLabels), findsOneWidget);
      // In the order they are read: first, beside, below.
      expect(find.text('s', findRichText: true), findsOneWidget);
      await typeKeys(tester, 's');
      expect(find.byType(JumpLabels), findsNothing);
      expect(canvas.selection, <String>{'beside'});

      // A letter no label has gives up.
      await typeKeys(tester, 'fz');
      expect(find.byType(JumpLabels), findsNothing);
      expect(canvas.selection, <String>{'beside'});
    });

    testWidgets('u undoes and U redoes in select mode, as in the others', (
      tester,
    ) async {
      final canvas = await openBoxes(tester);
      await typeKeys(tester, 'jvd');
      expect(_mode(tester), EditorMode.select);
      expect(canvas.elementById('first'), isNull, reason: 'deleted');

      await typeKeys(tester, 'u');
      expect(canvas.elementById('first'), isNotNull, reason: 'undone');
      await typeKeys(tester, 'U');
      expect(canvas.elementById('first'), isNull, reason: 'redone');
      expect(_mode(tester), EditorMode.select);
    });

    testWidgets('m moves what is picked, a step or ten at a time', (
      tester,
    ) async {
      final canvas = await openBoxes(tester);
      await typeKeys(tester, 'j');
      await typeKeys(tester, 'mlllJ');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final moved = canvas.elementById('first')!.frame;
      expect(moved.x, 103);
      expect(moved.y, 110);
    });
  });
}
