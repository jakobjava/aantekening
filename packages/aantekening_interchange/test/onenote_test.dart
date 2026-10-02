import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_interchange/src/bytes.dart';
import 'package:aantekening_interchange/src/onenote/model.dart';
import 'package:aantekening_interchange/src/onenote/notebook_reader.dart';
import 'package:aantekening_interchange/src/onenote/office_math.dart';
import 'package:aantekening_interchange/src/onenote/onenote_import.dart';
import 'package:aantekening_interchange/src/onenote/section_reader.dart';
import 'package:aantekening_interchange/src/onestore/revision_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const OneStyle _text = OneStyle(font: 'Calibri', size: 11);
const OneStyle _math = OneStyle(font: 'Cambria Math', size: 11, math: true);

/// A run of a formula, the object that starts in it given by [type] —
/// and, for its delimiters or operator, [char], [char1].
OneRun _formula(
  String text, [
  int? type,
  int arguments = 0,
  int? char,
  int? char1,
  int? columns,
]) => OneRun(
  text,
  _math,
  math: type == null
      ? null
      : OneMathObject(
          type: type,
          arguments: arguments,
          char: char,
          char1: char1,
          columns: columns,
        ),
);

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('onenote_'));
  tearDown(() => work.deleteSync(recursive: true));

  group('reading OneNote files', () {
    test('reads a section, and the file attached in it', () {
      final bytes = File(
        'test/fixtures/onenote-2016/OneWithFileData.one',
      ).readAsBytesSync();
      final section = readSection(RevisionStore.read(bytes), 'Fallback');
      expect(section.pages, hasLength(1));
      final page = section.pages.single;
      expect(page.createdAt, DateTime.utc(2019, 3, 14, 9, 6, 41, 288));
      final outline = page.contents.single as OneOutline;
      expect(outline.x, 1.0);
      final file = outline.elements.first.contents.single as OneFile;
      expect(file.name, 'testing.docx');
      // A .docx is a zip.
      expect(file.data!.sublist(0, 2), 'PK'.codeUnits);
    });

    test('orders sections as the table of contents lists them', () {
      final notebook = Directory(p.join(work.path, 'Notebook'))..createSync();
      File(
        'test/fixtures/toc/Open Notebook.onetoc2',
      ).copySync(p.join(notebook.path, 'Open Notebook.onetoc2'));
      for (final name in <String>[
        'Ink',
        'New Section 3',
        'New Section 2',
        'New Section 1 2',
        'Not listed',
      ]) {
        File(p.join(notebook.path, '$name.one')).writeAsStringSync('');
      }
      final entries = readNotebookFolder(notebook);
      expect(entries.map((entry) => entry.name), <String>[
        'New Section 1 2',
        'New Section 2',
        'New Section 3',
        'Ink',
        'Not listed',
      ]);
      expect(
        entries.first,
        isA<OneUnreadableSection>(),
        reason: 'an empty file is not a section, and says so',
      );
    });

    test('says a file from OneNote online cannot be read yet', () {
      final bytes = Uint8List(1024);
      // A section's file type, with the packaging format.
      bytes.setAll(0, Guid.parse('7B5C52E4-D88C-4DA7-AEB1-5378D02996D3').bytes);
      bytes.setAll(
        48,
        Guid.parse('638DE92F-A6D4-4BC1-9A36-B3FC2511A5B7').bytes,
      );
      expect(
        () => RevisionStore.read(bytes),
        throwsA(
          isA<FormatDamage>().having(
            (damage) => damage.message,
            'message',
            contains('OneNote online'),
          ),
        ),
      );
    });

    test('decodes ink paths as the Ink Serialized Format writes numbers', () {
      // Four values: 1, -1, 64, -300.
      final bytes = Uint8List.fromList(<int>[8, 2, 3, 0x80, 0x01, 0xD9, 0x04]);
      expect(decodeMultiByteSigned(bytes), <int>[1, -1, 64, -300]);
    });
  });

  group('formulas', () {
    test('become LaTeX, each structure as its object says', () {
      expect(
        officeMathToLatex(<OneRun>[
          _formula('𝑥='),
          _formula('﷐', 16, 2, 0x2F),
          _formula('1﷮'),
          _formula('2﷯'),
        ]),
        <String>[r'x=\frac{1}{2}'],
      );
      expect(
        officeMathToLatex(<OneRun>[
          _formula('﷐', 31, 2, 0x5E),
          _formula('𝑖﷮'),
          _formula('3﷯'),
        ]),
        <String>['{i}^{3}'],
      );
    });

    test('keep brackets, roots and matrices', () {
      final latex = officeMathToLatex(<OneRun>[
        _formula('𝐴='),
        _formula('﷐', 13, 1, 0x28, 0x29),
        _formula('﷐', 20, 4, 0x25A0, null, 2),
        _formula('1﷮'),
        _formula('0﷮'),
        _formula('﷐', 25, 2, 0x221A),
        _formula('﷮'),
        _formula('2﷯'),
        _formula('﷮'),
        _formula('1﷯'),
        _formula('﷯'),
      ]).single;
      expect(
        latex,
        r'A=\left( \begin{matrix}1 & 0 \\ \sqrt{2} & 1\end{matrix}\right)',
      );
    });

    test('stack an equation array, each equation with its number', () {
      final latex = officeMathToLatex(<OneRun>[
        _formula('﷐', 15, 2),
        _formula('𝑥=1#(1)﷮'),
        _formula('𝑦=2#﷯'),
      ]).single;
      expect(latex, r'\begin{gathered}x=1\qquad (1) \\ y=2\end{gathered}');
    });

    test('break after each semicolon, as OneNote wraps them', () {
      expect(officeMathToLatex(<OneRun>[_formula('𝑎=1; 𝑏=2;𝑐')]), <String>[
        'a=1;',
        'b=2;',
        'c',
      ]);
    });

    test('set italic letters as letters, upright ones upright', () {
      expect(mathText('𝑧=𝑎+𝑖𝑏'), 'z=a+ib');
      expect(mathText('sin𝜑'), r'\sin \varphi ');
      expect(mathText('Allgemein'), r'\mathrm{Allgemein}');
      expect(mathText('ℝ ∋ 0,5'), r'\mathbb{R}\ \ni \ 0{,}5');
      expect(mathText('𝐀'), r'\mathbf{A}');
    });

    test('keep the text of a damaged structure', () {
      expect(officeMathToLatex(<OneRun>[_formula('1﷮2﷯+𝑥')]), <String>[
        '12+x',
      ]);
    });
  });

  group('pages', () {
    OnePage page(List<OnePageItem> contents, {int level = 1}) => OnePage(
      title: 'Kinematics',
      level: level,
      createdAt: DateTime.utc(2025, 9, 17, 12),
      contents: contents,
    );

    NotesDraft convert(List<OnePage> pages) =>
        convertOneNote(<String, List<OneEntry>>{
          'Physics': <OneEntry>[OneSection('Mechanics', pages)],
        }, ImportWork(work));

    test('keeps the width of an outline sized by hand', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          const OneOutline(
            x: 2,
            y: 5,
            maxWidth: 4,
            sizeSetByUser: true,
            indents: <double>[],
            elements: <OneElement>[
              OneElement(
                contents: <OneContent>[
                  OneRichText(
                    runs: <OneRun>[OneRun('Narrow', _text)],
                    alignment: 0,
                  ),
                ],
                children: <OneElement>[],
              ),
            ],
          ),
        ]),
      ]);
      final box =
          draft
                  .notebooks
                  .single
                  .sections
                  .single
                  .pages
                  .single
                  .document
                  .elements
                  .single
              as TextElement;
      expect(box.autoWidth, isFalse);
      expect(box.frame.width, 192 + 2 * TextElement.sidePadding);
    });

    test('put each outline where it was, as one text box', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          const OneOutline(
            x: 2,
            y: 5,
            maxWidth: 10,
            indents: <double>[],
            elements: <OneElement>[
              OneElement(
                contents: <OneContent>[
                  OneRichText(
                    runs: <OneRun>[
                      OneRun(
                        'Velocity',
                        OneStyle(font: 'Calibri', size: 14, bold: true),
                      ),
                    ],
                    alignment: 1,
                  ),
                ],
                children: <OneElement>[
                  OneElement(
                    contents: <OneContent>[
                      OneRichText(
                        runs: <OneRun>[OneRun('ds/dt', _text)],
                        alignment: 0,
                      ),
                    ],
                    list: OneList(format: '§', font: 'Wingdings'),
                    children: <OneElement>[],
                  ),
                ],
              ),
            ],
          ),
          // An empty outline is nothing to bring.
          const OneOutline(
            x: 9,
            y: 9,
            indents: <double>[],
            elements: <OneElement>[
              OneElement(
                contents: <OneContent>[
                  OneRichText(runs: <OneRun>[OneRun('', _text)], alignment: 0),
                ],
                children: <OneElement>[],
              ),
            ],
          ),
        ]),
      ]);
      final document =
          draft.notebooks.single.sections.single.pages.single.document;
      final box = document.elements.single as TextElement;
      // Half-inches, 48 page units each: the text, not the box around it,
      // starts where the outline did.
      expect(box.frame.x + TextElement.sidePadding, 96);
      expect(box.frame.y + TextElement.grabBand, 240);
      expect(box.frame.width, 480 + 2 * TextElement.sidePadding);
      // Never sized by hand, it is as wide as its text, wrapping where the
      // outline did.
      expect(box.autoWidth, isTrue);
      expect(box.widthLimit, 480 + 2 * TextElement.sidePadding);
      final heading = box.blocks.first;
      expect(heading.align, BlockAlign.center);
      expect(heading.spacing, BlockSpacing.tight);
      expect(
        heading.runs.single.marks,
        const TextMarks(bold: true, size: 14, font: 'Calibri'),
      );
      final item = box.blocks.last;
      expect(item.kind, TextBlockKind.bulleted);
      expect(item.marker, '▪');
      expect(item.indent, 1);
    });

    test('put subpages beneath the page before them', () {
      final draft = convert(<OnePage>[
        page(const <OnePageItem>[]),
        page(const <OnePageItem>[], level: 2),
        page(const <OnePageItem>[], level: 3),
        page(const <OnePageItem>[], level: 2),
        page(const <OnePageItem>[]),
      ]);
      final pages = draft.notebooks.single.sections.single.pages;
      expect(pages, hasLength(2));
      expect(pages.first.subpages, hasLength(2));
      expect(pages.first.subpages.first.subpages, hasLength(1));
      expect(
        pages.first.createdAt,
        DateTime.utc(2025, 9, 17, 12).millisecondsSinceEpoch,
      );
    });

    test('keep tables whole, cell by cell', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          const OneOutline(
            x: 1,
            y: 1,
            indents: <double>[],
            elements: <OneElement>[
              OneElement(
                contents: <OneContent>[
                  OneTable(
                    columnWidths: <double>[2, 3],
                    bordersVisible: false,
                    rows: <List<OneCell>>[
                      <OneCell>[
                        OneCell(<OneElement>[
                          OneElement(
                            contents: <OneContent>[
                              OneRichText(
                                runs: <OneRun>[OneRun('a', _text)],
                                alignment: 0,
                              ),
                            ],
                            children: <OneElement>[],
                          ),
                        ], background: 0xFFFFFF00),
                        OneCell(<OneElement>[]),
                      ],
                    ],
                  ),
                ],
                children: <OneElement>[],
              ),
            ],
          ),
        ]),
      ]);
      final box =
          draft
                  .notebooks
                  .single
                  .sections
                  .single
                  .pages
                  .single
                  .document
                  .elements
                  .single
              as TextElement;
      // Two and three half-inches of text, inset on either side.
      expect(box.blocks.map((block) => block.cell), <TableCell>[
        const TableCell(0, 0, width: 108, shading: 0xFFFFFF00, borders: false),
        const TableCell(0, 1, width: 156, borders: false),
      ]);
      expect(TextTables.tablesIn(box.blocks).single.columns, 2);
    });

    test('draw handwriting where it was, in page units', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          const OneInk(
            x: 1,
            y: 2,
            groups: <OneInk>[],
            strokes: <OneStroke>[
              OneStroke(
                xs: <double>[0, 2540],
                ys: <double>[0, 0],
                width: 52.9,
                height: 52.9,
                color: 0xFFFF0000,
              ),
              OneStroke(
                xs: <double>[0, 100],
                ys: <double>[0, 100],
                width: 100,
                height: 600,
                transparency: 128,
                highlighter: true,
              ),
            ],
          ),
        ]),
      ]);
      final ink =
          draft
                  .notebooks
                  .single
                  .sections
                  .single
                  .pages
                  .single
                  .document
                  .elements
                  .single
              as InkElement;
      final pen = ink.strokes.first;
      // 1 half-inch across, 2 down, and an inch along.
      expect(pen.xAt(0), closeTo(48, 1e-6));
      expect(pen.yAt(0), closeTo(96, 1e-6));
      expect(pen.xAt(1), closeTo(48 + 96, 1e-3));
      expect(pen.width, closeTo(2, 0.01));
      expect(pen.color, 0xFFFF0000);
      final highlighter = ink.strokes.last;
      expect(highlighter.tool, InkTool.highlighter);
      expect(highlighter.width, closeTo(600 * 96 / 2540, 1e-6));
      expect(highlighter.color >> 24, 127);
    });

    test('turn formulas into formulas, and to-dos into to-dos', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          OneOutline(
            x: 1,
            y: 1,
            indents: const <double>[],
            elements: <OneElement>[
              OneElement(
                contents: <OneContent>[
                  OneRichText(
                    runs: <OneRun>[
                      const OneRun('Area ', _text),
                      _formula('𝜋'),
                      _formula('﷐', 31, 2, 0x5E),
                      _formula('𝑟﷮'),
                      _formula('2﷯'),
                    ],
                    alignment: 0,
                    tags: const <OneNoteTag>[
                      OneNoteTag(label: 'To Do', shape: 3, completed: true),
                    ],
                  ),
                ],
                children: const <OneElement>[],
              ),
            ],
          ),
        ]),
      ]);
      final block =
          (draft
                      .notebooks
                      .single
                      .sections
                      .single
                      .pages
                      .single
                      .document
                      .elements
                      .single
                  as TextElement)
              .blocks
              .single;
      expect(block.kind, TextBlockKind.todo);
      expect(block.checked, isTrue);
      expect(block.runs.last.isMath, isTrue);
      expect(block.runs.last.text, r'\pi {r}^{2}');
    });

    test('bring a printout\'s pages as pages of its PDF, kept once', () {
      final pdf = Uint8List.fromList('%PDF-1.7 the printed file'.codeUnits);
      OneImage printed(int page) => OneImage(
        data: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, page]),
        extension: null,
        y: page * 24.0,
        width: 16,
        height: 23,
        isBackground: true,
        fileName: 'Worksheet_${page + 1}.pdf',
        recognizedText: 'Page ${page + 1}',
        printout: OnePrintout(pdf, page),
      );
      final draft = convert(<OnePage>[
        page(<OnePageItem>[printed(0), printed(1)]),
      ]);
      final pages = draft
          .notebooks
          .single
          .sections
          .single
          .pages
          .single
          .document
          .elements
          .cast<PdfElement>();
      expect(pages.map((page) => page.pageIndex), <int>[0, 1]);
      expect(pages.map((page) => page.assetId).toSet(), hasLength(1));
      expect(pages.first.locked, isTrue);
      expect(pages.last.extractedText, 'Page 2');
      final asset = draft.assets[pages.first.assetId]!;
      expect(asset.mimeType, 'application/pdf');
      expect(asset.name, 'Worksheet.pdf');
      expect(draft.assets, hasLength(1));
    });

    test('keep pictures and attached files in a store of their own', () {
      final draft = convert(<OnePage>[
        page(<OnePageItem>[
          OneImage(
            data: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2]),
            extension: null,
            x: 0,
            y: 1,
            width: 2,
            height: 1,
            isBackground: true,
          ),
        ]),
      ]);
      final picture =
          draft
                  .notebooks
                  .single
                  .sections
                  .single
                  .pages
                  .single
                  .document
                  .elements
                  .single
              as ImageElement;
      expect(picture.locked, isTrue);
      expect(picture.frame, const Frame(x: 0, y: 48, width: 96, height: 48));
      final asset = draft.assets[picture.assetId]!;
      expect(asset.mimeType, 'image/png');
      expect(File(asset.path).readAsBytesSync(), hasLength(6));
    });
  });
}
