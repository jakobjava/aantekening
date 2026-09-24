/// Rich text written out as Markdown, for readers that are not people.
library;

import '../document/rich_text.dart';
import '../document/text_tables.dart';

/// Rich text as Markdown: headings, lists, to-dos, emphasis, highlights as
/// `==…==`, links, and formulas as `$…$` in their LaTeX.
///
/// What a reader of text needs to tell apart is kept — a highlighted phrase
/// is one the author marked as mattering — and what only changes the look,
/// such as a colour or a size, is left out.
abstract final class RichMarkdown {
  /// [block] as one line of Markdown, list markers and all; a formula alone
  /// in its paragraph is written on its own as display maths.
  static String block(TextBlock block, {int ordinal = 1}) {
    final runs = block.runs;
    if (runs.length == 1 && runs.single.isMath) {
      return '\$\$${runs.single.text}\$\$';
    }
    final text = inline(runs);
    final indent = '  ' * block.indent;
    return switch (block.kind) {
      TextBlockKind.heading1 => '# $text',
      TextBlockKind.heading2 => '## $text',
      TextBlockKind.heading3 => '### $text',
      TextBlockKind.bulleted => '$indent- $text',
      TextBlockKind.numbered => '$indent$ordinal. $text',
      TextBlockKind.todo => '$indent- [${block.checked ? 'x' : ' '}] $text',
      TextBlockKind.quote => '> $text',
      TextBlockKind.code => '`$text`',
      TextBlockKind.paragraph => '$indent$text',
    };
  }

  /// The sentences of [block], each as inline Markdown and where it lies
  /// in the block's text — so a citation can point at the very sentence.
  /// A block of one sentence, a heading or a formula alone gives none.
  static List<({String text, int from, int to})> sentences(TextBlock block) {
    if (block.kind != TextBlockKind.paragraph &&
        block.kind != TextBlockKind.bulleted &&
        block.kind != TextBlockKind.numbered &&
        block.kind != TextBlockKind.quote) {
      return const [];
    }
    final spans = SentenceSplitter.split(block.runs);
    if (spans.length < 2) return const [];
    return <({String text, int from, int to})>[
      for (final (from, to) in spans)
        (text: inline(_runsBetween(block.runs, from, to)), from: from, to: to),
    ];
  }

  /// The parts of [runs] between offsets [from] and [to] of their text.
  static List<TextRun> _runsBetween(List<TextRun> runs, int from, int to) {
    final out = <TextRun>[];
    var at = 0;
    for (final run in runs) {
      final start = at;
      final end = at + run.text.length;
      at = end;
      if (end <= from || start >= to) continue;
      if (run.isMath) {
        out.add(run);
        continue;
      }
      final a = from > start ? from - start : 0;
      final b = to < end ? to - start : run.text.length;
      out.add(run.copyWith(text: run.text.substring(a, b)));
    }
    return out;
  }

  /// [runs] as inline Markdown.
  static String inline(List<TextRun> runs) {
    final out = StringBuffer();
    for (final run in runs) {
      if (run.isMath) {
        out.write('\$${run.text}\$');
        continue;
      }
      var text = run.text;
      if (text.trim().isEmpty) {
        out.write(text);
        continue;
      }
      final marks = run.marks;
      if (marks.code) text = '`$text`';
      if (marks.bold) text = '**$text**';
      if (marks.italic) text = '*$text*';
      if (marks.strikethrough) text = '~~$text~~';
      if (marks.highlight != null) text = '==$text==';
      if (marks.link case final link?) text = '[$text]($link)';
      out.write(text);
    }
    return out.toString();
  }

  /// The rows of the table among [blocks] that [table] is, as Markdown
  /// table rows: a cell's lines joined by `<br>`, and after the first row
  /// the line that makes it the table's head.
  static List<String> tableRows(List<TextBlock> blocks, TextTable table) {
    final cells = List<List<String>>.generate(
      table.rows,
      (_) => List<String>.filled(table.columns, ''),
    );
    for (var i = table.start; i < table.end; i++) {
      final cell = blocks[i].cell!;
      final text = RichMarkdown.block(blocks[i]).replaceAll('|', r'\|');
      final kept = cells[cell.row][cell.column];
      cells[cell.row][cell.column] = kept.isEmpty ? text : '$kept<br>$text';
    }
    return <String>[
      for (var row = 0; row < table.rows; row++) ...<String>[
        '| ${cells[row].join(' | ')} |',
        if (row == 0) '|${' --- |' * table.columns}',
      ],
    ];
  }
}

/// Where sentences end, in text that may hold formulas: after `.`, `!`,
/// `?` or `…` followed by a space — but not after a number in a list, an
/// abbreviation such as "z. B." or "e.g.", or inside a formula.
abstract final class SentenceSplitter {
  static const Set<String> _abbreviations = <String>{
    'z',
    'b',
    'd',
    'h',
    'u',
    'a',
    'o',
    's',
    'e',
    'g',
    'i',
    'bzw',
    'ca',
    'usw',
    'etc',
    'vgl',
    'nr',
    'dr',
    'prof',
    'abb',
    'ggf',
    'evtl',
    'inkl',
    'max',
    'min',
    'mr',
    'mrs',
    'ms',
    'vs',
    'fig',
    'eq',
    'approx',
    'resp',
    'st',
    'bsp',
    'tab',
    'kap',
    'jh',
    'jhd',
    'sog',
    'insb',
    'zb',
    'dh',
  };

  static final RegExp _end = RegExp(r'[.!?…]+["”“»«)\]]*(?=\s)|\n');

  /// The sentences of [runs], as ranges of their text, spaces between left
  /// out.
  static List<(int, int)> split(List<TextRun> runs) {
    final text = runs.map((run) => run.text).join();
    // Where formulas are, which never end a sentence.
    final inFormula = List<bool>.filled(text.length, false);
    var at = 0;
    for (final run in runs) {
      if (run.isMath) inFormula.fillRange(at, at + run.text.length, true);
      at += run.text.length;
    }

    final spans = <(int, int)>[];
    var start = 0;
    void add(int end) {
      var from = start;
      while (from < end && _isSpace(text.codeUnitAt(from))) {
        from++;
      }
      var to = end;
      while (to > from && _isSpace(text.codeUnitAt(to - 1))) {
        to--;
      }
      if (to > from) spans.add((from, to));
    }

    for (final match in _end.allMatches(text)) {
      if (inFormula[match.start]) continue;
      if (text[match.start] == '.' && !_endsSentence(text, match.start)) {
        continue;
      }
      add(match.end);
      start = match.end;
    }
    add(text.length);
    return spans;
  }

  /// Whether the full stop at [dot] of [text] ends a sentence, rather than
  /// an abbreviation or a number.
  static bool _endsSentence(String text, int dot) {
    // A sentence goes on in small letters.
    final next = text.substring(dot + 1).trimLeft();
    if (next.isNotEmpty && next[0] != next[0].toUpperCase()) return false;
    var from = dot;
    while (from > 0 && _isWordUnit(text.codeUnitAt(from - 1))) {
      from--;
    }
    final word = text.substring(from, dot).toLowerCase();
    if (word.isEmpty) return true;
    // A unit after a slash, "m/s.", ends a sentence.
    final after = from > 0 ? text[from - 1] : ' ';
    if (after == '/' || RegExp(r'\d').hasMatch(after)) return true;
    if (_abbreviations.contains(word)) return false;
    // "1." at the start is a list's number.
    return !(RegExp(r'^\d+$').hasMatch(word) &&
        text.substring(0, from).trim().isEmpty);
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0xA0;

  static bool _isWordUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit >= 0xC0;
}
