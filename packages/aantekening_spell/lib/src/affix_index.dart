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

/// The affixes of a dictionary, arranged to find the ones a word can have.
library;

import 'affix_rules.dart';

/// Prefixes by their first character and suffixes by their last, in the
/// order Hunspell tries them.
final class AffixIndex {
  AffixIndex(AffixRules rules) {
    for (final prefix in rules.prefixes) {
      if (prefix.append.isEmpty) {
        // Hunspell puts affixes that add nothing at the head of its list.
        emptyPrefixes.insert(0, prefix);
      } else {
        (_prefixes[prefix.append.codeUnitAt(0)] ??= <Affix>[]).add(prefix);
      }
    }
    for (final suffix in rules.suffixes) {
      if (suffix.append.isEmpty) {
        emptySuffixes.insert(0, suffix);
      } else {
        (_suffixes[suffix.append.codeUnitAt(suffix.append.length - 1)] ??=
                <Affix>[])
            .add(suffix);
      }
    }
    for (final list in _prefixes.values) {
      list.sort((a, b) => a.append.compareTo(b.append));
    }
    for (final list in _suffixes.values) {
      list.sort((a, b) => _reversed(a.append).compareTo(_reversed(b.append)));
    }
    // By flag, the last defined first, as Hunspell chains them.
    for (final affix in <Affix>[...rules.prefixes, ...rules.suffixes]) {
      (_byFlag[affix.flag] ??= <Affix>[]).insert(0, affix);
    }
  }

  final List<Affix> emptyPrefixes = <Affix>[];
  final List<Affix> emptySuffixes = <Affix>[];
  final Map<int, List<Affix>> _prefixes = <int, List<Affix>>{};
  final Map<int, List<Affix>> _suffixes = <int, List<Affix>>{};
  final Map<int, List<Affix>> _byFlag = <int, List<Affix>>{};

  /// The prefixes adding something that could begin [word]: those adding a
  /// string that starts as [word] does. Whether [word] begins with it is
  /// for the caller to test.
  List<Affix> prefixCandidates(String word) => word.isEmpty
      ? const <Affix>[]
      : _prefixes[word.codeUnitAt(0)] ?? const <Affix>[];

  /// The suffixes adding something that could end [word].
  List<Affix> suffixCandidates(String word) => word.isEmpty
      ? const <Affix>[]
      : _suffixes[word.codeUnitAt(word.length - 1)] ?? const <Affix>[];

  /// Every affix marked by [flag].
  List<Affix> withFlag(int flag) => _byFlag[flag] ?? const <Affix>[];

  static String _reversed(String text) =>
      String.fromCharCodes(text.codeUnits.reversed);
}
