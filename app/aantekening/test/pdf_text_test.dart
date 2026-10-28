import 'dart:convert';
import 'dart:ui';

import 'package:aantekening/src/editor/media_views.dart';
import 'package:aantekening/src/editor/pdf_text.dart';
import 'package:aantekening/src/links/note_links.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'editor_harness.dart';

/// How wide a letter is, and how tall a line, in shares of the page.
const double _letter = 0.02;
const double _line = 0.03;

/// Where line [line] of the page's text begins, in shares of the page.
Offset _lineStart(int line) => Offset(0.1, 0.1 + line * 0.05);

/// A page with [lines] on it, a letter after another, each line under the
/// one before; with [links] over the given letters of the given lines.
PdfPageWords _words(
  List<String> lines, {
  List<(int line, int from, int to, PdfPageLink link)> links =
      const <(int, int, int, PdfPageLink)>[],
}) {
  final boxes = <Rect>[];
  final text = StringBuffer();
  for (final (index, line) in lines.indexed) {
    if (index > 0) {
      text.write('\n');
      boxes.add(Rect.zero);
    }
    final start = _lineStart(index);
    for (var i = 0; i < line.length; i++) {
      text.write(line[i]);
      boxes.add(
        Rect.fromLTWH(start.dx + i * _letter, start.dy, _letter, _line),
      );
    }
  }
  return PdfPageWords(
    text: '$text',
    boxes: boxes,
    links: <PdfPageLink>[
      for (final (line, from, to, link) in links)
        PdfPageLink(
          areas: <Rect>[
            Rect.fromLTRB(
              _lineStart(line).dx + from * _letter,
              _lineStart(line).dy,
              _lineStart(line).dx + to * _letter,
              _lineStart(line).dy + _line,
            ),
          ],
          url: link.url,
          page: link.page,
        ),
    ],
  );
}

/// The middle of letter [index] of line [line], in shares of the page.
Offset _at(int line, double index) =>
    _lineStart(line) + Offset((index + 0.5) * _letter, _line / 2);

const List<String> _sheet = <String>[
  'Golven en trillingen',
  'De frequentie is f = 1/T',
  'Zie ook bladzijde 2',
];

class _Links extends NoteLinks {
  _Links(super.ref);

  final List<String> opened = <String>[];

  @override
  Future<bool> open(String uri, {bool newTab = false}) async {
    opened.add(uri);
    return true;
  }
}

