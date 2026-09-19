// Ported to Dart from Hunspell 1.7.3 and modified for aantekening; see
// LICENSE in this package, which has MySpell's notice as well.
//
// ***** BEGIN LICENSE BLOCK *****
// Version: MPL 1.1/GPL 2.0/LGPL 2.1
//
// Copyright (C) 2002-2022 Németh László
//
// The contents of this file are subject to the Mozilla Public License Version
// 1.1 (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at
// http://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
// for the specific language governing rights and limitations under the
// License.
//
// Hunspell is based on MySpell which is Copyright (C) 2002 Kevin Hendricks.
//
// Alternatively, the contents of this file may be used under the terms of
// either the GNU General Public License Version 2 or later (the "GPL"), or
// the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
// in which case the provisions of the GPL or the LGPL are applicable instead
// of those above. If you wish to allow use of your version of this file only
// under the terms of either the GPL or the LGPL, and not to allow others to
// use your version of this file under the terms of the MPL, indicate your
// decision by deleting the provisions above and replace them with the notice
// and other provisions required by the GPL or the LGPL. If you do not delete
// the provisions above, a recipient may use your version of this file under
// the terms of any one of the MPL, the GPL or the LGPL.
//
// ***** END LICENSE BLOCK *****

/// What the rest of a word must look like for an affix to apply to it.
library;

/// One position of a condition: any character, or one of — or none of — a
/// set of characters.
final class _Slot {
  const _Slot.any() : characters = null, negated = false;

  const _Slot(this.characters, {this.negated = false});

  final Set<int>? characters;
  final bool negated;

  bool matches(int unit) {
    final set = characters;
    if (set == null) return true;
    return set.contains(unit) != negated;
  }
}

/// An affix condition as an affix file writes it: `.` for none, or a
/// character, `.`, `[abc]` or `[^abc]` for each position, matched against
/// the start of a word a prefix is added to, and the end of one a suffix is.
final class AffixCondition {
  AffixCondition._(this._slots);

  /// Reads [text]. `.` alone means no condition.
  factory AffixCondition.parse(String text) {
    if (text.isEmpty || text == '.') return none;
    final slots = <_Slot>[];
    var i = 0;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x5B) {
        // [
        var j = i + 1;
        var negated = false;
        if (j < text.length && text.codeUnitAt(j) == 0x5E) {
          negated = true;
          j++;
        }
        final characters = <int>{};
        while (j < text.length && text.codeUnitAt(j) != 0x5D) {
          characters.add(text.codeUnitAt(j));
          j++;
        }
        slots.add(_Slot(characters, negated: negated));
        i = j + 1;
      } else if (unit == 0x2E) {
        slots.add(const _Slot.any());
        i++;
      } else {
        slots.add(_Slot(<int>{unit}));
        i++;
      }
    }
    return AffixCondition._(slots);
  }

  static final AffixCondition none = AffixCondition._(const <_Slot>[]);

  final List<_Slot> _slots;

  /// How many characters the condition looks at.
  int get length => _slots.length;

  /// Whether [word] begins as the condition asks.
  bool matchesStart(String word) {
    if (word.length < _slots.length) return false;
    for (var i = 0; i < _slots.length; i++) {
      if (!_slots[i].matches(word.codeUnitAt(i))) return false;
    }
    return true;
  }

  /// Whether [word] ends as the condition asks.
  bool matchesEnd(String word) {
    final offset = word.length - _slots.length;
    if (offset < 0) return false;
    for (var i = 0; i < _slots.length; i++) {
      if (!_slots[i].matches(word.codeUnitAt(offset + i))) return false;
    }
    return true;
  }
}
