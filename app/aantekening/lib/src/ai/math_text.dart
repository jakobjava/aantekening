/// A line as the AI writes it, set: emphasis, highlights and formulas.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

/// [text] with its `**bold**`, `*italic*`, `==highlight==` and `$…$`
/// formulas set as they read, and [trailing] after it — the numbers of
/// what it cites, say.
class MathText extends StatelessWidget {
  const MathText(
    this.text, {
    this.style,
    this.textAlign,
    this.trailing = const <InlineSpan>[],
    this.maxLines,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final List<InlineSpan> trailing;
  final int? maxLines;

  static final RegExp _token = RegExp(
    r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$|\*\*(.+?)\*\*|==(.+?)==|(?<![\w*])\*(?!\s)([^*]+?)\*',
  );

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[...spans(text, base), ...trailing],
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
    );
  }

  /// [text] as spans in [style].
  static List<InlineSpan> spans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var from = 0;
    for (final match in _token.allMatches(text)) {
      if (match.start > from) {
        spans.add(TextSpan(text: text.substring(from, match.start)));
      }
      final display = match[1];
      final inline = match[2];
      if (display != null || inline != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MathView(
              source: (display ?? inline)!.trim(),
              mode: MathMode.latex,
              displayStyle: display != null,
              textStyle: style,
            ),
          ),
        );
      } else if (match[3] != null) {
        spans.add(
          TextSpan(
            children: MathText.spans(match[3]!, style),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match[4] != null) {
        // Highlighted in a tint of the text's own colour, which shows on
        // any base.
        spans.add(
          TextSpan(
            children: MathText.spans(match[4]!, style),
            style: TextStyle(
              backgroundColor: (style.color ?? const Color(0xFF000000))
                  .withValues(alpha: 0.14),
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            children: MathText.spans(match[5]!, style),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      from = match.end;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return spans;
  }
}
