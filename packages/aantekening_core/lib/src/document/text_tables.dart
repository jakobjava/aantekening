/// Finding the tables among a text box's blocks, and keeping them whole.
library;

import 'rich_text.dart';

/// A table among a text box's blocks: the blocks from [start] up to, but not
/// including, [end], every one of them a line of one of its cells.
class TextTable {
  const TextTable({
    required this.start,
    required this.end,
    required this.rows,
    required this.columns,
  });

  final int start;
  final int end;
  final int rows;
  final int columns;

  bool contains(int index) => index >= start && index < end;

  @override
  bool operator ==(Object other) =>
      other is TextTable &&
      other.start == start &&
      other.end == end &&
      other.rows == rows &&
      other.columns == columns;

  @override
  int get hashCode => Object.hash(start, end, rows, columns);

  @override
  String toString() => 'TextTable($start–$end, $rows×$columns)';
}

/// The blocks from [start] up to, but not including, [end]: the lines of one
/// cell.
typedef CellSpan = ({int start, int end});

/// Where tables are among a text box's blocks.
///
/// A table's cells come in reading order, so a cell that comes before the
/// one above it in the blocks begins another table.
abstract final class TextTables {
  /// Whether [block] carries on the table [previous] is in, rather than
  /// beginning a table — or being outside one.
  static bool continues(TextBlock previous, TextBlock block) {
    final before = previous.cell;
    final cell = block.cell;
    return before != null && cell != null && !cell.isBefore(before);
  }

  /// Every table in [blocks], in order.
  static List<TextTable> tablesIn(List<TextBlock> blocks) {
    final tables = <TextTable>[];
    var i = 0;
    while (i < blocks.length) {
      if (!blocks[i].inTable) {
        i++;
        continue;
      }
      final table = _tableFrom(blocks, i);
      tables.add(table);
      i = table.end;
    }
    return tables;
  }

  /// The table block [index] is in, or null for a block outside any.
  static TextTable? tableAt(List<TextBlock> blocks, int index) {
    if (index < 0 || index >= blocks.length || !blocks[index].inTable) {
      return null;
    }
    var start = index;
    while (start > 0 && continues(blocks[start - 1], blocks[start])) {
      start--;
    }
    return _tableFrom(blocks, start);
  }

  static TextTable _tableFrom(List<TextBlock> blocks, int start) {
    var end = start + 1;
    while (end < blocks.length && continues(blocks[end - 1], blocks[end])) {
      end++;
    }
    var rows = 0;
    var columns = 0;
    for (var i = start; i < end; i++) {
      final cell = blocks[i].cell!;
      if (cell.row >= rows) rows = cell.row + 1;
      if (cell.column >= columns) columns = cell.column + 1;
    }
    return TextTable(start: start, end: end, rows: rows, columns: columns);
  }

  /// The lines of the cell block [index] is in: itself alone outside a
  /// table.
  static CellSpan cellAt(List<TextBlock> blocks, int index) {
    final cell = blocks[index].cell;
    if (cell == null) return (start: index, end: index + 1);
    var start = index;
    while (start > 0 && _sameCell(blocks[start - 1], cell)) {
      start--;
    }
    var end = index + 1;
    while (end < blocks.length && _sameCell(blocks[end], cell)) {
      end++;
    }
    return (start: start, end: end);
  }

  static bool _sameCell(TextBlock block, TableCell cell) {
    final other = block.cell;
    return other != null && other.sameCell(cell);
  }

  /// The lines of cell [row], [column] of [table], or null for a cell it
  /// does not have.
  static CellSpan? cellIn(
    List<TextBlock> blocks,
    TextTable table,
    int row,
    int column,
  ) {
    for (var i = table.start; i < table.end; i++) {
      final cell = blocks[i].cell!;
      if (cell.row == row && cell.column == column) return cellAt(blocks, i);
    }
    return null;
  }

  /// The width each column of [table] was dragged to, or null for one
  /// fitted to what it holds.
  static List<double?> widthsOf(List<TextBlock> blocks, TextTable table) {
    final widths = List<double?>.filled(table.columns, null, growable: true);
    final seen = List<bool>.filled(table.columns, false);
    for (var i = table.start; i < table.end; i++) {
      final cell = blocks[i].cell!;
      if (seen[cell.column]) continue;
      seen[cell.column] = true;
      widths[cell.column] = cell.width;
    }
    return widths;
  }

  /// Whether every line of column [column] of [table] is empty.
  static bool columnIsEmpty(
    List<TextBlock> blocks,
    TextTable table,
    int column,
  ) {
    for (var i = table.start; i < table.end; i++) {
      final block = blocks[i];
      if (block.cell!.column == column && block.length > 0) return false;
    }
    return true;
  }

  /// Whether every line of row [row] of [table] is empty.
  static bool rowIsEmpty(List<TextBlock> blocks, TextTable table, int row) {
    for (var i = table.start; i < table.end; i++) {
      final block = blocks[i];
      if (block.cell!.row == row && block.length > 0) return false;
    }
    return true;
  }

  /// [blocks] with every table made a whole grid again: rows and columns
  /// numbered from zero with none skipped, a cell every row lacks added
  /// empty, and each column's width the one its first cell has.
  ///
  /// Editing works on lines, and removing lines can leave a table short of a
  /// cell or a row; this puts it right. [blocks] itself is returned when
  /// every table in it is whole.
  static List<TextBlock> normalize(List<TextBlock> blocks) {
    final tables = tablesIn(blocks);
    if (tables.isEmpty) return blocks;
    final out = <TextBlock>[];
    var next = 0;
    for (final table in tables) {
      out
        ..addAll(blocks.sublist(next, table.start))
        ..addAll(_normalized(blocks.sublist(table.start, table.end)));
      next = table.end;
    }
    out.addAll(blocks.sublist(next));
    if (out.length == blocks.length) {
      var same = true;
      for (var i = 0; i < out.length && same; i++) {
        same = out[i] == blocks[i];
      }
      if (same) return blocks;
    }
    return out;
  }

  static List<TextBlock> _normalized(List<TextBlock> lines) {
    final rows = <int>{for (final line in lines) line.cell!.row}.toList()
      ..sort();
    final columns = <int>{for (final line in lines) line.cell!.column}.toList()
      ..sort();
    final rowIndex = <int, int>{
      for (var i = 0; i < rows.length; i++) rows[i]: i,
    };
    final columnIndex = <int, int>{
      for (var i = 0; i < columns.length; i++) columns[i]: i,
    };
    final widths = List<double?>.filled(columns.length, null);
    final seen = List<bool>.filled(columns.length, false);
    for (final line in lines) {
      final column = columnIndex[line.cell!.column]!;
      if (seen[column]) continue;
      seen[column] = true;
      widths[column] = line.cell!.width;
    }

    final byCell = <int, List<TextBlock>>{};
    for (final line in lines) {
      final row = rowIndex[line.cell!.row]!;
      final column = columnIndex[line.cell!.column]!;
      (byCell[row * columns.length + column] ??= <TextBlock>[]).add(
        line.inCell(TableCell(row, column, width: widths[column])),
      );
    }
    return <TextBlock>[
      for (var row = 0; row < rows.length; row++)
        for (var column = 0; column < columns.length; column++)
          ...byCell[row * columns.length + column] ??
              <TextBlock>[
                TextBlock(cell: TableCell(row, column, width: widths[column])),
              ],
    ];
  }
}
