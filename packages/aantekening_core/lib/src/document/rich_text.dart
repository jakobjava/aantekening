/// The rich-text model used inside text elements.
library;

import '../util/json_read.dart';

/// The syntax a formula is written in.
enum MathMode {
  /// Raw LaTeX, authored directly by the user.
  latex,

  /// OneNote-style linear input (`1/2`, `x^2`, `sqrt(3)`), translated to LaTeX
  /// before rendering.
  linear,
}

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

/// The mark before the items of a bulleted list.
///
/// Typing `* ` starts a list of discs, `- ` one of dashes, as Word and OneNote
/// do. The mark stays the same however deeply the list nests, except for
/// discs, which turn into circles and then squares as lists nest.
enum BulletStyle { disc, dash }

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
    this.size,
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

  /// Font size in points, or null for the block's own size.
  final double? size;

  bool get isEmpty =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      !code &&
      color == null &&
      highlight == null &&
      link == null &&
      size == null;

  TextMarks copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? code,
    int? color,
    int? highlight,
    String? link,
    double? size,
  }) => TextMarks(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strikethrough: strikethrough ?? this.strikethrough,
    code: code ?? this.code,
    color: color ?? this.color,
    highlight: highlight ?? this.highlight,
    link: link ?? this.link,
    size: size ?? this.size,
  );

  /// A copy with the text colour set, or cleared with null.
  TextMarks withColor(int? color) => _with(color: () => color);

  /// A copy with the highlight set, or cleared with null.
  TextMarks withHighlight(int? highlight) => _with(highlight: () => highlight);

  /// A copy with the font size set, or cleared with null.
  TextMarks withSize(double? size) => _with(size: () => size);

  /// Only the marks a formula can carry: colour and size. Formulas are
  /// typeset by their own rules, so bold or underline mean nothing to them,
  /// and a highlight on one is part of its LaTeX, whole or in part.
  TextMarks get forFormula => TextMarks(color: color, size: size);

  TextMarks _with({
    int? Function()? color,
    int? Function()? highlight,
    double? Function()? size,
  }) => TextMarks(
    bold: bold,
    italic: italic,
    underline: underline,
    strikethrough: strikethrough,
    code: code,
    color: color == null ? this.color : color(),
    highlight: highlight == null ? this.highlight : highlight(),
    link: link,
    size: size == null ? this.size : size(),
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
    if (size != null) 'size': size,
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
      size: readDoubleOrNull(json, 'size'),
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
      other.link == link &&
      other.size == size;

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
    size,
  );
}

/// A contiguous span of text sharing one set of [TextMarks], or a formula.
///
/// A formula is a run whose [math] is set. Its [text] is the formula's source,
/// in the syntax [math] names, so a formula sits in the flow of a paragraph
/// exactly where it was typed and its source is what search indexes. It is
/// never merged with a neighbouring run: two formulas typed side by side stay
/// two formulas.
class TextRun {
  const TextRun(this.text, [this.marks = TextMarks.none]) : math = null;

  /// A formula written in [mode], optionally coloured or sized through
  /// [marks] (see [TextMarks.forFormula]).
  const TextRun.math(this.text, MathMode mode, [this.marks = TextMarks.none])
    : math = mode;

  const TextRun._(this.text, this.marks, this.math);

  final String text;
  final TextMarks marks;

  /// The syntax of this run's formula, or null for ordinary text.
  final MathMode? math;

  bool get isMath => math != null;

  TextRun copyWith({String? text, TextMarks? marks}) =>
      TextRun._(text ?? this.text, marks ?? this.marks, math);

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    if (!marks.isEmpty) 'marks': marks.toJson(),
    if (math != null) 'math': math!.name,
  };

  static TextRun fromJson(Map<String, Object?> json) {
    final text = readString(json, 'text');
    final math = json['math'];
    if (math is String) {
      return TextRun.math(
        text,
        readEnum(json, 'math', MathMode.values, MathMode.linear),
        TextMarks.fromJson(readObject(json, 'marks')).forFormula,
      );
    }
    return TextRun(text, TextMarks.fromJson(readObject(json, 'marks')));
  }

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      other.marks == marks &&
      other.math == math;

  @override
  int get hashCode => Object.hash(text, marks, math);

  @override
  String toString() =>
      math == null ? 'TextRun(${_quote(text)})' : 'Math(${_quote(text)})';

  static String _quote(String text) => "'${text.replaceAll('\n', r'\n')}'";
}

/// What an embedded object in a text box shows.
enum EmbedKind {
  /// A picture from the asset store.
  image,

  /// One page of a PDF from the asset store, as OneNote's "file printout"
  /// places it.
  pdfPage,
}

/// An image or PDF page placed inside a text box, on a line of its own.
///
/// Embeds reference assets by identifier, like the free-standing image and PDF
/// elements do, so the same picture can sit inside a text box on one page and
/// on its own on another while being stored once.
class BlockEmbed {
  const BlockEmbed({
    required this.kind,
    required this.assetId,
    required this.width,
    required this.height,
    this.pageIndex = 0,
    this.text,
  });

  final EmbedKind kind;
  final String assetId;

  /// Zero-based page within the PDF; meaningful only for [EmbedKind.pdfPage].
  final int pageIndex;

  /// Preferred size in page units. The box shrinks an embed that is wider than
  /// itself, keeping this aspect ratio.
  final double width;
  final double height;