void main() {
  group('The text of a PDF page', () {
    final words = _words(_sheet);

    test('is in lines, as it lies', () {
      expect(words.lines, hasLength(3));
      expect(words.textOf(words.lines[1].start, words.lines[1].end), _sheet[1]);
    });

    test('is found where it lies, and not beside it', () {
      expect(words.lineAt(_at(0, 3)), isNotNull);
      expect(words.lineAt(_at(1, 30)), isNull, reason: 'past the line');
      expect(words.lineAt(const Offset(0.5, 0.9)), isNull);
    });

    test('is pointed into between letters, before the one past the point', () {
      final first = words.lines.first.start;
      expect(words.caretAt(_at(0, 0) - const Offset(0.009, 0)), first);
      expect(words.caretAt(_at(0, 0) + const Offset(0.004, 0)), first + 1);
      expect(
        words.caretAt(_at(0, 60)),
        words.lines.first.end,
        reason: 'past its end, the end of the line',
      );
      expect(
        words.caretAt(const Offset(0.12, 0.99)),
        words.lines.last.start + 1,
        reason: 'below all of it, on the last line',
      );
    });

    test('gives the word round a point', () {
      final (from, to) = words.wordAt(_at(0, 13));
      expect(words.textOf(from, to), 'trillingen');
      final (one, two) = words.wordAt(_at(1, 19));
      expect(words.textOf(one, two), '=', reason: 'no word: the sign');
    });

    test('is lit a box to a line, and copied with its line breaks', () {
      final from = words.lines[0].start + 7;
      final to = words.lines[1].start + 2;
      expect(words.boxesOf(from, to), hasLength(2));
      expect(words.textOf(from, to), 'en trillingen\nDe');
    });

    test('on a page turned on its side runs down it, the first line '
        'rightmost', () {
      // Each letter under the one before, each line left of the one before.
      final boxes = <Rect>[];
      final text = StringBuffer();
      for (final (index, line) in <String>['Gedraaid', 'blad'].indexed) {
        if (index > 0) {
          text.write('\n');
          boxes.add(Rect.zero);
        }
        for (var i = 0; i < line.length; i++) {
          text.write(line[i]);
          boxes.add(
            Rect.fromLTWH(
              0.8 - index * 0.05,
              0.1 + i * _letter,
              _line,
              _letter,
            ),
          );
        }
      }
      final turned = PdfPageWords(text: '$text', boxes: boxes);
      expect(turned.lines, hasLength(2));
      final first = turned.lines.first;
      expect(turned.textOf(first.start, first.end), 'Gedraaid');
      expect(first.box.height, greaterThan(first.box.width), reason: 'down');
      // The middle of the third letter, and just above the fifth.
      const third = Offset(0.8 + _line / 2, 0.1 + 2.5 * _letter);
      final (from, to) = turned.wordAt(third);
      expect(turned.textOf(from, to), 'Gedraaid');
      const fifth = Offset(0.8 + _line / 2, 0.1 + 4.2 * _letter);
      expect(turned.caretAt(fifth), 4);
      expect(turned.textOf(0, turned.caretAt(fifth)), 'Gedr');
      expect(turned.boxesOf(0, 4).single.height, closeTo(4 * _letter, 1e-9));
    });

    test('is read from PDFium, its boxes measured from the page’s foot', () {
      final read = PdfPageWords.read(
        const PdfPageText(
          pageNumber: 1,
          fullText: 'Hi',
          charRects: <PdfRect>[
            PdfRect(10, 790, 20, 770),
            PdfRect(20, 790, 30, 770),
          ],
          fragments: <PdfPageTextFragment>[],
        ),
        <PdfLink>[
          PdfLink(const <PdfRect>[
            PdfRect(10, 790, 30, 770),
          ], url: Uri.parse('https://example.org')),
        ],
        width: 100,
        height: 800,
      );
      expect(read.boxes.first.left, closeTo(0.1, 1e-9));
      expect(read.boxes.first.top, closeTo(10 / 800, 1e-9));
      expect(read.linkAt(const Offset(0.2, 0.02))?.url?.host, 'example.org');
    });
  });

  group('On the page', () {
    late AantekeningStore store;
    late String pageId;
    useTestPage((s, id) {
      store = s;
      pageId = id;
    });

    late _Links links;

    /// Opens a page with a PDF page on it — set as the background, or not
    /// — whose text is [_sheet], with a link to a web page and one to the
    /// PDF's second page, which lies further down if [second].
    Future<CanvasController> open(
      WidgetTester tester, {
      bool background = true,
      bool second = false,
    }) async {
      // A file in the asset store, for the page to hold: never opened as
      // a PDF, its text is given here.
      final pdf = (await tester.runAsync(
        () => store.assets.importBytes(
          Uint8List.fromList(utf8.encode('%PDF-1.7')),
          mimeType: 'application/pdf',
        ),
      ))!.id;
      PdfWordsCache.shared.keep(
        pdf,
        0,
        _words(
          _sheet,
          links: <(int, int, int, PdfPageLink)>[
            (
              0,
              0,
              6,
              PdfPageLink(
                areas: const <Rect>[],
                url: Uri.parse('https://x.nl'),
              ),
            ),
            (2, 8, 19, const PdfPageLink(areas: <Rect>[], page: 1)),
          ],
        ),
      );
      PdfWordsCache.shared.keep(pdf, 1, _words(const <String>['Twee']));
      await tester.runAsync(
        () => store.pages.saveDocument(
          pageId,
          PageDocument(
            id: pageId,
            elements: <NoteElement>[
              PdfElement(
                id: 'sheet',
                frame: const Frame(x: 100, y: 150, width: 500, height: 700),
                createdAt: 0,
                updatedAt: 0,
                locked: background,
                assetId: pdf,
                pageIndex: 0,
              ),
              if (second)
                PdfElement(
                  id: 'second',
                  frame: const Frame(x: 100, y: 3000, width: 500, height: 700),
                  createdAt: 0,
                  updatedAt: 0,
                  assetId: pdf,
                  pageIndex: 1,
                ),
            ],
          ),
        ),
      );
      await openEditor(
        tester,
        store,
        pageId,
        overrides: [
          pdfDocumentProvider.overrideWith((ref, id) async => null),
          noteLinksProvider.overrideWith((ref) => links = _Links(ref)),
        ],
      );
      mockClipboard(tester);
      return tester
          .widget<InfiniteCanvas>(find.byType(InfiniteCanvas))
          .controller;
    }

    /// Where on the screen [share] of the PDF page lies.
    Offset screen(WidgetTester tester, CanvasController canvas, Offset share) {
      final page = Offset(100 + share.dx * 500, 150 + share.dy * 700);
      return tester.getTopLeft(find.byType(InfiniteCanvas)) +
          canvas.viewport.toScreen(page);
    }

    Future<String?> copied(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      return (await tester.runAsync(
        () => Clipboard.getData(Clipboard.kTextPlain),
      ))?.text;
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final mouse = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(Offset.lerp(from, to, 0.5)!);
      await mouse.moveTo(to);
      await mouse.up();
      await tester.pump();
    }

    testWidgets('a worksheet’s text is selected by dragging across it, and '
        'copied', (tester) async {
      final canvas = await open(tester);
      await drag(
        tester,
        screen(tester, canvas, _at(0, 0) - const Offset(0.009, 0)),
        screen(tester, canvas, _at(0, 5) + const Offset(0.009, 0)),
      );
      expect(await copied(tester), 'Golven');
      expect(canvas.document.elements, hasLength(1), reason: 'nothing made');
    });

    testWidgets('a worksheet still takes a click to type there', (
      tester,
    ) async {
      final canvas = await open(tester);
      await tester.tapAt(
        screen(tester, canvas, _at(1, 4)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await type(tester, 'Antwoord');
      await tester.pumpAndSettle();
      final typed = canvas.document.elements.whereType<TextElement>();
      expect(typed.single.blocks.single.runs.single.text, 'Antwoord');
    });

    testWidgets('a word is selected by a double-click', (tester) async {
      final canvas = await open(tester);
      final at = screen(tester, canvas, _at(0, 13));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(await copied(tester), 'trillingen');
    });

    testWidgets('a PDF page of its own has its text selected, and is not '
        'moved by it', (tester) async {
      final canvas = await open(tester, background: false);
      await drag(
        tester,
        screen(tester, canvas, _at(1, 3) - const Offset(0.004, 0)),
        screen(tester, canvas, _at(1, 12) + const Offset(0.004, 0)),
      );
      expect(await copied(tester), 'frequentie');
      expect(canvas.document.elementById('sheet')!.frame.x, 100);
    });

    testWidgets('a link opens with Ctrl and a click: a web page in the '
        'browser, another page of the PDF where it lies', (tester) async {
      final canvas = await open(tester, second: true);
      Future<void> ctrlClick(Offset share) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tapAt(
          screen(tester, canvas, share),
          kind: PointerDeviceKind.mouse,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await ctrlClick(_at(0, 2));
      expect(links.opened, <String>['https://x.nl']);

      final before = canvas.viewport.origin;
      await ctrlClick(_at(2, 12));
      expect(
        canvas.viewport.origin.dy,
        greaterThan(before.dy + 1000),
        reason: 'brought to the second page',
      );
    });
  });
}
