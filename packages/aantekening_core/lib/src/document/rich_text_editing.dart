/// Editing operations on the rich-text model.
///
/// Every operation takes a list of blocks and a selection and returns new ones,
/// leaving its inputs untouched. The text-box editor is a thin layer of input
/// handling over these functions, which is what lets the behaviour of Enter,
/// Backspace, paste and formatting be tested without a widget in sight.
library;

import 'dart:math' as math;

import 'rich_text.dart';
import 'text_tables.dart';

/// A caret position in a text box: a block and an offset within it.
///
/// Offsets count UTF-16 code units of the block's text, with a formula
/// counting its source. An embed block has offsets 0 (before the object) and 1
/// (after it).
class RichPosition implements Comparable<RichPosition> {
  const RichPosition(this.block, this.offset);

  static const RichPosition zero = RichPosition(0, 0);

  final int block;
  final int offset;

  @override
  int compareTo(RichPosition other) =>
      block != other.block ? block - other.block : offset - other.offset;

  bool operator <(RichPosition other) => compareTo(other) < 0;
  bool operator <=(RichPosition other) => compareTo(other) <= 0;
  bool operator >(RichPosition other) => compareTo(other) > 0;
  bool operator >=(RichPosition other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is RichPosition && other.block == block && other.offset == offset;

  @override
  int get hashCode => Object.hash(block, offset);

  @override
  String toString() => '($block:$offset)';
}

/// A selection in a text box, possibly spanning several blocks.
class RichSelection {
  const RichSelection(this.base, this.extent);

  const RichSelection.collapsed(RichPosition position)
    : base = position,
      extent = position;

  /// Where the selection was started; it stays put while [extent] moves.
  final RichPosition base;

  /// The end that moves as the selection is extended, and where the caret is.
  final RichPosition extent;

  bool get isCollapsed => base == extent;

  RichPosition get start => base <= extent ? base : extent;
  RichPosition get end => base <= extent ? extent : base;

  /// Whether the selection covers more than one block.
  bool get isMultiBlock => base.block != extent.block;

  @override
  bool operator ==(Object other) =>
      other is RichSelection && other.base == base && other.extent == extent;

  @override
  int get hashCode => Object.hash(base, extent);

  @override
  String toString() =>
      isCollapsed ? 'RichSelection($extent)' : 'RichSelection($base→$extent)';
}

/// The outcome of an edit: the new blocks and where the selection now is.
typedef RichEdit = ({List<TextBlock> blocks, RichSelection selection});

/// The start and end offsets of one run within its block.
typedef RunSpan = ({int start, int end});

/// What a selection takes in of one block: its text from [from] to [to], and
/// whether that is the block whole as a line of a table cell the selection
/// takes in whole ([cell]).
typedef Covered = ({int block, int from, int to, bool cell});

/// Pure editing operations over a list of [TextBlock]s.
abstract final class RichTextEditing {
  /// The deepest list nesting offered.
  static const int maxIndent = 8;

  // ------------------------------------------------------------------- runs

  /// Merges neighbouring runs that share formatting and drops empty text.
  ///
  /// Formulas are left exactly as they are — including an empty one, which is
  /// a formula the user has just started typing.
  static List<TextRun> normalizeRuns(List<TextRun> runs) {
    final out = <TextRun>[];
    for (final run in runs) {
      if (!run.isMath && run.text.isEmpty) continue;
      if (out.isNotEmpty &&
          !run.isMath &&
          !out.last.isMath &&
          out.last.marks == run.marks) {
        out[out.length - 1] = out.last.copyWith(text: out.last.text + run.text);
      } else {
        out.add(run);
      }
    }
    return out;
  }

  /// Splits [runs] at [offset] into what lies before and after it.
  ///
  /// A run of zero length sitting exactly at [offset] stays on the left.
  static (List<TextRun>, List<TextRun>) splitRuns(
    List<TextRun> runs,
    int offset,
  ) {
    final left = <TextRun>[];
    final right = <TextRun>[];
    var position = 0;
    for (final run in runs) {
      final end = position + run.text.length;
      if (end <= offset) {
        left.add(run);
      } else if (position >= offset) {
        right.add(run);
      } else {
        final cut = offset - position;
        left.add(run.copyWith(text: run.text.substring(0, cut)));
        right.add(run.copyWith(text: run.text.substring(cut)));
      }
      position = end;
    }
    return (left, right);
  }

  /// The start and end offset of every run in [block].
  static List<RunSpan> runSpans(TextBlock block) {
    final spans = <RunSpan>[];
    var position = 0;
    for (final run in block.runs) {
      final end = position + run.text.length;
      spans.add((start: position, end: end));
      position = end;
    }
    return spans;
  }

