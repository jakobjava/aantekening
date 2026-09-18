import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening/src/editor/ribbon/ribbon.dart';
import 'package:aantekening/src/editor/text/block_paragraph.dart';
import 'package:aantekening/src/editor/text/formula_preview.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/editor/text/text_styles.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
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
    EditableText.debugDeterministicCursor = true;
    assets = Directory.systemTemp.createTempSync('aantekening_text_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    final notebook = await store.library.createNotebook(title: 'Notes');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Section',
    );
    pageId = (await store.pages.createPage(sectionId: section.id)).id;
  });

  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
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

  testWidgets('letters that are tool shortcuts are typed, not obeyed', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);

    // P is the pen, E the eraser, H the hand, V and T the select tool.
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

  group('formulas', () {
    /// The caret's paragraph as the input method sees it, the formula being
    /// edited shown as its source. The room laid out either side of that
    /// source stands in the text as a placeholder, which is left out here.
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
      expect(find.byType(FormulaPreview), findsOneWidget);
      await type(tester, 'pi r^2');
      await tester.pumpAndSettle();

      expect(
        blocksOf(tester).single.runs.last,
        const TextRun.math(r'\pi r^2', MathMode.latex),
      );
      expect(inFormula(tester), isTrue);
      // Typed in the line itself, as its source; typeset only beneath.
      expect(typedLine(tester), 'Area pi r^2');
      expect(typesetInBox(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FormulaPreview),
          matching: find.byType(MathView),
        ),
        findsOneWidget,
      );

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await type(tester, ' units');

      final runs = blocksOf(tester).single.runs;
      expect(runs.map((run) => run.isMath), <bool>[false, true, false]);
      expect(runs[2].text, ' units');
      expect(inFormula(tester), isFalse);
      expect(find.byType(FormulaPreview), findsNothing);
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
      expect(find.byType(FormulaPreview), findsNothing);
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

      // The preview's switch does the same.
      await tester.tap(
        find.descendant(
          of: find.byType(FormulaPreview),
          matching: find.text('Simple'),
        ),
      );
      await tester.pumpAndSettle();
      expect(typedLine(tester), 'sum_(i = 1)^n i^2');
      expect(inFormula(tester), isTrue);
      expect(
        blocksOf(tester).single.runs.single.text,
        latex,
        reason: 'switching changes how it is typed, not what it is',
      );
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
      expect(typedLine(tester), 'mean (a + b)/2', reason: 'shown in Simple');
      expect(find.byType(FormulaPreview), findsOneWidget);

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(blocksOf(tester).single.runs.last.text, r'\frac{a+b}{2}');
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
      expect(typedLine(tester), 'so x');
      expect(typesetInBox(), findsNothing);

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

    testWidgets('the formula has room of its own beside the text', (
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
      final formula = paragraph.decoration.formula!;
      final box = paragraph.formulaRects(formula.start, formula.end).single;
      final letter = paragraph.rangeRects(0, 1).single;
      expect(box.left, greaterThanOrEqualTo(letter.right));
      // The caret stands inside the box, not on its edge.
      final caret = paragraph.caretRect(paragraph.decoration.caret!);
      expect(caret.left, greaterThan(box.left));
      expect(caret.right, lessThan(box.right));
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

    testWidgets('the preview appears beneath the formula and stays there', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'The area is ');

      // Alt+=, without a frame drawn in between, so the first frame the
      // preview could appear in is watched too.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final seen = <Offset>[];
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final preview = find.byType(FormulaPreview);
        if (preview.evaluate().isNotEmpty) seen.add(tester.getTopLeft(preview));
      }
      await type(tester, 'a');
      await tester.pumpAndSettle();

      expect(seen, isNotEmpty);
      final placed = tester.getTopLeft(find.byType(FormulaPreview));
      expect(seen.toSet(), <Offset>{placed}, reason: 'it never moved');
      final paragraph = tester.renderObject<RenderBlockParagraph>(
        find.byType(BlockParagraph),
      );
      final formula = paragraph.decoration.formula!;
      final box = MatrixUtils.transformRect(
        paragraph.getTransformTo(null),
        paragraph.formulaRects(formula.start, formula.end).single,
      );
      expect(placed.dy, greaterThan(box.bottom));
      expect((placed.dx - box.left).abs(), lessThan(10), reason: 'under it');
    });

    testWidgets('Done beneath the formula finishes it', (tester) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      await type(tester, 'e^x');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(inFormula(tester), isFalse);
      expect(find.byType(FormulaPreview), findsNothing);

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

    testWidgets('the Math tab puts structures in; Tab moves between places', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await press(tester, LogicalKeyboardKey.equal, alt: true);
      await tester.pumpAndSettle();
      expect(find.text('Structures'), findsOneWidget, reason: 'Math tab');

      await tester.tap(find.byTooltip('Fraction').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Fraction').last);
      await tester.pumpAndSettle();
      await type(tester, 'a');
      expect(typedLine(tester), '(a)/()');

      await press(tester, LogicalKeyboardKey.tab);
      await type(tester, 'b');
      expect(typedLine(tester), '(a)/(b)');
      expect(blocksOf(tester).single.runs.single.text, r'\frac{a}{b}');

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Font'), findsOneWidget, reason: 'back on Home');
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

  group('OneNote-style caret', () {
    List<NoteElement> selectedOnCanvas(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.byWidgetPredicate(
                        (w) =>
                            w is CustomPaint && w.painter is SelectionPainter,
                      ),
                    )
                    .painter!
                as SelectionPainter)
            .selected;

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

    testWidgets('a box emptied of its text can still be moved', (tester) async {
      final band = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                RichTextStyles.boxBandActive,
      );
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      expect(band, findsNothing, reason: 'a new box is only a caret');

      await type(tester, 'abc');
      await tester.pumpAndSettle();
      expect(band, findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.backspace);
      }
      await tester.pumpAndSettle();

      expect(textOf(tester), isEmpty);
      expect(band, findsOneWidget);
    });

    testWidgets('a box under the pointer is outlined in light grey', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'hover');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The mouse that clicked the page is still over it; it moves onto the
      // box.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(find.byType(TextBoxEditor)));
      await tester.pumpAndSettle();

      final outlines = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(TextBoxEditor),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.border)
          .whereType<Border>()
          .toList();
      expect(outlines, hasLength(1));
      expect(outlines.single.top.color, RichTextStyles.boxOutline);
    });
  });

  group('formatting', () {
    RibbonCommands bar(WidgetTester tester) =>
        tester.widget<Ribbon>(find.byType(Ribbon)).commands;

    testWidgets('size, colour and highlight apply to what is typed next', (
      tester,
    ) async {
      await openEditor(tester, store, pageId);
      await startTextBox(tester);
      await type(tester, 'plain ');

      bar(tester).text
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
      expect(bar(tester).text.state.fontSize, 24);
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
}
