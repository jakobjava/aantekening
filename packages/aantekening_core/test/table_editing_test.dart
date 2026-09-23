import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

TextBlock p(String text) => TextBlock.plain(text);

/// A line of cell [row], [column] holding [text].
TextBlock c(int row, int column, [String text = '', double? width]) =>
    TextBlock(
      runs: <TextRun>[if (text.isNotEmpty) TextRun(text)],
      cell: TableCell(row, column, width: width),
    );

RichSelection at(int block, int offset) =>
    RichSelection.collapsed(RichPosition(block, offset));

RichSelection range(int b1, int o1, int b2, int o2) =>
    RichSelection(RichPosition(b1, o1), RichPosition(b2, o2));

/// One entry per block: its text, after `r,c:` for a line of a cell.
List<String> show(List<TextBlock> blocks) => <String>[
  for (final block in blocks)
    switch (block.cell) {
      null => block.isEmbed ? '[image]' : block.plainText,
      final cell =>
        '${cell.row},${cell.column}:'
            '${block.isEmbed ? '[image]' : block.plainText}',
    },
];

/// A table of three rows of three cells, a to i.
final List<TextBlock> grid = <TextBlock>[
  for (var i = 0; i < 9; i++) c(i ~/ 3, i % 3, 'abcdefghi'[i]),
];

/// A table of two rows of two cells, between two paragraphs.
final List<TextBlock> sample = <TextBlock>[
  p('before'),
  c(0, 0, 'a'),
  c(0, 1, 'b'),
  c(1, 0, 'c'),
  c(1, 1, 'd'),
  p('after'),
];

