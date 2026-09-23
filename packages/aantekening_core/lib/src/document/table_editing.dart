/// Editing tables in a text box.
library;

import 'rich_text.dart';
import 'rich_text_editing.dart';
import 'text_tables.dart';

/// The lines of each cell of a table, row by row.
typedef TableGrid = List<List<List<TextBlock>>>;

/// Pure operations on the tables among a text box's blocks (see
/// [TableCell]), made as OneNote makes them: Tab after a word starts one,
/// and Tab and Enter grow it.
abstract final class TableEditing {
  /// The narrowest a column can be dragged to, in page units.
  static const double minColumnWidth = 24;

  /// Tab after a word: the paragraph becomes the first cell of a table, and
  /// the caret goes to a new cell beside it.
  ///
  /// Only a collapsed caret at the end of a plain paragraph with words in it
  /// starts a table, or null is returned: Tab in a list indents it.
  static RichEdit? startTable(List<TextBlock> blocks, RichSelection selection) {
    if (!selection.isCollapsed) return null;
    final caret = selection.extent;
    final block = blocks[caret.block];
    if (block.inTable ||
        block.isEmbed ||
        block.kind != TextBlockKind.paragraph ||
        block.plainText.trim().isEmpty ||
        caret.offset != block.length) {
      return null;
    }
    return (
      blocks: <TextBlock>[
        ...blocks.sublist(0, caret.block),
        block.inCell(const TableCell(0, 0)),
        const TextBlock(cell: TableCell(0, 1)),
        ...blocks.sublist(caret.block + 1),
      ],
      selection: RichSelection.collapsed(RichPosition(caret.block + 1, 0)),
    );
  }

  /// Tab in a table: on to the next cell, or with [backward] back to the one
  /// before, the caret at the end of what it holds. Null where the caret is
  /// not in a table.
  ///
  /// From the last cell of the first row, Tab adds a column, so a table is
  /// made as wide as it is typed; from the last cell of the table, it adds a
  /// row.
  static RichEdit? moveToCell(
    List<TextBlock> blocks,
    RichSelection selection, {
    bool backward = false,
  }) {
    final caret = selection.extent;
    final table = TextTables.tableAt(blocks, caret.block);
    if (table == null) return null;
    final cell = blocks[caret.block].cell!;
    final last = cell.column == table.columns - 1;

    if (backward) {
      if (cell.row == 0 && cell.column == 0) {
        return (blocks: blocks, selection: RichSelection.collapsed(caret));
      }
      return (
        blocks: blocks,
        selection: _atEndOf(
          blocks,
          table,
          row: cell.column == 0 ? cell.row - 1 : cell.row,
          column: cell.column == 0 ? table.columns - 1 : cell.column - 1,
        ),
      );
    }
    if (last && cell.row == 0) {
      return insertColumn(blocks, table, table.columns, caretRow: 0);
    }
    if (last && cell.row == table.rows - 1) {
      return insertRow(blocks, table, table.rows);
    }
    return (
      blocks: blocks,
      selection: _atEndOf(
        blocks,
        table,
        row: last ? cell.row + 1 : cell.row,
        column: last ? 0 : cell.column + 1,
      ),
    );
  }

  static RichSelection _atEndOf(
    List<TextBlock> blocks,
    TextTable table, {
    required int row,
    required int column,
  }) {
    final span = TextTables.cellIn(blocks, table, row, column)!;
    return RichSelection.collapsed(
      RichPosition(span.end - 1, blocks[span.end - 1].length),
    );
  }

  /// Enter in a table, or null where the caret is not in one or Enter
  /// should just start another line of its cell.
  ///
  /// In the first cell of an empty row, the row gives way to a paragraph and
  /// the caret leaves the table there; at the very end of a row's last cell,
  /// a row is added below.
  static RichEdit? insertBreak(
    List<TextBlock> blocks,
    RichSelection selection,
  ) {
    final edit = RichTextEditing.deleteRange(blocks, selection);
    final caret = edit.selection.extent;
    final table = TextTables.tableAt(edit.blocks, caret.block);
    if (table == null) return null;
    final cell = edit.blocks[caret.block].cell!;

    if (cell.column == 0 &&
        TextTables.rowIsEmpty(edit.blocks, table, cell.row)) {
      return _leave(edit.blocks, table, cell.row);
    }
    final span = TextTables.cellAt(edit.blocks, caret.block);
    final atEnd =
        caret.block == span.end - 1 &&
        caret.offset == edit.blocks[caret.block].length;
    if (cell.column == table.columns - 1 && atEnd) {
      return insertRow(edit.blocks, table, cell.row + 1);
    }
    return null;
  }

