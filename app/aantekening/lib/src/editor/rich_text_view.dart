/// Rendering and plain-text editing of the rich-text model.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

/// Paints a list of [TextBlock]s.
class RichTextBlocks extends StatelessWidget {
  const RichTextBlocks({required this.blocks, super.key, this.baseStyle});

  final List<TextBlock> blocks;
  final TextStyle? baseStyle;

  /// Indentation applied per nesting level, in page units.
  static const double indentStep = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        baseStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);

    var numberedCounter = 0;
    final rows = <Widget>[];

    for (final block in blocks) {
      if (block.kind == TextBlockKind.numbered) {
        numberedCounter++;
      } else {
        numberedCounter = 0;
      }
      rows.add(
        _BlockRow(
          block: block,
          base: base,
          ordinal: numberedCounter,
          scheme: theme.colorScheme,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  /// Converts a block's runs into a styled span.
  static TextSpan spanFor(TextBlock block, TextStyle base) => TextSpan(
    style: _blockStyle(block, base),
    children: <InlineSpan>[
      for (final run in block.runs)
        TextSpan(text: run.text, style: _runStyle(run.marks)),
    ],
  );

  static TextStyle _blockStyle(TextBlock block, TextStyle base) =>
      switch (block.kind) {
        TextBlockKind.heading1 => base.copyWith(
          fontSize: base.fontSize! * 1.7,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        TextBlockKind.heading2 => base.copyWith(
          fontSize: base.fontSize! * 1.4,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        TextBlockKind.heading3 => base.copyWith(
          fontSize: base.fontSize! * 1.15,
          fontWeight: FontWeight.w600,
        ),
        TextBlockKind.code => base.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const <String>['Courier New'],
        ),
        TextBlockKind.quote => base.copyWith(fontStyle: FontStyle.italic),
        _ => base,
      };

  static TextStyle? _runStyle(TextMarks marks) {
    if (marks.isEmpty) return null;
    return TextStyle(
      fontWeight: marks.bold ? FontWeight.w700 : null,
      fontStyle: marks.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine(<TextDecoration>[
        if (marks.underline) TextDecoration.underline,
        if (marks.strikethrough) TextDecoration.lineThrough,
      ]),
      color: marks.color != null ? Color(marks.color!) : null,
      backgroundColor: marks.highlight != null ? Color(marks.highlight!) : null,
      fontFamily: marks.code ? 'monospace' : null,
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.block,
    required this.base,
    required this.ordinal,
    required this.scheme,
  });

  final TextBlock block;
  final TextStyle base;
  final int ordinal;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final content = Text.rich(RichTextBlocks.spanFor(block, base));
    final marker = _marker();

    return Padding(
      padding: EdgeInsets.only(
        left: block.indent * RichTextBlocks.indentStep,
        bottom: 2,
      ),
      child: block.kind == TextBlockKind.quote
          ? _quoted(content)
          : (marker == null
                ? content
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      marker,
                      const SizedBox(width: 6),
                      Flexible(child: content),
                    ],
                  )),
    );
  }

  Widget _quoted(Widget child) => Container(
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: scheme.outlineVariant, width: 3)),
    ),
    child: child,
  );

  Widget? _marker() => switch (block.kind) {
    TextBlockKind.bulleted => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Icon(Icons.circle, size: 5, color: scheme.onSurfaceVariant),
    ),
    TextBlockKind.numbered => Text('$ordinal.', style: base),
    TextBlockKind.todo => Icon(
      block.checked
          ? Icons.check_box_rounded
          : Icons.check_box_outline_blank_rounded,
      size: 16,
      color: scheme.primary,
    ),
    _ => null,
  };
}

/// Applies edited plain text back onto existing blocks.
///
/// Each line keeps the kind, indentation and inline formatting of the block it
/// replaces, and lines added at the end inherit them from the last block. This
/// is the interim editor: it keeps a formatted note's structure intact while
/// typing, rather than flattening the page to plain paragraphs on every edit.
List<TextBlock> applyPlainText(List<TextBlock> existing, String text) {
  final lines = text.split('\n');
  const fallback = TextBlock();

  return <TextBlock>[
    for (var i = 0; i < lines.length; i++)
      _withText(
        i < existing.length
            ? existing[i]
            : (existing.isEmpty ? fallback : existing.last),
        lines[i],
      ),
  ];
}

TextBlock _withText(TextBlock template, String text) => template.copyWith(
  runs: <TextRun>[
    TextRun(
      text,
      template.runs.isEmpty ? TextMarks.none : template.runs.first.marks,
    ),
  ],
);

/// Flattens blocks to the plain text the editor works with.
String plainTextOf(List<TextBlock> blocks) =>
    blocks.map((block) => block.plainText).join('\n');
