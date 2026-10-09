import 'dart:io';
import 'dart:ui' as ui;

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'shell_harness.dart';

/// Pictures of the window, with each thing that floats over it open, in
/// the app's own typefaces, to be looked at: how it looks, not only that
/// it lays out.
///
///   AANTEKENING_SCREENS=1 flutter test test/screens_test.dart
///
/// writes them to `build/screens`, one PNG for each window and pane;
/// `AANTEKENING_SCREENS=picker` takes only the panes whose names hold it.
void main() {
  final asked = Platform.environment['AANTEKENING_SCREENS'];
  if (asked == null) {
    test('pictures of the window, when asked', () {}, skip: 'not asked');
    return;
  }
  const windows = <String, Size>{
    'wide': Size(1500, 950),
    'phone': Size(420, 900),
  };
  final out = Directory(p.join('build', 'screens'))
    ..createSync(recursive: true);

  setUpAll(_loadTypefaces);

  late AantekeningStore store;
  late Directory assets;
  setUp(() {
    assets = Directory.systemTemp.createTempSync('aantekening_screens_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
  });
  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  for (final MapEntry(key: windowName, value: window) in windows.entries) {
    for (final dark in <bool>[false, true]) {
      for (final MapEntry(key: pane, value: keys) in panes.entries) {
        if (asked != '1' && !pane.contains(asked)) continue;
        final name =
            '$windowName ${dark ? 'dark' : 'light'} '
            '${pane.replaceAll(' ', '-')}';
        testWidgets(name, (tester) async {
          await openLongLibrary(tester, store, window, dark: dark);
          await pressChord(tester, keys);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(windowKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File(p.join(out.path, '$name.png'))
                .writeAsBytesSync(png!.buffer.asUint8List());
          });
        });
      }
    }
  }
}

/// The app's typefaces, read from its fonts folder: tests otherwise draw
/// every letter as a box.
Future<void> _loadTypefaces() async {
  final families = <String, List<String>>{};
  for (final file in Directory('fonts').listSync()) {
    final name = p.basename(file.path);
    if (!name.endsWith('.ttf')) continue;
    final family = switch (name) {
      _ when name.startsWith('IBMPlexSans') => 'IBM Plex Sans',
      _ when name.startsWith('IBMPlexMono') => 'IBM Plex Mono',
      _ when name.startsWith('Carlito') => 'Carlito',
      _ when name.startsWith('Inconsolata') => 'Inconsolata Aantekening',
      _ => null,
    };
    if (family != null) (families[family] ??= <String>[]).add(file.path);
  }
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        Future<ByteData>.value(
          ByteData.sublistView(File(file).readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }
}
