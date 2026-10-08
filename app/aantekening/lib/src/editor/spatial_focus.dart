/// Moving from one thing on the page to the next by direction, as h, j, k
/// and l do: to the nearest thing that way, keeping to the line it is on.
library;

import 'package:flutter/painting.dart';

/// Something on the page to move to, and where it lies.
typedef Placed = ({String id, Rect bounds});

/// The thing among [things] to move to from [from] in [direction]: of those
/// whose middle lies that way, the nearest — what lies off to the side
/// counting as further, so the move keeps to a line or a column where it
/// can. Null if nothing lies that way.
String? nearestTowards(
  Iterable<Placed> things,
  Rect from,
  AxisDirection direction,
) {
  final horizontal =
      direction == AxisDirection.left || direction == AxisDirection.right;
  final forward =
      direction == AxisDirection.right || direction == AxisDirection.down;
  String? best;
  var bestScore = double.infinity;
  for (final (:id, :bounds) in things) {
    final between = bounds.center - from.center;
    final ahead = (horizontal ? between.dx : between.dy) * (forward ? 1 : -1);
    if (ahead <= 0) continue;
    final aside = horizontal
        ? _apart(from.top, from.bottom, bounds.top, bounds.bottom)
        : _apart(from.left, from.right, bounds.left, bounds.right);
    final score = ahead + aside * _sideways;
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

/// How much further what lies off to the side counts than what lies ahead.
const double _sideways = 2.5;

/// How far apart two spans are: none where they overlap.
double _apart(double start, double end, double otherStart, double otherEnd) {
  if (otherEnd < start) return start - otherEnd;
  if (otherStart > end) return otherStart - end;
  return 0;
}

/// Whether [a] is read before [b] — negative — or after: the higher
/// first, and of two level with each other, the one further left.
int compareReading(Rect a, Rect b) => (a.top - b.top).abs() < _sameLine
    ? a.left.compareTo(b.left)
    : a.top.compareTo(b.top);

/// The first of [things] as they are read.
Placed? firstRead(Iterable<Placed> things) {
  Placed? first;
  for (final thing in things) {
    if (first == null || compareReading(thing.bounds, first.bounds) < 0) {
      first = thing;
    }
  }
  return first;
}

/// How near two tops are to count as level.
const double _sameLine = 12;
