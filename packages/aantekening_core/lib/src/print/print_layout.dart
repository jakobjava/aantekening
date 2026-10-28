/// A page laid out on paper to be printed or saved as a PDF: its sheets as
/// they are, or one paper without end cut where nothing is cut through.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../document/sheets.dart';
import '../util/geometry.dart';

/// How a page shown as one paper without end is put on paper.
enum CanvasPrint {
  /// On sheets of paper, cut where nothing written is cut through: between
  /// paragraphs, lines and drawings, where there is such a place.
  sheets('Sheets of paper'),

  /// On one paper as large as what is written, at its size, as it is seen.
  whole('One long page');

  const CanvasPrint(this.label);

  final String label;
}

/// What is drawn on a page, row by row: for each row [step] page units
/// tall, from [top] down, how much of it is drawn on and from where to
/// where across.
///
/// Worked out from the page drawn without its paper, it sees what is
/// written as it is seen — a gap between two lines of a text box, the
/// space round a formula — however the page's elements lie.
class ContentProfile {
  ContentProfile({
    required this.top,
    required this.step,
    required this.marked,
    required this.left,
    required this.right,
  }) : assert(marked.length == left.length && left.length == right.length);

  /// A profile of nothing drawn.
  factory ContentProfile.empty() => ContentProfile(
    top: 0,
    step: 1,
    marked: Uint32List(0),
    left: Float64List(0),
    right: Float64List(0),
  );

  /// Where on the page the first row's top lies.
  final double top;

  /// How tall a row is, in page units.
  final double step;

  /// How many points of each row are drawn on: none in a gap.
  final Uint32List marked;

  /// Where on the page what is drawn in each row begins and ends across; of
  /// a row drawn on nowhere, anything.
  final Float64List left;
  final Float64List right;

  int get length => marked.length;

  /// Where on the page the last row's bottom lies.
  double get bottom => top + length * step;

  /// The row [y] lies in, clamped to the rows there are.
  int rowAt(double y) =>
      ((y - top) / step).floor().clamp(0, math.max(0, length - 1));

  /// Where the top of row [row] lies on the page.
  double topOf(int row) => top + row * step;

  /// The first and last rows drawn on, or null if none is.
  (int, int)? get marks {
    var first = 0;
    while (first < length && marked[first] == 0) {
      first++;
    }
    if (first == length) return null;
    var last = length - 1;
    while (marked[last] == 0) {
      last--;
    }
    return (first, last);
  }

  /// How far across what is drawn from page [from] to [to] reaches: from
  /// where it begins to where it ends, or null if nothing is drawn there.
  (double, double)? across(double from, double to) {
    var low = double.infinity;
    var high = double.negativeInfinity;
    for (var row = rowAt(from); row < length && topOf(row) < to; row++) {
      if (marked[row] == 0) continue;
      low = math.min(low, left[row]);
      high = math.max(high, right[row]);
    }
    return low <= high ? (low, high) : null;
  }
}

/// One sheet of paper with a part of a page on it.
@immutable
class PrintedSheet {
  const PrintedSheet({
    required this.region,
    required this.shown,
    required this.width,
    required this.height,
    required this.scale,
    this.sheet,
  });

  /// The part of the page the paper shows, in page units: its corner at
  /// the paper's, [scale] times as large on it. The paper's ruling and
  /// template are drawn over all of it.
  final Aabb region;

  /// The part of [region] whose writing is on this paper; what lies in the
  /// rest is on the paper before or after it.
  final Aabb shown;

  /// How large the paper is, in page units at their size: a ninety-sixth
  /// of an inch.
  final double width;
  final double height;

  /// How many times as large the page is drawn on the paper: less than one
  /// where it is made smaller to fit.
  final double scale;

  /// For a page shown as sheets, the sheet this is: what lies on it is
  /// what has its middle on it, and is drawn whole, as the page shows it.
  /// Null for a part of one paper without end.
  final int? sheet;

