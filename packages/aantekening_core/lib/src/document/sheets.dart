/// A page shown as sheets of paper, one after another, rather than as one
/// paper without end.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

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
///
/// New pages are A4; Letter is kept for the pages made on it before.
enum SheetSize {
  a4('A4', 793.7, 1122.5),
  letter('Letter', 816, 1056);

  const SheetSize(this.label, this.width, this.height);

  final String label;
  final double width;
  final double height;
}

/// Which way up a sheet is turned: its short side across, or its long.
enum SheetOrientation {
  portrait('Portrait'),
  landscape('Landscape');

  const SheetOrientation(this.label);

  final String label;
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

/// The sheets of a page shown as [NoteLayout.pages]: how large they are,
/// which way up each is turned, and what is printed on each.
///
/// The page itself is the same either way: its content lies in one space,
/// the sheets cutting it into bands from its top, each as tall as its sheet,
/// one after another. Shown as sheets and shown again as one paper, nothing
/// on it has moved.
@immutable
class Sheets {
  /// Sheets printed with [templates], each turned as [orientations] has it
  /// — the sheets past its end turned as its last is, and every sheet as
  /// [orientation] without it.
  Sheets({
    this.size = SheetSize.a4,
    SheetOrientation orientation = SheetOrientation.portrait,
    this.scale = 1,
    List<SheetTemplate> templates = const <SheetTemplate>[SheetTemplate.blank],
    List<SheetOrientation>? orientations,
  }) : templates = List<SheetTemplate>.unmodifiable(
         templates.isEmpty
             ? const <SheetTemplate>[SheetTemplate.blank]
             : templates,
       ),
       orientations = List<SheetOrientation>.unmodifiable(<SheetOrientation>[
         for (var i = 0; i < math.max(1, templates.length); i++)
           orientations == null || orientations.isEmpty
               ? orientation
               : orientations[math.min(i, orientations.length - 1)],
       ]);

  final SheetSize size;

  /// How many times [size] the sheets are: more than once only for a page
  /// whose writing was wider than a sheet, which is made to fit it.
  final double scale;

  /// What is printed on each sheet, the first first: as many as there are
  /// sheets, and never none.
  final List<SheetTemplate> templates;

  /// Which way up each sheet is turned, the first first: as many as there
  /// are sheets.
  final List<SheetOrientation> orientations;

  int get count => templates.length;

  /// Which way up the sheet [index] is turned: a sheet past the last, as
  /// the last is.
  SheetOrientation orientationOf(int index) =>
      orientations[index.clamp(0, count - 1)];

  /// How wide and tall the sheet [index] is: a sheet past the last, as the
  /// last is.
  double widthOf(int index) => _paperWidth(orientationOf(index)) * scale;
  double heightOf(int index) => _paperHeight(orientationOf(index)) * scale;

  double _paperWidth(SheetOrientation turned) =>
      turned == SheetOrientation.landscape ? size.height : size.width;
  double _paperHeight(SheetOrientation turned) =>
      turned == SheetOrientation.landscape ? size.width : size.height;

  /// How wide the widest sheet is.
  double get width => _widestPaper * scale;

  double get _widestPaper => orientations.contains(SheetOrientation.landscape)
      ? _paperWidth(SheetOrientation.landscape)
      : _paperWidth(SheetOrientation.portrait);

  /// Where each sheet's top lies on the page, and after them the last's
  /// bottom.
  late final List<double> _tops = () {
    final tops = <double>[0];
    for (var i = 0; i < count; i++) {
      tops.add(tops.last + heightOf(i));
    }
    return tops;
  }();

  /// Where the top of the sheet [index] lies on the page: past the last,
  /// as though there were more sheets as tall as it.
  double topOf(int index) {
    if (index <= 0) return 0;
    if (index <= count) return _tops[index];
    return _tops[count] + (index - count) * heightOf(count - 1);
  }

  /// Where the last sheet's bottom lies on the page.
  double get bottom => _tops[count];

  /// The sheet [y] lies on, counted from 0, however far below the last.
  int sheetAt(double y) => sheetOn(_tops, y, heightOf(count - 1));

  /// Where the sheet [index] lies on the page.
  Aabb bandOf(int index) {
    final top = topOf(index);
    return Aabb(0, top, widthOf(index), top + heightOf(index));
  }

