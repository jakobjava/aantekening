import 'dart:math' as math;

import 'package:aantekening/src/editor/media_views.dart';
import 'package:aantekening/src/editor/text/block_paragraph.dart';
import 'package:aantekening/src/editor/text/block_widgets.dart';
import 'package:aantekening/src/editor/text/cheat_sheet.dart';
import 'package:aantekening/src/editor/text/formula_overlay.dart';
import 'package:aantekening/src/editor/text/formula_window.dart';
import 'package:aantekening/src/editor/text/shrink_to_width.dart';
import 'package:aantekening/src/editor/text/table_view.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/editor/text/text_styles.dart';
import 'package:aantekening/src/look/glass.dart';
import 'package:aantekening/src/modes/key_guide.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide TableCell;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

List<NoteElement> selectedOnCanvas(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is SelectionPainter,
                  ),
                )
                .painter!
            as SelectionPainter)
        .selected;

/// What draws the source of the formula being edited over the text.
RenderFormulaLayer formulaLayerOf(WidgetTester tester) =>
    tester.renderObject<RenderFormulaLayer>(find.byType(FormulaLayer));

/// The formula being edited, as it is drawn over the text.
FormulaOverlay overlayOf(WidgetTester tester) =>
    tester.widget<FormulaLayer>(find.byType(FormulaLayer)).formula!;