  /// How large the paper is, in PDF points: a seventy-second of an inch.
  double get widthInPoints => width * pointsPerUnit;
  double get heightInPoints => height * pointsPerUnit;

  /// PDF points to a page unit.
  static const double pointsPerUnit = 72 / 96;

  @override
  bool operator ==(Object other) =>
      other is PrintedSheet &&
      other.region == region &&
      other.shown == shown &&
      other.width == width &&
      other.height == height &&
      other.scale == scale &&
      other.sheet == sheet;

  @override
  int get hashCode => Object.hash(region, shown, width, height, scale, sheet);

  @override
  String toString() =>
      'PrintedSheet($shown on ${width.round()}×${height.round()}'
      '${scale == 1 ? '' : ' at ${scale.toStringAsFixed(2)}'}'
      '${sheet == null ? '' : ', sheet $sheet'})';
}

/// How a page is laid out on paper.
abstract final class PrintLayout {
  /// The room left round what is written on a sheet of paper, in page
  /// units: half an inch.
  static const double margin = 48;

  /// The longest side a PDF page may have, in page units: two hundred
  /// inches.
  static const double longestPage = 200 * 96;

  /// How far up a sheet a cut is looked for, as a share of the sheet: a
  /// sheet is never left emptier than this to cut between two things.
  static const double _leastFilled = 0.25;

  /// A page shown as [sheets]: each sheet a sheet of paper, as large as it
  /// was made — a page whose writing was wider than the paper made smaller
  /// to fit it again.
  static List<PrintedSheet> ofSheets(Sheets sheets) => <PrintedSheet>[
    for (var i = 0; i < sheets.count; i++)
      PrintedSheet(
        region: sheets.bandOf(i),
        shown: sheets.bandOf(i),
        width: sheets.widthOf(i) / sheets.scale,
        height: sheets.heightOf(i) / sheets.scale,
        scale: 1 / sheets.scale,
        sheet: i,
      ),
  ];

  /// A page shown as one paper, drawn as [profile] has it, laid out on
  /// paper as [print] has it.
  static List<PrintedSheet> ofCanvas(
    ContentProfile profile, {
    CanvasPrint print = CanvasPrint.sheets,
    SheetSize paper = SheetSize.a4,
  }) {
    final marks = profile.marks;
    if (marks == null) {
      // Nothing written: a blank sheet, as the page is.
      final band = Aabb(0, 0, paper.width, paper.height);
      return <PrintedSheet>[
        PrintedSheet(
          region: band,
          shown: band,
          width: paper.width,
          height: paper.height,
          scale: 1,
        ),
      ];
    }
    final (first, last) = marks;
    final top = profile.topOf(first);
    final bottom = profile.topOf(last + 1);
    final (left, right) = profile.across(top, bottom)!;
    // From the page's own corner while what is written lies near it, so it
    // lies on the paper as on the page; from a margin before it, further.
    final start = Vec2(math.max(0, left - margin), math.max(0, top - margin));
    return switch (print) {
      CanvasPrint.whole => <PrintedSheet>[
        _whole(start, Aabb(left, top, right, bottom)),
      ],
      CanvasPrint.sheets => _cut(profile, start, bottom, paper),
    };
  }

  /// All that is written, from [start], on one paper as large as it is,
  /// with a margin round it.
  static PrintedSheet _whole(Vec2 start, Aabb written) {
    final width = written.right + margin - start.x;
    final height = written.bottom + margin - start.y;
    final scale = math.min(1.0, longestPage / math.max(width, height));
    final region = Aabb(start.x, start.y, start.x + width, start.y + height);
    return PrintedSheet(
      region: region,
      shown: region,
      width: width * scale,
      height: height * scale,
      scale: scale,
    );
  }

