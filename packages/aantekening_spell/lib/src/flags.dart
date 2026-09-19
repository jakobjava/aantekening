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

/// The flags a Hunspell dictionary marks words and affixes with.
library;

import 'dart:typed_data';

/// How an affix file writes its flags: one character each, two characters
/// each, decimal numbers separated by commas, or one Unicode character each.
enum FlagMode { single, long, numeric, unicode }

/// Flags with a meaning of their own.
abstract final class Flags {
  /// No flag: testing for it always fails.
  static const int none = 0;

  /// The flag marking forbidden words when the affix file names none.
  static const int forbiddenDefault = 65510;

  /// Marks the capitalised form of a mixed-case or all-caps dictionary word
  /// that is accepted only when the whole word is written in capitals.
  static const int onlyUpcase = 65511;

  /// Reads the flags [text] writes in [mode].
  static List<int> decode(String text, FlagMode mode) {
    if (text.isEmpty) return const <int>[];
    switch (mode) {
      case FlagMode.single:
        return text.codeUnits;
      case FlagMode.long:
        return <int>[
          for (var i = 0; i + 1 < text.length; i += 2)
            (text.codeUnitAt(i) << 16) | text.codeUnitAt(i + 1),
        ];
      case FlagMode.numeric:
        return <int>[
          for (final number in text.split(','))
            if (int.tryParse(number.trim()) case final flag? when flag > 0)
              flag,
        ];
      case FlagMode.unicode:
        return text.runes.toList();
    }
  }

  /// Reads the one flag [text] writes in [mode], or [none].
  static int decodeOne(String text, FlagMode mode) {
    final flags = decode(text, mode);
    return flags.isEmpty ? none : flags.first;
  }
}

/// The flags one word or affix carries.
final class FlagSet {
  FlagSet._(this._flags);

  /// A set of [flags], in any order.
  factory FlagSet.of(Iterable<int> flags) {
    final sorted = flags.toSet().toList()..sort();
    return sorted.isEmpty ? empty : FlagSet._(Uint32List.fromList(sorted));
  }

  static final FlagSet empty = FlagSet._(Uint32List(0));

  final Uint32List _flags;

  bool get isEmpty => _flags.isEmpty;

  int get length => _flags.length;

  Iterable<int> get flags => _flags;

  /// Whether this set holds [flag]; never for [Flags.none].
  bool contains(int flag) {
    if (flag == Flags.none) return false;
    var low = 0;
    var high = _flags.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final value = _flags[middle];
      if (value == flag) return true;
      if (value < flag) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return false;
  }

  /// This set with [flag] added.
  FlagSet withFlag(int flag) => FlagSet.of(<int>[..._flags, flag]);
}
