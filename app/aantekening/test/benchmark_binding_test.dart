// The keys it presses are those Linux's window hands over, and the
// benchmarks are built for Linux and run there only.
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../benchmark/input.dart';
import '../benchmark/measuring.dart' hide find;

/// The binding the benchmarks run the app on, run here as they run it —
/// not a test's binding, but the app's own, in the test's window that
/// nobody sees: it overhears which field has the keyboard, keys and typing
/// reach that field by the engine's own channels, and each frame drawn is
/// found again among the timings the engine hands over.
void main() {
  test(
    'the benchmark’s binding overhears the keyboard, types, and tells frames',
    () async {
      BenchBinding.start();
      Frames.start();
      final field = TextEditingController();
      addTearDown(field.dispose);
      String? submitted;
      runApp(
        MaterialApp(
          home: Material(
            child: TextField(
              controller: field,
              autofocus: true,
              onSubmitted: (value) => submitted = value,
            ),
          ),
        ),
      );
      final typed = BenchBinding.typed;
      for (var tries = 0; tries < 300 && typed.client == null; tries++) {
        await wait(const Duration(milliseconds: 10));
      }
      expect(typed.client, isNotNull, reason: 'the field took the keyboard');
      expect(typed.deltas, isFalse);

      // Each letter: a key the window leaves alone, then the input
      // method's edit, then a frame that shows it.
      final keys = Keys();
      final shown = <int?>[];
      for (final letter in 'Ab 1'.split('')) {
        expect(await keys.down(letter), isFalse);
        final next = Frames.next();
        expect(await typed.type(letter), isTrue);
        await keys.up(letter);
        shown.add(await next);
      }
      expect(field.text, 'Ab 1');
      expect(shown, everyElement(isNotNull));

      expect(await keys.down('Enter'), isFalse);
      expect(await typed.perform(), isTrue);
      await keys.up('Enter');
      expect(submitted, 'Ab 1');

      // Nothing asked of it, the window settles — and the frames it drew
      // are those the engine timed.
      expect(await Frames.settled(), isNotNull);
      await Frames.handedOver();
      expect(Frames.timings, isNotEmpty);
      expect(Frames.timingOf(shown.last!, Frames.timings), isNotNull);
      expect(
        shown.map((frame) => Frames.timingOf(frame!, Frames.timings)).toSet(),
        hasLength(shown.length),
        reason: 'each key was shown by a frame of its own',
      );
      final run = Run.between('typing', 0, now())
        ..shown('key to pixels', shown.first! - 1000, shown.first);
      final times =
          run.toJson(Frames.timings)['times']! as Map<String, Object?>;
      // From a millisecond before the frame was built until it was drawn.
      expect(
        (times['key to pixels']! as Map<String, Object?>)['p50'],
        greaterThanOrEqualTo(1.0),
      );
    },
  );
}