  /// The formatting that typing at [offset] in [block] should pick up: that of
  /// the text before it, or of the text after it where none comes before.
  ///
  /// Formulas are passed over, so writing on after one continues the text
  /// before it. Beside a formula with no text either side, typing takes the
  /// formula's size and colour, the only formatting it has.
  static TextMarks marksAt(TextBlock block, int offset) {
    var position = 0;
    TextRun? before;
    TextRun? after;
    TextRun? formula;
    for (final run in block.runs) {
      final end = position + run.text.length;
      if (!run.isMath && position < offset && offset < end) return run.marks;
      if (run.isMath) {
        formula ??= run;
      } else if (run.text.isNotEmpty) {
        if (end <= offset) {
          before = run;
        } else {
          after ??= run;
        }
      }
      position = end;
    }
    return (before ?? after)?.marks ?? formula?.marks ?? TextMarks.none;
  }

  // ----------------------------------------------------------------- blocks

  static TextBlock _withRuns(TextBlock block, List<TextRun> runs) =>
      block.copyWith(runs: normalizeRuns(runs));

  /// The part of [block] before [offset], or null when nothing is left of it.
  static TextBlock? _prefix(TextBlock block, int offset) {
    if (block.isEmbed) return offset >= 1 ? block : null;
    return _withRuns(block, splitRuns(block.runs, offset).$1);
  }

  /// The part of [block] from [offset] on, or null when nothing is left of it.
  static TextBlock? _suffix(TextBlock block, int offset) {
    if (block.isEmbed) return offset <= 0 ? block : null;
    return _withRuns(block, splitRuns(block.runs, offset).$2);
  }

  static List<TextBlock> _replaceRange(
    List<TextBlock> blocks,
    int from,
    int to,
    List<TextBlock> replacement,
  ) => <TextBlock>[
    ...blocks.sublist(0, from),
    ...replacement,
    ...blocks.sublist(to),
  ];

  /// Clamps [position] to a valid place in [blocks].
  static RichPosition clamp(List<TextBlock> blocks, RichPosition position) {
    if (blocks.isEmpty) return RichPosition.zero;
    final block = position.block.clamp(0, blocks.length - 1);
    final offset = position.offset.clamp(0, blocks[block].length);
    return RichPosition(block, offset);
  }

  /// The position at the very end of [blocks].
  static RichPosition endOf(List<TextBlock> blocks) => blocks.isEmpty
      ? RichPosition.zero
      : RichPosition(blocks.length - 1, blocks.last.length);

  // --------------------------------------------------------------- deleting

  /// Removes everything in [range], joining what is left either side.
  ///
  /// The joined block keeps the kind of the block the range started in, as
  /// every word processor does. An embed wholly inside the range is removed.
  /// A range across a table's cells never joins them (see
  /// [_deleteCells]); with [closeUp], as Delete and Cut have it, the rows
  /// and columns a block of selected cells takes in whole go with it, and
  /// without, as typing over them has it, they are emptied.
  static RichEdit deleteRange(
    List<TextBlock> blocks,
    RichSelection range, {
    bool closeUp = false,
  }) {
    if (range.isCollapsed) return (blocks: blocks, selection: range);
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);
    if (_crossesCells(blocks, start.block, end.block)) {
      return _deleteCells(blocks, start, end, closeUp: closeUp);
    }

    final head = _prefix(blocks[start.block], start.offset);
    final tail = _suffix(blocks[end.block], end.offset);

    final List<TextBlock> middle;
    final RichPosition caret;
    if (head != null && tail != null && !head.isEmbed && !tail.isEmbed) {
      middle = <TextBlock>[
        _withRuns(head, <TextRun>[...head.runs, ...tail.runs]),
      ];
      caret = RichPosition(start.block, head.length);
    } else if (head == null && tail == null) {
      final template = blocks[start.block];
      middle = <TextBlock>[
        template.isEmbed
            ? TextBlock(cell: template.cell)
            : _withRuns(template, const <TextRun>[]),
      ];
      caret = RichPosition(start.block, 0);
    } else {
      middle = <TextBlock>[?head, ?tail];
      // After a kept embed, the caret belongs at the start of the text that
      // follows it rather than on the object itself.
      caret = head == null
          ? RichPosition(start.block, 0)
          : (head.isEmbed && tail != null && !tail.isEmbed
                ? RichPosition(start.block + 1, 0)
                : RichPosition(start.block, head.length));
    }

    return (
      blocks: _replaceRange(blocks, start.block, end.block + 1, middle),
      selection: RichSelection.collapsed(caret),
    );
  }

  /// Whether the blocks from [from] to [to] are not all lines of one cell,
  /// nor all outside any table.
  static bool _crossesCells(List<TextBlock> blocks, int from, int to) {
    final first = blocks[from].cell;
    for (var i = from + 1; i <= to; i++) {
      final cell = blocks[i].cell;
      if (first == null ? cell != null : !_inCell(blocks[i], first)) {
        return true;
      }
    }
    return false;
  }

  static bool _inCell(TextBlock block, TableCell cell) =>
      block.cell?.sameCell(cell) ?? false;

  /// Whether blocks [a] and [b], one after the other, are lines of the same
  /// cell.
  static bool _sameCell(TextBlock a, TextBlock b) {
    final cell = a.cell;
    return cell != null && _inCell(b, cell);
  }

