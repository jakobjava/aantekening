/// A OneNote notebook as OneNote's object model has it: sections of pages,
/// each page a set of outlines, pictures, files and drawings placed on it.
///
/// Positions and sizes are in OneNote's half-inches; ink in its own units,
/// already scaled, placed relative to the container it is in.
library;

import 'dart:typed_data';

/// A section, or a group of sections, in a notebook.
sealed class OneEntry {
  const OneEntry(this.name);
  final String name;
}

final class OneSectionGroup extends OneEntry {
  const OneSectionGroup(super.name, this.entries);
  final List<OneEntry> entries;
}

final class OneSection extends OneEntry {
  const OneSection(super.name, this.pages, {this.color});

  /// The pages in order; a page's [OnePage.level] puts it beneath the one
  /// before it.
  final List<OnePage> pages;
  final int? color;
}

/// A section that could not be read, and why.
final class OneUnreadableSection extends OneEntry {
  const OneUnreadableSection(super.name, this.reason);
  final String reason;
}

final class OnePage {
  const OnePage({
    required this.title,
    required this.level,
    required this.createdAt,
    required this.contents,
    this.titleItem,
    this.modifiedAt,
  });

  final String title;

  /// 1 for a page, 2 for a subpage, 3 for a subpage of that.
  final int level;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  /// Where the title is: its outline, placed on the page.
  final OneOutline? titleItem;

  /// What is on the page, in the order OneNote keeps it.
  final List<OnePageItem> contents;
}

/// Something placed on a page, or in an outline.
sealed class OnePageItem {
  const OnePageItem({this.x, this.y});

  /// Where it is from its parent's origin, if it was placed there.
  final double? x;
  final double? y;
}

/// A text container: paragraphs, lists and tables, in one box.
final class OneOutline extends OnePageItem {
  const OneOutline({
    required this.elements,
    required this.indents,
    super.x,
    super.y,
    this.maxWidth,
    this.maxHeight,
    this.sizeSetByUser = false,
  });

  final List<OneElement> elements;

  /// How far each level of the outline is indented.
  final List<double> indents;
  final double? maxWidth;
  final double? maxHeight;
  final bool sizeSetByUser;
}

/// One paragraph of an outline, with the list mark before it and the
/// paragraphs indented beneath it.
final class OneElement {
  const OneElement({required this.contents, required this.children, this.list});

  final List<OneContent> contents;
  final OneList? list;
  final List<OneElement> children;
}

/// What an outline element holds.
sealed class OneContent {
  const OneContent();
}

/// A list's mark: a bullet, or a number in a format.
final class OneList {
  const OneList({
    required this.format,
    this.font,
    this.restart,
    this.bold = false,
    this.italic = false,
    this.fontSize,
    this.color,
  });

  /// The mark's format: a bullet character, or text around a number whose
  /// place is marked by a character below U+0020.
  final String format;
  final String? font;
  final int? restart;
  final bool bold;
  final bool italic;
  final double? fontSize;
  final int? color;
}

/// A paragraph of text in runs, each with its style.
final class OneRichText extends OneContent {
  const OneRichText({
    required this.runs,
    required this.alignment,
    this.styleId,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineSpacing,
    this.tags = const <OneNoteTag>[],
    this.isTitleDate = false,
    this.isTitleTime = false,
  });

  final List<OneRun> runs;

  /// 0 left, 1 centre, 2 right.
  final int alignment;

  /// The paragraph style: `p`, `h1` to `h6`, `code`, `cite`, `blockquote`,
  /// `PageTitle`, if one is set.
  final String? styleId;
  final double spaceBefore;
  final double spaceAfter;
  final double? lineSpacing;
  final List<OneNoteTag> tags;
  final bool isTitleDate;
  final bool isTitleTime;

  String get text => runs.map((run) => run.text).join();
}

/// A run of text in one style; a run of a formula also carries the math
/// object that starts in it.
final class OneRun {
  const OneRun(this.text, this.style, {this.math, this.link});

