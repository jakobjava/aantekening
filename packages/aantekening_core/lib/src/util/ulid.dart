/// Lexicographically sortable, collision-resistant identifiers.
library;

import 'dart:math';

/// A ULID: a 26-character, Crockford base-32 identifier whose leading 10
/// characters encode a millisecond timestamp.
///
/// Sorting ULIDs as strings sorts them by creation time, which lets SQLite use
/// a plain `ORDER BY id` (backed by the primary-key index) instead of sorting
/// on a separate timestamp column. Identifiers generated within the same
/// millisecond are monotonically increasing rather than random, so insertion
/// order is preserved even in tight loops.
abstract final class Ulid {
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Number of base-32 characters used for the timestamp (48 bits).
  static const int timeChars = 10;

  /// Number of base-32 characters used for the random suffix (80 bits).
  static const int randomChars = 16;

  /// Total identifier length.
  static const int length = timeChars + randomChars;

  static final Random _random = Random.secure();
  static final List<int> _suffix = List<int>.filled(randomChars, 0);
  static int _lastMillis = -1;

  /// Generates a new identifier, optionally for an explicit [at] timestamp.
  static String generate([DateTime? at]) {
    final millis = (at ?? DateTime.now()).millisecondsSinceEpoch;
    if (millis == _lastMillis) {
      _incrementSuffix();
    } else {
      _lastMillis = millis;
      for (var i = 0; i < randomChars; i++) {
        _suffix[i] = _random.nextInt(32);
      }
    }

    final out = StringBuffer();
    var remaining = millis;
    final time = List<int>.filled(timeChars, 0);
    for (var i = timeChars - 1; i >= 0; i--) {
      time[i] = remaining & 0x1f;
      remaining >>= 5;
    }
    for (final value in time) {
      out.write(_alphabet[value]);
    }
    for (final value in _suffix) {
      out.write(_alphabet[value]);
    }
    return out.toString();
  }

  /// Recovers the creation time encoded in [id].
  ///
  /// Throws [FormatException] if [id] is not a well-formed ULID.
  static DateTime timestampOf(String id) {
    if (id.length != length) {
      throw FormatException('Expected a $length character ULID', id);
    }
    var millis = 0;
    for (var i = 0; i < timeChars; i++) {
      final index = _alphabet.indexOf(id[i].toUpperCase());
      if (index < 0) {
        throw FormatException('Invalid ULID character "${id[i]}"', id, i);
      }
      millis = (millis << 5) | index;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Returns whether [id] is a syntactically valid ULID.
  static bool isValid(String id) {
    if (id.length != length) return false;
    for (var i = 0; i < length; i++) {
      if (!_alphabet.contains(id[i].toUpperCase())) return false;
    }
    return true;
  }

  /// Carries the random suffix by one, so identifiers minted in the same
  /// millisecond still sort in creation order.
  static void _incrementSuffix() {
    for (var i = randomChars - 1; i >= 0; i--) {
      if (_suffix[i] < 31) {
        _suffix[i]++;
        return;
      }
      _suffix[i] = 0;
    }
  }
}
