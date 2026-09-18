/// Editing operations on the rich-text model.
///
/// Every operation takes a list of blocks and a selection and returns new ones,
/// leaving its inputs untouched. The text-box editor is a thin layer of input
/// handling over these functions, which is what lets the behaviour of Enter,
/// Backspace, paste and formatting be tested without a widget in sight.
library;

import 'rich_text.dart';

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
  /// the text just before it, or just after it at the start of a block.
  ///
  /// Formulas lend no formatting, so typing after one starts plain.
  static TextMarks marksAt(TextBlock block, int offset) {
    var position = 0;
    TextRun? before;
    TextRun? after;
    for (final run in block.runs) {
      final end = position + run.text.length;
      if (end <= offset && run.text.isNotEmpty) before = run;
      if (position >= offset && after == null && run.text.isNotEmpty) {
        after = run;
      }
      if (position < offset && offset < end) return run.marks;
      position = end;
    }
    final source = before ?? after;
    if (source == null || source.isMath) return TextMarks.none;
    return source.marks;
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
  static RichEdit deleteRange(List<TextBlock> blocks, RichSelection range) {
    if (range.isCollapsed) return (blocks: blocks, selection: range);
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);

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
            ? const TextBlock()
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
  /// only thing in the box.
  static RichEdit deleteEmbed(List<TextBlock> blocks, int index) {
    if (blocks.length == 1) {
      return (
        blocks: const <TextBlock>[TextBlock()],
        selection: const RichSelection.collapsed(RichPosition.zero),
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
      final line = TextBlock(runs: normalizeRuns(<TextRun>[run]));
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
          TextBlock(indent: block.indent),
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
        ? TextBlock(indent: block.indent, kind: continuation)
        : _withRuns(block, left);
    final second = atStart
        ? block
        : TextBlock(
            kind: continuation,
            indent: block.indent,
            runs: normalizeRuns(right),
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
  /// whole paragraphs in between keep their own kind and formatting.
  static RichEdit insertFragment(
    List<TextBlock> blocks,
    RichSelection selection,
    List<TextBlock> fragment,
  ) {
    if (fragment.isEmpty) return deleteRange(blocks, selection);
    final edit = deleteRange(blocks, selection);
    final caret = edit.selection.extent;
    final target = edit.blocks[caret.block];

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

    final pieces = <TextBlock>[...fragment];
    RichPosition end;

    if (head == null || tail == null) {
      final replaced = _replaceRange(edit.blocks, insertAt, insertAt, pieces);
      final last = insertAt + pieces.length - 1;
      end = RichPosition(last, replaced[last].length);
      return (blocks: replaced, selection: RichSelection.collapsed(end));
    }

    final result = <TextBlock>[];
    final first = pieces.first;
    if (pieces.length == 1 && !first.isEmbed) {
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

    if (first.isEmbed) {
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
      if (last.isEmbed) {
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
      blocks: _replaceRange(edit.blocks, caret.block, caret.block + 1, result),
      selection: RichSelection.collapsed(end),
    );
  }

  /// Copies the blocks in [range], trimmed to it.
  static List<TextBlock> slice(List<TextBlock> blocks, RichSelection range) {
    if (range.isCollapsed) return const <TextBlock>[];
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);
    final out = <TextBlock>[];
    for (var i = start.block; i <= end.block; i++) {
      var block = blocks[i];
      if (block.isEmbed) {
        final from = i == start.block ? start.offset : 0;
        final to = i == end.block ? end.offset : 1;
        if (from < to) out.add(block);
        continue;
      }
      if (i == end.block) {
        block = _withRuns(block, splitRuns(block.runs, end.offset).$1);
      }
      if (i == start.block) {
        block = _withRuns(block, splitRuns(block.runs, start.offset).$2);
      }
      out.add(block);
    }
    return out;
  }

  /// The plain text of a fragment, one line per block.
  static String plainTextOf(List<TextBlock> fragment) =>
      fragment.map((block) => block.plainText).join('\n');

  // ---------------------------------------------------------------- formulas

  /// Inserts an empty formula at [at] and returns where it went.
  ///
  /// At an embed, the formula starts a new line beside it.
  static (RichEdit, {int block, int run}) insertMath(
    List<TextBlock> blocks,
    RichSelection selection,
    MathMode mode,
  ) {
    final edit = deleteRange(blocks, selection);
    final position = edit.selection.extent;
    final block = edit.blocks[position.block];
    final formula = TextRun.math('', mode);

    if (block.isEmbed) {
      final index = position.offset == 0 ? position.block : position.block + 1;
      return (
        (
          blocks: _replaceRange(edit.blocks, index, index, <TextBlock>[
            TextBlock(runs: <TextRun>[formula]),
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
    if (range.isCollapsed) return blocks;
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);
    final out = List<TextBlock>.of(blocks);

    for (var i = start.block; i <= end.block; i++) {
      final block = blocks[i];
      if (block.isEmbed) continue;
      final from = i == start.block ? start.offset : 0;
      final to = i == end.block ? end.offset : block.length;
      if (from >= to) continue;

      final (head, rest) = splitRuns(block.runs, from);
      final (middle, tail) = splitRuns(rest, to - from);
      out[i] = _withRuns(block, <TextRun>[
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
  ) {
    final start = clamp(blocks, range.start);
    final end = clamp(blocks, range.end);
    var sawText = false;
    for (var i = start.block; i <= end.block; i++) {
      final block = blocks[i];
      if (block.isEmbed) continue;
      final from = i == start.block ? start.offset : 0;
      final to = i == end.block ? end.offset : block.length;
      var position = 0;
      for (final run in block.runs) {
        final runEnd = position + run.text.length;
        final overlaps = runEnd > from && position < to;
        if (overlaps && !run.isMath) {
          sawText = true;
          if (!test(run.marks)) return false;
        }
        position = runEnd;
      }
    }
    return sawText;
  }

  /// Sets every block touched by [range] to [kind], or back to a paragraph
  /// when they all already are one — the toggle a toolbar button expects.
  static List<TextBlock> toggleBlockKind(
    List<TextBlock> blocks,
    RichSelection range,
    TextBlockKind kind,
  ) {
    final start = clamp(blocks, range.start).block;
    final end = clamp(blocks, range.end).block;
    var all = true;
    for (var i = start; i <= end; i++) {
      if (!blocks[i].isEmbed && blocks[i].kind != kind) all = false;
    }
    final target = all ? TextBlockKind.paragraph : kind;
    return <TextBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (i < start || i > end || blocks[i].isEmbed)
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
    final start = clamp(blocks, range.start).block;
    final end = clamp(blocks, range.end).block;
    return <TextBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (i < start || i > end)
          blocks[i]
        else
          blocks[i].copyWith(
            indent: (blocks[i].indent + delta).clamp(0, maxIndent),
          ),
    ];
  }

  /// Ticks or unticks the to-do in block [index].
  static List<TextBlock> toggleChecked(List<TextBlock> blocks, int index) =>
      _replaceRange(blocks, index, index + 1, <TextBlock>[
        blocks[index].copyWith(checked: !blocks[index].checked),
      ]);

  // --------------------------------------------------------------- shortcuts

  /// Markdown-style prefixes that turn a paragraph into another kind when
  /// followed by a space.
  static const Map<String, TextBlockKind> markdownPrefixes =
      <String, TextBlockKind>{
        '-': TextBlockKind.bulleted,
        '*': TextBlockKind.bulleted,
        '1.': TextBlockKind.numbered,
        '[]': TextBlockKind.todo,
        '[ ]': TextBlockKind.todo,
        '#': TextBlockKind.heading1,
        '##': TextBlockKind.heading2,
        '###': TextBlockKind.heading3,
        '>': TextBlockKind.quote,
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
    final kind = markdownPrefixes[prefix];
    if (kind == null) return null;

    final (_, rest) = splitRuns(block.runs, caret.offset);
    return (
      blocks: _replaceRange(blocks, caret.block, caret.block + 1, <TextBlock>[
        TextBlock(kind: kind, indent: block.indent, runs: normalizeRuns(rest)),
      ]),
      selection: RichSelection.collapsed(RichPosition(caret.block, 0)),
    );
  }
}