  /// What [range] takes in of each block it touches, in order.
  ///
  /// Within a cell, or outside any table, a selection takes in text, as in a
  /// paragraph, every block from its start to its end included. From one
  /// cell into another of the same table, it takes in the cells between
  /// them, whole, as OneNote selects cells: the block of them with those two
  /// at its corners. Running into or out of a table, it takes in whole every
  /// cell it passes.
  static List<Covered> coveredBy(List<TextBlock> blocks, RichSelection range) {
    if (range.isCollapsed) return const <Covered>[];
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);
    Covered text(int i) => (
      block: i,
      from: i == start.block ? start.offset : 0,
      to: i == end.block ? end.offset : blocks[i].length,
      cell: false,
    );
    Covered whole(int i) =>
        (block: i, from: 0, to: blocks[i].length, cell: true);

    if (!_crossesCells(blocks, start.block, end.block)) {
      return <Covered>[for (var i = start.block; i <= end.block; i++) text(i)];
    }
    final table = TextTables.tableAt(blocks, start.block);
    if (table != null && table.contains(end.block)) {
      final a = blocks[start.block].cell!;
      final b = blocks[end.block].cell!;
      final rows = (math.min(a.row, b.row), math.max(a.row, b.row));
      final columns = (
        math.min(a.column, b.column),
        math.max(a.column, b.column),
      );
      return <Covered>[
        for (var i = table.start; i < table.end; i++)
          if (blocks[i].cell! case final cell
              when cell.row >= rows.$1 &&
                  cell.row <= rows.$2 &&
                  cell.column >= columns.$1 &&
                  cell.column <= columns.$2)
            whole(i),
      ];
    }
    return <Covered>[
      for (var i = start.block; i <= end.block; i++)
        blocks[i].inTable ? whole(i) : text(i),
    ];
  }

  /// Deletes from [start] to [end] across a table's cells, which are never
  /// joined, and what is left of the text either side joins only outside
  /// any table.
  ///
  /// The cells the range takes in (see [coveredBy]) are emptied. Running
  /// into or out of a table, it takes away the rows it takes in whole, and a
  /// table it takes in whole, as it would lines of text. A block of cells
  /// selected from cell to cell is only emptied, unless [closeUp]: then the
  /// rows and columns it takes in whole go too.
  static RichEdit _deleteCells(
    List<TextBlock> blocks,
    RichPosition start,
    RichPosition end, {
    required bool closeUp,
  }) {
    final covered = <int>{
      for (final part in coveredBy(blocks, RichSelection(start, end)))
        part.block,
    };
    final within = TextTables.tableAt(blocks, start.block);
    final block = within != null && within.contains(end.block) ? within : null;
    final gone = <int>{
      for (final table in TextTables.tablesIn(blocks))
        if (table != block || closeUp)
          ..._goneFrom(blocks, table, covered, columns: table == block),
    };
    final first = blocks[start.block];
    final last = blocks[end.block];
    final head = first.inTable ? null : _prefix(first, start.offset);
    final tail = last.inTable ? null : _suffix(last, end.offset);

    final out = <TextBlock>[];
    RichPosition? caret = head == null
        ? null
        : RichPosition(start.block, head.length);
    for (var i = 0; i < blocks.length; i++) {
      final cell = blocks[i].cell;
      if (i == start.block && head != null) {
        out.add(head);
      } else if (i == end.block && tail != null) {
        if (head != null && !head.isEmbed && !tail.isEmbed) {
          out.last = _withRuns(head, <TextRun>[...head.runs, ...tail.runs]);
        } else {
          out.add(tail);
        }
      } else if (!covered.contains(i)) {
        out.add(blocks[i]);
      } else {
        // The caret goes to the first cell taken in, or where it was: the
        // end of the cell before it in its table, or else what follows.
        caret ??= !gone.contains(i)
            ? RichPosition(out.length, 0)
            : (out.isNotEmpty && TextTables.continues(out.last, blocks[i])
                  ? RichPosition(out.length - 1, out.last.length)
                  : RichPosition(out.length, 0));
        // An emptied cell keeps one line, empty.
        if (cell != null &&
            !gone.contains(i) &&
            !(i > 0 && _inCell(blocks[i - 1], cell))) {
          out.add(TextBlock(cell: cell));
        }
      }
    }
    if (out.isEmpty) out.add(const TextBlock());

    // Rows and columns left with no cells close up.
    final result = TextTables.normalize(out);
    return (
      blocks: result,
      selection: RichSelection.collapsed(
        clamp(result, caret ?? RichPosition(start.block, 0)),
      ),
    );
  }

  /// The lines of [table] in the rows [covered] takes in whole, and with
  /// [columns] in the columns it takes in whole.
  static Iterable<int> _goneFrom(
    List<TextBlock> blocks,
    TextTable table,
    Set<int> covered, {
    required bool columns,
  }) {
    final inRow = List<int>.filled(table.rows, 0);
    final inColumn = List<int>.filled(table.columns, 0);
    for (var i = table.start; i < table.end; i++) {
      final cell = blocks[i].cell!;
      // Each cell counted once, by its first line.
      final laterLine = i > table.start && _inCell(blocks[i - 1], cell);
      if (!covered.contains(i) || laterLine) continue;
      inRow[cell.row]++;
      inColumn[cell.column]++;
    }
    return <int>[
      for (var i = table.start; i < table.end; i++)
        if (inRow[blocks[i].cell!.row] == table.columns ||
            (columns && inColumn[blocks[i].cell!.column] == table.rows))
          i,
    ];
  }

  /// Backspace with a collapsed caret at the start of block [index].
  ///
  /// Unwinds the block one step at a time, the way list editing works in
  /// OneNote and Word: a list item first loses its bullet, then its
  /// indentation, and only then joins the block above.
  static RichEdit deleteBackwardAtBlockStart(
    List<TextBlock> blocks,
    int index,
  ) {
    final block = blocks[index];
    final unchanged = (
      blocks: blocks,
      selection: RichSelection.collapsed(RichPosition(index, 0)),
    );

    if (!block.isEmbed) {
      if (block.kind != TextBlockKind.paragraph) {
        return (
          blocks: _replaceRange(blocks, index, index + 1, <TextBlock>[
            block.copyWith(kind: TextBlockKind.paragraph, checked: false),
          ]),
          selection: unchanged.selection,
        );
      }
      if (block.indent > 0) {
        return (
          blocks: _replaceRange(blocks, index, index + 1, <TextBlock>[
            block.copyWith(indent: block.indent - 1),
          ]),
          selection: unchanged.selection,
        );
      }
    }
    if (index == 0) return unchanged;

    final previous = blocks[index - 1];
    if ((block.inTable || previous.inTable) && !_sameCell(previous, block)) {
      // Cells are never joined, to one another or to the text around their
      // table. Below a table, an empty line goes and the caret steps into
      // the last cell, as it does from a line with something on it.
      if (block.inTable) return unchanged;
      final lastCell = RichSelection.collapsed(
        RichPosition(index - 1, previous.length),
      );
      return (
        blocks: block.length == 0 && !block.isEmbed
            ? _replaceRange(blocks, index, index + 1, const <TextBlock>[])
            : blocks,
        selection: lastCell,
      );
    }
    if (previous.isEmbed) {
      // The object above is removed whole; the caret stays where it was.
      return (
        blocks: _replaceRange(blocks, index - 1, index, const <TextBlock>[]),
        selection: RichSelection.collapsed(RichPosition(index - 1, 0)),
      );
    }
    if (block.isEmbed) {
      // An object cannot join a paragraph. An empty line above it is removed;
      // otherwise the caret simply moves up.
      if (previous.length == 0) {
        return (
          blocks: _replaceRange(blocks, index - 1, index, const <TextBlock>[]),
          selection: RichSelection.collapsed(RichPosition(index - 1, 0)),
        );
      }
      return (
        blocks: blocks,
        selection: RichSelection.collapsed(
          RichPosition(index - 1, previous.length),
        ),
      );
    }
    return deleteRange(
      blocks,
      RichSelection(
        RichPosition(index - 1, previous.length),
        RichPosition(index, 0),
      ),
    );
  }

  /// Delete with a collapsed caret at the end of block [index].
  static RichEdit deleteForwardAtBlockEnd(List<TextBlock> blocks, int index) {
    final block = blocks[index];
    final unchanged = (
      blocks: blocks,
      selection: RichSelection.collapsed(RichPosition(index, block.length)),
    );
    if (index == blocks.length - 1) return unchanged;

    final next = blocks[index + 1];
    if ((block.inTable || next.inTable) && !_sameCell(block, next)) {
      // Cells are never joined; above a table, an empty line goes.
      if (block.inTable || block.length > 0 || block.isEmbed) return unchanged;
      return (
        blocks: _replaceRange(blocks, index, index + 1, const <TextBlock>[]),
        selection: RichSelection.collapsed(RichPosition(index, 0)),
      );
    }
    if (next.isEmbed) {
      return (
        blocks: _replaceRange(
          blocks,
          index + 1,
          index + 2,
          const <TextBlock>[],
        ),
        selection: unchanged.selection,
      );
    }
    if (block.isEmbed) {
      if (next.length == 0) {
        return (
          blocks: _replaceRange(
            blocks,
            index + 1,
            index + 2,
            const <TextBlock>[],
          ),
          selection: unchanged.selection,
        );
      }
      return (
        blocks: blocks,
        selection: RichSelection.collapsed(RichPosition(index + 1, 0)),
      );
    }
    return deleteRange(
      blocks,
      RichSelection(
        RichPosition(index, block.length),
        RichPosition(index + 1, 0),
      ),
    );
  }

  /// Removes the embed block at [index], leaving an empty line if it was the
  /// only thing in the box, or in its table cell.
  static RichEdit deleteEmbed(List<TextBlock> blocks, int index) {
    final cell = TextTables.cellAt(blocks, index);
    if (blocks.length == 1 || cell.end - cell.start == 1) {
      return (
        blocks: _replaceRange(blocks, index, index + 1, <TextBlock>[
          TextBlock(cell: blocks[index].cell),
        ]),
        selection: RichSelection.collapsed(RichPosition(index, 0)),
      );
    }
    final next = _replaceRange(blocks, index, index + 1, const <TextBlock>[]);
    final caret = index < next.length
        ? RichPosition(index, 0)
        : RichPosition(index - 1, next[index - 1].length);
    return (blocks: next, selection: RichSelection.collapsed(caret));
  }

  // -------------------------------------------------------------- inserting

  /// Types [text] over [selection].
  ///
  /// Line breaks in [text] start new blocks, exactly as pressing Enter would,
  /// so pasting several lines of plain text behaves like typing them.
  static RichEdit insertText(
    List<TextBlock> blocks,
    RichSelection selection,
    String text, {
    TextMarks marks = TextMarks.none,
  }) {
    var edit = deleteRange(blocks, selection);
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) edit = splitBlock(edit.blocks, edit.selection.extent);
      if (lines[i].isEmpty) continue;
      edit = _insertInline(
        edit.blocks,
        edit.selection.extent,
        TextRun(lines[i], marks),
      );
    }
    return edit;
  }

  /// Inserts [run] at [at] without breaking the line.
  static RichEdit _insertInline(
    List<TextBlock> blocks,
    RichPosition at,
    TextRun run,
  ) {
    final position = clamp(blocks, at);
    final block = blocks[position.block];

    if (block.isEmbed) {
      // Text cannot go into an object, so it starts a line of its own beside
      // it: above when the caret is before the object, below when after.
      final line = TextBlock(
        runs: normalizeRuns(<TextRun>[run]),
        cell: block.cell,
      );
      final index = position.offset == 0 ? position.block : position.block + 1;
      return (
        blocks: _replaceRange(blocks, index, index, <TextBlock>[line]),
        selection: RichSelection.collapsed(
          RichPosition(index, run.text.length),
        ),
      );
    }

    final (left, right) = splitRuns(block.runs, position.offset);
    final updated = block.copyWith(runs: <TextRun>[...left, run, ...right]);
    return (
      blocks: _replaceRange(
        blocks,
        position.block,
        position.block + 1,
        <TextBlock>[updated.copyWith(runs: normalizeRuns(updated.runs))],
      ),
      selection: RichSelection.collapsed(
        RichPosition(position.block, position.offset + run.text.length),
      ),
    );
  }

  /// Splits the block at [at] in two, as Enter does.
  ///
  /// The new block continues a list, a quotation or a code block, but a
  /// heading is followed by an ordinary paragraph and a to-do starts
  /// unchecked. Enter beside an embed adds an empty line above or below it.
  static RichEdit splitBlock(List<TextBlock> blocks, RichPosition at) {
    final position = clamp(blocks, at);
    final block = blocks[position.block];

    if (block.isEmbed) {
      final before = position.offset == 0;
      final index = before ? position.block : position.block + 1;
      return (
        blocks: _replaceRange(blocks, index, index, <TextBlock>[
          TextBlock(indent: block.indent, cell: block.cell),
        ]),
        selection: RichSelection.collapsed(
          before ? RichPosition(position.block + 1, 0) : RichPosition(index, 0),
        ),
      );
    }

    final (left, right) = splitRuns(block.runs, position.offset);
    final continuation = switch (block.kind) {
      TextBlockKind.heading1 ||
      TextBlockKind.heading2 ||
      TextBlockKind.heading3 => TextBlockKind.paragraph,
      final kind => kind,
    };
    // Splitting at the very start of a heading moves the whole heading down
    // and leaves an ordinary line above it, rather than a heading-styled blank.
    final atStart = position.offset == 0 && block.length > 0;
    final first = atStart
        ? TextBlock(
            indent: block.indent,
            kind: continuation,
            bullet: block.bullet,
            cell: block.cell,
          )
        : _withRuns(block, left);
    final second = atStart
        ? block
        : TextBlock(
            kind: continuation,
            indent: block.indent,
            bullet: block.bullet,
            runs: normalizeRuns(right),
            cell: block.cell,
          );

    return (
      blocks: _replaceRange(
        blocks,
        position.block,
        position.block + 1,
        <TextBlock>[first, second],
      ),
      selection: RichSelection.collapsed(RichPosition(position.block + 1, 0)),
    );
  }

  /// Enter over [selection].
  ///
  /// On an empty list item, Enter leaves the list instead of adding another
  /// empty item — first by outdenting, then by becoming a plain paragraph —
  /// which is how every list editor lets you type your way out of a list.
  static RichEdit insertParagraphBreak(
    List<TextBlock> blocks,
    RichSelection selection,
  ) {
    final edit = deleteRange(blocks, selection);
    final caret = edit.selection.extent;
    final block = edit.blocks[caret.block];

    final isListLike = switch (block.kind) {
      TextBlockKind.bulleted ||
      TextBlockKind.numbered ||
      TextBlockKind.todo ||
      TextBlockKind.quote => true,
      _ => false,
    };
    if (!block.isEmbed && block.length == 0 && isListLike) {
      final unwound = block.indent > 0
          ? block.copyWith(indent: block.indent - 1)
          : block.copyWith(kind: TextBlockKind.paragraph, checked: false);
      return (
        blocks: _replaceRange(
          edit.blocks,
          caret.block,
          caret.block + 1,
          <TextBlock>[unwound],
        ),
        selection: edit.selection,
      );
    }
    return splitBlock(edit.blocks, caret);
  }

  /// Pastes [fragment] — blocks copied with [slice] — over [selection].
  ///
  /// The first and last pasted blocks join the text either side of the caret,
  /// so pasting part of a sentence into the middle of another reads on, while
  /// whole paragraphs in between keep their own kind and formatting. Pasted
  /// into a table cell, everything becomes lines of the cell; a table pasted
  /// elsewhere stays a table, joined to nothing.
  static RichEdit insertFragment(
    List<TextBlock> blocks,
    RichSelection selection,
    List<TextBlock> fragment,
  ) {
    if (fragment.isEmpty) return deleteRange(blocks, selection);
    final edit = deleteRange(blocks, selection);
    final caret = edit.selection.extent;
    final target = edit.blocks[caret.block];
    final cell = target.cell;
    bool joins(TextBlock piece) => !piece.isEmbed && !piece.inTable;

    // Pasting beside an embed never merges with it.
    final TextBlock? head;
    final TextBlock? tail;
    var insertAt = caret.block;
    if (target.isEmbed) {
      head = null;
      tail = null;
      insertAt = caret.offset == 0 ? caret.block : caret.block + 1;
    } else {
      head = _prefix(target, caret.offset);
      tail = _suffix(target, caret.offset);
    }

    final pieces = <TextBlock>[
      for (final piece in fragment) cell == null ? piece : piece.inCell(null),
    ];
    RichPosition end;

    if (head == null || tail == null) {
      final replaced = _replaceRange(
        edit.blocks,
        insertAt,
        insertAt,
        _intoCell(pieces, cell),
      );
      final last = insertAt + pieces.length - 1;
      end = RichPosition(last, replaced[last].length);
      return (
        blocks: TextTables.normalize(replaced),
        selection: RichSelection.collapsed(end),
      );
    }

    final result = <TextBlock>[];
    final first = pieces.first;
    if (pieces.length == 1 && joins(first)) {
      final joined = _withRuns(head, <TextRun>[
        ...head.runs,
        ...first.runs,
        ...tail.runs,
      ]);
      return (
        blocks: _replaceRange(
          edit.blocks,
          caret.block,
          caret.block + 1,
          <TextBlock>[joined],
        ),
        selection: RichSelection.collapsed(
          RichPosition(caret.block, head.length + first.length),
        ),
      );
    }

    if (!joins(first)) {
      if (head.length > 0) result.add(head);
      result.add(first);
    } else {
      result.add(_withRuns(head, <TextRun>[...head.runs, ...first.runs]));
    }
    for (var i = 1; i < pieces.length - 1; i++) {
      result.add(pieces[i]);
    }
    if (pieces.length > 1) {
      final last = pieces.last;
      if (!joins(last)) {
        result
          ..add(last)
          ..add(tail);
        end = RichPosition(caret.block + result.length - 1, 0);
      } else {
        result.add(_withRuns(last, <TextRun>[...last.runs, ...tail.runs]));
        end = RichPosition(caret.block + result.length - 1, last.length);
      }
    } else {
      // A single embed pasted into the middle of text: the text after the
      // caret continues on the line below it.
      result.add(tail);
      end = RichPosition(caret.block + result.length - 1, 0);
    }

    return (
      blocks: TextTables.normalize(
        _replaceRange(
          edit.blocks,
          caret.block,
          caret.block + 1,
          _intoCell(result, cell),
        ),
      ),
      selection: RichSelection.collapsed(end),
    );
  }

  /// [pieces] as lines of [cell], or as they are for null.
  static List<TextBlock> _intoCell(List<TextBlock> pieces, TableCell? cell) =>
      cell == null
      ? pieces
      : <TextBlock>[for (final piece in pieces) piece.inCell(cell)];

  /// Copies what [range] takes in (see [coveredBy]), trimmed to it.
  ///
  /// Cells taken in whole are copied as a table of just those cells; text
  /// copied from within one cell is copied as paragraphs.
  static List<TextBlock> slice(List<TextBlock> blocks, RichSelection range) {
    final out = <TextBlock>[];
    for (final part in coveredBy(blocks, range)) {
      final block = part.cell
          ? blocks[part.block]
          : blocks[part.block].inCell(null);
      if (block.isEmbed) {
        if (part.from < part.to) out.add(block);
        continue;
      }
      final (kept, _) = splitRuns(block.runs, part.to);
      out.add(_withRuns(block, splitRuns(kept, part.from).$2));
    }
    return TextTables.normalize(out);
  }

  /// The plain text of a fragment, one line per block, and a table's cells
  /// separated by tabs, as spreadsheets paste them.
  static String plainTextOf(List<TextBlock> fragment) {
    final out = StringBuffer();
    for (var i = 0; i < fragment.length; i++) {
      if (i > 0) {
        final previous = fragment[i - 1];
        final nextCell =
            TextTables.continues(previous, fragment[i]) &&
            !_sameCell(previous, fragment[i]) &&
            previous.cell!.row == fragment[i].cell!.row;
        out.write(nextCell ? '\t' : '\n');
      }
      out.write(fragment[i].plainText);
    }
    return out.toString();
  }

  // ---------------------------------------------------------------- formulas

  /// Inserts an empty formula at [at] and returns where it went.
  ///
  /// The formula takes the size and colour of [marks] — the formatting the
  /// text around it has — so it matches what it is written among. At an
  /// embed, the formula starts a new line beside it.
  static (RichEdit, {int block, int run}) insertMath(
    List<TextBlock> blocks,
    RichSelection selection,
    MathMode mode, {
    TextMarks marks = TextMarks.none,
  }) {
    final edit = deleteRange(blocks, selection);
    final position = edit.selection.extent;
    final block = edit.blocks[position.block];
    final formula = TextRun.math('', mode, marks.forFormula);

    if (block.isEmbed) {
      final index = position.offset == 0 ? position.block : position.block + 1;
      return (
        (
          blocks: _replaceRange(edit.blocks, index, index, <TextBlock>[
            TextBlock(runs: <TextRun>[formula], cell: block.cell),
          ]),
          selection: RichSelection.collapsed(RichPosition(index, 0)),
        ),
        block: index,
        run: 0,
      );
    }

    final (left, right) = splitRuns(block.runs, position.offset);
    final before = normalizeRuns(left);
    final runs = <TextRun>[...before, formula, ...normalizeRuns(right)];
    return (
      (
        blocks: _replaceRange(
          edit.blocks,
          position.block,
          position.block + 1,
          <TextBlock>[block.copyWith(runs: runs)],
        ),
        selection: RichSelection.collapsed(position),
      ),
      block: position.block,
      run: before.length,
    );
  }

  /// Replaces the text of run [run] in block [block], keeping every other run
  /// exactly as it is. This is how a formula's source is edited.
  static List<TextBlock> replaceRunText(
    List<TextBlock> blocks,
    int block,
    int run,
    String text,
  ) {
    final target = blocks[block];
    final runs = List<TextRun>.of(target.runs);
    runs[run] = runs[run].copyWith(text: text);
    return _replaceRange(blocks, block, block + 1, <TextBlock>[
      target.copyWith(runs: runs),
    ]);
  }

  /// Replaces run [run] of block [block] with [replacement].
  static List<TextBlock> replaceRun(
    List<TextBlock> blocks,
    int block,
    int run,
    TextRun replacement,
  ) {
    final target = blocks[block];
    final runs = List<TextRun>.of(target.runs);
    runs[run] = replacement;
    return _replaceRange(blocks, block, block + 1, <TextBlock>[
      target.copyWith(runs: runs),
    ]);
  }

  /// Removes run [run] from block [block], joining the text either side.
  static List<TextBlock> removeRun(List<TextBlock> blocks, int block, int run) {
    final target = blocks[block];
    final runs = List<TextRun>.of(target.runs)..removeAt(run);
    return _replaceRange(blocks, block, block + 1, <TextBlock>[
      target.copyWith(runs: normalizeRuns(runs)),
    ]);
  }

  // -------------------------------------------------------------- formatting

  /// Applies [change] to the formatting of all text in [range].
  ///
  /// Formulas are typeset by their own rules and keep only the colour and size
  /// the change gives them.
  static List<TextBlock> applyMarks(
    List<TextBlock> blocks,
    RichSelection range,
    TextMarks Function(TextMarks marks) change,
  ) {
    final out = List<TextBlock>.of(blocks);
    for (final (:block, :from, :to, cell: _) in coveredBy(blocks, range)) {
      final text = blocks[block];
      if (text.isEmbed || from >= to) continue;

      final (head, rest) = splitRuns(text.runs, from);
      final (middle, tail) = splitRuns(rest, to - from);
      out[block] = _withRuns(text, <TextRun>[
        ...head,
        for (final run in middle)
          run.copyWith(
            marks: run.isMath
                ? change(run.marks).forFormula
                : change(run.marks),
          ),
        ...tail,
      ]);
    }
    return out;
  }

  /// Whether every character of text in [range] satisfies [test].
  ///
  /// An empty or formula-only range does not count as formatted, so toggling
  /// over it switches the formatting on.
  static bool everyMark(
    List<TextBlock> blocks,
    RichSelection range,
    bool Function(TextMarks marks) test,
  ) => everyRun(blocks, range, (run) => test(run.marks), formulas: false);

  /// Whether every run in [range] — the text in it, and unless [formulas] is
  /// false the formulas — satisfies [test].
  ///
  /// A range holding none of those does not count, so toggling over it
  /// switches the formatting on.
  static bool everyRun(
    List<TextBlock> blocks,
    RichSelection range,
    bool Function(TextRun run) test, {
    bool formulas = true,
  }) {
    var saw = false;
    for (final (:block, :from, :to, cell: _) in coveredBy(blocks, range)) {
      final text = blocks[block];
      if (text.isEmbed) continue;
      var position = 0;
      for (final run in text.runs) {
        final runEnd = position + run.text.length;
        final overlaps = runEnd > from && position < to;
        if (overlaps && (formulas || !run.isMath)) {
          saw = true;
          if (!test(run)) return false;
        }
        position = runEnd;
      }
    }
    return saw;
  }

  /// The blocks [range] touches: the caret's alone while it is collapsed.
  static Set<int> _touched(List<TextBlock> blocks, RichSelection range) =>
      range.isCollapsed
      ? <int>{clamp(blocks, range.extent).block}
      : <int>{for (final part in coveredBy(blocks, range)) part.block};

  /// Sets every block touched by [range] to [kind], or back to a paragraph
  /// when they all already are one — the toggle a toolbar button expects.
  static List<TextBlock> toggleBlockKind(
    List<TextBlock> blocks,
    RichSelection range,
    TextBlockKind kind,
  ) {
    final touched = _touched(blocks, range);
    final all = touched.every(
      (i) => blocks[i].isEmbed || blocks[i].kind == kind,
    );
    final target = all ? TextBlockKind.paragraph : kind;
    return <TextBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (!touched.contains(i) || blocks[i].isEmbed)
          blocks[i]
        else
          blocks[i].copyWith(kind: target, checked: false),
    ];
  }

  /// Changes the indentation of every block touched by [range] by [delta].
  static List<TextBlock> indentBlocks(
    List<TextBlock> blocks,
    RichSelection range,
    int delta,
  ) {
    final touched = _touched(blocks, range);
    return <TextBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (!touched.contains(i))
          blocks[i]
        else
          blocks[i].copyWith(
            indent: (blocks[i].indent + delta).clamp(0, maxIndent),
          ),
    ];
  }

  /// Puts [embed] on block [index] in place of the object there, as resizing
  /// a picture does.
  static List<TextBlock> replaceEmbed(
    List<TextBlock> blocks,
    int index,
    BlockEmbed embed,
  ) => _replaceRange(blocks, index, index + 1, <TextBlock>[
    TextBlock.embedded(
      embed,
      indent: blocks[index].indent,
      cell: blocks[index].cell,
    ),
  ]);

  /// Ticks or unticks the to-do in block [index].
  static List<TextBlock> toggleChecked(List<TextBlock> blocks, int index) =>
      _replaceRange(blocks, index, index + 1, <TextBlock>[
        blocks[index].copyWith(checked: !blocks[index].checked),
      ]);

  // --------------------------------------------------------------- shortcuts

  /// Markdown-style prefixes that turn a paragraph into another kind when
  /// followed by a space, each with the mark its items take where it starts
  /// a bulleted list: a dash keeps its dash, as it does in Word.
  static const Map<String, ({TextBlockKind kind, BulletStyle bullet})>
  markdownPrefixes = <String, ({TextBlockKind kind, BulletStyle bullet})>{
    '-': (kind: TextBlockKind.bulleted, bullet: BulletStyle.dash),
    '*': (kind: TextBlockKind.bulleted, bullet: BulletStyle.disc),
    '1.': (kind: TextBlockKind.numbered, bullet: BulletStyle.disc),
    '[]': (kind: TextBlockKind.todo, bullet: BulletStyle.disc),
    '[ ]': (kind: TextBlockKind.todo, bullet: BulletStyle.disc),
    '#': (kind: TextBlockKind.heading1, bullet: BulletStyle.disc),
    '##': (kind: TextBlockKind.heading2, bullet: BulletStyle.disc),
    '###': (kind: TextBlockKind.heading3, bullet: BulletStyle.disc),
    '>': (kind: TextBlockKind.quote, bullet: BulletStyle.disc),
  };

  /// Converts a paragraph that begins with a Markdown prefix and a space into
  /// the matching kind, when the caret sits right after that space.
  ///
  /// Returns null when nothing applies, so the caller can tell whether the
  /// space it just typed turned into formatting.
  static RichEdit? applyMarkdownShortcut(
    List<TextBlock> blocks,
    RichPosition caret,
  ) {
    final block = blocks[caret.block];
    if (block.isEmbed || block.kind != TextBlockKind.paragraph) return null;
    if (block.runs.isEmpty || block.runs.first.isMath) return null;
    final text = block.plainText;
    if (caret.offset < 2 || text[caret.offset - 1] != ' ') return null;

    final prefix = text.substring(0, caret.offset - 1);
    final started = markdownPrefixes[prefix];
    if (started == null) return null;

    final (_, rest) = splitRuns(block.runs, caret.offset);
    return (
      blocks: _replaceRange(blocks, caret.block, caret.block + 1, <TextBlock>[
        TextBlock(
          kind: started.kind,
          indent: block.indent,
          bullet: started.bullet,
          runs: normalizeRuns(rest),
          cell: block.cell,
        ),
      ]),
      selection: RichSelection.collapsed(RichPosition(caret.block, 0)),
    );
  }
}
