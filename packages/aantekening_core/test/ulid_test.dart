import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

void main() {
  group('Ulid', () {
    test('generates identifiers of the documented length', () {
      expect(Ulid.generate().length, Ulid.length);
      expect(Ulid.isValid(Ulid.generate()), isTrue);
    });

    test('round-trips the encoded timestamp', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1758000000000);
      expect(Ulid.timestampOf(Ulid.generate(at)), at);
    });

    test('sorts in creation order even within one millisecond', () {
      final ids = List<String>.generate(1000, (_) => Ulid.generate());
      final sorted = List<String>.of(ids)..sort();
      expect(sorted, ids, reason: 'identifiers must be monotonic');
    });

    test('rejects malformed identifiers', () {
      expect(Ulid.isValid('too-short'), isFalse);
      expect(
        Ulid.isValid('U' * Ulid.length),
        isFalse,
        reason: 'U is not in the alphabet',
      );
      expect(() => Ulid.timestampOf('nope'), throwsFormatException);
    });
  });
}
