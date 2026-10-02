/// The caret's blinking.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Blinks a caret on and off, [visible], for a while after the last key or
/// click, then leaves it lit, as GTK's does: blinking on in a window left
/// alone, it would keep the screen drawing twice a second.
///
/// The caret is drawn by whatever listens to [visible], so blinking rebuilds
/// nothing.
class CaretBlink {
  static const Duration _interval = Duration(milliseconds: 530);
  static const Duration _blinksFor = Duration(seconds: 10);

  /// Whether the caret is lit.
  final ValueNotifier<bool> visible = ValueNotifier<bool>(true);

  Timer? _timer;

  /// Lights the caret, and blinks it from now on for a while.
  void restart() {
    _timer?.cancel();
    visible.value = true;
    // Tests turn blinking off through the framework's own switch, so that
    // waiting for the page to settle does not wait on the caret forever.
    if (EditableText.debugDeterministicCursor) return;
    var blinks = _blinksFor.inMilliseconds ~/ _interval.inMilliseconds;
    _timer = Timer.periodic(_interval, (timer) {
      if (--blinks > 0) {
        visible.value = !visible.value;
      } else {
        timer.cancel();
        visible.value = true;
      }
    });
  }

  /// Stops blinking, the caret lit.
  void stop() {
    _timer?.cancel();
    _timer = null;
    visible.value = true;
  }

  void dispose() {
    _timer?.cancel();
    visible.dispose();
  }
}