  /// Searchable text: a PDF page's text layer, or an image's description.
  final String? text;

  double get aspectRatio => height > 0 ? width / height : 1;

  BlockEmbed copyWith({double? width, double? height, String? text}) =>
      BlockEmbed(
        kind: kind,
        assetId: assetId,
        width: width ?? this.width,
        height: height ?? this.height,
        pageIndex: pageIndex,
        text: text ?? this.text,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'assetId': assetId,
    if (kind == EmbedKind.pdfPage) 'page': pageIndex,
    'width': width,
    'height': height,
    if (text != null) 'text': text,
  };

  static BlockEmbed fromJson(Map<String, Object?> json) => BlockEmbed(
    kind: readEnum(json, 'kind', EmbedKind.values, EmbedKind.image),
    assetId: readString(json, 'assetId'),
    pageIndex: readInt(json, 'page'),
    width: readDouble(json, 'width', 320),
    height: readDouble(json, 'height', 240),
    text: readStringOrNull(json, 'text'),
  );

  @override
  bool operator ==(Object other) =>
      other is BlockEmbed &&
      other.kind == kind &&
      other.assetId == assetId &&
      other.pageIndex == pageIndex &&
      other.width == width &&
      other.height == height &&
      other.text == text;

  @override
  int get hashCode =>
      Object.hash(kind, assetId, pageIndex, width, height, text);
}

/// One paragraph-level block of rich text, or an embedded object.
class TextBlock {
  const TextBlock({
    this.kind = TextBlockKind.paragraph,
    this.runs = const <TextRun>[],
    this.indent = 0,
    this.checked = false,
    this.bullet = BulletStyle.disc,
    this.embed,
  });

  /// Convenience constructor for an unformatted paragraph.
  factory TextBlock.plain(
    String text, {
    TextBlockKind kind = TextBlockKind.paragraph,
  }) => TextBlock(kind: kind, runs: <TextRun>[TextRun(text)]);

  /// A line holding an image or PDF page.
  const TextBlock.embedded(BlockEmbed this.embed, {this.indent = 0})
    : kind = TextBlockKind.paragraph,
      runs = const <TextRun>[],
      checked = false,
      bullet = BulletStyle.disc;

  final TextBlockKind kind;
  final List<TextRun> runs;

  /// Nesting depth for list blocks.
  final int indent;

  /// Completion state, meaningful only for [TextBlockKind.todo].
  final bool checked;

  /// The mark before the item, meaningful only for [TextBlockKind.bulleted].
  final BulletStyle bullet;

  /// The object this block shows instead of text, if any. An embed block has
  /// no runs.
  final BlockEmbed? embed;

  bool get isEmbed => embed != null;

  /// The block's text with all formatting removed. Formulas contribute their
  /// source; an embed contributes nothing.
  String get plainText {
    if (runs.isEmpty) return '';
    if (runs.length == 1) return runs.first.text;
    final buffer = StringBuffer();
    for (final run in runs) {
      buffer.write(run.text);
    }
    return buffer.toString();
  }

  /// The number of caret steps across this block: its text's length, or one
  /// for an embed, which the caret passes over as a single object.
  int get length => embed != null ? 1 : plainText.length;

  TextBlock copyWith({
    TextBlockKind? kind,
    List<TextRun>? runs,
    int? indent,
    bool? checked,
    BulletStyle? bullet,
  }) => TextBlock(
    kind: kind ?? this.kind,
    runs: runs ?? this.runs,
    indent: indent ?? this.indent,
    checked: checked ?? this.checked,
    bullet: bullet ?? this.bullet,
    embed: embed,
  );

  Map<String, Object?> toJson() {
    final embed = this.embed;
    if (embed != null) {
      return <String, Object?>{
        'embed': embed.toJson(),
        if (indent != 0) 'indent': indent,
      };
    }
    return <String, Object?>{
      if (kind != TextBlockKind.paragraph) 'kind': kind.name,
      'runs': <Object?>[for (final run in runs) run.toJson()],
      if (indent != 0) 'indent': indent,
      if (checked) 'checked': true,
      if (bullet != BulletStyle.disc) 'bullet': bullet.name,
    };
  }

  static TextBlock fromJson(Map<String, Object?> json) {
    final embed = json['embed'];
    if (embed is Map) {
      return TextBlock.embedded(
        BlockEmbed.fromJson(embed.cast<String, Object?>()),
        indent: readInt(json, 'indent'),
      );
    }
    return TextBlock(
      kind: readEnum(
        json,
        'kind',
        TextBlockKind.values,
        TextBlockKind.paragraph,
      ),
      runs: <TextRun>[
        for (final run in readObjectList(json, 'runs')) TextRun.fromJson(run),
      ],
      indent: readInt(json, 'indent'),
      checked: readBool(json, 'checked'),
      bullet: readEnum(json, 'bullet', BulletStyle.values, BulletStyle.disc),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! TextBlock ||
        other.kind != kind ||
        other.indent != indent ||
        other.checked != checked ||
        other.bullet != bullet ||
        other.embed != embed ||
        other.runs.length != runs.length) {
      return false;
    }
    for (var i = 0; i < runs.length; i++) {
      if (other.runs[i] != runs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(kind, indent, checked, bullet, embed, Object.hashAll(runs));

  @override
  String toString() => embed != null
      ? 'TextBlock(embed ${embed!.kind.name})'
      : 'TextBlock(${kind.name}, $runs)';
}
