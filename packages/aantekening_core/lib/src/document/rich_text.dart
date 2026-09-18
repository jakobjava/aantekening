/// The rich-text model used inside text elements.
library;

import '../util/json_read.dart';

/// The block-level role of a paragraph of text.
enum TextBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  bulleted,
  numbered,
  todo,
  code,
  quote,
}

/// Inline formatting applied to a [TextRun].
///
/// Marks serialise only the fields that differ from the default, which keeps
/// unformatted documents — by far the common case — close to plain text on disk.
class TextMarks {
  const TextMarks({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.code = false,
    this.color,
    this.highlight,
    this.link,
  });

  /// Formatting-free marks, shared so that plain runs allocate nothing.
  static const TextMarks none = TextMarks();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool code;

  /// Foreground colour as a 32-bit ARGB value, or null to inherit.
  final int? color;

  /// Highlight colour as a 32-bit ARGB value, or null for none.
  final int? highlight;

  /// Target of a hyperlink; either an external URI or an `aantekening://`
  /// internal link to another page.
  final String? link;

  bool get isEmpty =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      !code &&
      color == null &&
      highlight == null &&
      link == null;

  TextMarks copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? code,
    int? color,
    int? highlight,
    String? link,
  }) => TextMarks(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strikethrough: strikethrough ?? this.strikethrough,
    code: code ?? this.code,
    color: color ?? this.color,
    highlight: highlight ?? this.highlight,
    link: link ?? this.link,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (underline) 'underline': true,
    if (strikethrough) 'strikethrough': true,
    if (code) 'code': true,
    if (color != null) 'color': color,
    if (highlight != null) 'highlight': highlight,
    if (link != null) 'link': link,
  };

  static TextMarks fromJson(Map<String, Object?> json) {
    if (json.isEmpty) return none;
    return TextMarks(
      bold: readBool(json, 'bold'),
      italic: readBool(json, 'italic'),
      underline: readBool(json, 'underline'),
      strikethrough: readBool(json, 'strikethrough'),
      code: readBool(json, 'code'),
      color: readIntOrNull(json, 'color'),
      highlight: readIntOrNull(json, 'highlight'),
      link: readStringOrNull(json, 'link'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextMarks &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.code == code &&
      other.color == color &&
      other.highlight == highlight &&
      other.link == link;

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    strikethrough,
    code,
    color,
    highlight,
    link,
  );
}

/// A contiguous span of text sharing one set of [TextMarks].
class TextRun {
  const TextRun(this.text, [this.marks = TextMarks.none]);

  final String text;
  final TextMarks marks;

  TextRun copyWith({String? text, TextMarks? marks}) =>
      TextRun(text ?? this.text, marks ?? this.marks);

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    if (!marks.isEmpty) 'marks': marks.toJson(),
  };

  static TextRun fromJson(Map<String, Object?> json) => TextRun(
    readString(json, 'text'),
    TextMarks.fromJson(readObject(json, 'marks')),
  );

  @override
  bool operator ==(Object other) =>
      other is TextRun && other.text == text && other.marks == marks;

  @override
  int get hashCode => Object.hash(text, marks);
}

/// One paragraph-level block of rich text.
class TextBlock {
  const TextBlock({
    this.kind = TextBlockKind.paragraph,
    this.runs = const <TextRun>[],
    this.indent = 0,
    this.checked = false,
  });

  /// Convenience constructor for an unformatted paragraph.
  factory TextBlock.plain(
    String text, {
    TextBlockKind kind = TextBlockKind.paragraph,
  }) => TextBlock(kind: kind, runs: <TextRun>[TextRun(text)]);

  final TextBlockKind kind;
  final List<TextRun> runs;

  /// Nesting depth for list blocks.
  final int indent;

  /// Completion state, meaningful only for [TextBlockKind.todo].
  final bool checked;

  /// The block's text with all formatting removed.
  String get plainText {
    if (runs.isEmpty) return '';
    if (runs.length == 1) return runs.first.text;
    final buffer = StringBuffer();
    for (final run in runs) {
      buffer.write(run.text);
    }
    return buffer.toString();
  }

  TextBlock copyWith({
    TextBlockKind? kind,
    List<TextRun>? runs,
    int? indent,
    bool? checked,
  }) => TextBlock(
    kind: kind ?? this.kind,
    runs: runs ?? this.runs,
    indent: indent ?? this.indent,
    checked: checked ?? this.checked,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    if (kind != TextBlockKind.paragraph) 'kind': kind.name,
    'runs': <Object?>[for (final run in runs) run.toJson()],
    if (indent != 0) 'indent': indent,
    if (checked) 'checked': true,
  };

  static TextBlock fromJson(Map<String, Object?> json) => TextBlock(
    kind: readEnum(json, 'kind', TextBlockKind.values, TextBlockKind.paragraph),
    runs: <TextRun>[
      for (final run in readObjectList(json, 'runs')) TextRun.fromJson(run),
    ],
    indent: readInt(json, 'indent'),
    checked: readBool(json, 'checked'),
  );
}
