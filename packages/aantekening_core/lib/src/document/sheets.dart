/// A page shown as sheets of paper, one after another, rather than as one
/// paper without end.
library;

import 'dart:math' as math;

import '../util/geometry.dart';
import '../util/json_read.dart';

/// How a page is shown and written on.
enum NoteLayout {
  /// One paper running on without end to the right and down.
  canvas('Canvas'),

  /// Sheets of a set size, one under another, added to as the notes grow.
  pages('Pages');

  const NoteLayout(this.label);

  final String label;
}

/// The size of a sheet, upright, in page units: a ninety-sixth of an inch.
enum SheetSize {
  a4('A4', 793.7, 1122.5),
  letter('Letter', 816, 1056);

  const SheetSize(this.label, this.width, this.height);

  final String label;
  final double width;
  final double height;
}

/// What is printed on a sheet before anything is written on it.
enum SheetTemplate {
  blank('Blank'),
  lined('Lined'),
  grid('Squared'),
  dotted('Dotted'),
  music('Music'),
  cornell('Cornell');

  const SheetTemplate(this.label);

  final String label;
}

/// The sheets of a page shown as [NoteLayout.pages]: how large they are and
/// what is printed on each.
///
/// The page itself is the same either way: its content lies in one space,
/// the sheets cutting it into bands [height] tall from its top, one after
/// another. Shown as sheets and shown again as one paper, nothing on it has
/// moved.
class Sheets {
  Sheets({
    this.size = SheetSize.a4,
    this.scale = 1,
    List<SheetTemplate> templates = const <SheetTemplate>[SheetTemplate.blank],
  }) : templates = List<SheetTemplate>.unmodifiable(
         templates.isEmpty
             ? const <SheetTemplate>[SheetTemplate.blank]
             : templates,
       );

  final SheetSize size;

  /// How many times [size] the sheets are: more than once only for a page
  /// whose writing was wider than a sheet, which is made to fit it.
  final double scale;

  /// What is printed on each sheet, the first first: as many as there are
  /// sheets, and never none.
  final List<SheetTemplate> templates;

  double get width => size.width * scale;
  double get height => size.height * scale;

  int get count => templates.length;

  /// The sheet [y] lies on, counted from 0, however far below the last.
  int sheetAt(double y) => math.max(0, (y / height).floor());

  /// Where the sheet [index] lies on the page.
  Aabb bandOf(int index) =>
      Aabb(0, index * height, width, (index + 1) * height);

  /// The sheets of a page holding [content]: as wide as its widest writing,
  /// and enough of them to hold all of it, the new ones printed as the
  /// last is.
  Sheets fittedTo(Aabb content) {
    final fit = content.isEmpty
        ? scale
        : math.max(1.0, content.right / size.width);
    final grown = Sheets(size: size, scale: fit, templates: templates);
    return grown.holding(content);
  }

  /// These sheets, with as many more as it takes to hold [content].
  Sheets holding(Aabb content) {
    if (content.isEmpty) return this;
    final needed = (content.bottom / height).ceil();
    if (needed <= count) return this;
    return copyWith(
      templates: <SheetTemplate>[
        ...templates,
        for (var i = count; i < needed; i++) templates.last,
      ],
    );
  }

  Sheets copyWith({
    SheetSize? size,
    double? scale,
    List<SheetTemplate>? templates,
  }) => Sheets(
    size: size ?? this.size,
    scale: scale ?? this.scale,
    templates: templates ?? this.templates,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'size': size.name,
    'scale': scale,
    'templates': <String>[for (final template in templates) template.name],
  };

  static Sheets fromJson(Map<String, Object?> json) => Sheets(
    size: readEnum(json, 'size', SheetSize.values, SheetSize.a4),
    scale: math.max(1, readDouble(json, 'scale', 1)),
    templates: <SheetTemplate>[
      for (final name in readStringList(json, 'templates'))
        SheetTemplate.values.asNameMap()[name] ?? SheetTemplate.blank,
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is Sheets &&
      other.size == size &&
      other.scale == scale &&
      _sameTemplates(other.templates, templates);

  @override
  int get hashCode => Object.hash(size, scale, Object.hashAll(templates));

  static bool _sameTemplates(List<SheetTemplate> a, List<SheetTemplate> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
