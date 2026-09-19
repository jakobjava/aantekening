import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

TextBlock p(String text, {TextBlockKind kind = TextBlockKind.paragraph}) =>
    TextBlock.plain(text, kind: kind);

const BlockEmbed picture = BlockEmbed(
  kind: EmbedKind.image,
  assetId: 'img',
  width: 200,
  height: 100,
);

RichSelection at(int block, int offset) =>
    RichSelection.collapsed(RichPosition(block, offset));

RichSelection range(int b1, int o1, int b2, int o2) =>
    RichSelection(RichPosition(b1, o1), RichPosition(b2, o2));

/// A compact rendering of blocks for readable expectations: one entry per
/// block, `[image]` for embeds, `$…$` around formulas.
List<String> show(List<TextBlock> blocks) => <String>[
  for (final block in blocks)
    block.isEmbed
        ? '[image]'
        : '${block.kind == TextBlockKind.paragraph ? '' : '${block.kind.name}:'}'
              '${block.runs.map((r) => r.isMath ? '\$${r.text}\$' : r.text).join()}',
];

void main() {
  group('runs', () {
    test('neighbouring runs with the same marks merge', () {
      final runs = RichTextEditing.normalizeRuns(const <TextRun>[
        TextRun('a'),
        TextRun('b'),
        TextRun(''),
        TextRun('c', TextMarks(bold: true)),
      ]);
      expect(runs, const <TextRun>[
        TextRun('ab'),
        TextRun('c', TextMarks(bold: true)),
      ]);
    });

    test('formulas never merge, and an empty one survives', () {
      final runs = RichTextEditing.normalizeRuns(const <TextRun>[
        TextRun.math('x', MathMode.linear),
        TextRun.math('', MathMode.linear),
        TextRun('a'),
      ]);
      expect(runs, hasLength(3));
    });

    test('typing picks up the formatting of the text before the caret', () {
      const block = TextBlock(
        runs: <TextRun>[
          TextRun('plain '),
          TextRun('bold', TextMarks(bold: true)),
        ],
      );
      expect(RichTextEditing.marksAt(block, 10).bold, isTrue);
      expect(RichTextEditing.marksAt(block, 3).bold, isFalse);
      expect(RichTextEditing.marksAt(block, 0).bold, isFalse);
    });

    test('typing after a formula continues the text before it', () {
      const large = TextMarks(size: 20);
      const block = TextBlock(
        runs: <TextRun>[
          TextRun('area ', large),
          TextRun.math('x^2', MathMode.latex, TextMarks(size: 20)),
        ],
      );
      expect(RichTextEditing.marksAt(block, 8), large);
    });

    test('beside a lone formula, typing takes its size and colour', () {
      const marks = TextMarks(size: 24, color: 0xFF1A73E8);
      const block = TextBlock(
        runs: <TextRun>[TextRun.math('x', MathMode.latex, marks)],
      );
      expect(RichTextEditing.marksAt(block, 1), marks);
      expect(RichTextEditing.marksAt(block, 0), marks);
      expect(RichTextEditing.marksAt(const TextBlock(), 0), TextMarks.none);
    });
  });

  group('typing', () {
    test('inserts into the middle of a word', () {
      final edit = RichTextEditing.insertText(
        <TextBlock>[p('helo')],
        at(0, 3),
        'l',
      );
      expect(show(edit.blocks), <String>['hello']);
      expect(edit.selection, at(0, 4));
    });

    test('replaces a selection spanning blocks', () {
      final edit = RichTextEditing.insertText(
        <TextBlock>[p('one two'), p('three'), p('four five')],
        range(0, 4, 2, 5),
        'X',
      );
      expect(show(edit.blocks), <String>['one Xfive']);
      expect(edit.selection, at(0, 5));
    });

    test('pasted line breaks become new blocks of the same kind', () {
      final edit = RichTextEditing.insertText(
        <TextBlock>[p('', kind: TextBlockKind.bulleted)],
        at(0, 0),
        'a\nb\nc',
      );
      expect(show(edit.blocks), <String>[
        'bulleted:a',
        'bulleted:b',
        'bulleted:c',
      ]);
      expect(edit.selection, at(2, 1));
    });

    test('text typed beside an embed gets a line of its own', () {
      final after = RichTextEditing.insertText(
        const <TextBlock>[TextBlock.embedded(picture)],
        at(0, 1),
        'caption',
      );
      expect(show(after.blocks), <String>['[image]', 'caption']);

      final before = RichTextEditing.insertText(
        const <TextBlock>[TextBlock.embedded(picture)],
        at(0, 0),
        'title',
      );
      expect(show(before.blocks), <String>['title', '[image]']);
    });
  });

  group('Enter', () {
    test('splits a paragraph at the caret', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        p('hello world'),
      ], at(0, 5));
      expect(show(edit.blocks), <String>['hello', ' world']);
      expect(edit.selection, at(1, 0));
    });

    test('continues a list', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        p('item', kind: TextBlockKind.bulleted),
      ], at(0, 4));
      expect(show(edit.blocks), <String>['bulleted:item', 'bulleted:']);
    });

    test('a to-do continues unchecked', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        const TextBlock(
          kind: TextBlockKind.todo,
          checked: true,
          runs: <TextRun>[TextRun('done')],
        ),
      ], at(0, 4));
      expect(edit.blocks[1].kind, TextBlockKind.todo);
      expect(edit.blocks[1].checked, isFalse);
    });

    test('a heading is followed by a paragraph', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        p('Title', kind: TextBlockKind.heading1),
      ], at(0, 5));
      expect(show(edit.blocks), <String>['heading1:Title', '']);
    });

    test('at the start of a heading, moves the heading down intact', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        p('Title', kind: TextBlockKind.heading1),
      ], at(0, 0));
      expect(show(edit.blocks), <String>['', 'heading1:Title']);
      expect(edit.selection, at(1, 0));
    });

    test('on an empty list item, leaves the list', () {
      final edit = RichTextEditing.insertParagraphBreak(<TextBlock>[
        p('item', kind: TextBlockKind.bulleted),
        p('', kind: TextBlockKind.bulleted),
      ], at(1, 0));
      expect(show(edit.blocks), <String>['bulleted:item', '']);
    });

    test('on an empty nested item, outdents first', () {
      final edit = RichTextEditing.insertParagraphBreak(const <TextBlock>[
        TextBlock(kind: TextBlockKind.bulleted, indent: 2),
      ], at(0, 0));
      expect(edit.blocks.single.kind, TextBlockKind.bulleted);
      expect(edit.blocks.single.indent, 1);
    });

    test('beside an embed adds an empty line above or below it', () {
      final below = RichTextEditing.insertParagraphBreak(const <TextBlock>[
        TextBlock.embedded(picture),
      ], at(0, 1));
      expect(show(below.blocks), <String>['[image]', '']);
      expect(below.selection, at(1, 0));

      final above = RichTextEditing.insertParagraphBreak(const <TextBlock>[
        TextBlock.embedded(picture),
      ], at(0, 0));
      expect(show(above.blocks), <String>['', '[image]']);
      expect(above.selection, at(1, 0));
    });
  });

  group('Backspace at the start of a block', () {
    test('first removes a bullet, then the indent, then joins', () {
      var blocks = <TextBlock>[
        p('above'),
        const TextBlock(
          kind: TextBlockKind.bulleted,
          indent: 1,
          runs: <TextRun>[TextRun('item')],
        ),
      ];

      blocks = RichTextEditing.deleteBackwardAtBlockStart(blocks, 1).blocks;
      expect(blocks[1].kind, TextBlockKind.paragraph);
      expect(blocks[1].indent, 1);

      blocks = RichTextEditing.deleteBackwardAtBlockStart(blocks, 1).blocks;
      expect(blocks[1].indent, 0);

      final joined = RichTextEditing.deleteBackwardAtBlockStart(blocks, 1);
      expect(show(joined.blocks), <String>['aboveitem']);
      expect(joined.selection, at(0, 5));
    });

    test('removes an embed above', () {
      final edit = RichTextEditing.deleteBackwardAtBlockStart(<TextBlock>[
        const TextBlock.embedded(picture),
        p('text'),
      ], 1);
      expect(show(edit.blocks), <String>['text']);
      expect(edit.selection, at(0, 0));
    });

    test('does nothing at the very start', () {
      final blocks = <TextBlock>[p('text')];
      expect(
        RichTextEditing.deleteBackwardAtBlockStart(blocks, 0).blocks,
        same(blocks),
      );
    });
  });

  group('Delete at the end of a block', () {
    test('joins the next block', () {
      final edit = RichTextEditing.deleteForwardAtBlockEnd(<TextBlock>[
        p('a'),
        p('b'),
      ], 0);
      expect(show(edit.blocks), <String>['ab']);
    });

    test('removes an embed below', () {
      final edit = RichTextEditing.deleteForwardAtBlockEnd(<TextBlock>[
        p('a'),
        const TextBlock.embedded(picture),
        p('b'),
      ], 0);
      expect(show(edit.blocks), <String>['a', 'b']);
    });
  });

  group('deleting ranges', () {
    test('an embed inside the range is removed', () {
      final edit = RichTextEditing.deleteRange(<TextBlock>[
        p('ab'),
        const TextBlock.embedded(picture),
        p('cd'),
      ], range(0, 1, 2, 1));
      expect(show(edit.blocks), <String>['ad']);
    });

    test('selecting just an embed removes only it', () {
      final edit = RichTextEditing.deleteRange(<TextBlock>[
        p('a'),
        const TextBlock.embedded(picture),
        p('b'),
      ], range(1, 0, 1, 1));
      expect(show(edit.blocks), <String>['a', '', 'b']);
    });

    test('deleting everything leaves one empty block', () {
      final edit = RichTextEditing.deleteRange(<TextBlock>[
        p('a'),
        p('b'),
      ], range(0, 0, 1, 1));
      expect(show(edit.blocks), <String>['']);
    });

    test('a formula inside the range goes with it', () {
      final blocks = <TextBlock>[
        const TextBlock(
          runs: <TextRun>[
            TextRun('a '),
            TextRun.math('x^2', MathMode.linear),
            TextRun(' b'),
          ],
        ),
      ];
      final edit = RichTextEditing.deleteRange(blocks, range(0, 1, 0, 5));
      expect(show(edit.blocks), <String>['a b']);
    });
  });

  group('formulas', () {
    test('an empty formula is inserted at the caret', () {
      final (edit, :block, :run) = RichTextEditing.insertMath(
        <TextBlock>[p('area = ')],
        at(0, 7),
        MathMode.linear,
      );
      expect(block, 0);
      expect(run, 1);
      expect(edit.blocks[0].runs[1], const TextRun.math('', MathMode.linear));
    });

    test('a new formula takes the size and colour of its text', () {
      final (edit, :block, :run) = RichTextEditing.insertMath(
        <TextBlock>[p('area = ')],
        at(0, 7),
        MathMode.latex,
        marks: const TextMarks(bold: true, size: 20, color: 0xFFD93025),
      );
      expect(
        edit.blocks[block].runs[run].marks,
        const TextMarks(size: 20, color: 0xFFD93025),
      );
    });

    test('a formula inserted mid-word splits the word around it', () {
      final (edit, block: _, :run) = RichTextEditing.insertMath(
        <TextBlock>[p('ab')],
        at(0, 1),
        MathMode.latex,
      );
      expect(run, 1);
      expect(show(edit.blocks), <String>[r'a$$b']);
    });

    test('editing a formula changes only its source', () {
      final (edit, :block, :run) = RichTextEditing.insertMath(
        <TextBlock>[p('ab')],
        at(0, 1),
        MathMode.linear,
      );
      final blocks = RichTextEditing.replaceRunText(
        edit.blocks,
        block,
        run,
        '1/2',
      );
      expect(show(blocks), <String>[r'a$1/2$b']);
      expect(blocks[0].plainText, 'a1/2b');
    });

    test('text typed right after a formula stays outside it', () {
      final blocks = <TextBlock>[
        const TextBlock(runs: <TextRun>[TextRun.math('x', MathMode.linear)]),
      ];
      final edit = RichTextEditing.insertText(blocks, at(0, 1), ' is odd');
      expect(show(edit.blocks), <String>[r'$x$ is odd']);
    });

    test('removing a formula joins the text either side', () {
      final blocks = RichTextEditing.removeRun(
        <TextBlock>[
          const TextBlock(
            runs: <TextRun>[
              TextRun('a'),
              TextRun.math('', MathMode.linear),
              TextRun('b'),
            ],
          ),
        ],
        0,
        1,
      );
      expect(blocks.single.runs, const <TextRun>[TextRun('ab')]);
    });
  });

  group('formatting', () {
    test('marks apply to exactly the selected text', () {
      final blocks = RichTextEditing.applyMarks(
        <TextBlock>[p('one two three')],
        range(0, 4, 0, 7),
        (marks) => marks.copyWith(bold: true),
      );
      expect(blocks.single.runs, const <TextRun>[
        TextRun('one '),
        TextRun('two', TextMarks(bold: true)),
        TextRun(' three'),
      ]);
    });

    test('marks span blocks and skip formulas', () {
      final blocks = RichTextEditing.applyMarks(
        <TextBlock>[
          const TextBlock(
            runs: <TextRun>[TextRun('a'), TextRun.math('x', MathMode.linear)],
          ),
          p('b'),
        ],
        range(0, 0, 1, 1),
        (marks) => marks.copyWith(italic: true),
      );
      expect(blocks[0].runs[0].marks.italic, isTrue);
      expect(blocks[0].runs[1].isMath, isTrue);
      expect(blocks[0].runs[1].marks.isEmpty, isTrue);
      expect(blocks[1].runs.single.marks.italic, isTrue);
    });

    test('a toggle checks every character of the selection', () {
      final blocks = <TextBlock>[
        const TextBlock(
          runs: <TextRun>[TextRun('bold', TextMarks(bold: true)), TextRun('!')],
        ),
      ];
      expect(
        RichTextEditing.everyMark(blocks, range(0, 0, 0, 4), (m) => m.bold),
        isTrue,
      );
      expect(
        RichTextEditing.everyMark(blocks, range(0, 0, 0, 5), (m) => m.bold),
        isFalse,
      );
    });

    test('a block kind toggles back to a paragraph', () {
      var blocks = <TextBlock>[p('a'), p('b')];
      blocks = RichTextEditing.toggleBlockKind(
        blocks,
        range(0, 0, 1, 0),
        TextBlockKind.bulleted,
      );
      expect(show(blocks), <String>['bulleted:a', 'bulleted:b']);
      blocks = RichTextEditing.toggleBlockKind(
        blocks,
        range(0, 0, 1, 0),
        TextBlockKind.bulleted,
      );
      expect(show(blocks), <String>['a', 'b']);
    });

    test('indentation is clamped', () {
      final blocks = RichTextEditing.indentBlocks(
        <TextBlock>[p('a')],
        at(0, 0),
        -1,
      );
      expect(blocks.single.indent, 0);
    });
  });

  group('copy and paste', () {
    test('a slice is trimmed to the selection', () {
      final fragment = RichTextEditing.slice(<TextBlock>[
        p('one two'),
        p('three'),
        p('four five'),
      ], range(0, 4, 2, 4));
      expect(show(fragment), <String>['two', 'three', 'four']);
      expect(RichTextEditing.plainTextOf(fragment), 'two\nthree\nfour');
    });

    test('pasting a fragment joins its ends to the surrounding text', () {
      final edit = RichTextEditing.insertFragment(
        <TextBlock>[p('AB')],
        at(0, 1),
        <TextBlock>[p('x'), p('middle', kind: TextBlockKind.bulleted), p('y')],
      );
      expect(show(edit.blocks), <String>['Ax', 'bulleted:middle', 'yB']);
      expect(edit.selection, at(2, 1));
    });

    test('pasting a single line stays inline', () {
      final edit = RichTextEditing.insertFragment(
        <TextBlock>[p('AB')],
        at(0, 1),
        <TextBlock>[p('xy')],
      );
      expect(show(edit.blocks), <String>['AxyB']);
      expect(edit.selection, at(0, 3));
    });

    test('pasting a picture into text puts it on its own line', () {
      final edit = RichTextEditing.insertFragment(
        <TextBlock>[p('AB')],
        at(0, 1),
        const <TextBlock>[TextBlock.embedded(picture)],
      );
      expect(show(edit.blocks), <String>['A', '[image]', 'B']);
      expect(edit.selection, at(2, 0));
    });

    test('pasting a picture into an empty line replaces the line', () {
      final edit = RichTextEditing.insertFragment(
        <TextBlock>[p('')],
        at(0, 0),
        const <TextBlock>[TextBlock.embedded(picture)],
      );
      expect(show(edit.blocks), <String>['[image]', '']);
      expect(edit.selection, at(1, 0));
    });
  });

  group('Markdown shortcuts', () {
    test('a dash and a space start a bulleted list', () {
      final typed = RichTextEditing.insertText(
        <TextBlock>[p('-')],
        at(0, 1),
        ' ',
      );
      final edit = RichTextEditing.applyMarkdownShortcut(
        typed.blocks,
        typed.selection.extent,
      );
      expect(show(edit!.blocks), <String>['bulleted:']);
      expect(edit.selection, at(0, 0));
    });

    test('hashes make headings', () {
      final edit = RichTextEditing.applyMarkdownShortcut(<TextBlock>[
        p('## '),
      ], const RichPosition(0, 3));
      expect(edit!.blocks.single.kind, TextBlockKind.heading2);
    });

    test('an ordinary space is left alone', () {
      expect(
        RichTextEditing.applyMarkdownShortcut(<TextBlock>[
          p('word '),
        ], const RichPosition(0, 5)),
        isNull,
      );
    });
  });

  group('serialisation', () {
    test('formulas and embeds round-trip through JSON', () {
      final element = TextElement(
        id: 't',
        frame: const Frame(x: 0, y: 0, width: 300, height: 100),
        createdAt: 0,
        updatedAt: 0,
        blocks: const <TextBlock>[
          TextBlock(
            runs: <TextRun>[
              TextRun('area '),
              TextRun.math(r'\pi r^2', MathMode.latex),
            ],
          ),
          TextBlock.embedded(
            BlockEmbed(
              kind: EmbedKind.pdfPage,
              assetId: 'doc',
              pageIndex: 3,
              width: 612,
              height: 792,
              text: 'lecture slide',
            ),
          ),
        ],
      );

      final decoded = TextElement.fromJson(element.toJson());

      expect(decoded.blocks, element.blocks);
      expect(decoded.assetIds, <String>['doc']);
      final search = StringBuffer();
      decoded.writeSearchText(search);
      expect(search.toString(), contains(r'\pi r^2'));
      expect(search.toString(), contains('lecture slide'));
    });
  });
}