  /// Backspace at the start of an empty cell, block [index] its first line,
  /// or null where that is not a table matter.
  ///
  /// The cell's column goes if it is empty all the way down, as a column Tab
  /// has just added is; else its row goes if it is empty all the way along,
  /// as a row Enter has just added is; else the caret steps back into the
  /// cell before. Either way the caret ends at the end of the cell before.
  /// A list item in a cell unwinds first, as anywhere.
  static RichEdit? deleteBackward(List<TextBlock> blocks, int index) {
    final table = TextTables.tableAt(blocks, index);
    final block = blocks[index];
    if (table == null ||
        block.kind != TextBlockKind.paragraph ||
        block.indent != 0) {
      return null;
    }
    final lines = TextTables.cellAt(blocks, index);
    if (lines.start != index) return null;
    for (var i = lines.start; i < lines.end; i++) {
      if (blocks[i].length > 0) return null;
    }
    final cell = block.cell!;
    if (TextTables.columnIsEmpty(blocks, table, cell.column)) {
      final edit = deleteColumn(blocks, table, cell.column, caretRow: cell.row);
      return cell.column == 0
          ? edit
          : _afterward(edit.blocks, table.start, cell.row, cell.column - 1);
    }
    if (TextTables.rowIsEmpty(blocks, table, cell.row)) {
      final edit = deleteRow(blocks, table, cell.row);
      return cell.row == 0
          ? edit
          : _afterward(
              edit.blocks,
              table.start,
              cell.row - 1,
              table.columns - 1,
            );
    }
    if (cell.row == 0 && cell.column == 0) return null;
    return cell.column == 0
        ? _afterward(blocks, table.start, cell.row - 1, table.columns - 1)
        : _afterward(blocks, table.start, cell.row, cell.column - 1);
  }

  /// [blocks], with the caret at the end of cell [row], [column] of the
  /// table starting at block [start].
  static RichEdit _afterward(
    List<TextBlock> blocks,
    int start,
    int row,
    int column,
  ) => (
    blocks: blocks,
    selection: _atEndOf(
      blocks,
      TextTables.tableAt(blocks, start)!,
      row: row,
      column: column,
    ),
  );

  /// Turns [row] of [table] into an empty paragraph, the rows either side of
  /// it staying tables of their own.
  static RichEdit _leave(List<TextBlock> blocks, TextTable table, int row) {
    final out = <TextBlock>[...blocks.sublist(0, table.start)];
    int? paragraph;
    for (var i = table.start; i < table.end; i++) {
      if (blocks[i].cell!.row != row) {
        out.add(blocks[i]);
      } else if (paragraph == null) {
        paragraph = out.length;
        out.add(const TextBlock());
      }
    }
    out.addAll(blocks.sublist(table.end));
    return (
      blocks: TextTables.normalize(out),
      selection: RichSelection.collapsed(RichPosition(paragraph!, 0)),
    );
  }

  // ------------------------------------------------------------ rows, columns

  /// The lines of each cell of [table], row by row.
  static TableGrid gridOf(List<TextBlock> blocks, TextTable table) {
    final grid = <List<List<TextBlock>>>[
      for (var row = 0; row < table.rows; row++)
        <List<TextBlock>>[
          for (var column = 0; column < table.columns; column++) <TextBlock>[],
        ],
    ];
    for (var i = table.start; i < table.end; i++) {
      final cell = blocks[i].cell!;
      grid[cell.row][cell.column].add(blocks[i]);
    }
    return grid;
  }