  /// The sheets of a page holding [content]: as wide as its widest writing,
  /// and enough of them to hold all of it, the new ones printed and turned
  /// as the last is.
  Sheets fittedTo(Aabb content) {
    final fit = content.isEmpty
        ? scale
        : math.max(1.0, content.right / _widestPaper);
    final grown = copyWith(scale: fit);
    return grown.holding(content);
  }

  /// These sheets, with as many more as it takes to hold [content], each
  /// printed and turned as the last is.
  Sheets holding(Aabb content) {
    if (content.isEmpty || content.bottom <= bottom) return this;
    final more = ((content.bottom - bottom) / heightOf(count - 1)).ceil();
    return copyWith(
      templates: <SheetTemplate>[
        ...templates,
        for (var i = 0; i < more; i++) templates.last,
      ],
    );
  }

  /// These sheets with one printed with each of [added] before the sheet
  /// [index], each turned as [turned] has it — as the sheet before them
  /// is, past its end.
  Sheets inserting(
    int index,
    List<SheetTemplate> added, [
    List<SheetOrientation> turned = const <SheetOrientation>[],
  ]) => copyWith(
    templates: <SheetTemplate>[...templates]..insertAll(index, added),
    orientations: <SheetOrientation>[...orientations]
      ..insertAll(index, <SheetOrientation>[
        for (var i = 0; i < added.length; i++)
          i < turned.length ? turned[i] : orientationOf(index - 1),
      ]),
  );

  /// These sheets without the sheet [index].
  Sheets without(int index) => copyWith(
    templates: <SheetTemplate>[...templates]..removeAt(index),
    orientations: <SheetOrientation>[...orientations]..removeAt(index),
  );

  /// These sheets in [order]: each a sheet's index as it is now.
  Sheets reordered(List<int> order) => copyWith(
    templates: <SheetTemplate>[for (final sheet in order) templates[sheet]],
    orientations: <SheetOrientation>[
      for (final sheet in order) orientations[sheet],
    ],
  );

  /// The sheets past the last given in [templates] are turned as the last
  /// of [orientations] is.
  Sheets copyWith({
    SheetSize? size,
    double? scale,
    List<SheetTemplate>? templates,
    List<SheetOrientation>? orientations,
  }) => Sheets(
    size: size ?? this.size,
    scale: scale ?? this.scale,
    templates: templates ?? this.templates,
    orientations: orientations ?? this.orientations,
  );

  /// Upright sheets are written as before there were landscape ones, and
  /// sheets all turned one way as before they could be turned each its
  /// own.
  Map<String, Object?> toJson() {
    final turned = orientations.toSet();
    return <String, Object?>{
      'size': size.name,
      if (turned.length > 1)
        'orientations': <String>[
          for (final orientation in orientations) orientation.name,
        ]
      else if (turned.single == SheetOrientation.landscape)
        'orientation': SheetOrientation.landscape.name,
      'scale': scale,
      'templates': <String>[for (final template in templates) template.name],
    };
  }

  static Sheets fromJson(Map<String, Object?> json) => Sheets(
    size: readEnum(json, 'size', SheetSize.values, SheetSize.a4),
    orientation: readEnum(
      json,
      'orientation',
      SheetOrientation.values,
      SheetOrientation.portrait,
    ),
    orientations: <SheetOrientation>[
      for (final name in readStringList(json, 'orientations'))
        SheetOrientation.values.asNameMap()[name] ?? SheetOrientation.portrait,
    ],
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
      _same(other.templates, templates) &&
      _same(other.orientations, orientations);

  @override
  int get hashCode => Object.hash(
    size,
    scale,
    Object.hashAll(templates),
    Object.hashAll(orientations),
  );

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The band [y] lies in, of bands one under another from [tops] — each
/// band's top, and after them the last's bottom — counted from 0: above
/// the first, the first; below the last, as though there were more bands
/// [after] tall.
int sheetOn(List<double> tops, double y, double after) {
  final count = tops.length - 1;
  if (y < tops[count]) {
    // The last top at or above [y].
    var low = 0;
    var high = count - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (tops[middle] <= y) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
  return count + ((y - tops[count]) / after).floor();
}
