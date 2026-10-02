import 'package:aantekening/src/editor/ribbon/ribbon.dart';
import 'package:aantekening/src/editor/ribbon/ribbon_items.dart'
    show RibbonButton, RibbonLargeButton, mathGalleryOf;
import 'package:aantekening/src/editor/ribbon/ribbon_layout.dart';
import 'package:aantekening/src/editor/ribbon/ribbon_state.dart';
import 'package:aantekening/src/editor/text/math_templates.dart';
import 'package:aantekening/src/editor/text/typefaces.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

const String _bold = 'Bold  (Ctrl+B)';

RibbonCommands _commands(WidgetTester tester) =>
    tester.widget<Ribbon>(find.byType(Ribbon)).commands;

RibbonState _ribbon(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Ribbon)))
        .read(ribbonProvider);

RibbonLayout _layout(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Ribbon)))
        .read(ribbonLayoutProvider);

/// The button showing [tooltip].
RibbonButton _button(WidgetTester tester, String tooltip) =>
    tester.widget<RibbonButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(RibbonButton),
          )
          .first,
    );

/// Drags the button showing [tooltip] with a mouse and drops it where
/// [target] says, having first held it at each of [via] for [pause].
Future<void> _drag(
  WidgetTester tester,
  String tooltip, {
  required ValueGetter<Offset> target,
  List<Offset> via = const <Offset>[],
  Duration pause = Duration.zero,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byTooltip(tooltip)),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(10, 0));
  await tester.pump();
  for (final point in via) {
    await gesture.moveTo(point);
    await tester.pump();
    await tester.pump(pause);
    await tester.pump();
  }
  final end = target();
  await gesture.moveTo(end + const Offset(1, 0));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  test('every structure and symbol on the Math tab typesets', () {
    void expectTypesets(String latex, String what) => expect(
      () =>
          TexParser(RendererLatex.of(latex), const TexParserSettings()).parse(),
      returnsNormally,
      reason: '$what: $latex',
    );

    for (final gallery in RibbonItem.values.map(mathGalleryOf).nonNulls) {
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

  testWidgets('opens on Home, its sections named beneath them', (tester) async {
    await openEditor(tester, store, pageId);

    for (final tab in RibbonTab.values) {
      expect(find.text(tab.label), findsOneWidget);
    }
    for (final section in <String>[
      'History',
      'Font',
      'Paragraph',
      'Styles',
      'Formulas',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  testWidgets('every tab lays out, even in a narrow window', (tester) async {
    await openEditor(tester, store, pageId, size: const Size(420, 700));
    for (final tab in RibbonTab.values) {
      // The tabs scroll sideways where they do not fit.
      await tester.ensureVisible(find.text(tab.label));
      await tester.tap(find.text(tab.label));
      await tester.pumpAndSettle();
      expect(_ribbon(tester).tab, tab);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('text formatting stays put, greyed out with nothing to format', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    final place = tester.getCenter(find.byTooltip(_bold));
    expect(_button(tester, _bold).onPressed, isNull);

    await startTextBox(tester);
    await type(tester, 'hello');
    expect(_button(tester, _bold).onPressed, isNotNull);
    expect(tester.getCenter(find.byTooltip(_bold)), place);

    // Pressing Bold leaves the caret in the box: what is typed next is bold.
    await tester.tap(find.byTooltip(_bold), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await type(tester, ' world');
    final runs = blocksOf(tester).single.runs;
    expect(runs.last.text, ' world');
    expect(runs.last.marks.bold, isTrue);
    expect(runs.first.marks.bold, isFalse);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byTooltip(_bold)), place);
    expect(_button(tester, _bold).onPressed, isNull);
  });

  testWidgets("a tool's shortcut brings its tab forward", (tester) async {
    await openEditor(tester, store, pageId);
    final canvas = _commands(tester).canvas;

    await press(tester, LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.pen);
    expect(_ribbon(tester).tab, RibbonTab.draw);
    expect(find.text('Thickness'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.select);
    expect(_ribbon(tester).tab, RibbonTab.home);

    await press(tester, LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.eraser);
    expect(_ribbon(tester).tab, RibbonTab.draw);

    // Picking a tool on the ribbon leaves its tab showing.
    await tester.tap(find.byTooltip('Highlighter  (H)'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.highlighter);
    expect(_ribbon(tester).tab, RibbonTab.draw);
  });

  testWidgets('a colour on the Draw tab takes up that pen in it', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    final canvas = _commands(tester).canvas;
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pen colour: Blue'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.pen);
    expect(canvas.penSettings.color, 0xFF1A73E8);

    await tester.tap(find.byTooltip('Highlighter  (H)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Highlighter colour: Green'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.highlighter);
    expect(canvas.highlighterSettings.color, 0xFF34A853);
    expect(canvas.penSettings.color, 0xFF1A73E8, reason: 'the pen keeps its');

    await tester.tap(find.byTooltip('Highlighter: 40 pt'));
    await tester.pumpAndSettle();
    expect(canvas.highlighterSettings.width, 40);
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
    final canvas = _commands(tester).canvas;
    List<SheetTemplate> templates() =>
        canvas.document.canvas.sheetsShown!.templates;

    // Asked, and Enter takes what the sheet in view is printed with.
    await tester.tap(find.byTooltip(RegExp('^Add sheet')).first);
    await tester.pumpAndSettle();
    expect(find.text('Add a sheet after sheet 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(templates(), <SheetTemplate>[
      SheetTemplate.lined,
      SheetTemplate.lined,
    ]);

    // A click takes another; the new sheet is shown.
    await tester.tap(find.byTooltip(RegExp('^Add sheet')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    expect(templates(), hasLength(3));
    expect(templates()[canvas.currentSheet], SheetTemplate.music);

    final shown = canvas.currentSheet;
    // The ribbon scrolls to it, in a window too narrow for all of Home.
    await tester.ensureVisible(find.byTooltip(RegExp('^Move sheet up')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(RegExp('^Move sheet up')));
    await tester.pumpAndSettle();
    expect(templates()[shown - 1], SheetTemplate.music);
    expect(canvas.currentSheet, shown - 1, reason: 'followed');
  });

  testWidgets('a shape chosen on the Draw tab is dragged out in the pen', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    final canvas = _commands(tester).canvas;
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is RibbonLargeButton && widget.label == 'Shapes',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Axes in 3D'));
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.shape);
    expect(canvas.shapeKind, ShapeKind.axes3d);

    // A colour leaves the shape tool in hand: the inverse of what is
    // beneath among them.
    await tester.tap(find.byTooltip('Pen colour: Inverted'));
    await tester.pumpAndSettle();
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

    await press(tester, LogicalKeyboardKey.keyV);
    await press(tester, LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(canvas.tool, CanvasTool.shape);
    expect(_ribbon(tester).tab, RibbonTab.draw);
  });

  testWidgets('a font chosen on the ribbon sets the text in it, and stays '
      'through other formatting', (tester) async {
    await tester.runAsync(() async {
      final page = PageDocument.empty(id: pageId).withElementAdded(
        const TextElement(
          id: 'note',
          frame: Frame(x: 100, y: 100, width: 300, height: 60),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            TextBlock(runs: <TextRun>[TextRun('a few words')]),
          ],
        ),
      );
      await store.pages.saveDocument(pageId, page);
    });
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
    final canvas = _commands(tester).canvas;
    TextMarks marks() => (canvas.document.elementById('note')! as TextElement)
        .blocks
        .single
        .runs
        .single
        .marks;
    canvas.select('note');
    await tester.pumpAndSettle();

    Future<void> choose(String font) async {
      await tester.tap(find.byTooltip('Font'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text(font).last);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Font'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('ON THIS COMPUTER'), findsOneWidget);
    expect(find.text('DejaVu Sans'), findsOneWidget);
    await tester.tap(find.text('IBM Plex Mono'));
    await tester.pumpAndSettle();
    expect(marks().font, 'IBM Plex Mono');
    expect(find.text('IBM Plex Mono'), findsOneWidget, reason: 'its name');

    await tester.tap(find.byTooltip(_bold), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(marks().bold, isTrue);
    expect(marks().font, 'IBM Plex Mono');

    await choose('Default');
    expect(marks().font, isNull);
  });

  testWidgets('text can be the inverse of what is beneath it', (tester) async {
    await tester.runAsync(() async {
      final page = PageDocument.empty(id: pageId).withElementAdded(
        const TextElement(
          id: 'note',
          frame: Frame(x: 100, y: 100, width: 300, height: 60),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            TextBlock(runs: <TextRun>[TextRun('over a picture')]),
          ],
        ),
      );
      await store.pages.saveDocument(pageId, page);
    });
    await openEditor(tester, store, pageId);
    final canvas = _commands(tester).canvas;
    canvas.select('note');
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('Text colour: choose'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inverted'));
    await tester.pumpAndSettle();
    final box = canvas.document.elementById('note')! as TextElement;
    expect(box.blocks.single.runs.single.marks.color, NoteColors.inverse);
    expect(
      find.byTooltip('Text colour\nText colour: Inverted'),
      findsOneWidget,
    );
  });

  testWidgets('formatting a selected box formats all of it, undone at once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final page = PageDocument.empty(id: pageId).withElementAdded(
        const TextElement(
          id: 'note',
          frame: Frame(x: 100, y: 100, width: 300, height: 60),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            TextBlock(
              runs: <TextRun>[
                TextRun('plain '),
                TextRun('strong', TextMarks(bold: true)),
              ],
            ),
          ],
        ),
      );
      await store.pages.saveDocument(pageId, page);
    });
    await openEditor(tester, store, pageId);
    final canvas = _commands(tester).canvas;
    TextElement box() => canvas.document.elementById('note')! as TextElement;

    canvas.select('note');
    await tester.pumpAndSettle();
    expect(_button(tester, _bold).onPressed, isNotNull);
    expect(_button(tester, _bold).selected, isFalse, reason: 'mixed');

    await tester.tap(find.byTooltip(_bold), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(box().blocks.single.runs.every((run) => run.marks.bold), isTrue);
    expect(_button(tester, _bold).selected, isTrue);

    canvas.undo();
    await tester.pumpAndSettle();
    expect(box().blocks.single.runs.first.marks.bold, isFalse);
  });

  testWidgets('a button dragged along its section stays where it is put', (
    tester,
  ) async {
    final preferences = Preferences.inMemory();
    await openEditor(tester, store, pageId, preferences: preferences);

    await _drag(
      tester,
      'Italic  (Ctrl+I)',
      target: () =>
          tester.getRect(find.byTooltip(_bold)).centerLeft + const Offset(3, 0),
    );

    final font = _layout(tester).itemsIn(RibbonGroup.font);
    expect(font.indexOf(RibbonItem.italic), font.indexOf(RibbonItem.bold) - 1);
    expect(preferences['ribbon.layout'], isNotNull, reason: 'saved');
    expect(
      RibbonLayout.fromJson(RibbonGroup.values, preferences['ribbon.layout']),
      _layout(tester),
    );
  });

  testWidgets('a button held over another tab can be dropped on it', (
    tester,
  ) async {
    final preferences = Preferences.inMemory();
    await openEditor(tester, store, pageId, preferences: preferences);

    await _drag(
      tester,
      'Undo  (Ctrl+Z)',
      via: <Offset>[tester.getCenter(find.text('Insert'))],
      pause: const Duration(milliseconds: 500),
      target: () =>
          tester.getRect(find.text('Picture')).centerLeft - const Offset(4, 0),
    );

    expect(_ribbon(tester).tab, RibbonTab.insert);
    expect(_layout(tester).itemsIn(RibbonGroup.files).first, RibbonItem.undo);
    expect(find.byTooltip('Undo  (Ctrl+Z)'), findsOneWidget);

    // And everything put back from the View tab.
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset ribbon'));
    await tester.pumpAndSettle();
    expect(_layout(tester).isDefault, isTrue);
    expect(preferences['ribbon.layout'], isNull);
  });

  testWidgets('a saved arrangement is there next time', (tester) async {
    final moved = RibbonLayout.defaults(RibbonGroup.values)
        .move(RibbonItem.pen, RibbonGroup.history, 0);
    final preferences = Preferences.inMemory(<String, Object?>{
      'ribbon.layout': moved.toJson(),
    });
    await openEditor(tester, store, pageId, preferences: preferences);

    expect(_layout(tester), moved);
    expect(find.byTooltip('Pen  (P)'), findsOneWidget, reason: 'on Home');
  });

  testWidgets('the ribbon folds away to its tabs', (tester) async {
    await openEditor(tester, store, pageId);
    final canvasTop = tester.getTopLeft(find.byType(InfiniteCanvas)).dy;

    await press(tester, LogicalKeyboardKey.f1, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Font'), findsNothing);
    expect(
      tester.getTopLeft(find.byType(InfiniteCanvas)).dy,
      lessThan(canvasTop - 50),
    );

    // Opening a tab brings it back.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Font'), findsOneWidget);
  });
}