void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  testWidgets('clicking empty canvas starts a text box that takes typing', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    expect(find.byType(TextBoxEditor), findsNothing);

    await startTextBox(tester);
    expect(textBox(tester).isEditing, isTrue);

    await type(tester, 'Hello world');
    expect(textOf(tester), 'Hello world');
  });

  testWidgets('pressing the paper takes the box\'s frame away with the '
      'rest of its marks, before the press ends', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Hello');
    await tester.pumpAndSettle();
    expect(selectedOnCanvas(tester), hasLength(1));

    final press = await tester.startGesture(
      const Offset(900, 600),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(selectedOnCanvas(tester), isEmpty);
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a box shows nothing under the pointer; clicked, it is framed '
      'as a picture is, with handles for its width alone', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'hover');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    Iterable<Border> outlines() => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(TextBoxEditor),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>();

    // The mouse that started the box is still over the window.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(const Offset(900, 600));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(TextBoxEditor)));
    await tester.pumpAndSettle();
    expect(outlines(), isEmpty);
    expect(selectedOnCanvas(tester), isEmpty);

    await tester.tapAt(
      tester.getCenter(find.byType(TextBoxEditor)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(textBox(tester).isEditing, isTrue);
    final framed = selectedOnCanvas(tester);
    expect(framed.single.id, textBox(tester).element.id);
    final view = tester
        .widget<InfiniteCanvas>(find.byType(InfiniteCanvas))
        .controller
        .viewport;
    expect(
      SelectionHandles.positionsFor(framed, view).keys,
      unorderedEquals(<SelectionHandle>[
        SelectionHandle.left,
        SelectionHandle.right,
        SelectionHandle.rotate,
      ]),
    );
  });

  testWidgets('letters that are tool shortcuts are typed, not obeyed', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);

    // In normal mode d draws, v selects, p pastes and e is nothing.
    await type(tester, 'the pen');
    expect(textOf(tester), 'the pen');
    expect(textBox(tester).isEditing, isTrue, reason: 'no tool switched');
    expect(textBox(tester).interactive, isTrue);
  });

  testWidgets('Backspace edits the text rather than deleting the box', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'abc');

    await press(tester, LogicalKeyboardKey.backspace);

    expect(find.byType(TextBoxEditor), findsOneWidget);
    expect(textOf(tester), 'ab');
  });

  testWidgets('Enter starts a new paragraph and "- " a bulleted list', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);

    await type(tester, 'Title');
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, '- first');

    final blocks = blocksOf(tester);
    expect(blocks, hasLength(2));
    expect(blocks[1].kind, TextBlockKind.bulleted);
    expect(blocks[1].plainText, 'first');
  });

  testWidgets('Arrow Up and Down move to the paragraph above and below', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'abc');
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, 'de');

    await press(tester, LogicalKeyboardKey.arrowUp);
    await type(tester, 'X');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await type(tester, 'Y');

    expect(blocksOf(tester).map((block) => block.plainText), <String>[
      'abXc',
      'deY',
    ]);
  });

  testWidgets('Ctrl+B makes the following text bold', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);

    await type(tester, 'plain ');
    await press(tester, LogicalKeyboardKey.keyB, control: true);
    await type(tester, 'bold');

    final runs = blocksOf(tester).single.runs;
    expect(runs.last.text, 'bold');
    expect(runs.last.marks.bold, isTrue);
    expect(runs.first.marks.bold, isFalse);
  });

  testWidgets('Ctrl+− strikes text through, and leaves the zoom alone', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    final canvas = tester
        .widget<InfiniteCanvas>(find.byType(InfiniteCanvas))
        .controller;
    final zoom = canvas.viewport.zoom;
    await startTextBox(tester);

    await press(tester, LogicalKeyboardKey.minus, control: true);
    await type(tester, 'struck');

    expect(blocksOf(tester).single.runs.single.marks.strikethrough, isTrue);
    expect(canvas.viewport.zoom, zoom, reason: 'typing had the key');
  });

  group('formulas', () {
    /// What the input method sees: the caret's paragraph, or in a formula
    /// being edited, its source alone. Formulas stand in a paragraph as a
    /// placeholder each, which is left out here.
    String typedLine(WidgetTester tester) =>
        (tester.testTextInput.editingState!['text'] as String).replaceAll(
          '\uFFFC',
          '',
        );

    Finder typesetInBox() => find.descendant(
      of: find.byType(TextBoxEditor),
      matching: find.byType(MathView),
    );

    Future<void> savePage(WidgetTester tester, List<TextRun> runs) =>
        tester.runAsync(() async {
          final page = PageDocument.empty(id: pageId).withElementAdded(
            TextElement(
              id: 'box',
              frame: const Frame(x: 100, y: 100, width: 300, height: 60),
              createdAt: 0,
              updatedAt: 0,
              blocks: <TextBlock>[TextBlock(runs: runs)],
            ),
          );
          await store.pages.saveDocument(pageId, page);
        });

    testWidgets('Alt+= starts a formula typed in the box, stored as LaTeX', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      await type(tester, 'Area ');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      expect(formulaLayerOf(tester).formulaBox, isNotNull);
      await type(tester, 'pi r^2');
      await tester.pumpAndSettle();

      expect(
        blocksOf(tester).single.runs.last,
        const TextRun.math(r'\pi r^2', MathMode.latex),
      );
      expect(inFormula(tester), isTrue);
      // Typed as its source, beneath its line; typeset in its place as it
      // is typed.
      expect(typedLine(tester), 'pi r^2');
      expect(tester.widget<MathView>(typesetInBox()).source, r'\pi r^2');

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await type(tester, ' units');

      final runs = blocksOf(tester).single.runs;
      expect(runs.map((run) => run.isMath), <bool>[false, true, false]);
      expect(runs[2].text, ' units');
      expect(inFormula(tester), isFalse);
      expect(formulaLayerOf(tester).formulaBox, isNull);
      expect(typesetInBox(), findsOneWidget);
    });

    testWidgets('Ctrl+M works on any keyboard layout', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      await press(tester, LogicalKeyboardKey.keyM, control: true);
      await tester.pumpAndSettle();
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.keyM, control: true);
      await tester.pumpAndSettle();

      expect(
        blocksOf(tester).single.runs.single,
        const TextRun.math('x', MathMode.latex),
      );
      expect(formulaLayerOf(tester).formulaBox, isNull);
    });

    testWidgets('switching syntax translates the formula', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'sum_(i=1)^n i^2');
      final latex = blocksOf(tester).single.runs.single.text;
      expect(latex, r'\sum_{i = 1}^n i^2');

      await press(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
      await tester.pumpAndSettle();
      expect(typedLine(tester), latex);

      // The menu's switch does the same.
      await press(tester, LogicalKeyboardKey.space, control: true);
      await typeKeys(tester, 'ml');
      expect(typedLine(tester), 'sum_(i = 1)^n i^2');
      expect(inFormula(tester), isTrue);
      expect(
        blocksOf(tester).single.runs.single.text,
        latex,
        reason: 'switching changes how it is typed, not what it is',
      );
    });

    testWidgets('the cheat sheet writes an example into the formula', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.space, control: true);
      await typeKeys(tester, 'mc');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x = ');

      final example = find.descendant(
        of: find.byType(CheatSheet),
        matching: find.text('ket(psi)'),
      );
      await tester.scrollUntilVisible(
        example,
        200,
        scrollable: find.descendant(
          of: find.byType(CheatSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(example);
      await tester.pumpAndSettle();

      expect(inFormula(tester), isTrue, reason: 'the caret stays put');
      expect(typedLine(tester), 'x = ket(psi) ');
      expect(blocksOf(tester).single.runs.single.text, r'x = \ket{\psi}');
    });

    testWidgets(r'typing $$ starts a formula in LaTeX', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      await type(tester, r'$$');
      await tester.pumpAndSettle();
      await type(tester, r'\alpha');

      expect(typedLine(tester), r'\alpha');
      expect(
        blocksOf(tester).single.runs.single,
        const TextRun.math(r'\alpha', MathMode.latex),
      );
    });

    testWidgets('a formula alone on its line stays at its start until '
        'it ends with #', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      TextAlign drawnAlign() => tester
          .widget<RichText>(
            find
                .descendant(
                  of: find.byType(TextBoxEditor),
                  matching: find.byType(RichText),
                )
                .first,
          )
          .textAlign;

      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x^2');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).single.align, BlockAlign.start);
      expect(drawnAlign(), TextAlign.start);

      // Opened again, it is centred by ending it with the mark.
      await tester.tapAt(
        tester.getCenter(find.byType(MathView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await type(tester, ' #');
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final centred = blocksOf(tester).first;
      expect(centred.align, BlockAlign.center);
      expect(centred.runs.single, const TextRun.math('x^2', MathMode.latex));
      expect(drawnAlign(), TextAlign.center);
      // Finished, it leaves the caret on a line of its own beneath.
      expect(blocksOf(tester), hasLength(2));
      expect(blocksOf(tester).last.align, BlockAlign.start);

      // Centred across the box, however narrow the formula.
      final box = tester.getRect(find.byType(TextBoxEditor));
      expect(
        tester.getCenter(find.byType(MathView)).dx,
        moreOrLessEquals(box.center.dx, epsilon: 1),
      );

      // Opened again, it shows the mark; taken away, the line goes back.
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(
        tester.getCenter(find.byType(MathView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(typedLine(tester), 'x^2 #');
      await press(tester, LogicalKeyboardKey.backspace);
      await press(tester, LogicalKeyboardKey.backspace);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).first.align, BlockAlign.start);
      expect(
        blocksOf(tester).first.runs.single,
        const TextRun.math('x^2', MathMode.latex),
      );
    });

    testWidgets('text goes on where lines start after a centred formula', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x^2 #');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await type(tester, 'so');
      await tester.pumpAndSettle();
      // The caret went on to the line beneath.
      final lines = blocksOf(tester);
      expect(lines, hasLength(2));
      expect(lines[0].align, BlockAlign.center);
      expect(lines[1].runs.single.text, 'so');
      expect(lines[1].align, BlockAlign.start);

      // A line broken off the formula's is not centred, nor is text typed
      // beside it, the formula no longer alone.
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(blocksOf(tester)[0].align, BlockAlign.center);
      expect(blocksOf(tester)[1].align, BlockAlign.start);
      await press(tester, LogicalKeyboardKey.backspace);
      await type(tester, ' is');
      await tester.pumpAndSettle();
      expect(blocksOf(tester)[0].runs.last.text, ' is');
      expect(blocksOf(tester)[0].align, BlockAlign.start);
    });

    testWidgets('a formula wider than its box is made smaller to fit', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final page = PageDocument.empty(id: pageId).withElementAdded(
          const TextElement(
            id: 'box',
            frame: Frame(x: 100, y: 100, width: 60, height: 60),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[
              TextBlock(
                runs: <TextRun>[
                  TextRun.math('a+b+c+d+e+f+g+h+i+j', MathMode.latex),
                ],
              ),
            ],
          ),
        );
        await store.pages.saveDocument(pageId, page);
      });
      await openEditor(tester, store, pageId);

      // Nothing overflows, and the formula lies within the box.
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(TextBoxEditor));
      final formula = tester.getRect(find.byType(ShrinkToWidth));
      expect(formula.right, lessThanOrEqualTo(box.right));
    });

    testWidgets('a formula opened and left unchanged keeps its LaTeX', (
      tester,
    ) async {
      await savePage(tester, const <TextRun>[
        TextRun('mean '),
        TextRun.math(r'\frac{a+b}{2}', MathMode.latex),
      ]);
      await openEditor(tester, store, pageId);

      await tester.tapAt(
        tester.getCenter(find.byType(MathView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(typedLine(tester), '(a + b)/2', reason: 'shown in Simple');
      expect(inFormula(tester), isTrue);

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).single.runs.last.text, r'\frac{a+b}{2}');
    });

    testWidgets('a TikZ picture in a line of text opens as LaTeX', (
      tester,
    ) async {
      const picture = r'\tikz \draw[->] (0,0) -- (1,0) node[right] {$x$};';
      await savePage(tester, const <TextRun>[
        TextRun('An arrow: '),
        TextRun.math(picture, MathMode.latex),
      ]);
      await openEditor(tester, store, pageId);
      expect(find.byType(TikzView), findsOneWidget);
      expect(blocksOf(tester).single.isEmbed, isFalse);

      await tester.tapAt(
        tester.getCenter(find.byType(TikzView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      expect(overlayOf(tester).source.text, picture, reason: 'Simple has none');

      // Simple is not offered, and its key leaves it as it is.
      await press(tester, LogicalKeyboardKey.space, control: true);
      await typeKeys(tester, 'm');
      final simple = tester.widget<KeyGuideRow>(
        find.ancestor(
          of: find.textContaining('switch to Simple'),
          matching: find.byType(KeyGuideRow),
        ),
      );
      expect(simple.action.enabled, isFalse);
      await typeKeys(tester, 'l');
      expect(overlayOf(tester).source.text, picture);
      expect(inFormula(tester), isTrue);
    });

    testWidgets('a TikZ picture on its own line is a picture in the text, '
        'its source edited from its menu', (tester) async {
      mockClipboard(tester);
      const picture =
          '\\begin{tikzpicture}\n'
          '  \\draw[->] (0,0) -- (1,0) node[right] {\$x\$};\n'
          '\\end{tikzpicture}';
      // Kept as a formula, as pages from before kept it.
      await savePage(tester, const <TextRun>[
        TextRun.math(picture, MathMode.latex),
      ]);
      await openEditor(tester, store, pageId);
      expect(find.byType(TikzView), findsOneWidget);

      // A click picks it, as it picks a picture; a corner resizes it.
      final drawn = tester.getRect(find.byType(EmbedBlock));
      final object = tester.getRect(find.byType(TikzView));
      await tester.tapAt(object.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(
        tester.widget<EmbedBlock>(find.byType(EmbedBlock)).selected,
        isTrue,
      );
      final gesture = await tester.startGesture(
        tester.getRect(find.byType(FittedBox)).bottomRight,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final resized = blocksOf(tester).single.embed!;
      expect(resized.kind, EmbedKind.tikz);
      expect(resized.width, greaterThan(object.width));
      expect(
        tester.getRect(find.byType(FittedBox)).width,
        closeTo(resized.width, 1),
      );
      expect(drawn.height, greaterThan(0));

      // Its source is edited from its menu, in a window of its own, the
      // picture drawn again as it changes.
      await rightClick(tester, tester.getCenter(find.byType(TikzView)));
      await tester.tap(find.text('Edit TikZ source'));
      await tester.pumpAndSettle();
      final window = find.widgetWithText(GlassDialog, 'TikZ picture');
      final field = find.descendant(
        of: window,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller!.text, picture);
      final changed = picture.replaceFirst('{\$x\$}', '{\$y\$}');
      await tester.enterText(field, changed);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).single.embed!.source, changed);
      expect(blocksOf(tester).single.embed!.width, resized.width);
      // Enter is a new line there; Ctrl+Enter finishes.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(window, findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter, control: true);
      await tester.pumpAndSettle();
      expect(window, findsNothing);
      expect(blocksOf(tester).single.embed!.source, changed);
    });

    /// Opens the source window of a TikZ picture drawn from [source], and
    /// finds its field.
    Future<Finder> openSourceOf(WidgetTester tester, String source) async {
      mockClipboard(tester);
      await tester.runAsync(
        () => store.pages.saveDocument(
          pageId,
          PageDocument(
            id: pageId,
            elements: <NoteElement>[
              TextElement(
                id: 'box',
                frame: const Frame(x: 100, y: 100, width: 300, height: 60),
                createdAt: 0,
                updatedAt: 0,
                blocks: <TextBlock>[
                  TextBlock.embedded(BlockEmbed.tikz(source)),
                ],
              ),
            ],
          ),
        ),
      );
      await openEditor(tester, store, pageId);
      await rightClick(tester, tester.getCenter(find.byType(TikzView)));
      await tester.tap(find.text('Edit TikZ source'));
      await tester.pumpAndSettle();
      return find.descendant(
        of: find.widgetWithText(GlassDialog, 'TikZ picture'),
        matching: find.byType(TextField),
      );
    }

    testWidgets('the source window is as tall as a short source', (
      tester,
    ) async {
      final field = await openSourceOf(tester, r'\tikz \draw (0,0) -- (1,0);');
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: field, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.maxScrollExtent, 0);
      expect(tester.getSize(field).height, lessThan(100));
    });

    testWidgets('a long source fills the screen, opens at its top, and '
        'undoes back to where the change was', (tester) async {
      final lines = <String>[
        for (var i = 0; i < 40; i++) '  \\draw (0,0) -- ($i,1);',
      ];
      final source =
          '\\begin{tikzpicture}\n${lines.join('\n')}\n\\end{tikzpicture}';
      final field = await openSourceOf(tester, source);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(field).height, greaterThan(screen.height / 3));
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: field, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.pixels, 0, reason: 'it opens at its top');
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.selection, const TextSelection.collapsed(offset: 0));

      controller.selection = const TextSelection.collapsed(offset: 30);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(controller.text.length, source.length - 1);
      await press(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pumpAndSettle();
      expect(controller.text, source);
      expect(controller.selection, const TextSelection.collapsed(offset: 30));
      expect(scroll.position.pixels, 0, reason: 'where the change was');
      expect(blocksOf(tester).single.embed!.source, source);
      await press(tester, LogicalKeyboardKey.keyY, control: true);
      await tester.pumpAndSettle();
      expect(controller.text.length, source.length - 1);
    });

    testWidgets('a TikZ picture typed alone on its line becomes a picture', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await press(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
      await type(tester, r'\tikz \draw (0,0) -- (1,1);');
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        blocksOf(tester).single.embed,
        const BlockEmbed.tikz(r'\tikz \draw (0,0) -- (1,1);'),
      );
      expect(find.byType(TikzView), findsOneWidget);
    });

    testWidgets('formulas from older pages are stored as LaTeX', (
      tester,
    ) async {
      await savePage(tester, const <TextRun>[
        TextRun.math('x^2/3', MathMode.linear),
      ]);
      await openEditor(tester, store, pageId);

      expect(
        blocksOf(tester).single.runs.single,
        const TextRun.math(r'\frac{x^2}{3}', MathMode.latex),
      );
      final saved = await tester.runAsync(
        () => store.pages.loadDocument(pageId),
      );
      final box = saved!.elements.single as TextElement;
      expect(box.blocks.single.runs.single.math, MathMode.latex);
    });

    testWidgets('an empty formula disappears when left', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      await type(tester, 'a');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(blocksOf(tester).single.runs, const <TextRun>[TextRun('a')]);
    });

    testWidgets('Backspace selects a formula first, then deletes it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'a ');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.backspace);
      expect(blocksOf(tester).single.runs, hasLength(2), reason: 'selected');

      await press(tester, LogicalKeyboardKey.backspace);
      expect(blocksOf(tester).single.runs, const <TextRun>[TextRun('a ')]);
    });

    testWidgets('the arrow keys go into a formula and back out after it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'so ');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(typesetInBox(), findsOneWidget);

      // Arrowing into it from the right shows its source, caret at the end.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue, reason: 'formula reopened');
      expect(typedLine(tester), 'x');
      // Typeset in its place, its source drawn beneath it.
      expect(overlayOf(tester).source.text, 'x');

      await type(tester, '2');
      expect(blocksOf(tester).single.runs.last.text, 'x 2');

      // Off the end of the source, back into the text just after it.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(typesetInBox(), findsOneWidget);
      await type(tester, '!');
      expect(blocksOf(tester).single.runs.last.text, '!');

      // From the left the caret goes in at the start, and out before it.
      await press(tester, LogicalKeyboardKey.home);
      for (var i = 0; i < 'so '.length; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(inFormula(tester), isFalse, reason: 'just before it');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      await type(tester, 'y');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      await type(tester, ':');
      expect(
        blocksOf(tester).single.runs.map((run) => run.text).toList(),
        <String>['so :', 'y x 2', '!'],
      );
    });

    testWidgets('the source is typed across the box, beneath the formula', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'y');
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      final layer = formulaLayerOf(tester);
      final field = MatrixUtils.transformRect(
        layer.getTransformTo(null),
        layer.formulaBox!,
      );
      final letter = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        paragraph.rangeRects(0, 1).single,
      );
      final box = tester.getRect(find.byType(TextBoxEditor));
      expect(field.left, moreOrLessEquals(box.left));
      expect(field.right, moreOrLessEquals(box.right));
      expect(
        field.top,
        greaterThanOrEqualTo(letter.bottom - 0.5),
        reason: 'beneath its line',
      );
      // The formula is outlined where it is typeset, the click on it
      // keeping it open.
      final formula = tester.getRect(typesetInBox());
      expect(formula.bottom, lessThanOrEqualTo(field.top + 0.5));
      await tester.tapAt(formula.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      // Over everything on the page, the frame round the box included.
      expect(
        find.descendant(
          of: find.byType(InfiniteCanvas),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is FormulaFieldPainter,
          ),
        ),
        findsOneWidget,
      );
      // The caret is drawn with the source, inside its box.
      expect(paragraph.decoration.caret, isNull);
      final caret = layer.sourceCaretRect(overlayOf(tester).caret!)!;
      final drawnBox = layer.formulaBox!;
      expect(caret.left, greaterThan(drawnBox.left));
      expect(caret.right, lessThan(drawnBox.right));
      expect(caret.top, greaterThanOrEqualTo(drawnBox.top));
      expect(caret.bottom, lessThanOrEqualTo(drawnBox.bottom));
    });

    Finder formulaWindow() => find.widgetWithText(GlassDialog, 'Formula');
    Finder windowField() =>
        find.descendant(of: formulaWindow(), matching: find.byType(TextField));

    testWidgets('a long source is typed in a window, Enter finishing it', (
      tester,
    ) async {
      final long = r'\frac{a}{b} + ' * 6;
      expect(long.length, greaterThan(FormulaWindow.usual));
      await savePage(tester, <TextRun>[TextRun.imported(long)]);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getRect(typesetInBox()).center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      expect(formulaWindow(), findsOneWidget);
      expect(tester.widget<TextField>(windowField()).controller!.text, long);
      // Only the formula is outlined on the page; nothing is typed there.
      expect(formulaLayerOf(tester).formulaBox, isNull);

      final changed = '$long c';
      await tester.enterText(windowField(), changed);
      await tester.pumpAndSettle();
      expect(tester.widget<MathView>(typesetInBox()).source, changed);
      await tester.enterText(windowField(), '$changed + \\frac{');
      await tester.pumpAndSettle();
      expect(find.textContaining("Expected '}'"), findsOneWidget);
      expect(tester.widget<MathView>(typesetInBox()).source, changed);
      await tester.enterText(windowField(), changed);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
      expect(inFormula(tester), isFalse);
      expect(blocksOf(tester).single.runs.single.text, changed);
      expect(blocksOf(tester).single.runs.single.imported, isTrue);
    });

    testWidgets('a source on lines of its own keeps them in its window', (
      tester,
    ) async {
      const formula =
          '\\begin{cases}\n'
          '  1 & x > 0 \\\\\n'
          '  0\n'
          '\\end{cases}';
      expect(formula.length, lessThan(const FormulaWindow().closesBelow));
      await savePage(tester, <TextRun>[const TextRun.imported(formula)]);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getRect(typesetInBox()).center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsOneWidget);
      expect(tester.widget<TextField>(windowField()).controller!.text, formula);

      const more =
          '\\begin{cases}\n'
          '  1 & x > 0 \\\\\n'
          '  0 & x = 0 \\\\\n'
          '  -1\n'
          '\\end{cases}';
      await tester.enterText(windowField(), more);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
      expect(blocksOf(tester).first.runs.single.text, more);
    });

    testWidgets('a source goes to its window past 80, back only below 60', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      final sum = List<String>.generate(20, (i) => 'x').join(' + ');
      expect(sum.length, lessThanOrEqualTo(FormulaWindow.usual));
      await type(tester, sum);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
      await type(tester, ' + y');
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsOneWidget);
      expect(formulaLayerOf(tester).formulaBox, isNull);

      // Between the two it stays in its window.
      await tester.enterText(windowField(), 'x' * 70);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsOneWidget);
      await tester.enterText(windowField(), 'x' * 59);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
      expect(inFormula(tester), isTrue);
      expect(formulaLayerOf(tester).formulaBox, isNotNull);
      expect(overlayOf(tester).source.text, 'x' * 59);
      await type(tester, 'y');
      await tester.pumpAndSettle();
      expect(overlayOf(tester).source.text, '${'x' * 59}y');
    });

    testWidgets('the length a source gets its window past is a setting', (
      tester,
    ) async {
      await openEditor(
        tester,
        store,
        pageId,
        preferences: Preferences.inMemory(<String, Object?>{
          'math.windowPast': 40,
        }),
      );
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'x' * 40);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
      await type(tester, 'x');
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsOneWidget);

      // Back beneath its line twenty shorter.
      await tester.enterText(windowField(), 'x' * 20);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsOneWidget);
      await tester.enterText(windowField(), 'x' * 19);
      await tester.pumpAndSettle();
      expect(formulaWindow(), findsNothing);
    });

    testWidgets('a click on the source below the box places the caret in it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'a + b + c + d + e + f + g + h + i + j + k');
      await tester.pumpAndSettle();
      final layer = formulaLayerOf(tester);
      final field = MatrixUtils.transformRect(
        layer.getTransformTo(null),
        layer.formulaBox!,
      );
      final box = tester.getRect(find.byType(TextBoxEditor));
      expect(field.bottom, greaterThan(box.bottom), reason: 'it wraps');

      await tester.tapAt(
        Offset(field.left + 8, field.bottom - 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      expect(overlayOf(tester).caret, greaterThan(0));
      expect(
        overlayOf(tester).caret,
        lessThan(overlayOf(tester).source.text!.length),
      );
    });

    testWidgets('what is typed is laid out as it will be once finished', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'Above');
      await press(tester, LogicalKeyboardKey.enter);
      await type(tester, 'Below');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.end);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'sum_(i=1)^n i^2 / (n+1) + sqrt(a^2+b^2) + x^2 + y^2');
      await tester.pumpAndSettle();

      final typing = tester.getRect(find.byType(BlockParagraph).last);
      // The source runs on over the line beneath rather than pushing it
      // down.
      final layer = formulaLayerOf(tester);
      expect(
        layer.formulaBox!.bottom,
        greaterThan(
          MatrixUtils.transformRect(
            tester
                .renderObject<RenderBox>(find.byType(BlockParagraph).last)
                .getTransformTo(layer),
            Offset.zero & typing.size,
          ).top,
        ),
      );

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(tester.getRect(find.byType(BlockParagraph).last), typing);
    });

    testWidgets('a slip while typing leaves the formula as it last was', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await press(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
      await tester.pumpAndSettle();
      await type(tester, r'\frac{a}{b}');
      await tester.pumpAndSettle();
      expect(tester.widget<MathView>(typesetInBox()).source, r'\frac{a}{b}');
      expect(overlayOf(tester).problem, isNull);

      await type(tester, r' + \frac{');
      await tester.pumpAndSettle();
      expect(
        tester.widget<MathView>(typesetInBox()).source,
        r'\frac{a}{b} + ',
        reason: 'the last of it that typesets stays in place',
      );
      expect(overlayOf(tester).problem, isNotNull, reason: 'said beneath');
    });

    group('highlighting part of one', () {
      Future<void> typeAndSelect(WidgetTester tester) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await press(tester, LogicalKeyboardKey.equal, alt: true);
        await type(tester, 'a + b^2');
        for (var i = 0; i < 3; i++) {
          await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
        }
        await tester.pumpAndSettle();
      }

      /// The formula, last on its line, as it is stored.
      String stored(WidgetTester tester) =>
          blocksOf(tester).single.runs.last.text;

      Iterable<String> previewed(WidgetTester tester) => tester
          .widgetList<MathView>(typesetInBox())
          .map((view) => view.source);

      testWidgets('marks what is selected, and only that', (tester) async {
        await typeAndSelect(tester);
        await press(
          tester,
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        );
        await tester.pumpAndSettle();

        expect(typedLine(tester), 'a + highlight(b^2)');
        expect(stored(tester), r'a + \colorbox{#FFEF9D}{$b^2$}');
        expect(
          previewed(tester),
          contains(r'a + \colorbox{#FFEF9D}{$b^2$}'),
          reason: 'the typeset formula shows the highlight',
        );
        expect(inFormula(tester), isTrue);
        expect(
          blocksOf(tester).single.runs.single.marks.highlight,
          isNull,
          reason: 'not the whole formula',
        );
        // In the source being typed, what it marks is on its colour too,
        // drawn in the formula's box.
        final overlay = overlayOf(tester);
        final mark = overlay.marks.single;
        expect(
          overlay.source.text!.substring(mark.range.start, mark.range.end),
          'b^2',
        );
        expect(
          mark.color,
          const Color(0xFF000000 | HighlightNode.defaultColor),
        );

        // Pressed again, with what it marks still selected, it comes off.
        await press(
          tester,
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        );
        await tester.pumpAndSettle();
        expect(typedLine(tester), 'a + b^2');
      });

      testWidgets('takes the colour chosen, and changes it', (tester) async {
        await typeAndSelect(tester);
        final text = pageText(tester);
        const green = 0xFF34A853;
        text.setHighlight(RichTextStyles.highlightFor(green));
        await tester.pumpAndSettle();
        final onPaper = RichTextStyles.onPaper(
          RichTextStyles.highlightFor(green),
        );
        expect(
          typedLine(tester),
          'a + highlight(${HighlightNode.hex(onPaper)}, b^2)',
        );

        text.setHighlight(RichTextStyles.highlightYellow);
        await tester.pumpAndSettle();
        expect(typedLine(tester), 'a + highlight(b^2)');

        text.setHighlight(null);
        await tester.pumpAndSettle();
        expect(typedLine(tester), 'a + b^2');
      });

      testWidgets('marks a whole part, never half of one', (tester) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await press(tester, LogicalKeyboardKey.equal, alt: true);
        await type(tester, 'a + b^2 = c');
        // "2 =", which alone would leave "=" with nothing on its left.
        for (var i = 0; i < 2; i++) {
          await press(tester, LogicalKeyboardKey.arrowLeft);
        }
        for (var i = 0; i < 3; i++) {
          await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
        }
        await press(
          tester,
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        );
        await tester.pumpAndSettle();

        expect(typedLine(tester), 'a + b^highlight(2) = c');
        expect(stored(tester), isNot(contains(r'\square')));
      });

      testWidgets('one highlighted from the text comes off inside it', (
        tester,
      ) async {
        await savePage(tester, const <TextRun>[
          TextRun('so '),
          TextRun.math('x^2', MathMode.latex),
        ]);
        await openEditor(tester, store, pageId);
        final box = tester.getRect(find.byType(TextBoxEditor));
        await tester.tapAt(
          Offset(box.left + 8, box.top + TextBoxEditor.grabBand + 10),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.keyA, control: true);
        await press(
          tester,
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        );
        await tester.pumpAndSettle();
        expect(stored(tester), r'\colorbox{#FFEF9D}{$x^2$}');

        // Into the formula, where the highlight is part of its source.
        await press(tester, LogicalKeyboardKey.end);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(inFormula(tester), isTrue);
        expect(typedLine(tester), 'highlight(x^2)');

        await press(
          tester,
          LogicalKeyboardKey.keyH,
          control: true,
          shift: true,
        );
        await tester.pumpAndSettle();
        expect(typedLine(tester), 'x^2');
      });

      test("the highlighter's yellow is the formulas' own", () {
        expect(
          RichTextStyles.onPaper(RichTextStyles.highlightYellow),
          HighlightNode.defaultColor,
        );
      });
    });

    testWidgets("Shift+Left at a formula's start selects the text before", (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'ab');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.home);

      await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      await tester.pumpAndSettle();

      // The formula is finished and the selection reaches into the text.
      expect(inFormula(tester), isFalse);
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      expect(paragraph.decoration.selection, isNotNull);
    });

    testWidgets('the source is placed beneath the formula at once', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'The area is ');

      // Alt+=, without a frame drawn in between, so the first frame the
      // source could appear in is watched too.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final seen = <Rect>{};
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final box = formulaLayerOf(tester).formulaBox;
        if (box != null) seen.add(box);
      }
      expect(seen, hasLength(1), reason: 'it never moved');
    });

    testWidgets('the page finishes the formula', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'e^x');

      pageText(tester).finishFormula();
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(formulaLayerOf(tester).formulaBox, isNull);

      await type(tester, ' grows');
      expect(blocksOf(tester).single.runs.last.text, ' grows');
    });

    testWidgets('undo while typing a formula keeps it open', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'ab');

      await press(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pumpAndSettle();
      expect(inFormula(tester), isTrue);
      expect(typedLine(tester), '');

      await type(tester, 'c');
      expect(
        blocksOf(tester).single.runs.single,
        const TextRun.math('c', MathMode.latex),
      );
    });

    testWidgets('the menu puts structures in; Tab moves between places', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.space, control: true);
      await typeKeys(tester, 'mf');
      await tester.tap(find.byTooltip('Fraction'));
      await tester.pumpAndSettle();
      await type(tester, 'a');
      expect(typedLine(tester), '(a)/()');

      await press(tester, LogicalKeyboardKey.tab);
      await type(tester, 'b');
      expect(typedLine(tester), '(a)/(b)');
      expect(blocksOf(tester).single.runs.single.text, r'\frac{a}{b}');
    });
  });

  testWidgets('the box grows as lines are added', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    final before = textBox(tester).element.frame.height;

    for (var i = 0; i < 4; i++) {
      await type(tester, 'line');
      await press(tester, LogicalKeyboardKey.enter);
    }
    await tester.pumpAndSettle();

    expect(textBox(tester).element.frame.height, greaterThan(before + 60));
  });

  testWidgets('an abandoned empty box is removed', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    expect(find.byType(TextBoxEditor), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextBoxEditor), findsNothing);
  });

  testWidgets('clicking a finished box places the caret in it again', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'word');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(textBox(tester).isEditing, isFalse);

    final box = tester.getRect(find.byType(TextBoxEditor));
    await tester.tapAt(
      Offset(box.right - 4, box.top + TextBoxEditor.grabBand + 12),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await type(tester, 's');

    expect(textBox(tester).isEditing, isTrue);
    expect(textOf(tester), 'words');
  });

  testWidgets('a dash and a space start a list marked with dashes', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, '- milk');
    await press(tester, LogicalKeyboardKey.enter);
    await type(tester, 'bread');
    await tester.pumpAndSettle();

    final blocks = blocksOf(tester);
    expect(blocks.map((block) => block.plainText), <String>['milk', 'bread']);
    for (final block in blocks) {
      expect(block.kind, TextBlockKind.bulleted);
      expect(block.bullet, BulletStyle.dash);
    }
  });

  testWidgets('what was typed is saved to the page', (tester) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'persisted');
    await press(tester, LogicalKeyboardKey.escape);
    // Past the autosave delay.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final document = await store.pages.loadDocument(pageId);
    expect(document!.extractSearchText(), 'persisted');
  });

  testWidgets('scrolling does not put off saving what was typed', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'persisted');
    await press(tester, LogicalKeyboardKey.escape);
    // Scrolled on and on, past the autosave delay.
    for (var i = 0; i < 12; i++) {
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(600, 500),
          scrollDelta: Offset(0, 4),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final document = await tester.runAsync(
      () => store.pages.loadDocument(pageId),
    );
    expect(document!.extractSearchText(), 'persisted');
    await tester.pumpAndSettle();
  });

  testWidgets('LaTeX of many lines goes in as text and formulas', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Notes');
    await press(tester, LogicalKeyboardKey.enter);

    await press(tester, LogicalKeyboardKey.space, control: true);
    await typeKeys(tester, 'il');
    await tester.enterText(
      find.descendant(
        of: find.byType(GlassDialog),
        matching: find.byType(TextField),
      ),
      'Let \$f(x) = x^2\$. Then\n'
      '\\begin{align*}\n'
      "  f'(x) &= 2x \\\\\n"
      "  f''(x) &= 2\n"
      '\\end{align*}\n',
    );
    await press(tester, LogicalKeyboardKey.enter, control: true);
    await tester.pumpAndSettle();

    expect(find.byType(GlassDialog), findsNothing);
    final blocks = blocksOf(tester);
    expect(blocks.first.plainText, 'Notes');
    expect(blocks[1].runs[1], const TextRun.imported('f(x) = x^2'));
    expect(
      blocks[2].runs.single.text,
      "\\begin{align*}\n  f'(x) &= 2x \\\\\n  f''(x) &= 2\n\\end{align*}",
      reason: 'laid out as written',
    );
    expect(blocks[2].align, BlockAlign.center);
    expect(tester.takeException(), isNull, reason: 'typeset as it is');
  });

  testWidgets('LaTeX brought in stays LaTeX, and reads its packages', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await press(tester, LogicalKeyboardKey.space, control: true);
    await typeKeys(tester, 'il');
    await tester.enterText(
      find.descendant(
        of: find.byType(GlassDialog),
        matching: find.byType(TextField),
      ),
      r'Water is $\ce{H2O}$, and $\frac{a}{b}$.',
    );
    await press(tester, LogicalKeyboardKey.enter, control: true);
    await tester.pumpAndSettle();
    final runs = blocksOf(tester).single.runs;
    expect(runs[1], const TextRun.imported(r'\ce{H2O}'));

    // Opened, a fraction brought in is LaTeX, though Simple is chosen.
    await tester.tapAt(
      tester.getCenter(find.byType(MathView).last),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(inFormula(tester), isTrue);
    expect(
      overlayOf(tester).source.text,
      r'\frac{a}{b}',
      reason: 'not (a)/(b)',
    );
    expect(pageText(tester).state.latexOnly, isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      blocksOf(tester).single.runs[3],
      const TextRun.imported(r'\frac{a}{b}'),
    );

    // mhchem is read in what was brought in, and not in a formula typed.
    await tester.tapAt(
      tester.getCenter(find.byType(MathView).first),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(overlayOf(tester).problem, isNull);
    await press(tester, LogicalKeyboardKey.end, control: true);
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.end, control: true);
    await press(tester, LogicalKeyboardKey.equal, alt: true);
    await press(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
    await tester.pumpAndSettle();
    await type(tester, r'\ce{H2O}');
    await tester.pumpAndSettle();
    expect(overlayOf(tester).problem, isNotNull);
    expect(blocksOf(tester).single.runs.last.imported, isFalse);
  });

  testWidgets('a formula in a table cell is laid out', (tester) async {
    await tester.runAsync(
      () => store.pages.saveDocument(
        pageId,
        PageDocument(
          id: pageId,
          elements: <NoteElement>[
            TextElement(
              id: 'box',
              frame: const Frame(x: 100, y: 100, width: 300, height: 100),
              createdAt: 0,
              updatedAt: 0,
              blocks: <TextBlock>[
                const TextBlock(
                  runs: <TextRun>[TextRun.math('x^2', MathMode.latex)],
                ).inCell(const TableCell(0, 0)),
                const TextBlock(runs: <TextRun>[TextRun('four')])
                    .inCell(const TableCell(0, 1)),
              ],
            ),
          ],
        ),
      ),
    );
    await openEditor(tester, store, pageId);
    expect(tester.takeException(), isNull);
    expect(find.byType(MathView), findsOneWidget);
  });

  group('OneNote-style caret', () {
    testWidgets('a click leaves only a caret until something is typed', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      expect(textBox(tester).isEditing, isTrue);
      expect(selectedOnCanvas(tester), isEmpty, reason: 'no box, no handles');

      await type(tester, 'a');
      await tester.pumpAndSettle();

      expect(selectedOnCanvas(tester).single.id, textBox(tester).element.id);
    });

    testWidgets('a new box widens with its text, then wraps', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'ab');
      await tester.pumpAndSettle();
      final narrow = textBox(tester).element.frame.width;

      await type(tester, ' a somewhat longer line of text');
      await tester.pumpAndSettle();
      final wider = textBox(tester).element.frame.width;
      expect(narrow, TextBoxEditor.minAutoWidth);
      expect(wider, greaterThan(narrow + 100));

      await type(tester, ' and it goes on' * 12);
      await tester.pumpAndSettle();
      final frame = textBox(tester).element.frame;
      // Wrapped, the box is as wide as its longest line, just short of the
      // limit.
      expect(frame.width, lessThanOrEqualTo(TextBoxEditor.maxAutoWidth));
      expect(frame.width, greaterThan(TextBoxEditor.maxAutoWidth - 40));
      expect(frame.height, greaterThan(80), reason: 'wrapped onto more lines');
    });
  });

  group('typing', () {
    RenderBlockParagraph paragraphOf(WidgetTester tester) =>
        tester.renderObject<RenderBlockParagraph>(find.byType(BlockParagraph));

    Rect caretOf(WidgetTester tester) {
      final paragraph = paragraphOf(tester);
      return paragraph.caretRect(
        paragraph.decoration.caret!,
        paragraph.decoration.caretAffinity,
      );
    }

    testWidgets('a space moves the caret on and widens the box', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'test');
      await tester.pumpAndSettle();
      final before = caretOf(tester);
      final width = paragraphOf(tester).size.width;

      await type(tester, ' ');
      await tester.pumpAndSettle();

      final after = caretOf(tester);
      expect(textOf(tester), 'test ');
      expect(after.left, greaterThan(before.left + 2));
      expect(after.height, closeTo(before.height, 1), reason: 'as tall');
      expect(paragraphOf(tester).size.width, greaterThan(width + 2));
      expect(after.left, lessThan(paragraphOf(tester).size.width));
    });

    testWidgets('a box emptied of its text can still be moved by its top', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'abc');
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.backspace);
      }
      await tester.pumpAndSettle();
      expect(textOf(tester), isEmpty);

      final before = textBox(tester).element.frame;
      final box = tester.getRect(find.byType(TextBoxEditor));
      await tester.dragFrom(
        Offset(box.center.dx, box.top + TextBoxEditor.grabBand / 2),
        const Offset(60, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final after = textBox(tester).element.frame;
      expect(after.x, closeTo(before.x + 60, 1));
      expect(after.y, closeTo(before.y + 40, 1));
    });
  });

  group('moving a box', () {
    TextElement box(String id, double y, List<TextRun> runs) => TextElement(
      id: id,
      frame: Frame(x: 200, y: y, width: 240, height: 60),
      createdAt: 0,
      updatedAt: 0,
      blocks: <TextBlock>[TextBlock(runs: runs)],
    );

    Finder editorOf(String id) => find.byWidgetPredicate(
      (widget) => widget is TextBoxEditor && widget.element.id == id,
    );

    testWidgets('is moved by its top however fast it is dragged, across '
        'another, which is left alone', (tester) async {
      await store.pages.saveDocument(
        pageId,
        PageDocument(
          id: pageId,
          elements: <NoteElement>[
            box('below', 420, const <TextRun>[
              TextRun('area '),
              TextRun.math(r'\frac{a}{b}', MathMode.latex),
            ]),
            box('above', 220, const <TextRun>[TextRun('in the way')]),
          ],
        ),
      );
      await openEditor(tester, store, pageId);
      CanvasController canvas() =>
          tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

      final topLeft = tester.getTopLeft(editorOf('below'));
      final mouse = await tester.startGesture(
        topLeft + const Offset(120, 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // Up, faster than the box can follow within a frame, and across the
      // other box's top.
      for (var i = 0; i < 12; i++) {
        await mouse.moveBy(const Offset(3, -20));
        await tester.pump();
      }
      await mouse.up();
      await tester.pumpAndSettle();
      expect(canvas().elementById('below')!.frame.y, closeTo(420 - 240, 2));
      expect(canvas().elementById('above')!.frame.y, 220);
      expect(selectedOnCanvas(tester).map((element) => element.id), <String>[
        'below',
      ]);
    });
  });

  group('formatting', () {
    testWidgets('size, colour and highlight apply to what is typed next', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'plain ');

      pageText(tester)
        ..setFontSize(24)
        ..setTextColor(0xFFD93025)
        ..setHighlight(RichTextStyles.highlightFor(0xFFFFD60A));
      await tester.pump();
      await type(tester, 'loud');

      final runs = blocksOf(tester).single.runs;
      expect(runs.first.marks.isEmpty, isTrue);
      expect(runs.last.text, 'loud');
      expect(runs.last.marks.size, 24);
      expect(runs.last.marks.color, 0xFFD93025);
      expect(runs.last.marks.highlight! >>> 24, RichTextStyles.highlightAlpha);
      expect(pageText(tester).state.fontSize, 24);
    });

    RenderBlockParagraph paragraph(WidgetTester tester) => tester
        .renderObject<RenderBlockParagraph>(find.byType(BlockParagraph).first);

    /// The caret as it is drawn, and the box of the letter before it.
    (Rect, Rect) caretAndLetter(WidgetTester tester) {
      final render = paragraph(tester);
      final decoration = render.decoration;
      final caret = decoration.caret!;
      final letter = render.paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: caret - 1, extentOffset: caret),
          )
          .single
          .toRect();
      return (
        render.caretRect(
          caret,
          decoration.caretAffinity,
          decoration.typingStyle,
        ),
        letter,
      );
    }

    testWidgets('the caret stands beside large text, not below it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      pageText(tester).setFontSize(72);
      await tester.pump();
      await type(tester, 'Big');
      await tester.pumpAndSettle();

      final (caret, letter) = caretAndLetter(tester);
      expect(caret.top, moreOrLessEquals(letter.top, epsilon: 0.5));
      expect(caret.bottom, moreOrLessEquals(letter.bottom, epsilon: 0.5));
      expect(caret.bottom, lessThanOrEqualTo(paragraph(tester).size.height));
    });

    testWidgets('the caret takes a new size as soon as it is chosen', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'small');
      await tester.pumpAndSettle();
      final (before, letter) = caretAndLetter(tester);

      pageText(tester).setFontSize(36);
      await tester.pump();
      final (after, _) = caretAndLetter(tester);

      // Taller, as 36 point text is, and standing on the same line.
      expect(after.height, greaterThan(before.height * 2.5));
      expect(
        after.bottom,
        moreOrLessEquals(
          letter.bottom + (after.height - before.height) * 0.2,
          epsilon: after.height * 0.15,
        ),
      );
    });

    testWidgets('a formula takes the size of the text it is written in', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      pageText(tester).setFontSize(20);
      await tester.pump();
      await type(tester, 'area ');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'x');

      final formula = blocksOf(tester).single.runs.last;
      expect(formula.isMath, isTrue);
      expect(formula.marks.size, 20);
      // Its source is typed at the size of the text around it too.
      expect(
        overlayOf(tester).source.style!.fontSize,
        20 * RichTextStyles.unitsPerPoint,
      );

      // Finished, it is typeset at that size, and typing goes on at it.
      await press(tester, LogicalKeyboardKey.enter);
      await type(tester, ' more');
      final runs = blocksOf(tester).single.runs;
      expect(runs.last.text, ' more');
      expect(runs.last.marks.size, 20);
    });

    testWidgets('a formula is highlighted with the words, in its LaTeX', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'area ');
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await type(tester, 'x');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(TextBoxEditor));
      await tester.tapAt(
        Offset(box.left + 8, box.top + TextBoxEditor.grabBand + 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyA, control: true);
      await press(tester, LogicalKeyboardKey.keyH, control: true, shift: true);
      await tester.pumpAndSettle();

      final runs = blocksOf(tester).single.runs;
      expect(runs.first.marks.highlight, RichTextStyles.highlightYellow);
      expect(runs.last.isMath, isTrue);
      expect(runs.last.text, r'\colorbox{#FFEF9D}{$x$}');
      expect(runs.last.marks.highlight, isNull, reason: 'one place for it');

      // Pressing again takes it off the formula as well as off the text.
      await press(tester, LogicalKeyboardKey.keyH, control: true, shift: true);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).single.runs.last.text, 'x');
      expect(blocksOf(tester).single.runs.first.marks.highlight, isNull);
    });

    testWidgets('text is black by default, on the white paper', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'ink');
      await tester.pumpAndSettle();

      final paragraph = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TextBoxEditor),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.text.style!.color, const Color(0xFF000000));
    });
  });

  testWidgets('a turned box can still be clicked into and typed in', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final page = PageDocument.empty(id: pageId).withElementAdded(
        const TextElement(
          id: 'turned',
          frame: Frame(x: 100, y: 100, width: 300, height: 60, rotation: 0.5),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            TextBlock(runs: <TextRun>[TextRun('turned')]),
          ],
        ),
      );
      await store.pages.saveDocument(pageId, page);
    });
    await openEditor(tester, store, pageId);

    // Click the middle of the box, which a turn about its centre leaves
    // where it was.
    final canvas = tester.getTopLeft(find.byType(InfiniteCanvas));
    await tester.tapAt(
      canvas + const Offset(250, 130),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.end);
    await type(tester, '!');

    expect(textBox(tester).isEditing, isTrue);
    expect(textOf(tester), 'turned!');
  });

  group('selecting', () {
    testWidgets('Ctrl+A takes the box first, then the whole page', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'some words');

      await press(tester, LogicalKeyboardKey.keyA, control: true);
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      expect(
        paragraph.decoration.selection,
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );

      // Again, with nothing left to select, the page takes it.
      await press(tester, LogicalKeyboardKey.keyA, control: true);
      await tester.pumpAndSettle();
      expect(selectedOnCanvas(tester).single.id, textBox(tester).element.id);
      expect(textBox(tester).isEditing, isFalse);
    });

    testWidgets('Ctrl+A at a bare caret selects everything on the page', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'written');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // A second box, only a caret, which has nothing to select.
      await tester.tapAt(const Offset(700, 500), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.keyA, control: true);
      await tester.pumpAndSettle();

      expect(selectedOnCanvas(tester), hasLength(1));
      expect(find.byType(TextBoxEditor), findsOneWidget);
    });

    testWidgets('Ctrl+A never picks the bare caret it leaves', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'written');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final written = textBox(tester).element.id;
      await tester.tapAt(const Offset(700, 500), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Frame by frame, the handles only ever go round what stays.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        expect(
          selectedOnCanvas(tester).map((element) => element.id),
          everyElement(written),
          reason: 'frame $frame',
        );
      }
      expect(selectedOnCanvas(tester), hasLength(1));
    });

    testWidgets('the band picks a box being typed in, for Delete to remove', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'all of this');
      expect(textBox(tester).isEditing, isTrue);

      final box = tester.getRect(find.byType(TextBoxEditor));
      await tester.tapAt(
        Offset(box.center.dx, box.top + TextBoxEditor.grabBand / 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(textBox(tester).isEditing, isFalse);
      expect(textBox(tester).selected, isTrue);
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      expect(
        paragraph.decoration.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      expect(paragraph.decoration.caret, isNull);

      await press(tester, LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(TextBoxEditor), findsNothing);
    });

    testWidgets('pressing the paper keeps the text formattable until the '
        'click is done', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'first');
      bool formattable() => pageText(tester).hasTarget;
      expect(formattable(), isTrue);

      final mouse = await tester.startGesture(
        const Offset(700, 550),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump();
      expect(formattable(), isTrue, reason: 'the button is still down');

      await mouse.up();
      await tester.pumpAndSettle();
      expect(formattable(), isTrue, reason: 'a new caret, to type at');
      final boxes = tester.widgetList<TextBoxEditor>(
        find.byType(TextBoxEditor),
      );
      expect(boxes.where((box) => box.isEditing), hasLength(1));
      expect(
        boxes.singleWhere((box) => box.isEditing).element.blocks,
        const <TextBlock>[TextBlock()],
        reason: 'the new, empty box has the caret',
      );
    });

    testWidgets('dragging across other boxes picks them and ends typing', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'other');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final other = tester.getRect(find.byType(TextBoxEditor));
      await tester.tapAt(const Offset(700, 550), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await type(tester, 'typing');
      await tester.pumpAndSettle();

      final mouse = await tester.startGesture(
        other.topLeft - const Offset(20, 20),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(other.center);
      await tester.pump();
      await mouse.moveTo(other.bottomRight + const Offset(20, 20));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      final boxes = tester.widgetList<TextBoxEditor>(
        find.byType(TextBoxEditor),
      );
      expect(boxes.where((box) => box.isEditing), isEmpty);
      expect(selectedOnCanvas(tester).map((element) => element.id), <String>[
        boxes.first.element.id,
      ]);
    });

    testWidgets('dragging across a bare caret picks nothing of it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      final canvas = tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas));
      await tester.tapAt(const Offset(600, 450), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(
        canvas.controller.document.elements,
        hasLength(1),
        reason: 'caret',
      );

      Future<void> dragOver(Rect band) async {
        final mouse = await tester.startGesture(
          band.topLeft,
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveTo(band.center);
        await tester.pump();
        await mouse.moveTo(band.bottomRight);
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
      }

      // Alone, the caret's empty box is not picked, nor shown.
      await dragOver(const Rect.fromLTRB(560, 400, 760, 520));
      expect(canvas.controller.selection, isEmpty);

      // With a box that has text, only that box is picked, and the empty
      // one goes.
      await press(tester, LogicalKeyboardKey.escape);
      await startTextBox(tester);
      await type(tester, 'words');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final words = tester.getRect(find.byType(TextBoxEditor).first);
      await tester.tapAt(const Offset(900, 600), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await dragOver(
        Rect.fromPoints(
          words.topLeft - const Offset(20, 20),
          const Offset(1000, 700),
        ),
      );
      final picked = canvas.controller.selectedElements;
      expect(picked, hasLength(1));
      expect(
        TextBoxEditor.isEmpty((picked.single as TextElement).blocks),
        isFalse,
      );
      expect(
        canvas.controller.document.elements.whereType<TextElement>().where(
          (box) => TextBoxEditor.isEmpty(box.blocks),
        ),
        isEmpty,
      );
    });

    group('a caret placed on the paper', () {
      CanvasController canvasOf(WidgetTester tester) =>
          tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas)).controller;

      /// Whether the box shows as a box, framed — by the page, as anything
      /// picked is, or by itself while a formula is begun at a caret — not
      /// yet only a caret.
      bool framed(WidgetTester tester) => selectedOnCanvas(tester).isNotEmpty;

      testWidgets('beside a box, lets a click through to the box', (
        tester,
      ) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await type(tester, 'x+y');
        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final box = tester.getRect(find.byType(TextBoxEditor));
        final written = canvasOf(tester).document.elements.single.id;

        // A caret placed just left of the box, whose empty box reaches
        // over it.
        await tester.tapAt(
          Offset(box.left - 8, box.center.dy + 6),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(canvasOf(tester).document.elements, hasLength(2));

        await tester.tapAt(
          Offset(box.left + 4, box.center.dy + 6),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final editing = tester
            .widgetList<TextBoxEditor>(find.byType(TextBoxEditor))
            .where((editor) => editor.isEditing);
        expect(editing.single.element.id, written);
        expect(canvasOf(tester).document.elements, hasLength(1));
      });

      testWidgets('with a formula begun, is picked as the box it will be, '
          'with its handles, and left, goes leaving nothing to undo', (
        tester,
      ) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        final canvas = canvasOf(tester);

        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await tester.pumpAndSettle();
        expect(inFormula(tester), isTrue);
        expect(framed(tester), isTrue, reason: 'a box to type it in');
        expect(canvas.selection, hasLength(1), reason: 'with its handles');
        expect(canvas.isDirty, isFalse, reason: 'nothing written yet');

        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await tester.pumpAndSettle();
        expect(inFormula(tester), isFalse);
        expect(framed(tester), isFalse, reason: 'still only a caret');
        expect(canvas.selection, isEmpty);

        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(TextBoxEditor), findsNothing);
        expect(canvas.selection, isEmpty);
        expect(canvas.canUndo, isFalse);
        expect(canvas.isDirty, isFalse);
      });

      testWidgets('with a formula begun, moves where the paper is clicked, '
          'all at once', (tester) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await tester.pumpAndSettle();

        await tester.tapAt(
          const Offset(700, 500),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(canvasOf(tester).document.elements, hasLength(1));
        expect(textBox(tester).isEditing, isTrue);
        expect(framed(tester), isFalse);
      });

      testWidgets('becomes a box with the first thing written, which undo '
          'takes back whole', (tester) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await press(tester, LogicalKeyboardKey.keyM, control: true);
        await type(tester, 'x');
        await tester.pumpAndSettle();
        expect(framed(tester), isTrue, reason: 'written in: a box');
        await press(tester, LogicalKeyboardKey.escape);
        await press(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final canvas = canvasOf(tester);
        expect(canvas.document.elements, hasLength(1));

        await press(tester, LogicalKeyboardKey.keyZ, control: true);
        await tester.pumpAndSettle();
        expect(canvas.document.elements, isEmpty, reason: 'no empty box');
        expect(find.byType(TextBoxEditor), findsNothing);
        await press(tester, LogicalKeyboardKey.keyY, control: true);
        await tester.pumpAndSettle();
        expect(
          (canvas.document.elements.single as TextElement).blocks,
          isNot(TextBoxEditor.isEmpty),
        );
      });

      testWidgets('is not saved with the page', (tester) async {
        await openEditor(tester, store, pageId);
        await startTextBox(tester);
        await type(tester, 'kept');
        await tester.tapAt(
          const Offset(700, 500),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(canvasOf(tester).document.elements, hasLength(2));

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        final saved = await tester.runAsync(
          () => store.pages.loadDocument(pageId),
        );
        expect(saved!.elements, hasLength(1));
      });
    });

    testWidgets('a box picked by its band shows its contents selected', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'all of this');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(TextBoxEditor));
      await tester.tapAt(
        Offset(box.center.dx, box.top + TextBoxEditor.grabBand / 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(textBox(tester).selected, isTrue);
      expect(textBox(tester).isEditing, isFalse);
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      expect(
        paragraph.decoration.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
    });
  });

  group('objects in the text', () {
    late BlockEmbed picture;

    Future<void> savePicture(WidgetTester tester) => tester.runAsync(() async {
      final asset = await store.assets.importBytes(
        pngBytes,
        mimeType: 'image/png',
      );
      picture = BlockEmbed(
        kind: EmbedKind.image,
        assetId: asset.id,
        width: 120,
        height: 60,
      );
      await store.pages.saveDocument(
        pageId,
        PageDocument(
          id: pageId,
          elements: <NoteElement>[
            TextElement(
              id: 'box',
              frame: const Frame(x: 100, y: 100, width: 300, height: 120),
              createdAt: 0,
              updatedAt: 0,
              blocks: <TextBlock>[TextBlock.embedded(picture)],
            ),
          ],
        ),
      );
    });

    BlockEmbed embedOf(WidgetTester tester) => blocksOf(tester).single.embed!;

    testWidgets('the caret beside a picture is a line tall, on its foot', (
      tester,
    ) async {
      await savePicture(tester);
      await openEditor(tester, store, pageId);
      final object = tester.getRect(find.byType(AssetImageView));
      await tester.tapAt(
        Offset(object.right + 40, object.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(tester.widget<EmbedBlock>(find.byType(EmbedBlock)).caretSide, 1);
      final caret = tester.getRect(
        find.descendant(
          of: find.byType(EmbedBlock),
          matching: find.byType(ValueListenableBuilder<bool>),
        ),
      );
      expect(caret.bottom, moreOrLessEquals(object.bottom));
      expect(caret.height, lessThan(object.height));
      final line = RichTextStyles.bodySize * 1.4 * object.height / 60;
      expect(caret.height, moreOrLessEquals(line, epsilon: 0.5));
    });

    testWidgets('clicking a picture picks it', (tester) async {
      await savePicture(tester);
      await openEditor(tester, store, pageId);

      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<EmbedBlock>(find.byType(EmbedBlock)).selected,
        isTrue,
      );
    });

    testWidgets('its handles stay the same size on screen at any zoom', (
      tester,
    ) async {
      await savePicture(tester);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final handle = find.descendant(
        of: find.byType(EmbedBlock),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.resizeUpLeftDownRight,
        ),
      );

      Future<void> expectScreenSized() async {
        for (final rect
            in tester
                .widgetList(handle)
                .map((_) => tester.getRect(handle.first))) {
          expect(rect.width, closeTo(SelectionHandles.size, 0.01));
        }
      }

      await expectScreenSized();
      final before = tester.getRect(find.byType(AssetImageView)).width;
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.equal, control: true);
      }
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(AssetImageView)).width,
        greaterThan(before * 1.5),
        reason: 'the page was zoomed in',
      );
      await expectScreenSized();
    });

    testWidgets('a corner of a picked picture resizes it', (tester) async {
      await savePicture(tester);
      await openEditor(tester, store, pageId);
      await tester.tapAt(
        tester.getCenter(find.byType(AssetImageView)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final object = tester.getRect(find.byType(AssetImageView));
      final gesture = await tester.startGesture(
        object.bottomRight,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final resized = embedOf(tester);
      expect(resized.width, greaterThan(150));
      expect(resized.aspectRatio, closeTo(picture.aspectRatio, 0.001));
      expect(
        tester.getRect(find.byType(AssetImageView)).width,
        closeTo(resized.width, 1),
      );
      // One undo step for the whole drag.
      await press(tester, LogicalKeyboardKey.keyZ, control: true);
      await tester.pumpAndSettle();
      expect(embedOf(tester).width, picture.width);
    });

    testWidgets('a picked picture has the page\'s handles, sides and all, '
        'grabbed as far off on a scaled display', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      await savePicture(tester);
      await openEditor(tester, store, pageId);
      final object = tester.getRect(find.byType(AssetImageView));
      await tester.tapAt(object.center, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      // The right side's handle stands out from the picture as the page's
      // do, and a press a few pixels off it still takes hold.
      final handle =
          object.centerRight + const Offset(SelectionHandles.outlineInset, 0);
      final gesture = await tester.startGesture(
        handle + const Offset(SelectionHandles.mouseReach - 2, 0),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final resized = embedOf(tester);
      expect(resized.width, closeTo(picture.width + 40, 1));
      expect(resized.aspectRatio, closeTo(picture.aspectRatio, 0.001));
    });
  });

  group('a turned box', () {
    Future<void> saveTurned(WidgetTester tester, double rotation) =>
        tester.runAsync(() async {
          final page = PageDocument.empty(id: pageId).withElementAdded(
            TextElement(
              id: 'turned',
              frame: Frame(
                x: 100,
                y: 100,
                width: 300,
                height: 60,
                rotation: rotation,
              ),
              createdAt: 0,
              updatedAt: 0,
              blocks: const <TextBlock>[
                TextBlock(runs: <TextRun>[TextRun('turned')]),
              ],
            ),
          );
          await store.pages.saveDocument(pageId, page);
        });

    testWidgets('moves by its band, wherever the band has turned to', (
      tester,
    ) async {
      await saveTurned(tester, math.pi);
      await openEditor(tester, store, pageId);
      final frame = textBox(tester).element.frame;

      // Upside down, the band runs along the bottom of the box on screen.
      final band = frame.localToPage.apply(frame.width / 2, 5);
      final canvas = tester.getTopLeft(find.byType(InfiniteCanvas));
      await tester.dragFrom(
        canvas + Offset(band.x, band.y),
        const Offset(40, 100),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final moved = textBox(tester).element.frame;
      expect(moved.centerX, closeTo(frame.centerX + 40, 0.5));
      expect(moved.centerY, closeTo(frame.centerY + 100, 0.5));
      expect(textBox(tester).isEditing, isFalse, reason: 'moved, not typed in');
    });

    testWidgets('resizes by its side, without selecting text', (tester) async {
      await saveTurned(tester, 0.5);
      await openEditor(tester, store, pageId);
      final canvas = tester.getTopLeft(find.byType(InfiniteCanvas));
      await tester.tapAt(
        canvas + const Offset(250, 130),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final frame = textBox(tester).element.frame;

      // The right side's handle, just outside the box, and a drag 60 along
      // the box's own width.
      final handle = frame.localToPage.apply(
        frame.width + SelectionHandles.outlineInset,
        frame.height / 2,
      );
      final along = Offset(60 * math.cos(0.5), 60 * math.sin(0.5));
      final gesture = await tester.startGesture(
        canvas + Offset(handle.x, handle.y),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(along / 2);
      await gesture.moveBy(along / 2);
      await gesture.up();
      await tester.pumpAndSettle();

      final resized = textBox(tester).element.frame;
      expect(resized.width, closeTo(frame.width + 60, 0.5));
      expect(resized.rotation, 0.5);
      expect(resized.corners.first.x, closeTo(frame.corners.first.x, 0.5));
      expect(resized.corners.first.y, closeTo(frame.corners.first.y, 0.5));
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      expect(paragraph.decoration.selection, isNull, reason: 'no text chosen');
    });

    testWidgets('grows from its top corner as lines are added', (tester) async {
      await saveTurned(tester, 0.5);
      await openEditor(tester, store, pageId);
      final corner = textBox(tester).element.frame.corners.first;

      final canvas = tester.getTopLeft(find.byType(InfiniteCanvas));
      await tester.tapAt(
        canvas + const Offset(250, 130),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.end);
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.enter);
        await type(tester, 'more');
      }
      await tester.pumpAndSettle();

      final frame = textBox(tester).element.frame;
      expect(frame.height, greaterThan(100));
      expect(frame.corners.first.x, closeTo(corner.x, 0.01));
      expect(frame.corners.first.y, closeTo(corner.y, 0.01));
    });
  });

  group('tables', () {
    /// The box's blocks, a line of a cell written after `row,column:`.
    List<String> cellsOf(WidgetTester tester) => <String>[
      for (final block in blocksOf(tester))
        switch (block.cell) {
          null => block.plainText,
          final cell => '${cell.row},${cell.column}:${block.plainText}',
        },
    ];

    /// Types a table of [rows], Tab between cells and Enter between rows.
    Future<void> typeTable(WidgetTester tester, List<List<String>> rows) async {
      for (var r = 0; r < rows.length; r++) {
        if (r > 0) await press(tester, LogicalKeyboardKey.enter);
        for (var c = 0; c < rows[r].length; c++) {
          if (c > 0) await press(tester, LogicalKeyboardKey.tab);
          await type(tester, rows[r][c]);
        }
      }
      await tester.pumpAndSettle();
    }

    RenderTextTable tableOf(WidgetTester tester) =>
        tester.renderObject<RenderTextTable>(find.byType(TextTableView));

    /// Where the right-hand line of [column] is on screen, half way down.
    Offset edgeOf(WidgetTester tester, int column) {
      final table = tableOf(tester);
      return table.localToGlobal(
        Offset(table.columnEdges[column], table.size.height / 2),
      );
    }

    testWidgets('Tab after a word starts one, and Tab and Enter grow it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);

      await typeTable(tester, <List<String>>[
        <String>['Name', 'Age', 'Town'],
        <String>['Ann', '30', 'Oslo'],
      ]);
      expect(cellsOf(tester), <String>[
        '0,0:Name',
        '0,1:Age',
        '0,2:Town',
        '1,0:Ann',
        '1,1:30',
        '1,2:Oslo',
      ]);
      expect(find.byType(TextTableView), findsOneWidget);

      // Enter at the end of a row adds another; Enter in its empty first
      // cell leaves the table, for the text after it.
      await press(tester, LogicalKeyboardKey.enter);
      expect(cellsOf(tester), hasLength(9));
      await press(tester, LogicalKeyboardKey.enter);
      await type(tester, 'after');
      expect(cellsOf(tester).sublist(5), <String>['1,2:Oslo', 'after']);
    });

    testWidgets('Enter in another cell starts a line of that cell', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b'],
      ]);
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      await press(tester, LogicalKeyboardKey.enter);
      await type(tester, 'more');

      expect(cellsOf(tester), <String>['0,0:a', '0,0:more', '0,1:b']);
    });

    testWidgets('the arrows go up and down its rows, and in and out of it', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'top');
      await press(tester, LogicalKeyboardKey.enter);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);

      await press(tester, LogicalKeyboardKey.arrowUp);
      await type(tester, '1');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await type(tester, '2');
      expect(cellsOf(tester), <String>[
        'top2',
        '0,0:a',
        '0,1:b1',
        '1,0:c',
        '1,1:d',
      ]);

      // From the text above, down into the cell beneath the caret.
      await press(tester, LogicalKeyboardKey.home);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await type(tester, '3');
      expect(cellsOf(tester)[1], '0,0:3a');
    });

    testWidgets('a click goes into the cell clicked', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['first', 'second'],
        <String>['third', 'fourth'],
      ]);

      // Below the short text of a cell, still in its row.
      final table = tableOf(tester);
      final inCell = table.localToGlobal(
        Offset(table.columnStart(1) + 4, table.size.height - 3),
      );
      await tester.tapAt(inCell, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 500));
      await type(tester, '!');
      expect(cellsOf(tester)[3], '1,1:fourth!');
    });

    testWidgets('columns fit their text, and share a narrow box', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b'],
      ]);
      // Short text leaves a column about an inch wide, room to type in.
      expect(tableOf(tester).columnWidth(0), RenderTextTable.fittedWidth);
      expect(tableOf(tester).columnWidth(1), RenderTextTable.fittedWidth);

      await type(tester, ' ${'long words ' * 40}');
      await tester.pumpAndSettle();
      final table = tableOf(tester);
      expect(
        table.size.width,
        lessThanOrEqualTo(
          TextBoxEditor.maxAutoWidth - TextBoxEditor.padding.horizontal,
        ),
      );
      expect(table.columnWidth(0), lessThan(table.columnWidth(1)));
    });

    testWidgets('dragging a column line sets its width; a double click fits '
        'it again', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['Name', 'Age'],
      ]);
      final before = tableOf(tester).columnWidth(0);

      // The mouse that clicked the page is still over it; it moves onto the
      // line.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.moveTo(edgeOf(tester, 0));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.resizeColumn,
      );
      await gesture.down(edgeOf(tester, 0));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      final width = blocksOf(tester).first.cell!.width!;
      expect(width, closeTo(before + 40, 0.5));
      expect(blocksOf(tester)[1].cell!.width, isNull);
      expect(tableOf(tester).columnWidth(0), closeTo(width, 0.5));

      await tester.pump(const Duration(seconds: 1));
      await gesture.down(edgeOf(tester, 0));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(edgeOf(tester, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(blocksOf(tester).first.cell!.width, isNull);
    });

    testWidgets('Backspace in an empty column takes it away again', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b'],
      ]);
      await press(tester, LogicalKeyboardKey.tab);
      expect(cellsOf(tester), hasLength(3));

      await press(tester, LogicalKeyboardKey.backspace);
      expect(cellsOf(tester), <String>['0,0:a', '0,1:b']);
      await type(tester, '!');
      expect(
        cellsOf(tester).last,
        '0,1:b!',
        reason: 'caret in the cell before',
      );
    });

    testWidgets('a drag from cell to cell selects the cells, which Delete '
        'takes away as it does text', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b', 'c'],
        <String>['d', 'e', 'f'],
      ]);
      final paragraphs = find.byType(BlockParagraph);

      await tester.pump(const Duration(seconds: 1));
      final drag = await tester.startGesture(
        tester.getCenter(paragraphs.at(1)),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(tester.getCenter(paragraphs.at(5)));
      await drag.up();
      await tester.pump();
      expect(tableOf(tester).selected, <int>{1, 2, 4, 5});
      expect(
        tester
            .renderObject<RenderBlockParagraph>(paragraphs.at(1))
            .decoration
            .selection,
        isNull,
        reason: 'the cell is drawn selected, not its text',
      );

      // Two columns top to bottom: they go.
      await press(tester, LogicalKeyboardKey.delete);
      expect(cellsOf(tester), <String>['0,0:a', '1,0:d']);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('typing over selected cells empties them and types in the '
        'first', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b', 'c'],
        <String>['d', 'e', 'f'],
      ]);
      // From the end of e up into b: the two cells of a column, which
      // typing empties rather than taking away.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowUp, shift: true);
      await type(tester, 'x');

      expect(cellsOf(tester), <String>[
        '0,0:a',
        '0,1:x',
        '0,2:c',
        '1,0:d',
        '1,1:',
        '1,2:f',
      ]);
    });

    testWidgets('its menu adds rows and columns and removes them', (
      tester,
    ) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await typeTable(tester, <List<String>>[
        <String>['a', 'b'],
      ]);
      final cell = tester.getCenter(find.byType(BlockParagraph).first);

      await rightClick(tester, cell);
      await tester.tap(find.text('Insert row below'));
      await tester.pumpAndSettle();
      await rightClick(tester, cell);
      await tester.tap(find.text('Insert column left'));
      await tester.pumpAndSettle();
      expect(cellsOf(tester), <String>[
        '0,0:',
        '0,1:a',
        '0,2:b',
        '1,0:',
        '1,1:',
        '1,2:',
      ]);

      await rightClick(
        tester,
        tester.getCenter(find.byType(BlockParagraph).first),
      );
      await tester.tap(find.text('Delete table'));
      await tester.pumpAndSettle();
      expect(find.byType(TextTableView), findsNothing);
    });
  });

  group('links', () {
    testWidgets('a link pasted alone is pasted as a link', (tester) async {
      mockClipboard(tester);
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'See ');
      await Clipboard.setData(
        const ClipboardData(text: 'https://example.org/forces'),
      );
      await press(tester, LogicalKeyboardKey.keyV, control: true);
      await tester.pumpAndSettle();

      final runs = blocksOf(tester).single.runs;
      expect(runs.last.text, 'https://example.org/forces');
      expect(runs.last.marks.link, 'https://example.org/forces');

      // Typing on after it is not part of it.
      await type(tester, ' now');
      expect(blocksOf(tester).single.runs.last.marks.link, isNull);
    });

    testWidgets('Ctrl+click follows a link to another page', (tester) async {
      final other = await tester.runAsync(() async {
        final page = await store.pages.createPage(
          sectionId: (await store.pages.findPage(pageId))!.sectionId,
          title: 'Elsewhere',
        );
        await store.pages.saveDocument(
          pageId,
          PageDocument(
            id: pageId,
            elements: <NoteElement>[
              TextElement(
                id: 'box',
                frame: const Frame(x: 100, y: 200, width: 300, height: 60),
                createdAt: 0,
                updatedAt: 0,
                blocks: <TextBlock>[
                  TextBlock(
                    runs: <TextRun>[
                      TextRun(
                        'elsewhere',
                        TextMarks(link: NoteLink.page(page.id).toString()),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
        return page;
      });
      await openEditor(tester, store, pageId);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TextBoxEditor)),
      );

      // On the word, which is shorter than its box.
      final word =
          tester.getTopLeft(find.byType(BlockParagraph)) + const Offset(20, 8);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(word, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(container.read(selectedPageProvider), other!.id);
    });
  });

  testWidgets('a box as wide as its text wraps at its limit and centres '
      'what is centred', (tester) async {
    await tester.runAsync(() async {
      final page = PageDocument.empty(id: pageId).withElementAdded(
        const TextElement(
          id: 'box',
          frame: Frame(x: 100, y: 100, width: 400, height: 60),
          createdAt: 0,
          updatedAt: 0,
          autoWidth: true,
          widthLimit: 200,
          blocks: <TextBlock>[
            TextBlock(
              align: BlockAlign.center,
              runs: <TextRun>[TextRun('Title')],
            ),
            TextBlock(
              runs: <TextRun>[
                TextRun('words enough to wrap well past the box limit'),
              ],
            ),
          ],
        ),
      );
      await store.pages.saveDocument(pageId, page);
    });
    await openEditor(tester, store, pageId);

    final box = tester.getRect(find.byType(TextBoxEditor));
    expect(textBox(tester).element.frame.width, lessThanOrEqualTo(200));
    final title = tester.getRect(
      find.descendant(
        of: find.byType(TextBoxEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'Title',
        ),
      ),
    );
    expect(title.center.dx, moreOrLessEquals(box.center.dx, epsilon: 1));
  });

  test('lines set closer than the type is tall are set as the typeface '
      'sets them', () {
    const base = TextStyle(fontSize: 11 * RichTextStyles.unitsPerPoint);
    final natural = RichTextStyles.spacedStyle(base, BlockSpacing.tight);
    // OneNote keeps some paragraphs with lines exactly three points apart.
    final tooClose = RichTextStyles.spacedStyle(
      base,
      const BlockSpacing(line: 3),
    );
    expect(tooClose.height, natural.height);
    final spaced = RichTextStyles.spacedStyle(
      base,
      const BlockSpacing(line: 22),
    );
    expect(spaced.height, closeTo(2, 1e-9), reason: 'twice the type');
  });
}
