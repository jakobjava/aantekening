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

/// Upper and lower case as Hunspell sees it: one UTF-16 unit at a time, so a
/// word keeps its length whatever its case.
library;

/// How a word is capitalised.
enum CapType {
  /// No capitals: `word`.
  none,

  /// A capital first letter alone: `Word`.
  initial,

  /// Capitals throughout: `WORD`, `CIA'S`.
  all,

  /// Capitals within, not first: `iPhone`.
  mixed,

  /// Capitals first and within: `OpenOffice`.
  mixedInitial,
}

abstract final class Casing {
  static final Map<int, int> _upper = <int, int>{};
  static final Map<int, int> _lower = <int, int>{};

  /// [unit] in upper case, where that is one unit; itself otherwise, as
  /// `ß` stays `ß`.
  static int upperUnit(int unit) => _upper[unit] ??= _map(unit, upper: true);

  /// [unit] in lower case, where that is one unit.
  static int lowerUnit(int unit) => _lower[unit] ??= _map(unit, upper: false);

  static int _map(int unit, {required bool upper}) {
    if (unit < 0x80) {
      if (upper && unit >= 0x61 && unit <= 0x7A) return unit - 0x20;
      if (!upper && unit >= 0x41 && unit <= 0x5A) return unit + 0x20;
      return unit;
    }
    if (unit >= 0xD800 && unit <= 0xDFFF) return unit;
    final character = String.fromCharCode(unit);
    final mapped = upper ? character.toUpperCase() : character.toLowerCase();
    return mapped.length == 1 ? mapped.codeUnitAt(0) : unit;
  }

  /// How [word] is capitalised.
  static CapType of(String word) {
    var capitals = 0;
    var neutral = 0;
    for (var i = 0; i < word.length; i++) {
      final unit = word.codeUnitAt(i);
      final lower = lowerUnit(unit);
      if (unit != lower) capitals++;
      if (upperUnit(unit) == lower) neutral++;
    }
    if (capitals == 0) return CapType.none;
    final first = word.codeUnitAt(0);
    final firstCapital = first != lowerUnit(first);
    if (capitals == 1 && firstCapital) return CapType.initial;
    if (capitals == word.length || capitals + neutral == word.length) {
      return CapType.all;
    }
    if (capitals > 1 && firstCapital) return CapType.mixedInitial;
    return CapType.mixed;
  }

  static String lower(String word) =>
      String.fromCharCodes(<int>[for (final u in word.codeUnits) lowerUnit(u)]);

  static String upper(String word) =>
      String.fromCharCodes(<int>[for (final u in word.codeUnits) upperUnit(u)]);

  /// [word] with a capital first letter, the rest as it is.
  static String initialCapital(String word) => word.isEmpty
      ? word
      : String.fromCharCode(upperUnit(word.codeUnitAt(0))) + word.substring(1);

  /// [word] with a small first letter, the rest as it is.
  static String initialSmall(String word) => word.isEmpty
      ? word
      : String.fromCharCode(lowerUnit(word.codeUnitAt(0))) + word.substring(1);

  /// [word] in lower case with a capital first letter.
  static String capitalised(String word) => initialCapital(lower(word));
}
