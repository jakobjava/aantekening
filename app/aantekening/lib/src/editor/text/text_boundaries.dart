/// Where the caret stops as it moves a character or a word at a time.
library;

import 'package:flutter/widgets.dart';

/// Character and word boundaries in laid-out text.
abstract final class TextBoundaries {
  /// The start of the character before [offset] in [text], a whole
  /// grapheme — an emoji or a letter with its accent — at a time.
  static int characterBefore(String text, int offset) {
    if (offset <= 0) return 0;
    final range = CharacterRange.at(text, offset);
    return range.moveBack() ? range.stringBeforeLength : 0;
  }

  /// The end of the character after [offset] in [text].
  static int characterAfter(String text, int offset) {
    if (offset >= text.length) return text.length;
    final range = CharacterRange.at(text, offset);
    return range.moveNext()
        ? text.length - range.stringAfterLength
        : text.length;
  }

  /// The start of the word before [offset], past any spaces; a mark other
  /// than a letter is a word of its own.
  static int wordBefore(String text, int offset) {
    var i = offset;
    while (i > 0 && _isSpace(text.codeUnitAt(i - 1))) {
      i--;
    }
    if (i == 0) return 0;
    if (!_isWordCharacter(text.codeUnitAt(i - 1))) return i - 1;
    while (i > 0 && _isWordCharacter(text.codeUnitAt(i - 1))) {
      i--;
    }
    return i;
  }

  /// The end of the word after [offset].
  static int wordAfter(String text, int offset) {
    var i = offset;
    while (i < text.length && _isSpace(text.codeUnitAt(i))) {
      i++;
    }
    if (i == text.length) return i;
    if (!_isWordCharacter(text.codeUnitAt(i))) return i + 1;
    while (i < text.length && _isWordCharacter(text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  static bool _isWordCharacter(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      (unit >= 0xC0 && unit != 0xD7 && unit != 0xF7 && unit != 0xFFFC);

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x0A;
}
