/// How the rich-text model looks: block and run styles shared by the text-box
/// editor and every read-only rendering of rich text.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

abstract final class RichTextStyles {
  /// Page units per typographic point: the page is laid out at 96 units per
  /// inch, as screens are, and a point is 1/72 inch.
  static const double unitsPerPoint = 96 / 72;

  /// The default body size, in points, as in OneNote.
  static const double defaultPoints = 11;

  /// Body text size in page units.
  static const double bodySize = defaultPoints * unitsPerPoint;

  /// Code, and the source of formulas: the platform's monospace face, and
  /// those most systems have in case it has none.
  static const TextStyle monospace = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>[
      'DejaVu Sans Mono',
      'Noto Sans Mono',
      'Liberation Mono',
      'Courier New',
    ],
  );

  /// The default text colour. The paper is white in light and dark mode alike,
  /// so text is black rather than following the interface's theme.
  static const Color ink = Color(0xFF000000);

  /// The outline round a text box under the pointer: a light grey on the
  /// paper, as OneNote draws it, and never the theme's outline colour, which
  /// in dark mode is nearly black.
  static const Color boxOutline = Color(0xFFCDD2DA);

  /// The band along the top of a text box that moves it, while the pointer
  /// is over the box and while it is being typed in.
  static const Color boxBand = Color(0x0D000000);
  static const Color boxBandActive = Color(0x141C4FA8);

  /// The grip drawn in the middle of that band.
  static const Color boxGrip = Color(0x59000000);

  /// Text that says something about the page rather than being on it: the
  /// date and time beneath the title, and the title's hint.
  static const Color inkMuted = Color(0xFF6B7280);

  /// The line beneath a page's title.
  static const Color titleRule = Color(0xFFD5D9E0);

  /// The lines round a table's cells.
  static const Color tableRule = Color(0xFFB4BAC4);

  /// Linked text, where it has no colour of its own.
  static const Color link = Color(0xFF1A5FB4);

  /// Behind words a search found: amber, so it is not taken for a yellow
  /// highlight someone made.
  static const Color searchMatch = Color(0x99FFB020);

  /// The wavy line beneath a word spelled wrongly.
  static const Color misspelling = Color(0xFFD93025);

  /// The font sizes offered, in points.
  static const List<double> pointSizes = <double>[
    8,
    9,
    10,
    11,
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    32,
    36,
    48,
    72,
  ];

  /// Indentation per nesting level, in page units.
  static const double indentStep = 22;

  /// Width reserved for a bullet, number or checkbox.
  static const double markerWidth = 22;

  /// The style every text box starts from.
  static TextStyle base(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: bodySize,
      height: 1.4,
      color: ink,
    );
  }

  /// The size, in points, of text in [block] that has no size of its own:
  /// the body size, or a heading's.
  static double defaultPointsFor(TextBlock block) {
    final size = blockStyle(
      block.isEmbed ? TextBlockKind.paragraph : block.kind,
      const TextStyle(fontSize: bodySize),
    ).fontSize!;
    return (size / unitsPerPoint * 10).roundToDouble() / 10;
  }

  /// The style of a whole block, before its runs' own formatting.
  static TextStyle blockStyle(TextBlockKind kind, TextStyle base) {
    final size = base.fontSize ?? bodySize;
    return switch (kind) {
      TextBlockKind.heading1 => base.copyWith(
        fontSize: size * 1.7,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      TextBlockKind.heading2 => base.copyWith(
        fontSize: size * 1.4,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      TextBlockKind.heading3 => base.copyWith(
        fontSize: size * 1.15,
        fontWeight: FontWeight.w600,
      ),
      TextBlockKind.code =>
        base.merge(monospace).copyWith(fontSize: size * 0.92),
      TextBlockKind.quote => base.copyWith(fontStyle: FontStyle.italic),
      _ => base,
    };
  }

  /// The style a run's marks add on top of its block's style, or null for an
  /// unformatted run.
  static TextStyle? runStyle(TextMarks marks) {
    if (marks.isEmpty) return null;
    final style = TextStyle(
      fontWeight: marks.bold ? FontWeight.w700 : null,
      fontStyle: marks.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine(<TextDecoration>[
        if (marks.underline || marks.link != null) TextDecoration.underline,
        if (marks.strikethrough) TextDecoration.lineThrough,
      ]),
      color: marks.color != null
          ? Color(marks.color!)
          : marks.link != null
          ? link
          : null,
      backgroundColor: marks.highlight != null ? Color(marks.highlight!) : null,
      fontSize: marks.size != null ? marks.size! * unitsPerPoint : null,
    );
    return marks.code ? style.merge(monospace) : style;
  }

  /// The source of the formula being edited: code-like, in the accent the
  /// box marks it with, at the formula's own size — the size of the text
  /// it is written in.
  static TextStyle formulaSource(TextStyle blockStyle, TextMarks marks) {
    final size =
        (marks.size != null ? marks.size! * unitsPerPoint : null) ??
        blockStyle.fontSize ??
        bodySize;
    return monospace.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: formulaAccent,
    );
  }

  /// The accent marking the formula being edited. The paper is white in
  /// light and dark mode alike, so it is fixed rather than themed.
  static const Color formulaAccent = Color(0xFF1C4FA8);

  /// The tint behind the formula being edited, and its outline.
  static const Color formulaFill = Color(0xFFE9F0FC);
  static const Color formulaOutline = Color(0xFF9DB9EA);

  /// The room on either side of the formula being edited, inside its box, in
  /// page units. It is part of the line, so the box never covers the text
  /// beside it.
  static const double formulaPadding = 4;

  /// How wide an empty formula's box is, to type into.
  static const double emptyFormulaWidth = 18;

  /// How opaque a text highlight is: enough to mark the words, not so much
  /// that dark colours hide them.
  static const int highlightAlpha = 0x66;

  /// The highlight colour for a palette colour.
  static int highlightFor(int color) =>
      (color & 0x00FFFFFF) | (highlightAlpha << 24);

  /// The default highlight: yellow.
  static const int highlightYellow = 0x66FFD60A;

  /// [argb], a translucent colour, as it looks on the white paper, as 24-bit
  /// RGB: how a highlight inside a formula is kept, since LaTeX's colours
  /// are opaque.
  static int onPaper(int argb) {
    final alpha = (argb >>> 24) / 255;
    int channel(int shift) =>
        (255 - (255 - ((argb >> shift) & 0xFF)) * alpha).round();
    return channel(16) << 16 | channel(8) << 8 | channel(0);
  }

  /// A plain span for a block's runs, formulas shown as their source. Used by
  /// the free-standing tables of earlier builds, which are shown but not
  /// edited; tables are made in text boxes now.
  static TextSpan plainSpanFor(TextBlock block, TextStyle base) => TextSpan(
    style: blockStyle(block.kind, base),
    children: <InlineSpan>[
      for (final run in block.runs)
        TextSpan(text: run.text, style: runStyle(run.marks)),
    ],
  );
}
