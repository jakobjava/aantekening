/// Counting clicks: one, two or three in a row.
library;

import 'dart:ui';

/// Counts each press as the first, second or third click in a row, where it
/// comes soon enough after the one before and near enough to it, as a
/// double-click selects a word and a triple-click a paragraph.
class ClickCounter {
  static const Duration _window = Duration(milliseconds: 450);

  /// How far apart, in logical pixels, two clicks of one double-click may be.
  static const double _slop = 6;

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastPosition = Offset.zero;
  int _count = 0;

  /// What the last press counted as: 1, 2 or 3.
  int get count => _count;

  /// Counts a press at [position], now.
  int press(Offset position) {
    final now = DateTime.now();
    final repeat =
        now.difference(_last) < _window &&
        (position - _lastPosition).distance < _slop;
    _count = repeat ? (_count % 3) + 1 : 1;
    _last = now;
    _lastPosition = position;
    return _count;
  }
}
