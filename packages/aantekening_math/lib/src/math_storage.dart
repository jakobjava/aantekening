/// Keeping the formulas on a page as LaTeX.
library;

import 'package:aantekening_core/aantekening_core.dart';

import 'linear_math.dart';

/// Formulas are stored as LaTeX, however they were typed.
///
/// LaTeX is what every other tool reads, so a page's formulas survive export,
/// copying and a change of mind about which syntax to type in. Simple syntax
/// is only a way of editing them: translated from the LaTeX when a formula is
/// opened, and back when it changes. Pages from before this was so hold some
/// formulas in Simple syntax; they are translated when the page is opened.
abstract final class MathStorage {
  /// [document] with every formula held in Simple syntax translated to LaTeX,
  /// or [document] itself if it has none.
  static PageDocument withLatexFormulas(PageDocument document) {
    var changed = false;
    final elements = <NoteElement>[
      for (final element in document.elements)
        switch (element) {
          TextElement(:final blocks) => () {
            final converted = latexBlocks(blocks);
            if (identical(converted, blocks)) return element;
            changed = true;
            return element.copyWith(blocks: converted);
          }(),
          TableElement(:final rows) => () {
            var tableChanged = false;
            final converted = <List<TextBlock>>[
              for (final row in rows)
                <TextBlock>[
                  for (final cell in row)
                    () {
                      final latex = latexBlock(cell);
                      if (!identical(latex, cell)) tableChanged = true;
                      return latex;
                    }(),
                ],
            ];
            if (!tableChanged) return element;
            changed = true;
            return element.copyWith(rows: converted);
          }(),
          _ => element,
        },
    ];
    return changed ? document.copyWith(elements: elements) : document;
  }

  /// [blocks] with their formulas as LaTeX, or [blocks] itself if they
  /// already are.
  static List<TextBlock> latexBlocks(List<TextBlock> blocks) {
    List<TextBlock>? converted;
    for (var i = 0; i < blocks.length; i++) {
      final block = latexBlock(blocks[i]);
      if (!identical(block, blocks[i])) {
        (converted ??= List<TextBlock>.of(blocks))[i] = block;
      }
    }
    return converted ?? blocks;
  }

  /// [block] with its formulas as LaTeX, or [block] itself if they already
  /// are.
  static TextBlock latexBlock(TextBlock block) {
    if (!block.runs.any((run) => run.math == MathMode.linear)) return block;
    return block.copyWith(
      runs: <TextRun>[
        for (final run in block.runs)
          run.math == MathMode.linear
              ? TextRun.math(
                  LinearMath.toLatex(run.text),
                  MathMode.latex,
                  run.marks,
                )
              : run,
      ],
    );
  }
}