  final String text;
  final OneStyle style;
  final OneMathObject? math;
  final String? link;
}

final class OneStyle {
  const OneStyle({
    this.font,
    this.size,
    this.color,
    this.highlight,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.superscript = false,
    this.subscript = false,
    this.math = false,
    this.hidden = false,
    this.hyperlink = false,
  });

  final String? font;

  /// In points.
  final double? size;
  final int? color;
  final int? highlight;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool superscript;
  final bool subscript;
  final bool math;
  final bool hidden;
  final bool hyperlink;
}

/// The operator of a formula's structure — a fraction, a root, a matrix —
/// that begins in a run ([MS-ONE] 2.2.?? MathInlineObject).
final class OneMathObject {
  const OneMathObject({
    required this.type,
    required this.arguments,
    this.columns,
    this.align,
    this.char,
    this.char1,
    this.char2,
  });

  final int type;
  final int arguments;
  final int? columns;
  final int? align;
  final int? char;
  final int? char1;
  final int? char2;
}

/// A note tag: a to-do box, a star, a question mark.
final class OneNoteTag {
  const OneNoteTag({
    required this.label,
    required this.shape,
    this.completed = false,
  });

  final String label;
  final int shape;
  final bool completed;
}

final class OneTable extends OneContent {
  const OneTable({
    required this.rows,
    required this.columnWidths,
    required this.bordersVisible,
  });

  final List<List<OneCell>> rows;
  final List<double> columnWidths;
  final bool bordersVisible;
}

final class OneCell {
  const OneCell(this.elements, {this.background});

  final List<OneElement> elements;
  final int? background;
}

/// A picture, on the page or in an outline.
final class OneImage extends OnePageItem implements OneContent {
  const OneImage({
    required this.data,
    required this.extension,
    super.x,
    super.y,
    this.width,
    this.height,
    this.altText,
    this.fileName,
    this.link,
    this.isBackground = false,
    this.recognizedText,
    this.printout,
  });

  final Uint8List? data;
  final String? extension;
  final double? width;
  final double? height;
  final String? altText;
  final String? fileName;
  final String? link;
  final bool isBackground;

  /// Text OneNote read in the picture.
  final String? recognizedText;

  /// The page of a PDF the picture shows, where it is one of a file
  /// printout's pages.
  final OnePrintout? printout;
}

/// A page of a PDF printed out onto a page.
final class OnePrintout {
  const OnePrintout(this.pdf, this.pageIndex);

  /// The PDF, as OneNote keeps it with the pictures of its pages.
  final Uint8List pdf;

  /// Which of its pages, counting from 0.
  final int pageIndex;
}

/// A file attached to a page, or put in an outline.
final class OneFile extends OnePageItem implements OneContent {
  const OneFile({
    required this.name,
    required this.data,
    super.x,
    super.y,
    this.width,
    this.height,
  });

  final String name;
  final Uint8List? data;
  final double? width;
  final double? height;
}

/// Handwriting and drawing: strokes, or groups of them, each group placed
/// from its parent.
final class OneInk extends OnePageItem implements OneContent {
  const OneInk({required this.strokes, required this.groups, super.x, super.y});

  final List<OneStroke> strokes;
  final List<OneInk> groups;
}

final class OneStroke {
  const OneStroke({
    required this.xs,
    required this.ys,
    required this.width,
    required this.height,
    this.pressures,
    this.color,
    this.transparency = 0,
    this.highlighter = false,
    this.rectangularTip = false,
  });

  /// Coordinates in HIMETRIC — hundredths of a millimetre.
  final List<double> xs;
  final List<double> ys;

  /// Pressures from 0 to 1, where the pen recorded them.
  final List<double>? pressures;

  /// The pen tip's size, in HIMETRIC.
  final double width;
  final double height;
  final int? color;

  /// 0 opaque to 255 clear.
  final int transparency;
  final bool highlighter;
  final bool rectangularTip;
}