void main() {
  group('finding tables', () {
    test('a table is the run of lines of its cells', () {
      expect(TextTables.tablesIn(sample), const <TextTable>[
        TextTable(start: 1, end: 5, rows: 2, columns: 2),
      ]);
      expect(TextTables.tableAt(sample, 3)?.start, 1);
      expect(TextTables.tableAt(sample, 0), isNull);
    });

    test('a cell that comes before the one above it starts another table', () {
      final tables = TextTables.tablesIn(<TextBlock>[
        c(0, 0, 'a'),
        c(0, 1, 'b'),
        c(0, 0, 'x'),
      ]);
      expect(tables.map((table) => (table.start, table.end)), <(int, int)>[
        (0, 2),
        (2, 3),
      ]);
    });

    test('several lines of one cell are that cell', () {
      final blocks = <TextBlock>[c(0, 0, 'a'), c(0, 0, 'more'), c(0, 1, 'b')];
      expect(TextTables.cellAt(blocks, 1), (start: 0, end: 2));
      expect(TextTables.tableAt(blocks, 2)?.columns, 2);
    });

    test('normalizing fills missing cells and renumbers', () {
      final blocks = TextTables.normalize(<TextBlock>[
        c(0, 0, 'a', 80),
        c(2, 0, 'c'),
        c(2, 1, 'd'),
      ]);
      expect(show(blocks), <String>['0,0:a', '0,1:', '1,0:c', '1,1:d']);
      expect(blocks[2].cell!.width, 80, reason: 'the column keeps its width');
    });

    test('a cell is saved with its block, and read back', () {
      final block = c(1, 2, 'x', 120.5);
      expect(TextBlock.fromJson(block.toJson()), block);
      const embed = TextBlock.embedded(
        BlockEmbed(kind: EmbedKind.image, assetId: 'i', width: 4, height: 3),
        cell: TableCell(0, 1),
      );
      expect(TextBlock.fromJson(embed.toJson()), embed);
      expect(p('plain').toJson().containsKey('cell'), isFalse);
    });
  });

  group('Tab', () {
    test('after a word starts a table, the caret in a new cell beside it', () {
      final edit = TableEditing.startTable(<TextBlock>[p('Name')], at(0, 4))!;
      expect(show(edit.blocks), <String>['0,0:Name', '0,1:']);
      expect(edit.selection, at(1, 0));
    });

    test('on an empty line, in a list or mid-word, starts none', () {
      expect(TableEditing.startTable(<TextBlock>[p('')], at(0, 0)), isNull);
      expect(TableEditing.startTable(<TextBlock>[p('ab')], at(0, 1)), isNull);
      expect(
        TableEditing.startTable(<TextBlock>[
          TextBlock.plain('item', kind: TextBlockKind.bulleted),
        ], at(0, 4)),
        isNull,
      );
    });

    test('in the last cell of the first row adds a column', () {
      final edit = TableEditing.moveToCell(<TextBlock>[
        c(0, 0, 'a'),
        c(0, 1, 'b'),
      ], at(1, 1))!;
      expect(show(edit.blocks), <String>['0,0:a', '0,1:b', '0,2:']);
      expect(edit.selection, at(2, 0));
    });

    test('a column added to a table of several rows is added to each', () {
      final table = TextTables.tableAt(sample, 1)!;
      final edit = TableEditing.insertColumn(sample, table, 1, caretRow: 1);
      expect(show(edit.blocks), <String>[
        'before',
        '0,0:a',
        '0,1:',
        '0,2:b',
        '1,0:c',
        '1,1:',
        '1,2:d',
        'after',
      ]);
      expect(edit.selection, at(5, 0));
    });

    test('moves on to the end of the next cell, and to the next row', () {
      expect(TableEditing.moveToCell(sample, at(3, 0))!.selection, at(4, 1));
      final edit = TableEditing.moveToCell(<TextBlock>[
        ...sample.sublist(0, 5),
        c(2, 0, 'e'),
        c(2, 1, 'f'),
      ], at(4, 1))!;
      expect(edit.selection, at(5, 1), reason: 'the third row');
    });

    test('in the last cell of the table adds a row', () {
      final edit = TableEditing.moveToCell(sample, at(4, 1))!;
      expect(show(edit.blocks).sublist(5, 7), <String>['2,0:', '2,1:']);
      expect(edit.selection, at(5, 0));
    });

    test('Shift+Tab goes back, to the row above from a first cell', () {
      expect(
        TableEditing.moveToCell(sample, at(3, 0), backward: true)!.selection,
        at(2, 1),
      );
      expect(
        TableEditing.moveToCell(sample, at(1, 0), backward: true)!.selection,
        at(1, 0),
      );
    });

    test('outside a table is not a table matter', () {
      expect(TableEditing.moveToCell(sample, at(0, 2)), isNull);
    });
  });

  group('Enter', () {
    test('at the end of a row adds a row below it', () {
      final edit = TableEditing.insertBreak(sample, at(2, 1))!;
      expect(show(edit.blocks), <String>[
        'before',
        '0,0:a',
        '0,1:b',
        '1,0:',
        '1,1:',
        '2,0:c',
        '2,1:d',
        'after',
      ]);
      expect(edit.selection, at(3, 0));
    });

    test('in another cell is a new line of that cell', () {
      expect(TableEditing.insertBreak(sample, at(1, 1)), isNull);
      final edit = RichTextEditing.insertParagraphBreak(sample, at(1, 1));
      expect(show(edit.blocks).sublist(1, 4), <String>[
        '0,0:a',
        '0,0:',
        '0,1:b',
      ]);
    });

    test('in the first cell of an empty last row leaves the table', () {
      final grown = TableEditing.insertBreak(sample, at(4, 1))!;
      final left = TableEditing.insertBreak(grown.blocks, grown.selection)!;
      expect(show(left.blocks), <String>[
        'before',
        '0,0:a',
        '0,1:b',
        '1,0:c',
        '1,1:d',
        '',
        'after',
      ]);
      expect(left.selection, at(5, 0));
    });

    test('in an empty row in the middle splits the table there', () {
      final edit = TableEditing.insertBreak(
        TextTables.normalize(<TextBlock>[
          c(0, 0, 'a'),
          c(0, 1),
          c(1, 0),
          c(1, 1),
          c(2, 0, 'c'),
          c(2, 1),
        ]),
        at(2, 0),
      )!;
      expect(show(edit.blocks), <String>['0,0:a', '0,1:', '', '0,0:c', '0,1:']);
      expect(TextTables.tablesIn(edit.blocks), hasLength(2));
    });

    test('in the only row, when empty, turns it back into a paragraph', () {
      final edit = TableEditing.insertBreak(<TextBlock>[
        c(0, 0),
        c(0, 1),
      ], at(0, 0))!;
      expect(show(edit.blocks), <String>['']);
    });
  });

  group('deleting', () {
    test('a block of cells is emptied, without joining them', () {
      final edit = RichTextEditing.deleteRange(grid, range(2, 1, 4, 0));
      expect(show(edit.blocks), <String>[
        '0,0:a',
        '0,1:',
        '0,2:',
        '1,0:d',
        '1,1:',
        '1,2:',
        '2,0:g',
        '2,1:h',
        '2,2:i',
      ]);
      expect(edit.selection, at(1, 0), reason: 'in its top-left cell');
    });

    test('rows taken in whole go, and columns taken in whole', () {
      final rows = RichTextEditing.deleteRange(
        grid,
        range(3, 0, 5, 1),
        closeUp: true,
      );
      expect(show(rows.blocks), <String>[
        '0,0:a',
        '0,1:b',
        '0,2:c',
        '1,0:g',
        '1,1:h',
        '1,2:i',
      ]);
      final columns = RichTextEditing.deleteRange(
        grid,
        range(8, 1, 1, 0),
        closeUp: true,
      );
      expect(show(columns.blocks), <String>['0,0:a', '1,0:d', '2,0:g']);
      expect(columns.selection, at(0, 1), reason: 'where the block was');

      // Typing over them only empties them.
      final typed = RichTextEditing.insertText(grid, range(8, 1, 1, 0), 'x');
      expect(show(typed.blocks), <String>[
        '0,0:a',
        '0,1:x',
        '0,2:',
        '1,0:d',
        '1,1:',
        '1,2:',
        '2,0:g',
        '2,1:',
        '2,2:',
      ]);
    });

    test('a selection from one cell into another takes in the block of '
        'cells between them', () {
      final covered = RichTextEditing.coveredBy(grid, range(1, 0, 5, 1));
      expect(covered.map((part) => part.block), <int>[1, 2, 4, 5]);
      expect(covered.every((part) => part.cell), isTrue);
      final bold = RichTextEditing.applyMarks(
        grid,
        range(1, 0, 3, 1),
        (marks) => marks.copyWith(bold: true),
      );
      expect(
        show(bold.where((block) => block.runs.single.marks.bold).toList()),
        <String>['0,0:a', '0,1:b', '1,0:d', '1,1:e'],
      );
    });

    test('a table taken in whole goes, and the text either side joins', () {
      final edit = RichTextEditing.deleteRange(sample, range(0, 3, 5, 2));
      expect(show(edit.blocks), <String>['befter']);
      expect(edit.selection, at(0, 3));
    });

    test('from the text above into a table, the rows taken go', () {
      final edit = RichTextEditing.deleteRange(sample, range(0, 3, 3, 1));
      expect(show(edit.blocks), <String>['bef', '0,0:', '0,1:d', 'after']);
    });

    test('Backspace at the start of a cell leaves the cells as they are', () {
      final edit = RichTextEditing.deleteBackwardAtBlockStart(sample, 2);
      expect(edit.blocks, same(sample));
      expect(edit.selection, at(2, 0));
    });

    test('Backspace below a table steps into it, removing an empty line', () {
      final into = RichTextEditing.deleteBackwardAtBlockStart(sample, 5);
      expect(into.blocks, same(sample));
      expect(into.selection, at(4, 1));
      final emptied = RichTextEditing.deleteBackwardAtBlockStart(<TextBlock>[
        ...sample.sublist(0, 5),
        p(''),
      ], 5);
      expect(show(emptied.blocks).last, '1,1:d');
      expect(emptied.selection, at(4, 1));
    });

    test('Delete at the end of a cell, or above a table, joins nothing', () {
      expect(
        RichTextEditing.deleteForwardAtBlockEnd(sample, 1).blocks,
        same(sample),
      );
      expect(
        RichTextEditing.deleteForwardAtBlockEnd(sample, 0).blocks,
        same(sample),
      );
      final emptied = RichTextEditing.deleteForwardAtBlockEnd(<TextBlock>[
        p(''),
        ...sample.sublist(1),
      ], 0);
      expect(show(emptied.blocks).first, '0,0:a');
    });

    test(
      'Backspace in an empty cell of an empty column removes the column',
      () {
        final edit = TableEditing.deleteBackward(<TextBlock>[
          c(0, 0, 'a'),
          c(0, 1),
          c(1, 0, 'b'),
          c(1, 1),
        ], 3)!;
        expect(show(edit.blocks), <String>['0,0:a', '1,0:b']);
        expect(
          edit.selection,
          at(1, 1),
          reason: 'at the end of the cell before',
        );
      },
    );

    test('Backspace in an empty row removes the row', () {
      final edit = TableEditing.deleteBackward(<TextBlock>[
        ...sample.sublist(1, 5),
        c(2, 0),
        c(2, 1),
      ], 4)!;
      expect(show(edit.blocks), <String>['0,0:a', '0,1:b', '1,0:c', '1,1:d']);
      expect(edit.selection, at(3, 1));
    });

    test('Backspace in an empty cell otherwise steps back a cell', () {
      final edit = TableEditing.deleteBackward(<TextBlock>[
        c(0, 0, 'a'),
        c(0, 1, 'b'),
        c(1, 0, 'c'),
        c(1, 1),
      ], 3)!;
      expect(edit.blocks, hasLength(4));
      expect(edit.selection, at(2, 1));
      expect(TableEditing.deleteBackward(sample, 2), isNull, reason: 'text');
    });

    test('the lines of one cell join as paragraphs do', () {
      final edit = RichTextEditing.deleteBackwardAtBlockStart(<TextBlock>[
        c(0, 0, 'a'),
        c(0, 0, 'b'),
        c(0, 1),
      ], 1);
      expect(show(edit.blocks), <String>['0,0:ab', '0,1:']);
    });

    test('a picture alone in a cell leaves the cell an empty line', () {
      final edit = RichTextEditing.deleteEmbed(<TextBlock>[
        const TextBlock.embedded(
          BlockEmbed(kind: EmbedKind.image, assetId: 'i', width: 4, height: 3),
          cell: TableCell(0, 0),
        ),
        c(0, 1, 'b'),
      ], 0);
      expect(show(edit.blocks), <String>['0,0:', '0,1:b']);
    });

    test('rows, columns and tables are removed whole', () {
      final table = TextTables.tableAt(sample, 1)!;
      expect(show(TableEditing.deleteRow(sample, table, 0).blocks), <String>[
        'before',
        '0,0:c',
        '0,1:d',
        'after',
      ]);
      expect(
        show(TableEditing.deleteColumn(sample, table, 0, caretRow: 0).blocks),
        <String>['before', '0,0:b', '1,0:d', 'after'],
      );
      expect(show(TableEditing.deleteTable(sample, table).blocks), <String>[
        'before',
        'after',
      ]);
    });
  });

  group('copying and pasting', () {
    test('a table copied whole stays a table, cells are copied as one, and '
        'text in a cell as text', () {
      expect(show(RichTextEditing.slice(sample, range(0, 6, 5, 0))), <String>[
        '',
        '0,0:a',
        '0,1:b',
        '1,0:c',
        '1,1:d',
        '',
      ]);
      expect(show(RichTextEditing.slice(grid, range(5, 1, 7, 0))), <String>[
        '0,0:e',
        '0,1:f',
        '1,0:h',
        '1,1:i',
      ]);
      expect(show(RichTextEditing.slice(sample, range(1, 0, 1, 1))), <String>[
        'a',
      ]);
    });

    test('a table as plain text has its cells separated by tabs', () {
      expect(RichTextEditing.plainTextOf(sample.sublist(1, 5)), 'a\tb\nc\td');
    });

    test('pasted into a cell, lines become lines of the cell', () {
      final edit = RichTextEditing.insertFragment(sample, at(1, 1), <TextBlock>[
        p('x'),
        p('y'),
      ]);
      expect(show(edit.blocks).sublist(1, 4), <String>[
        '0,0:ax',
        '0,0:y',
        '0,1:b',
      ]);
    });

    test('a table pasted into a paragraph stays one, beside the text', () {
      final edit = RichTextEditing.insertFragment(
        <TextBlock>[p('onetwo')],
        at(0, 3),
        sample.sublist(1, 5),
      );
      expect(show(edit.blocks), <String>[
        'one',
        '0,0:a',
        '0,1:b',
        '1,0:c',
        '1,1:d',
        'two',
      ]);
    });

    test('Enter in a cell keeps the new line in it', () {
      final edit = RichTextEditing.splitBlock(sample, const RichPosition(1, 0));
      expect(edit.blocks[1].cell, const TableCell(0, 0));
      expect(edit.blocks[2].cell, const TableCell(0, 0));
    });
  });

  group('column widths', () {
    test('a dragged width is kept by every cell of its column', () {
      final table = TextTables.tableAt(sample, 1)!;
      final blocks = TableEditing.setColumnWidth(sample, table, 1, 10);
      expect(TextTables.widthsOf(blocks, table), <double?>[
        null,
        TableEditing.minColumnWidth,
      ]);
      final fitted = TableEditing.setColumnWidth(blocks, table, 1, null);
      expect(TextTables.widthsOf(fitted, table), <double?>[null, null]);
      final wide = TableEditing.setColumnWidth(blocks, table, 0, 50);
      expect(
        TextTables.widthsOf(TableEditing.fitColumns(wide, table), table),
        <double?>[null, null],
      );
    });

    test('removing the first row keeps the widths', () {
      final table = TextTables.tableAt(sample, 1)!;
      final wide = TableEditing.setColumnWidth(sample, table, 0, 90);
      final edit = TableEditing.deleteRow(wide, table, 0);
      expect(
        TextTables.widthsOf(edit.blocks, TextTables.tableAt(edit.blocks, 1)!),
        <double?>[90, null],
      );
    });
  });
}
