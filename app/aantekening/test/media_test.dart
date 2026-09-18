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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RasterCache', () {
    test('delivers a produced image', () async {
      final cache = RasterCache();

      final image = await cache
          .obtain('page', () => solidImage(20, 10))
          .timeout(const Duration(seconds: 5));

      expect(image!.width, 20);
      image.dispose();
    });

    test('serves the second request from memory', () async {
      final cache = RasterCache();
      var produced = 0;
      Future<ui.Image?> produce() {
        produced++;
        return solidImage(8, 8);
      }

      (await cache.obtain('page', produce))!.dispose();
      (await cache.obtain('page', produce))!.dispose();

      expect(produced, 1);
    });

    test('concurrent requests share one render', () async {
      final cache = RasterCache();
      final gate = Completer<ui.Image?>();
      var produced = 0;
      Future<ui.Image?> produce() {
        produced++;
        return gate.future;
      }

      final first = cache.obtain('page', produce);
      final second = cache.obtain('page', produce);
      gate.complete(await solidImage(4, 4));

      final images = await Future.wait(<Future<ui.Image?>>[first, second])
          .timeout(const Duration(seconds: 5));
      expect(produced, 1);
      expect(images.every((image) => image != null), isTrue);
      for (final image in images) {
        image!.dispose();
      }
    });

    test('evicts the least recently used images beyond its budget', () async {
      final cache = RasterCache(maxPixels: 250);

      for (final key in <String>['a', 'b', 'c']) {
        (await cache.obtain(key, () => solidImage(10, 10)))!.dispose();
      }

      expect(cache.length, 2, reason: 'three 100-pixel images, 250 allowed');
    });
  });
}
