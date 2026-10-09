import 'dart:io';
import 'dart:ui' as ui;

import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // What the window says when the notes cannot be opened.
  for (final (name, error) in <(String, Object)>[
    ('notes-missing', const NotesFolderMissing('/media/usb/Notes')),
    ('notes-in-use', const NotesInUse()),
  ]) {
    if (asked != '1' && !name.contains(asked)) continue;
    testWidgets('wide light $name', (tester) async {
      tester.view.physicalSize = windows['wide']!;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: windowKey,
          child: ProviderScope(
            overrides: [
              storeProvider.overrideWith((ref) => Future.error(error)),
              preferencesProvider.overrideWith(
                (ref) async => Preferences.inMemory(),
              ),
            ],
            retry: (_, _) => null,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              home: const HomeShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _picture(tester, p.join(out.path, 'wide light $name.png'));
    }, variant: platformFor(windows['wide']!));
  }

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
          await _picture(tester, p.join(out.path, '$name.png'));
        }, variant: platformFor(window));
      }
    }
  }
}

/// Writes a picture of the window to [path].
Future<void> _picture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(windowKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
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
