import 'dart:async';
import 'dart:ui' as ui;

import 'package:aantekening/src/editor/media_views.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> solidImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  return recorder.endRecording().toImage(width, height);
}

/// A render of [image] that says when it is called off.
RasterRender rendered(FutureOr<ui.Image?> image, {void Function()? onCancel}) =>
    (image: Future<ui.Image?>.value(image), cancel: onCancel ?? () {});

PdfRaster whole(int width) => (width: width, column: -1, row: -1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfRasters', () {
    test('draws a picture once, however many ask, and tells of it', () async {
      final page = PdfRasters().of('page');
      var renders = 0;
      var told = 0;
      page.addListener(() => told++);
      RasterRender render() {
        renders++;
        return rendered(solidImage(20, 10));
      }

      page
        ..want(whole(512), render)
        ..want(whole(512), render);
      await pumpEventQueue();

      expect(renders, 1);
      expect(told, 1);
      expect(page.whole(512)!.width, 20);
    });

    test('shows the nearest drawn until what is asked for is', () async {
      final page = PdfRasters().of('page');
      expect(page.whole(1024), isNull);
      page
        ..want(whole(512), () => rendered(solidImage(512, 1)))
        ..want(whole(2048), () => rendered(solidImage(2048, 1)));
      await pumpEventQueue();

      expect(page.whole(1024)!.width, 2048, reason: 'the narrowest wider');
      expect(page.whole(4096)!.width, 2048, reason: 'the widest narrower');
      expect(page.whole(256)!.width, 512);
    });

    test(
      'keeps what is wanted, and lets go of what is not, oldest first',
      () async {
        final all = PdfRasters(maxPixels: 250);
        final page = all.of('page');
        for (final width in <int>[1, 2, 3]) {
          page.want(whole(width), () => rendered(solidImage(10, 10)));
        }
        await pumpEventQueue();
        expect(all.pixels, 300, reason: 'all three are wanted');

        page
          ..unwant(whole(1))
          ..unwant(whole(2));
        expect(all.pixels, 200);
        expect(page.whole(1)!.width, 10, reason: 'nearest left is 3, wider');
        page.unwant(whole(3));
        expect(all.pixels, 200, reason: 'the least recently wanted, 1, went');
      },
    );

    test('calls off what is no longer wanted before it is drawn', () async {
      final page = PdfRasters().of('page');
      final gate = Completer<ui.Image?>();
      var cancelled = false;
      page
        ..want(
          whole(512),
          () => rendered(gate.future, onCancel: () => cancelled = true),
        )
        ..unwant(whole(512));
      expect(cancelled, isTrue);
      gate.complete(null);
      await pumpEventQueue();
      expect(page.isEmpty, isTrue);
    });

    test('draws again what was called off and then wanted again', () async {
      final page = PdfRasters().of('page');
      final gate = Completer<ui.Image?>();
      var renders = 0;
      RasterRender render() {
        renders++;
        return renders == 1
            ? rendered(gate.future)
            : rendered(solidImage(8, 8));
      }

      page
        ..want(whole(512), render)
        ..unwant(whole(512))
        ..want(whole(512), render);
      gate.complete(null);
      await pumpEventQueue();

      expect(renders, 2);
      expect(page.whole(512), isNotNull);
    });

    test('gives the tiles drawn, the coarsest first', () async {
      final page = PdfRasters().of('page');
      for (final width in <int>[4608, 3072, 6912]) {
        page.want((
          width: width,
          column: 0,
          row: 0,
        ), () => rendered(solidImage(4, 4)));
      }
      await pumpEventQueue();

      expect(page.tiles(upTo: 4608).map((tile) => tile.$1.width), <int>[
        3072,
        4608,
      ]);
    });
  });
}