  /// What is written, from [start] down to [bottom], cut into sheets of
  /// [paper].
  ///
  /// Each sheet is turned as what is on it fits: upright while it is no
  /// wider than the paper, else on its side, else made smaller to fit,
  /// turned whichever way makes it largest. It is cut where nothing is
  /// drawn — the lowest such place a quarter of the sheet down or more —
  /// and else where least is: through a drawing, or a picture taller than
  /// a sheet. A stretch of nothing between two cuts is left out.
  static List<PrintedSheet> _cut(
    ContentProfile profile,
    Vec2 start,
    double bottom,
    SheetSize paper,
  ) {
    final sheets = <PrintedSheet>[];
    // Where what the sheet shows begins.
    var top = start.y;
    while (top < bottom) {
      final (width, height, scale) = _turned(profile, start.x, top, paper);
      // The first sheet begins as the page does; each after it a margin
      // above what it shows, so that it has one, the end of what the sheet
      // before it showed left out of it.
      final paperTop = sheets.isEmpty ? top : top - margin / scale;
      // What is written ends a margin above the paper's foot.
      final end = paperTop + (height - margin) / scale;
      final double cut;
      double next;
      if (bottom <= end) {
        cut = bottom;
        next = bottom;
      } else {
        (cut, next) = _cutBetween(
          profile,
          top + (end - top) * _leastFilled,
          end,
        );
      }
      final right = start.x + width / scale;
      sheets.add(
        PrintedSheet(
          region: Aabb(start.x, paperTop, right, paperTop + height / scale),
          shown: Aabb(start.x, top, right, cut),
          width: width,
          height: height,
          scale: scale,
        ),
      );
      // Past the stretch of nothing below the cut.
      top = math.max(cut, next);
    }
    return sheets;
  }

  /// How the sheet from [top] is turned: its width and height in page units,
  /// and how large the page is drawn on it.
  static (double, double, double) _turned(
    ContentProfile profile,
    double from,
    double top,
    SheetSize paper,
  ) {
    // How wide what is written on a sheet [tall] high from [top] is, from
    // [from] and with a margin past it.
    double wanted(double tall) {
      final across = profile.across(top, top + tall);
      return across == null ? 0 : across.$2 + margin - from;
    }

    final (narrow, wide) = (paper.width, paper.height);
    if (wanted(wide) <= narrow) return (narrow, wide, 1);
    if (wanted(narrow) <= wide) return (wide, narrow, 1);
    // Too wide either way: made smaller, as little as it can be, a sheet of
    // the page as much taller as it is made smaller.
    double fit(double across, double tall) {
      var scale = across / wanted(tall);
      // A taller sheet may take in something wider again.
      scale = math.min(scale, across / wanted(tall / scale));
      return scale;
    }

    final upright = fit(narrow, wide);
    final turned = fit(wide, narrow);
    return turned > upright ? (wide, narrow, turned) : (narrow, wide, upright);
  }

  /// Where between page [from] and [to] to cut, and where what follows the
  /// cut begins: the lowest row with nothing drawn on it, or else the
  /// lowest with least drawn on it.
  static (double, double) _cutBetween(
    ContentProfile profile,
    double from,
    double to,
  ) {
    final low = profile.rowAt(from);
    var row = math.min(profile.rowAt(to), profile.length - 1);
    // A row only partly above [to] is not wholly on the sheet.
    if (profile.topOf(row + 1) > to && row > low) row--;
    var least = row;
    for (var at = row; at >= low; at--) {
      if (profile.marked[at] == 0) {
        // The cut at the foot of the gap, as low as the sheet takes it;
        // what follows begins below the gap, however far it runs on.
        var below = at + 1;
        while (below < profile.length && profile.marked[below] == 0) {
          below++;
        }
        return (profile.topOf(at + 1), profile.topOf(below));
      }
      if (profile.marked[at] < profile.marked[least]) least = at;
    }
    // Nowhere blank: through the row with least on it, at its middle.
    final cut = profile.topOf(least) + profile.step / 2;
    return (cut, cut);
  }
}
