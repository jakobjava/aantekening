import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

/// The profile of a page with [boxes] drawn on it, filled, a row a page
/// unit tall.
ContentProfile profileOf(List<Aabb> boxes, {double step = 1}) {
  final bottom = boxes.fold(
    0.0,
    (low, box) => box.bottom > low ? box.bottom : low,
  );
  final rows = (bottom / step).ceil();
  final marked = Uint32List(rows);
  final left = Float64List(rows)..fillRange(0, rows, double.infinity);
  final right = Float64List(rows)..fillRange(0, rows, double.negativeInfinity);
  for (final box in boxes) {
    for (var row = (box.top / step).floor(); row * step < box.bottom; row++) {
      marked[row] += box.width.round();
      if (box.left < left[row]) left[row] = box.left;
      if (box.right > right[row]) right[row] = box.right;
    }
  }
  return ContentProfile(
    top: 0,
    step: step,
    marked: marked,
    left: left,
    right: right,
  );
}

/// Lines of text [lineHeight] apart, [count] of them, from [top], each a
/// line's height less a gap of [leading].
List<Aabb> linesOf(
  int count, {
  double top = 40,
  double lineHeight = 24,
  double leading = 6,
  double left = 40,
  double right = 600,
}) => <Aabb>[
  for (var i = 0; i < count; i++)
    Aabb(
      left,
      top + i * lineHeight,
      right,
      top + (i + 1) * lineHeight - leading,
    ),
];

