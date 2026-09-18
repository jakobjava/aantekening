import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  group('Aabb', () {
    test('detects overlap and separation', () {
      const a = Aabb(0, 0, 10, 10);
      expect(a.intersects(const Aabb(5, 5, 15, 15)), isTrue);
      expect(
        a.intersects(const Aabb(10, 10, 20, 20)),
        isFalse,
        reason: 'touching edges do not overlap',
      );
      expect(a.intersects(const Aabb(-5, -5, -1, -1)), isFalse);
    });

    test('unions grow to cover both boxes', () {
      final box = const Aabb(0, 0, 4, 4).union(const Aabb(6, -2, 8, 1));
      expect(box, const Aabb(0, -2, 8, 4));
    });

    test('empty is the identity for union', () {
      const a = Aabb(3, 3, 9, 9);
      expect(Aabb.empty.union(a), a);
    });
  });

  group('Frame', () {
    test('rotated bounds enclose the rotated rectangle', () {
      const frame = Frame(
        x: 0,
        y: 0,
        width: 10,
        height: 0,
        rotation: math.pi / 2,
      );
      final bounds = frame.rotatedBounds;
      expect(bounds.width, closeTo(0, 1e-9));
      expect(bounds.height, closeTo(10, 1e-9));
    });

    test('unrotated frames skip the trigonometry', () {
      const frame = Frame(x: 2, y: 3, width: 10, height: 4);
      expect(frame.rotatedBounds, frame.bounds);
    });
  });

  group('FractionalIndex', () {
    test('inserting between two keys yields a key that sorts between them', () {
      final middle = FractionalIndex.insert(previous: 0, next: 1024);
      expect(middle, greaterThan(0));
      expect(middle, lessThan(1024));
    });

    test('inserting at the ends extends the range', () {
      expect(FractionalIndex.insert(next: 0), lessThan(0));
      expect(FractionalIndex.insert(previous: 0), greaterThan(0));
    });

    test('flags exhausted precision for rebalancing', () {
      var low = 0.0;
      const high = 1.0;
      for (var i = 0; i < 80; i++) {
        low = FractionalIndex.between(low, high);
      }
      expect(FractionalIndex.needsRebalance(low, high), isTrue);
    });
  });
}
