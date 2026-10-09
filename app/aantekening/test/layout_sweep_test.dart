import 'dart:io';

import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell_harness.dart';

/// Everything that floats over the page, opened over a page with long
/// names in windows from a wide screen to a small phone, its words at their
/// size and larger, light and dark: nothing overflows what holds it, and
/// nothing goes wrong drawing it. An overflow fails the test that made it,
/// named by the window, the size of the words and what was open.
void main() {
  const windows = <String, Size>{
    'wide': Size(1500, 950),
    'laptop': Size(1024, 640),
    'small': Size(800, 600),
    'phone': Size(420, 900),
    'small phone': Size(360, 640),
  };
  const scales = <double>[1, 1.4];

  late AantekeningStore store;
  late Directory assets;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_sweep_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  for (final MapEntry(key: windowName, value: window) in windows.entries) {
    for (final scale in scales) {
      for (final MapEntry(key: pane, value: keys) in panes.entries) {
        final dark = pane.hashCode.isOdd;
        testWidgets('$pane, in a $windowName window, words at ${scale}x'
            '${dark ? ', dark' : ''}', (tester) async {
          // Every error, as it is reported: with the widget it came from,
          // which the exception alone does not say.
          final reported = <FlutterErrorDetails>[];
          final passOn = FlutterError.onError;
          FlutterError.onError = (details) {
            reported.add(details);
            passOn?.call(details);
          };
          addTearDown(() => FlutterError.onError = passOn);
          String said() => <String>[
            for (final details in reported)
              ...details.toString().split('\n').take(14),
          ].join('\n');

          await openLongLibrary(
            tester,
            store,
            window,
            scale: scale,
            dark: dark,
          );
          await pressChord(tester, keys);
          expect(tester.takeException(), isNull, reason: said());
          // Closed again, it leaves nothing behind.
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: said());
        });
      }
    }
  }
}
