import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  group('Sheets', () {
    test('cut the page into bands a sheet tall, from its top', () {
      final sheets = Sheets(size: SheetSize.letter);
      expect(sheets.sheetAt(0), 0);
      expect(sheets.sheetAt(1055), 0);
      expect(sheets.sheetAt(1056), 1);
      expect(sheets.sheetAt(-20), 0, reason: 'nothing lies above the first');
      expect(sheets.bandOf(2), const Aabb(0, 2112, 816, 3168));
    });

    test('turned landscape, are as wide as they were tall', () {
      final sheets = Sheets(orientation: SheetOrientation.landscape);
      expect(sheets.width, SheetSize.a4.height);
      expect(sheets.height, SheetSize.a4.width);
      expect(sheets.bandOf(1), const Aabb(0, 793.7, 1122.5, 1587.4));
      expect(
        sheets.fittedTo(const Aabb(0, 0, 1000, 300)).scale,
        1,
        reason: 'as wide as the turned sheet already',
      );
      expect(Sheets.fromJson(sheets.toJson()), sheets);
      expect(
        Sheets().toJson().containsKey('orientation'),
        isFalse,
        reason: 'pages made upright are written as before',
      );
    });

    test('fit the writing on a page: as wide as it is, and enough of them', () {
      final fitted = Sheets(
        templates: const <SheetTemplate>[SheetTemplate.lined],
      ).fittedTo(const Aabb(0, 0, 1587.4, 5000));

      expect(fitted.scale, closeTo(2, 1e-9));
      expect(fitted.width, closeTo(1587.4, 1e-9));
      expect(fitted.count, 3, reason: '5000 over sheets 2245 tall');
      expect(fitted.templates, everyElement(SheetTemplate.lined));
      expect(
        Sheets().fittedTo(const Aabb(0, 0, 300, 300)).scale,
        1,
        reason: 'never smaller than the paper',
      );
    });

    test('are kept with the page, shown as one paper or not', () {
      final settings = CanvasSettings(
        layout: NoteLayout.pages,
        sheets: Sheets(
          size: SheetSize.letter,
          scale: 1.5,
          templates: const <SheetTemplate>[
            SheetTemplate.music,
            SheetTemplate.cornell,
          ],
        ),
      );
      final read = CanvasSettings.fromJson(settings.toJson());
      expect(read.layout, NoteLayout.pages);
      expect(read.sheets, settings.sheets);

      final paper = CanvasSettings.fromJson(
        settings.copyWith(layout: NoteLayout.canvas).toJson(),
      );
      expect(paper.sheetsShown, isNull);
      expect(paper.sheets, settings.sheets, reason: 'there to go back to');
    });

    test('a page shown as sheets always has one, however it was written', () {
      final read = CanvasSettings.fromJson(<String, Object?>{
        'layout': 'pages',
        'sheets': <String, Object?>{'templates': <Object?>[], 'scale': 0.2},
      });
      expect(read.sheetsShown!.count, 1);
      expect(read.sheetsShown!.scale, 1);
      expect(
        CanvasSettings.fromJson(const <String, Object?>{}).layout,
        NoteLayout.canvas,
      );
    });
  });
}