void main() {
  group('A page shown as sheets', () {
    test('is printed a sheet to a sheet of paper, as large as the paper', () {
      final sheets = Sheets(
        templates: <SheetTemplate>[SheetTemplate.lined, SheetTemplate.grid],
        orientations: <SheetOrientation>[
          SheetOrientation.portrait,
          SheetOrientation.landscape,
        ],
      );
      final printed = PrintLayout.ofSheets(sheets);
      expect(printed, hasLength(2));
      expect(printed[0].region, sheets.bandOf(0));
      expect(printed[0].sheet, 0);
      expect(printed[0].widthInPoints, closeTo(595.3, 0.1), reason: 'A4');
      expect(printed[1].width, SheetSize.a4.height, reason: 'on its side');
      expect(printed[1].region.top, sheets.heightOf(0));
    });

    test('made wider to fit its writing, is made smaller again on paper', () {
      final sheets = Sheets(scale: 1.5);
      final printed = PrintLayout.ofSheets(sheets).single;
      expect(printed.region.width, closeTo(SheetSize.a4.width * 1.5, 1e-9));
      expect(printed.width, closeTo(SheetSize.a4.width, 1e-9));
      expect(printed.scale, closeTo(1 / 1.5, 1e-9));
    });
  });

  group('A page shown as one paper', () {
    test('with nothing on it is a blank sheet', () {
      final printed = PrintLayout.ofCanvas(ContentProfile.empty());
      expect(printed, hasLength(1));
      expect(printed.single.width, SheetSize.a4.width);
    });

    test('that fits a sheet is printed on one, as it lies on the page', () {
      final printed = PrintLayout.ofCanvas(profileOf(linesOf(10)));
      expect(printed, hasLength(1));
      final sheet = printed.single;
      expect(sheet.scale, 1);
      expect(sheet.region.left, 0, reason: 'from the page’s own corner');
      expect(sheet.region.top, 0);
      expect(sheet.width, SheetSize.a4.width, reason: 'upright');
    });

    test('far down and across is printed from a margin before it', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[const Aabb(2000, 5000, 2300, 5100)]),
      );
      final sheet = printed.single;
      expect(sheet.region.left, 2000 - PrintLayout.margin);
      expect(sheet.region.top, 5000 - PrintLayout.margin);
    });

    test('is cut between lines, never through one', () {
      final lines = linesOf(120);
      final printed = PrintLayout.ofCanvas(profileOf(lines));
      expect(printed.length, greaterThan(2));
      for (final sheet in printed) {
        for (final line in lines) {
          final through =
              line.top < sheet.shown.bottom && line.bottom > sheet.shown.bottom;
          expect(through, isFalse, reason: '$sheet cuts $line');
        }
        expect(
          sheet.shown.bottom - sheet.region.top,
          lessThanOrEqualTo(sheet.height - PrintLayout.margin),
          reason: 'a margin left at the foot',
        );
      }
      // One sheet after another, all of it on one or another, and only
      // nothing left out between them.
      for (var i = 1; i < printed.length; i++) {
        final (after, before) = (printed[i].shown, printed[i - 1].shown);
        expect(after.top, greaterThanOrEqualTo(before.bottom));
        expect(
          lines.where(
            (line) => line.top < after.top && line.bottom > before.bottom,
          ),
          isEmpty,
        );
        expect(
          after.top - printed[i].region.top,
          PrintLayout.margin,
          reason: 'a margin left at the top',
        );
      }
      expect(printed.last.shown.bottom, lines.last.bottom);
    });

    test('puts a picture that does not fit what is left of a sheet on the '
        'next, whole', () {
      final picture = const Aabb(40, 700, 500, 1300);
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[...linesOf(25), picture]),
      );
      expect(printed, hasLength(2));
      expect(printed[0].shown.bottom, lessThanOrEqualTo(picture.top));
      expect(printed[1].shown.top, lessThanOrEqualTo(picture.top));
      expect(printed[1].shown.bottom, picture.bottom);
      expect(
        picture.top - printed[1].region.top,
        greaterThanOrEqualTo(PrintLayout.margin),
        reason: 'not at the very top of the paper',
      );
    });

    test('cuts a picture taller than a sheet where least is drawn', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[
          const Aabb(40, 40, 500, 2400),
          // Narrower here: the least is drawn across this stretch.
          const Aabb(40, 900, 100, 1000),
        ]),
      );
      expect(printed.length, greaterThan(1));
      expect(printed.first.shown.bottom, greaterThan(40 + 0.25 * 1000));
    });

    test('leaves out a stretch of nothing between what is written', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[...linesOf(30), ...linesOf(5, top: 20000)]),
      );
      expect(printed, hasLength(2), reason: 'not the eighteen sheets between');
      expect(printed.last.region.top, 20000 - PrintLayout.margin);
    });

    test('wider than upright paper is turned on its side', () {
      final printed = PrintLayout.ofCanvas(profileOf(linesOf(10, right: 1000)));
      final sheet = printed.single;
      expect(sheet.width, SheetSize.a4.height);
      expect(sheet.scale, 1);
    });

    test('turns each sheet as what is on it fits', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[
          ...linesOf(40),
          ...linesOf(10, top: 2000, right: 1000),
        ]),
      );
      expect(printed.first.width, SheetSize.a4.width, reason: 'upright');
      expect(printed.last.width, SheetSize.a4.height, reason: 'on its side');
    });

    test('wider than paper on its side is made smaller to fit', () {
      final printed = PrintLayout.ofCanvas(profileOf(linesOf(10, right: 2400)));
      final sheet = printed.single;
      expect(sheet.scale, lessThan(1));
      expect(
        (2400 + PrintLayout.margin - sheet.region.left) * sheet.scale,
        lessThanOrEqualTo(sheet.width + 1e-9),
      );
    });

    test('as one long page is as large as what is written', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(linesOf(400)),
        print: CanvasPrint.whole,
      );
      final sheet = printed.single;
      expect(sheet.scale, 1);
      expect(sheet.height, 40 + 400 * 24 - 6 + PrintLayout.margin);
      expect(sheet.width, 600 + PrintLayout.margin);
    });

    test('as one long page is made smaller where it is longer than a PDF '
        'page may be', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(<Aabb>[const Aabb(0, 0, 100, 40000)], step: 8),
        print: CanvasPrint.whole,
      );
      expect(printed.single.height, closeTo(PrintLayout.longestPage, 1e-6));
    });

    test('on Letter is cut to Letter', () {
      final printed = PrintLayout.ofCanvas(
        profileOf(linesOf(10)),
        paper: SheetSize.letter,
      );
      expect(printed.single.height, SheetSize.letter.height);
    });
  });
}