  /// [blocks] with [table] made of [grid], each line given the cell it is
  /// now in, with the column widths [widths] and an empty line in a cell
  /// that has none. The caret goes to the end of cell [caretRow],
  /// [caretColumn], or with [atStart] to its start.
  static RichEdit _withGrid(
    List<TextBlock> blocks,
    TextTable table,
    TableGrid grid,
    List<double?> widths, {
    required int caretRow,
    required int caretColumn,
    bool atStart = false,
  }) {
    final lines = <TextBlock>[];
    RichPosition? caret;
    for (var row = 0; row < grid.length; row++) {
      for (var column = 0; column < grid[row].length; column++) {
        final cell = TableCell(row, column, width: widths[column]);
        final content = grid[row][column];
        final placed = <TextBlock>[
          for (final line in content) line.inCell(cell),
          if (content.isEmpty) TextBlock(cell: cell),
        ];
        if (row == caretRow && column == caretColumn) {
          caret = atStart
              ? RichPosition(table.start + lines.length, 0)
              : RichPosition(
                  table.start + lines.length + placed.length - 1,
                  placed.last.length,
                );
        }
        lines.addAll(placed);
      }
    }
    return (
      blocks: <TextBlock>[
        ...blocks.sublist(0, table.start),
        ...lines,
        ...blocks.sublist(table.end),
      ],
      selection: RichSelection.collapsed(caret!),
    );
  }

  /// Adds an empty row to [table] before row [at], the caret in its first
  /// cell.
  static RichEdit insertRow(List<TextBlock> blocks, TextTable table, int at) {
    final grid = gridOf(blocks, table)
      ..insert(at, <List<TextBlock>>[
        for (var column = 0; column < table.columns; column++) <TextBlock>[],
      ]);
    return _withGrid(
      blocks,
      table,
      grid,
      TextTables.widthsOf(blocks, table),
      caretRow: at,
      caretColumn: 0,
    );
  }

  /// Adds an empty column to [table] before column [at], fitted to what it
  /// will hold, the caret in it on [caretRow].
  static RichEdit insertColumn(
    List<TextBlock> blocks,
    TextTable table,
    int at, {
    required int caretRow,
  }) {
    final grid = gridOf(blocks, table);
    for (final row in grid) {
      row.insert(at, <TextBlock>[]);
    }
    return _withGrid(
      blocks,
      table,
      grid,
      TextTables.widthsOf(blocks, table)..insert(at, null),
      caretRow: caretRow,
      caretColumn: at,
    );
  }

  /// Removes row [row] of [table], or the table with its only row.
  static RichEdit deleteRow(List<TextBlock> blocks, TextTable table, int row) {
    if (table.rows == 1) return deleteTable(blocks, table);
    final grid = gridOf(blocks, table)..removeAt(row);
    return _withGrid(
      blocks,
      table,
      grid,
      TextTables.widthsOf(blocks, table),
      caretRow: row.clamp(0, grid.length - 1),
      caretColumn: 0,
      atStart: true,
    );
  }

  /// Removes column [column] of [table], or the table with its only column.
  static RichEdit deleteColumn(
    List<TextBlock> blocks,
    TextTable table,
    int column, {
    required int caretRow,
  }) {
    if (table.columns == 1) return deleteTable(blocks, table);
    final grid = gridOf(blocks, table);
    for (final row in grid) {
      row.removeAt(column);
    }
    return _withGrid(
      blocks,
      table,
      grid,
      TextTables.widthsOf(blocks, table)..removeAt(column),
      caretRow: caretRow,
      caretColumn: column.clamp(0, table.columns - 2),
      atStart: true,
    );
  }

  /// Removes [table], the caret going to where it was.
  static RichEdit deleteTable(List<TextBlock> blocks, TextTable table) {
    final out = <TextBlock>[
      ...blocks.sublist(0, table.start),
      ...blocks.sublist(table.end),
    ];
    if (out.isEmpty) out.add(const TextBlock());
    return (
      blocks: out,
      selection: RichSelection.collapsed(
        table.start < out.length
            ? RichPosition(table.start, 0)
            : RichTextEditing.endOf(out),
      ),
    );
  }

  /// Fits every column of [table] to what it holds again.
  static List<TextBlock> fitColumns(List<TextBlock> blocks, TextTable table) =>
      <TextBlock>[
        for (var i = 0; i < blocks.length; i++)
          if (table.contains(i))
            blocks[i].inCell(blocks[i].cell!.withWidth(null))
          else
            blocks[i],
      ];

  /// Makes column [column] of [table] [width] wide, or with null fits it to
  /// what it holds, as the column's border is dragged or double-clicked.
  static List<TextBlock> setColumnWidth(
    List<TextBlock> blocks,
    TextTable table,
    int column,
    double? width,
  ) {
    final kept = width?.clamp(minColumnWidth, double.infinity);
    return <TextBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (table.contains(i) && blocks[i].cell!.column == column)
          blocks[i].inCell(blocks[i].cell!.withWidth(kept))
        else
          blocks[i],
    ];
  }
}
