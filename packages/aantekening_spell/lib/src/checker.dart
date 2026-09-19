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

/// Whether a word is spelled correctly: Hunspell's checking, ported.
///
/// The port follows Hunspell 1.7.3's own code closely, down to the order it
/// tries affixes in and the state it keeps between them, so that a
/// dictionary accepts here what it accepts in LibreOffice or Firefox, which
/// use that line of Hunspell. Hungarian special cases and morphological
/// analysis are left out.
library;

import 'affix_index.dart';
import 'affix_rules.dart';
import 'casing.dart';
import 'flags.dart';
import 'word_table.dart';

/// What checking a word found out besides whether it is correct.
abstract final class SpellInfo {
  static const int compound = 1 << 0;
  static const int forbidden = 1 << 1;
  static const int initialCapital = 1 << 4;
  static const int originalCapitals = 1 << 5;
  static const int warn = 1 << 6;

  /// Only compounds of two words are allowed.
  static const int twoWordCompound = 1 << 7;
  static const int bestSuggestion = 1 << 8;
}

/// Where in a compound an affixed word is being looked for.
abstract final class InCompound {
  static const int not = 0;
  static const int begin = 1;
  static const int end = 2;
  static const int other = 3;
}

/// A mutable [SpellInfo] bit set, as Hunspell passes `int* info`.
final class InfoBox {
  InfoBox([this.value = 0]);

  int value;

  bool has(int bit) => value & bit != 0;
}

/// Checks words against one dictionary.
final class Checker {
  Checker(this.rules, this.words, this.affixes);

  final AffixRules rules;
  final WordTable words;
  final AffixIndex affixes;

  /// Tests a candidate the way the suggester does, set once the suggester
  /// exists: a compound of three or more words is accepted only if no
  /// simpler word is a likely intended spelling of it.
  bool Function(String word)? hasSimpleSuggestion;

  static const int _maxBreakDepth = 10;
  static const int _maxSharps = 5;
  static const int _maxWordLength = 300;
  static const Duration _compoundTimeLimit = Duration(milliseconds: 50);
  static const Duration _globalTimeLimit = Duration(milliseconds: 250);

  // Hunspell's affix manager remembers the last prefix and suffix it found,
  // and its compound checking reads them.
  Affix? _pfx;
  Affix? _sfx;

  final Stopwatch _compoundClock = Stopwatch();
  bool _compoundTimedOut = false;
  final Stopwatch _globalClock = Stopwatch();

  /// Whether [word] is spelled correctly.
  bool spell(String word, [InfoBox? info]) =>
      timed(() => _spell(word, <String>[], info ?? InfoBox()));

  /// Runs [check] within [limit], the time any one check may take unless
  /// told otherwise, unless already within a limit.
  T timed<T>(T Function() check, {Duration limit = _globalTimeLimit}) {
    if (_globalClock.isRunning) return check();
    _timeLimit = limit;
    _globalClock
      ..reset()
      ..start();
    try {
      return check();
    } finally {
      _globalClock.stop();
    }
  }

  Duration _timeLimit = _globalTimeLimit;

  bool _spell(String word, List<String> candidates, InfoBox info) {
    if (candidates.contains(word) || candidates.length >= _maxBreakDepth) {
      return false;
    }
    if (_globalClock.elapsed > _timeLimit) return false;
    candidates.add(word);
    final result = _spellInternal(word, candidates, info);
    candidates.removeLast();
    return result;
  }

  bool _spellInternal(String input, List<String> candidates, InfoBox info) {
    info.value = 0;
    if (input.length >= _maxWordLength) return false;
    final converted = rules.inputConversion?.convert(input) ?? input;
    if (converted.length >= _maxWordLength) return false;
    var (scw, abbreviation) = _clean(converted);
    if (scw.isEmpty) return true;
    final capType = Casing.of(scw);

    if (_isNumber(scw)) return true;

    WordEntry? rv;
    switch (capType) {
      case CapType.mixed:
      case CapType.mixedInitial:
      case CapType.none:
        if (capType != CapType.none) info.value |= SpellInfo.originalCapitals;
        rv = checkWord(scw, info);
        if (abbreviation > 0 && rv == null) rv = checkWord('$scw.', info);
      case CapType.all:
      case CapType.initial:
        if (capType == CapType.all) {
          info.value |= SpellInfo.originalCapitals;
          rv = checkWord(scw, info);
          if (rv != null) break;
          if (abbreviation > 0) {
            rv = checkWord('$scw.', info);
            if (rv != null) break;
          }
          // Prefixes written apart with an apostrophe: SANT'ELIA.
          final apostrophe = scw.indexOf("'");
          if (apostrophe >= 0) {
            scw = Casing.lower(scw);
            if (apostrophe < scw.length - 1) {
              scw =
                  scw.substring(0, apostrophe + 1) +
                  Casing.initialCapital(scw.substring(apostrophe + 1));
              rv = checkWord(scw, info);
              if (rv != null) break;
              scw = Casing.initialCapital(scw);
              rv = checkWord(scw, info);
              if (rv != null) break;
            }
          }
          if (rules.checkSharps && scw.contains('SS')) {
            scw = Casing.lower(scw);
            var buffer = scw;
            rv = _spellSharps(buffer, 0, 0, 0, info);
            if (rv == null) {
              scw = Casing.initialCapital(scw);
              rv = _spellSharps(scw, 0, 0, 0, info);
            }
            if (abbreviation > 0 && rv == null) {
              buffer = '$buffer.';
              rv = _spellSharps(buffer, 0, 0, 0, info);
              if (rv == null) {
                buffer = '$scw.';
                rv = _spellSharps(buffer, 0, 0, 0, info);
              }
            }
            if (rv != null) break;
          }
        }
        info.value |= SpellInfo.originalCapitals;
        if (capType == CapType.all) scw = Casing.capitalised(scw);
        if (capType == CapType.initial) info.value |= SpellInfo.initialCapital;
        rv = checkWord(scw, info);
        if (capType == CapType.initial) {
          info.value &= ~SpellInfo.initialCapital;
        }
        // Wrong capitals are forbidden by explicit forms in the dictionary:
        // Dutch "Ijs" instead of "IJs".
        if (info.has(SpellInfo.forbidden)) {
          rv = null;
          break;
        }
        if (rv != null && _isKeepCase(rv) && capType == CapType.all) rv = null;
        if (rv != null) break;

        final lowered = Casing.lower(scw);
        scw = Casing.capitalised(scw);
        rv = checkWord(lowered, info);
        var tried = lowered;
        if (abbreviation > 0 && rv == null) {
          rv = checkWord('$lowered.', info);
          if (rv == null) {
            tried = '$scw.';
            if (capType == CapType.initial) {
              info.value |= SpellInfo.initialCapital;
            }
            rv = checkWord(tried, info);
            if (capType == CapType.initial) {
              info.value &= ~SpellInfo.initialCapital;
            }
            if (rv != null && _isKeepCase(rv) && capType == CapType.all) {
              rv = null;
            }
            break;
          }
        }
        if (rv != null &&
            _isKeepCase(rv) &&
            (capType == CapType.all ||
                // With CHECKSHARPS, a KEEPCASE word with ß is allowed with
                // a capital first letter too.
                !(rules.checkSharps && tried.contains('ß')))) {
          rv = null;
        }
    }

    if (rv != null) {
      if (rules.warn != Flags.none && rv.has(rules.warn)) {
        info.value |= SpellInfo.warn;
        return !rules.forbidWarn;
      }
      return true;
    }

    // A word broken at a break point is right if both sides are.
    if (rules.breaks.isNotEmpty && !info.has(SpellInfo.forbidden)) {
      var breakPoints = 0;
      for (final pattern in rules.breaks) {
        var at = scw.indexOf(pattern);
        while (at >= 0) {
          breakPoints++;
          at = scw.indexOf(pattern, at + pattern.length);
        }
      }
      if (breakPoints >= _maxBreakDepth) return false;
      final length = scw.length;

      for (final pattern in rules.breaks) {
        final patternLength = pattern.length;
        if (patternLength == 1 || patternLength > length) continue;
        if (pattern.startsWith('^') &&
            scw.startsWith(pattern.substring(1)) &&
            _spell(scw.substring(patternLength - 1), candidates, InfoBox())) {
          info.value |= SpellInfo.compound;
          return true;
        }
        if (pattern.endsWith(r'$') &&
            scw.endsWith(pattern.substring(0, patternLength - 1)) &&
            _spell(
              scw.substring(0, length - patternLength + 1),
              candidates,
              InfoBox(),
            )) {
          info.value |= SpellInfo.compound;
          return true;
        }
      }

      for (final pattern in rules.breaks) {
        final patternLength = pattern.length;
        var found = scw.indexOf(pattern);
        if (found > 0 && found < length - patternLength) {
          // Breaking at the second occurrence recognises dictionary words
          // containing the break character.
          final second = scw.indexOf(pattern, found + 1);
          if (second > 0 && second < length - patternLength) found = second;
          if (!_spell(
            scw.substring(found + patternLength),
            candidates,
            InfoBox(),
          )) {
            continue;
          }
          if (_spell(scw.substring(0, found), candidates, InfoBox())) {
            info.value |= SpellInfo.compound;
            return true;
          }
        }
      }

      for (final pattern in rules.breaks) {
        final patternLength = pattern.length;
        final found = scw.indexOf(pattern);
        if (found > 0 && found < length - patternLength) {
          if (!_spell(
            scw.substring(found + patternLength),
            candidates,
            InfoBox(),
          )) {
            continue;
          }
          if (_spell(scw.substring(0, found), candidates, InfoBox())) {
            info.value |= SpellInfo.compound;
            return true;
          }
        }
      }
    }
    return false;
  }

  /// [word] without ignored characters, leading spaces and trailing full
  /// stops, and how many full stops there were.
  (String, int) _clean(String word) {
    var text = rules.removeIgnored(word);
    var start = 0;
    while (start < text.length && text.codeUnitAt(start) == 0x20) {
      start++;
    }
    var end = text.length;
    var dots = 0;
    while (end > start && text.codeUnitAt(end - 1) == 0x2E) {
      end--;
      dots++;
    }
    text = text.substring(start, end);
    return (text, dots);
  }

  /// Whether [word] is a number, with single dots, dashes or commas between
  /// its digits.
  static bool _isNumber(String word) {
    var sawDigit = false;
    var afterSeparator = false;
    for (var i = 0; i < word.length; i++) {
      final unit = word.codeUnitAt(i);
      if (unit >= 0x30 && unit <= 0x39) {
        sawDigit = true;
        afterSeparator = false;
      } else if (unit == 0x2C || unit == 0x2E || unit == 0x2D) {
        if (afterSeparator || i == 0) return false;
        afterSeparator = true;
      } else {
        return false;
      }
    }
    return sawDigit && !afterSeparator;
  }

  bool _isKeepCase(WordEntry entry) =>
      rules.keepCase != Flags.none && entry.has(rules.keepCase);

  /// Tries every way of writing each `ss` in [base] as `ß`.
  WordEntry? _spellSharps(
    String base,
    int from,
    int n,
    int replaced,
    InfoBox info,
  ) {
    final at = base.indexOf('ss', from);
    if (at >= 0 && n < _maxSharps) {
      final sharp = '${base.substring(0, at)}ß${base.substring(at + 2)}';
      final found = _spellSharps(sharp, at + 1, n + 1, replaced + 1, info);
      if (found != null) return found;
      return _spellSharps(base, at + 2, n + 1, replaced, info);
    }
    if (replaced > 0) return checkWord(base, info);
    return null;
  }

  /// The dictionary entry [input] is, alone, with affixes, or as a
  /// compound; null if it is none of these.
  WordEntry? checkWord(String input, InfoBox? info) {
    if (_globalClock.isRunning && _globalClock.elapsed > _timeLimit) {
      return null;
    }
    final word = rules.removeIgnored(input);
    if (word.isEmpty) return null;

    WordEntry? he;
    final homonyms = words.lookup(word);
    if (homonyms != null) {
      final first = homonyms.first;
      if (first.has(rules.forbiddenWord)) {
        info?.value |= SpellInfo.forbidden;
        return null;
      }
      for (final entry in homonyms) {
        final skip =
            (rules.needAffix != Flags.none && entry.has(rules.needAffix)) ||
            (rules.onlyInCompound != Flags.none &&
                entry.has(rules.onlyInCompound)) ||
            (info != null &&
                info.has(SpellInfo.initialCapital) &&
                entry.has(Flags.onlyUpcase));
        if (!skip) {
          he = entry;
          break;
        }
      }
    }

    if (he == null) {
      he = affixCheck(word);
      if (he != null &&
          ((rules.onlyInCompound != Flags.none &&
                  he.has(rules.onlyInCompound)) ||
              (info != null &&
                  info.has(SpellInfo.initialCapital) &&
                  he.has(Flags.onlyUpcase)))) {
        he = null;
      }
      if (he != null) {
        if (he.has(rules.forbiddenWord)) {
          info?.value |= SpellInfo.forbidden;
          return null;
        }
      } else if (rules.compounds) {
        final buffer = List<WordEntry?>.filled(100, null);
        // Two words first; then three or more.
        final setInfo = InfoBox(SpellInfo.twoWordCompound | (info?.value ?? 0));
        he = compoundCheck(word, 0, 100, 0, null, buffer, false, setInfo);
        info?.value = setInfo.value & ~SpellInfo.twoWordCompound;
        if (he == null &&
            info != null &&
            !info.has(SpellInfo.twoWordCompound)) {
          info.value &= ~SpellInfo.twoWordCompound;
          he = compoundCheck(word, 0, 100, 0, null, buffer, false, info);
          // Three words or more are accepted only if the word is not a
          // dictionary word with a typo, or two words run together — unless
          // it is a number the compound rules allow.
          if (he != null &&
              !_isDigit(word.codeUnitAt(0)) &&
              (hasSimpleSuggestion?.call(word) ?? false)) {
            he = null;
          }
        }
        if (he != null) info?.value |= SpellInfo.compound;
      }
    }
    return he;
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  // ------------------------------------------------------------- affixes

  bool _prefixAllowed(Affix prefix, int inCompound) =>
      (inCompound != InCompound.not ||
          !prefix.continues(rules.onlyInCompound)) &&
      (inCompound != InCompound.end || prefix.continues(rules.compoundPermit));

  /// A dictionary entry [word] is with a prefix taken off, and perhaps a
  /// suffix too.
  WordEntry? prefixCheck(
    String word,
    int inCompound, {
    int needFlag = Flags.none,
  }) {
    _pfx = null;
    WordEntry? tryPrefix(Affix prefix) {
      if (!_prefixAllowed(prefix, inCompound)) return null;
      final rv = _prefixCheckWord(prefix, word, inCompound, needFlag);
      if (rv != null) _pfx = prefix;
      return rv;
    }

    for (final prefix in affixes.emptyPrefixes) {
      if (tryPrefix(prefix) case final rv?) return rv;
    }
    for (final prefix in affixes.prefixCandidates(word)) {
      if (!word.startsWith(prefix.append)) continue;
      if (tryPrefix(prefix) case final rv?) return rv;
    }
    return null;
  }

  WordEntry? _prefixCheckWord(
    Affix prefix,
    String word,
    int inCompound,
    int needFlag,
  ) {
    final rest = word.length - prefix.append.length;
    if (rest > 0 || (rest == 0 && rules.fullStrip)) {
      final root = prefix.strip + word.substring(prefix.append.length);
      if (prefix.condition.matchesStart(root)) {
        for (final entry in words.lookup(root) ?? const <WordEntry>[]) {
          if (_prefixAppliesTo(prefix, entry, needFlag)) return entry;
        }
        if (prefix.crossProduct) {
          final he = suffixCheck(
            root,
            crossProduct: true,
            ppfx: prefix,
            needFlag: needFlag,
            inCompound: inCompound,
          );
          if (he != null) return he;
        }
      }
    }
    return null;
  }

  bool _prefixAppliesTo(Affix prefix, WordEntry entry, int needFlag) {
    if (!entry.has(prefix.flag)) return false;
    if (prefix.continues(rules.needAffix)) return false;
    if (needFlag != Flags.none &&
        !entry.has(needFlag) &&
        !prefix.continues(needFlag)) {
      return false;
    }
    return true;
  }

  bool _circumfixOk(Affix? prefix, Affix suffix) {
    if (rules.circumfix == Flags.none) return true;
    final inPrefix = prefix != null && prefix.continues(rules.circumfix);
    return inPrefix == suffix.continues(rules.circumfix);
  }

  bool _suffixApplicable(
    Affix? prefix,
    Affix suffix,
    int cclass,
    int inCompound,
  ) {
    if (inCompound == InCompound.begin &&
        !suffix.continues(rules.compoundPermit)) {
      return false;
    }
    if (!_circumfixOk(prefix, suffix)) return false;
    if (inCompound == InCompound.not &&
        suffix.continues(rules.onlyInCompound)) {
      return false;
    }
    if (cclass == Flags.none &&
        suffix.continues(rules.needAffix) &&
        !(prefix != null && !prefix.continues(rules.needAffix))) {
      return false;
    }
    return true;
  }

  /// A dictionary entry [word] is with a suffix taken off.
  WordEntry? suffixCheck(
    String word, {
    bool crossProduct = false,
    Affix? ppfx,
    int cclass = Flags.none,
    int needFlag = Flags.none,
    int inCompound = InCompound.not,
  }) {
    final badFlag = inCompound != InCompound.not
        ? Flags.none
        : rules.onlyInCompound;
    for (final suffix in affixes.emptySuffixes) {
      if (cclass != Flags.none && suffix.continuation.isEmpty) continue;
      if (!_suffixApplicable(ppfx, suffix, cclass, inCompound)) continue;
      final rv = _suffixCheckWord(
        suffix,
        word,
        crossProduct,
        ppfx,
        cclass,
        needFlag,
        badFlag,
      );
      if (rv != null) {
        _sfx = suffix;
        return rv;
      }
    }
    for (final suffix in affixes.suffixCandidates(word)) {
      if (!word.endsWith(suffix.append)) continue;
      if (!_suffixApplicable(ppfx, suffix, cclass, inCompound)) continue;
      if (inCompound == InCompound.end &&
          ppfx == null &&
          suffix.continues(rules.onlyInCompound)) {
        continue;
      }
      final rv = _suffixCheckWord(
        suffix,
        word,
        crossProduct,
        ppfx,
        cclass,
        needFlag,
        badFlag,
      );
      if (rv != null) {
        _sfx = suffix;
        return rv;
      }
    }
    return null;
  }

  WordEntry? _suffixCheckWord(
    Affix suffix,
    String word,
    bool crossProduct,
    Affix? ppfx,
    int cclass,
    int needFlag,
    int badFlag,
  ) {
    if (crossProduct && !suffix.crossProduct) return null;
    final rest = word.length - suffix.append.length;
    if ((rest > 0 || (rest == 0 && rules.fullStrip)) &&
        rest + suffix.strip.length >= suffix.condition.length) {
      final root = word.substring(0, rest) + suffix.strip;
      if (suffix.condition.matchesEnd(root)) {
        for (final entry in words.lookup(root) ?? const <WordEntry>[]) {
          if (_suffixAppliesTo(
            suffix,
            entry,
            crossProduct,
            ppfx,
            cclass,
            needFlag,
            badFlag,
          )) {
            return entry;
          }
        }
      }
    }
    return null;
  }

  bool _suffixAppliesTo(
    Affix suffix,
    WordEntry entry,
    bool crossProduct,
    Affix? ppfx,
    int cclass,
    int needFlag,
    int badFlag,
  ) {
    final inDictionary = entry.has(suffix.flag);
    final inPrefix = ppfx != null && ppfx.continues(suffix.flag);
    if (!inDictionary && !inPrefix) return false;
    if (crossProduct) {
      final prefixFlag = ppfx?.flag ?? Flags.none;
      final stemTakesIt = ppfx != null && entry.has(prefixFlag);
      final suffixTakesIt = ppfx != null && suffix.continues(prefixFlag);
      if (!stemTakesIt && !suffixTakesIt) return false;
    }
    if (cclass != Flags.none && !suffix.continues(cclass)) return false;
    if (badFlag != Flags.none && entry.has(badFlag)) return false;
    if (needFlag != Flags.none &&
        !entry.has(needFlag) &&
        !suffix.continues(needFlag)) {
      return false;
    }
    return true;
  }

  /// A dictionary entry [word] is with two suffixes taken off.
  WordEntry? suffixCheckTwoSuffixes(
    String word, {
    bool crossProduct = false,
    Affix? ppfx,
    int needFlag = Flags.none,
  }) {
    for (final suffix in affixes.emptySuffixes) {
      if (!rules.continuationClasses.contains(suffix.flag)) continue;
      final rv = _suffixCheckTwo(suffix, word, crossProduct, ppfx, needFlag);
      if (rv != null) return rv;
    }
    for (final suffix in affixes.suffixCandidates(word)) {
      if (!word.endsWith(suffix.append)) continue;
      if (!rules.continuationClasses.contains(suffix.flag)) continue;
      final rv = _suffixCheckTwo(suffix, word, crossProduct, ppfx, needFlag);
      if (rv != null) return rv;
    }
    return null;
  }

  WordEntry? _suffixCheckTwo(
    Affix suffix,
    String word,
    bool crossProduct,
    Affix? ppfx,
    int needFlag,
  ) {
    if (crossProduct && !suffix.crossProduct) return null;
    final rest = word.length - suffix.append.length;
    if ((rest > 0 || (rest == 0 && rules.fullStrip)) &&
        rest + suffix.strip.length >= suffix.condition.length) {
      final root = word.substring(0, rest) + suffix.strip;
      if (suffix.condition.matchesEnd(root)) {
        if (ppfx != null) {
          if (suffix.continues(ppfx.flag)) {
            return suffixCheck(root, cclass: suffix.flag, needFlag: needFlag);
          }
          return suffixCheck(
            root,
            crossProduct: crossProduct,
            ppfx: ppfx,
            cclass: suffix.flag,
            needFlag: needFlag,
          );
        }
        return suffixCheck(root, cclass: suffix.flag, needFlag: needFlag);
      }
    }
    return null;
  }

  /// A dictionary entry [word] is with a prefix and two suffixes taken off.
  WordEntry? prefixCheckTwoSuffixes(
    String word,
    int inCompound, {
    int needFlag = Flags.none,
  }) {
    _pfx = null;
    for (final prefix in affixes.emptyPrefixes) {
      final rv = _prefixCheckTwo(prefix, word, inCompound, needFlag);
      if (rv != null) return rv;
    }
    for (final prefix in affixes.prefixCandidates(word)) {
      if (!word.startsWith(prefix.append)) continue;
      final rv = _prefixCheckTwo(prefix, word, inCompound, needFlag);
      if (rv != null) {
        _pfx = prefix;
        return rv;
      }
    }
    return null;
  }

  WordEntry? _prefixCheckTwo(
    Affix prefix,
    String word,
    int inCompound,
    int needFlag,
  ) {
    final rest = word.length - prefix.append.length;
    if ((rest > 0 || (rest == 0 && rules.fullStrip)) &&
        rest + prefix.strip.length >= prefix.condition.length) {
      final root = prefix.strip + word.substring(prefix.append.length);
      if (prefix.condition.matchesStart(root) &&
          prefix.crossProduct &&
          inCompound != InCompound.begin) {
        return suffixCheckTwoSuffixes(
          root,
          crossProduct: true,
          ppfx: prefix,
          needFlag: needFlag,
        );
      }
    }
    return null;
  }

  /// A dictionary entry [word] is with its affixes taken off.
  WordEntry? affixCheck(
    String word, {
    int needFlag = Flags.none,
    int inCompound = InCompound.not,
  }) {
    final rv = prefixCheck(word, inCompound, needFlag: needFlag);
    if (rv != null) return rv;
    final suffixed = suffixCheck(
      word,
      needFlag: needFlag,
      inCompound: inCompound,
    );
    if (rules.continuationClasses.isEmpty) return suffixed;
    _sfx = null;
    _pfx = null;
    return suffixed ??
        suffixCheckTwoSuffixes(word, needFlag: needFlag) ??
        prefixCheckTwoSuffixes(word, InCompound.not, needFlag: needFlag);
  }

  // ------------------------------------------------------------ compounds

  bool _candidateCheck(String word) =>
      words.lookup(word) != null || affixCheck(word) != null;

  /// Whether [word], a compound, is a word with a common misspelling.
  bool _compoundRepCheck(String word) {
    if (word.length < 2 || rules.replacements.isEmpty) return false;
    for (final replacement in rules.replacements) {
      if (_compoundTimeUp()) return false;
      final output = replacement.outputs[0];
      if (output.isEmpty) continue;
      var at = word.indexOf(replacement.pattern);
      while (at >= 0) {
        final candidate = word.replaceRange(
          at,
          at + replacement.pattern.length,
          output,
        );
        if (_candidateCheck(candidate)) return true;
        at = word.indexOf(replacement.pattern, at + 1);
      }
    }
    return false;
  }

  /// Whether [word], a compound, is two dictionary words written apart.
  bool _compoundWordPairCheck(String word) {
    if (word.length <= 2) return false;
    for (var i = 1; i < word.length; i++) {
      if (_compoundTimeUp()) return false;
      if (_isLowSurrogate(word.codeUnitAt(i))) continue;
      if (_candidateCheck('${word.substring(0, i)} ${word.substring(i)}')) {
        return true;
      }
    }
    return false;
  }

  bool _compoundTimeUp() {
    if (_compoundTimedOut) return true;
    if (_compoundClock.elapsed > _compoundTimeLimit) _compoundTimedOut = true;
    return _compoundTimedOut;
  }

  /// Whether the join of [word] at [pos], between [first] and [second], is
  /// one CHECKCOMPOUNDPATTERN forbids.
  bool _compoundPatternCheck(
    String word,
    int pos,
    WordEntry? first,
    WordEntry? second,
  ) {
    for (final pattern in rules.compoundPatterns) {
      if (!_leadsWith(word, pos, pattern.right)) continue;
      if (first != null &&
          pattern.leftFlag != Flags.none &&
          !first.has(pattern.leftFlag)) {
        continue;
      }
      if (second != null &&
          pattern.rightFlag != Flags.none &&
          !second.has(pattern.rightFlag)) {
        continue;
      }
      final left = pattern.left;
      if (left.isEmpty) return true;
      if (left.startsWith('0')) {
        if (first == null) continue;
        final stem = first.word;
        if (stem.length <= pos &&
            word.substring(pos - stem.length, pos) == stem) {
          return true;
        }
      } else if (left.length <= pos &&
          word.substring(pos - left.length, pos) == left) {
        return true;
      }
    }
    return false;
  }

  /// Whether [word] continues at [pos] with [pattern], in which `.` stands
  /// for any character.
  static bool _leadsWith(String word, int pos, String pattern) {
    if (pos + pattern.length > word.length) return false;
    for (var k = 0; k < pattern.length; k++) {
      final unit = pattern.codeUnitAt(k);
      if (unit != 0x2E && unit != word.codeUnitAt(pos + k)) return false;
    }
    return true;
  }

  /// Whether the join of [word] at [pos] has a capital on either side.
  bool _compoundCaseCheck(String word, int pos) {
    final before = word.codeUnitAt(pos - 1);
    final after = pos < word.length ? word.codeUnitAt(pos) : 0;
    bool isUpper(int unit) =>
        Casing.upperUnit(unit) == unit && Casing.lowerUnit(unit) != unit;
    return (isUpper(after) || isUpper(before)) &&
        after != 0x2D &&
        before != 0x2D;
  }

  /// Checks the words of a compound so far against the COMPOUNDRULE
  /// patterns, with [entry] as word [wnum]. Returns whether a rule matches,
  /// and the list of words, which starts as [def] if there was none.
  (bool, List<WordEntry?>?) _compoundRuleCheck(
    List<WordEntry?>? words,
    int wnum,
    int maxWordNum,
    WordEntry entry,
    List<WordEntry?>? def,
    bool all,
  ) {
    var list = words;
    var borrowed = false;
    if (list == null) {
      borrowed = true;
      list = def;
    }
    if (list == null) return (false, words);
    List<WordEntry?>? fail() {
      list![wnum] = null;
      return borrowed ? null : list;
    }

    if (wnum >= maxWordNum) return (false, borrowed ? null : list);
    list[wnum] = entry;
    if (entry.flags.isEmpty) return (false, fail());
    var takesPart = false;
    for (final rule in rules.compoundRules) {
      for (final flag in rule) {
        if (flag != AffixRules.ruleStar &&
            flag != AffixRules.ruleQuestion &&
            entry.has(flag)) {
          takesPart = true;
          break;
        }
      }
    }
    if (!takesPart) return (false, fail());

    bool has(int wp, int flag) {
      final word = list![wp];
      return word != null && !word.flags.isEmpty && word.has(flag);
    }

    for (final rule in rules.compoundRules) {
      final backtrack = <List<int>>[
        <int>[0, 0, 0],
      ];
      var bt = 0;
      var pp = 0;
      var wp = 0;
      var ok2 = true;
      var ok = true;
      bool quantifierAt(int index) =>
          index < rule.length &&
          (rule[index] == AffixRules.ruleStar ||
              rule[index] == AffixRules.ruleQuestion);
      do {
        while (pp < rule.length && wp <= wnum) {
          if (quantifierAt(pp + 1)) {
            final wend = rule[pp + 1] == AffixRules.ruleQuestion ? wp : wnum;
            ok2 = true;
            pp += 2;
            backtrack[bt][0] = pp;
            backtrack[bt][1] = wp;
            while (wp <= wend) {
              if (!has(wp, rule[pp - 2])) {
                ok2 = false;
                break;
              }
              wp++;
            }
            if (wp <= wnum) ok2 = false;
            backtrack[bt][2] = wp - backtrack[bt][1];
            if (backtrack[bt][2] > 0) {
              bt++;
              backtrack.add(<int>[0, 0, 0]);
            }
            if (ok2) break;
          } else {
            ok2 = true;
            if (!has(wp, rule[pp])) {
              ok = false;
              break;
            }
            pp++;
            wp++;
            if (rule.length == pp && wp <= wnum) ok = false;
          }
        }
        if (ok && ok2) {
          var r = pp;
          while (rule.length > r && quantifierAt(r + 1)) {
            r += 2;
          }
          if (rule.length <= r) return (true, list);
        }
        if (bt > 0) {
          do {
            ok = true;
            backtrack[bt - 1][2]--;
            pp = backtrack[bt - 1][0];
            wp = backtrack[bt - 1][1] + backtrack[bt - 1][2];
          } while (backtrack[bt - 1][2] < 0 && --bt > 0);
        }
      } while (bt > 0);

      if (ok && ok2 && (!all || rule.length <= pp)) return (true, list);
      while (ok && ok2 && rule.length > pp && quantifierAt(pp + 1)) {
        pp += 2;
      }
      if (ok && ok2 && rule.length <= pp) return (true, list);
    }
    return (false, fail());
  }

  (int, int) _compoundBounds(String word, int length) {
    final min = rules.compoundMin;
    var cmin = 0;
    for (var i = 0; i < min && cmin < length; i++) {
      cmin++;
      while (cmin < length && _isLowSurrogate(word.codeUnitAt(cmin))) {
        cmin++;
      }
    }
    var cmax = length;
    for (var i = 0; i < min - 1 && cmax > 0; i++) {
      cmax--;
      while (cmax > 0 && _isLowSurrogate(word.codeUnitAt(cmax))) {
        cmax--;
      }
    }
    return (cmin, cmax);
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// The first word of [word] read as a compound, or null if it is not one.
  ///
  /// [words] holds the words found so far for the compound rules, and
  /// [ruleWords] is where that list is kept once it is started.
  WordEntry? compoundCheck(
    String word,
    int wordNum,
    int maxWordNum,
    int wnum,
    List<WordEntry?>? words,
    List<WordEntry?> ruleWords,
    bool isSuggestion,
    InfoBox? info,
  ) {
    if (wnum + 1 >= maxWordNum) return null;
    if (wnum == 0) {
      _compoundClock
        ..reset()
        ..start();
      _compoundTimedOut = false;
    } else if (_compoundClock.elapsed > _compoundTimeLimit) {
      _compoundTimedOut = true;
    }

    final oldWords = words;
    final patterns = rules.compoundPatterns;
    final minimum = rules.compoundMin;
    var length = word.length;
    var (cmin, cmax) = _compoundBounds(word, length);
    var st = word;
    var scpd = 0;
    var soldi = 0;
    var oldLength = 0;
    var oldCmin = 0;
    var oldCmax = 0;
    var striple = false;
    var checkedStriple = false;

    for (var i = cmin; i < cmax; i++) {
      while (i < st.length && _isLowSurrogate(st.codeUnitAt(i))) {
        i++;
      }
      if (i >= cmax) return null;

      words = oldWords;
      var onlyCompoundRule = words != null ? 1 : 0;

      do {
        final oldWordNum = wordNum;
        var checkedPrefix = false;

        do {
          if (_compoundTimeUp()) return null;

          if (scpd > 0) {
            while (scpd <= patterns.length &&
                (patterns[scpd - 1].replacement.isEmpty ||
                    i > word.length ||
                    !word.startsWith(patterns[scpd - 1].replacement, i))) {
              scpd++;
            }
            if (scpd > patterns.length) break;
            final pattern = patterns[scpd - 1];
            st = st.substring(0, i) + pattern.left;
            soldi = i;
            i += pattern.left.length;
            st =
                st.substring(0, i) +
                pattern.right +
                word.substring(soldi + pattern.replacement.length);
            oldLength = length;
            length +=
                pattern.left.length +
                pattern.right.length -
                pattern.replacement.length;
            oldCmin = cmin;
            oldCmax = cmax;
            (cmin, cmax) = _compoundBounds(st, length);
            cmax = length - minimum + 1;
          }

          if (i >= st.length) return null;
          final first = st.substring(0, i);
          _sfx = null;
          _pfx = null;

          // The first word.
          final homonyms = _lookup(first);
          var rv = homonyms?.first;

          // COMPOUNDFORBIDFLAG keeps a stem out of compounds altogether.
          if (rv != null &&
              rules.compoundForbid != Flags.none &&
              rv.has(rules.compoundForbid)) {
            final wouldContinue =
                onlyCompoundRule == 0 && rules.simplifiedCompound;
            if (scpd == 0 && wouldContinue) break;
            if (scpd > 0 && wouldContinue) {
              cmin = oldCmin;
              cmax = oldCmax;
            }
            continue;
          }

          // The first homonym that may begin or continue a compound.
          rv = null;
          for (final entry in homonyms ?? const <WordEntry>[]) {
            final bool skip;
            if (rules.needAffix != Flags.none && entry.has(rules.needAffix)) {
              skip = true;
            } else {
              var accepted =
                  (rules.compoundFlag != Flags.none &&
                      words == null &&
                      onlyCompoundRule == 0 &&
                      entry.has(rules.compoundFlag)) ||
                  (rules.compoundBegin != Flags.none &&
                      wordNum == 0 &&
                      onlyCompoundRule == 0 &&
                      entry.has(rules.compoundBegin)) ||
                  (rules.compoundMiddle != Flags.none &&
                      wordNum != 0 &&
                      words == null &&
                      onlyCompoundRule == 0 &&
                      entry.has(rules.compoundMiddle));
              if (!accepted &&
                  rules.compoundRules.isNotEmpty &&
                  onlyCompoundRule != 0) {
                if (words == null && wordNum == 0) {
                  final (matched, list) = _compoundRuleCheck(
                    words,
                    wnum,
                    maxWordNum,
                    entry,
                    ruleWords,
                    false,
                  );
                  words = list;
                  accepted = matched;
                } else if (words != null) {
                  final (matched, list) = _compoundRuleCheck(
                    words,
                    wnum,
                    maxWordNum,
                    entry,
                    ruleWords,
                    false,
                  );
                  words = list;
                  accepted = matched;
                }
              }
              skip =
                  !accepted ||
                  (scpd != 0 &&
                      patterns[scpd - 1].leftFlag != Flags.none &&
                      !entry.has(patterns[scpd - 1].leftFlag));
            }
            if (!skip) {
              rv = entry;
              break;
            }
          }

          if (rv == null) {
            if (onlyCompoundRule != 0) break;
            if (rules.compoundFlag != Flags.none) {
              rv = prefixCheck(
                first,
                InCompound.begin,
                needFlag: rules.compoundFlag,
              );
              if (rv == null) {
                rv = suffixCheck(
                  first,
                  needFlag: rules.compoundFlag,
                  inCompound: InCompound.begin,
                );
                if (rv == null && rules.compoundMoreSuffixes) {
                  rv = suffixCheckTwoSuffixes(
                    first,
                    needFlag: rules.compoundFlag,
                  );
                }
                final suffix = _sfx;
                if (rv != null &&
                    suffix != null &&
                    !suffix.continuation.isEmpty &&
                    ((rules.compoundForbid != Flags.none &&
                            suffix.continues(rules.compoundForbid)) ||
                        (rules.compoundEnd != Flags.none &&
                            suffix.continues(rules.compoundEnd)))) {
                  rv = null;
                }
              }
            }

            if (rv != null) {
              checkedPrefix = true;
            } else if (wordNum == 0 && rules.compoundBegin != Flags.none) {
              rv =
                  suffixCheck(
                    first,
                    needFlag: rules.compoundBegin,
                    inCompound: InCompound.begin,
                  ) ??
                  (rules.compoundMoreSuffixes
                      ? suffixCheckTwoSuffixes(
                          first,
                          needFlag: rules.compoundBegin,
                        )
                      : null) ??
                  prefixCheck(
                    first,
                    InCompound.begin,
                    needFlag: rules.compoundBegin,
                  );
              if (rv != null) checkedPrefix = true;
            } else if (wordNum > 0 && rules.compoundMiddle != Flags.none) {
              rv =
                  suffixCheck(
                    first,
                    needFlag: rules.compoundMiddle,
                    inCompound: InCompound.begin,
                  ) ??
                  (rules.compoundMoreSuffixes
                      ? suffixCheckTwoSuffixes(
                          first,
                          needFlag: rules.compoundMiddle,
                        )
                      : null) ??
                  prefixCheck(
                    first,
                    InCompound.begin,
                    needFlag: rules.compoundMiddle,
                  );
              if (rv != null) checkedPrefix = true;
            }
          } else if (rv.has(rules.forbiddenWord) ||
              rv.has(rules.needAffix) ||
              rv.has(Flags.onlyUpcase) ||
              (isSuggestion &&
                  rules.noSuggest != Flags.none &&
                  rv.has(rules.noSuggest))) {
            break;
          }

          final pfx = _pfx;
          final sfx = _sfx;
          // Affixes that keep their word out of compounds.
          if (rv != null &&
              ((pfx != null && pfx.continues(rules.compoundForbid)) ||
                  (sfx != null && sfx.continues(rules.compoundForbid)))) {
            rv = null;
          }
          // Affixes that only end a compound.
          if (rv != null &&
              !checkedPrefix &&
              rules.compoundEnd != Flags.none &&
              ((pfx != null && pfx.continues(rules.compoundEnd)) ||
                  (sfx != null && sfx.continues(rules.compoundEnd)))) {
            rv = null;
          }
          // Affixes that only stand in its middle.
          if (rv != null &&
              !checkedPrefix &&
              wordNum == 0 &&
              rules.compoundMiddle != Flags.none &&
              ((pfx != null && pfx.continues(rules.compoundMiddle)) ||
                  (sfx != null && sfx.continues(rules.compoundMiddle)))) {
            rv = null;
          }
          if (rv != null &&
              (rv.has(rules.forbiddenWord) ||
                  rv.has(Flags.onlyUpcase) ||
                  (isSuggestion &&
                      rules.noSuggest != Flags.none &&
                      rv.has(rules.noSuggest)))) {
            return null;
          }
          if (rv != null &&
              rules.compoundRoot != Flags.none &&
              rv.has(rules.compoundRoot)) {
            wordNum++;
          }

          // Is the first word acceptable in a compound?
          final firstOk =
              rv != null &&
              (checkedPrefix ||
                  (words != null && words[wnum] != null) ||
                  (rules.compoundFlag != Flags.none &&
                      rv.has(rules.compoundFlag)) ||
                  (oldWordNum == 0 &&
                      rules.compoundBegin != Flags.none &&
                      rv.has(rules.compoundBegin)) ||
                  (oldWordNum > 0 &&
                      rules.compoundMiddle != Flags.none &&
                      rv.has(rules.compoundMiddle))) &&
              (scpd == 0 ||
                  patterns[scpd - 1].leftFlag == Flags.none ||
                  rv.has(patterns[scpd - 1].leftFlag)) &&
              !((rules.checkCompoundTriple &&
                      scpd == 0 &&
                      words == null &&
                      i < word.length &&
                      word.codeUnitAt(i - 1) == word.codeUnitAt(i) &&
                      ((i > 1 &&
                              word.codeUnitAt(i - 1) ==
                                  word.codeUnitAt(i - 2)) ||
                          (i + 1 < word.length &&
                              word.codeUnitAt(i - 1) ==
                                  word.codeUnitAt(i + 1)))) ||
                  (rules.checkCompoundCase &&
                      scpd == 0 &&
                      words == null &&
                      i < word.length &&
                      _compoundCaseCheck(word, i)));

          if (firstOk) {
            final rvFirst = rv;

            do {
              if (rules.simplifiedTriple) {
                if (striple) {
                  checkedStriple = true;
                  i--; // "fahrt" rather than "ahrt" in "Schiffahrt"
                } else if (i > 2 &&
                    i <= word.length &&
                    word.codeUnitAt(i - 1) == word.codeUnitAt(i - 2)) {
                  striple = true;
                }
              }

              // The second word, as it is.
              final second = st.substring(i);
              WordEntry? rv2;
              for (final entry in _lookup(second) ?? const <WordEntry>[]) {
                final bool skip;
                if (rules.needAffix != Flags.none &&
                    entry.has(rules.needAffix)) {
                  skip = true;
                } else {
                  var accepted =
                      (rules.compoundFlag != Flags.none &&
                          words == null &&
                          entry.has(rules.compoundFlag)) ||
                      (rules.compoundEnd != Flags.none &&
                          words == null &&
                          entry.has(rules.compoundEnd));
                  if (!accepted &&
                      rules.compoundRules.isNotEmpty &&
                      words != null) {
                    final (matched, list) = _compoundRuleCheck(
                      words,
                      wnum + 1,
                      maxWordNum,
                      entry,
                      null,
                      true,
                    );
                    words = list;
                    accepted = matched;
                  }
                  skip =
                      !accepted ||
                      (scpd != 0 &&
                          patterns[scpd - 1].rightFlag != Flags.none &&
                          !entry.has(patterns[scpd - 1].rightFlag));
                }
                if (!skip) {
                  rv2 = entry;
                  break;
                }
              }
              var rvSecond = rv2;

              if (rvSecond != null &&
                  rules.forceUppercase != Flags.none &&
                  rvSecond.has(rules.forceUppercase) &&
                  !(info != null && info.has(SpellInfo.originalCapitals))) {
                rvSecond = null;
              }
              if (rvSecond != null &&
                  words != null &&
                  wnum + 1 < words.length &&
                  words[wnum + 1] != null) {
                return rvFirst;
              }

              final oldWordNum2 = wordNum;
              if (rvSecond != null &&
                  rules.compoundRoot != Flags.none &&
                  rvSecond.has(rules.compoundRoot)) {
                wordNum++;
              }
              if (rvSecond != null &&
                  (rvSecond.has(rules.forbiddenWord) ||
                      rvSecond.has(Flags.onlyUpcase) ||
                      (isSuggestion &&
                          rules.noSuggest != Flags.none &&
                          rvSecond.has(rules.noSuggest)))) {
                return null;
              }

              // The second word acceptable as it is?
              if (rvSecond != null &&
                  ((rules.compoundFlag != Flags.none &&
                          rvSecond.has(rules.compoundFlag)) ||
                      (rules.compoundEnd != Flags.none &&
                          rvSecond.has(rules.compoundEnd))) &&
                  (rules.compoundWordMax == -1 ||
                      wordNum + 1 < rules.compoundWordMax) &&
                  (patterns.isEmpty ||
                      scpd != 0 ||
                      (i < word.length &&
                          !_compoundPatternCheck(
                            word,
                            i,
                            rvFirst,
                            rvSecond,
                          ))) &&
                  (!rules.checkCompoundDup || !identical(rvSecond, rvFirst)) &&
                  (scpd == 0 ||
                      patterns[scpd - 1].rightFlag == Flags.none ||
                      rvSecond.has(patterns[scpd - 1].rightFlag))) {
                if ((rules.checkCompoundRep && _compoundRepCheck(word)) ||
                    _compoundWordPairCheck(word)) {
                  return null;
                }
                return rvFirst;
              }

              wordNum = oldWordNum2;

              // The second word with affixes?
              _sfx = null;
              rvSecond =
                  rules.compoundFlag != Flags.none &&
                      onlyCompoundRule == 0 &&
                      i < word.length
                  ? affixCheck(
                      word.substring(i),
                      needFlag: rules.compoundFlag,
                      inCompound: InCompound.end,
                    )
                  : null;
              if (rvSecond == null &&
                  rules.compoundEnd != Flags.none &&
                  onlyCompoundRule == 0) {
                _sfx = null;
                _pfx = null;
                if (i < word.length) {
                  rvSecond = affixCheck(
                    word.substring(i),
                    needFlag: rules.compoundEnd,
                    inCompound: InCompound.end,
                  );
                }
              }
              if (rvSecond == null &&
                  rules.compoundRules.isNotEmpty &&
                  words != null) {
                if (i < word.length) {
                  rvSecond = affixCheck(
                    word.substring(i),
                    inCompound: InCompound.end,
                  );
                }
                if (rvSecond != null) {
                  final (matched, list) = _compoundRuleCheck(
                    words,
                    wnum + 1,
                    maxWordNum,
                    rvSecond,
                    null,
                    true,
                  );
                  words = list;
                  if (matched) return rvFirst;
                }
                rvSecond = null;
              }

              if (rvSecond != null &&
                  !(scpd == 0 ||
                      patterns[scpd - 1].rightFlag == Flags.none ||
                      rvSecond.has(patterns[scpd - 1].rightFlag))) {
                rvSecond = null;
              }
              if (rvSecond != null &&
                  patterns.isNotEmpty &&
                  scpd == 0 &&
                  _compoundPatternCheck(word, i, rvFirst, rvSecond)) {
                rvSecond = null;
              }
              final pfx2 = _pfx;
              final sfx2 = _sfx;
              if (rvSecond != null &&
                  ((pfx2 != null && pfx2.continues(rules.compoundForbid)) ||
                      (sfx2 != null && sfx2.continues(rules.compoundForbid)))) {
                rvSecond = null;
              }
              if (rvSecond != null &&
                  rules.forceUppercase != Flags.none &&
                  rvSecond.has(rules.forceUppercase) &&
                  !(info != null && info.has(SpellInfo.originalCapitals))) {
                rvSecond = null;
              }
              if (rvSecond != null &&
                  (rvSecond.has(rules.forbiddenWord) ||
                      rvSecond.has(Flags.onlyUpcase) ||
                      (isSuggestion &&
                          rules.noSuggest != Flags.none &&
                          rvSecond.has(rules.noSuggest)))) {
                return null;
              }
              if (rvSecond != null &&
                  rules.compoundRoot != Flags.none &&
                  rvSecond.has(rules.compoundRoot)) {
                wordNum++;
              }
              if (rvSecond != null &&
                  (rules.compoundWordMax == -1 ||
                      wordNum + 1 < rules.compoundWordMax) &&
                  (!rules.checkCompoundDup || !identical(rvSecond, rvFirst))) {
                if ((rules.checkCompoundRep && _compoundRepCheck(word)) ||
                    _compoundWordPairCheck(word)) {
                  return null;
                }
                return rvFirst;
              }

              wordNum = oldWordNum2;

              // Perhaps the second word is a compound itself.
              WordEntry? rvRest;
              if ((info == null || !info.has(SpellInfo.twoWordCompound)) &&
                  wordNum + 2 < maxWordNum &&
                  wnum + 1 < maxWordNum) {
                rvRest = compoundCheck(
                  st.substring(i),
                  wordNum + 1,
                  maxWordNum,
                  wnum + 1,
                  words,
                  ruleWords,
                  isSuggestion,
                  info,
                );
                if (rvRest != null &&
                    patterns.isNotEmpty &&
                    i < word.length &&
                    ((scpd == 0 &&
                            _compoundPatternCheck(word, i, rvFirst, rvRest)) ||
                        (scpd != 0 &&
                            !_compoundPatternCheck(
                              word,
                              i,
                              rvFirst,
                              rvRest,
                            )))) {
                  rvRest = null;
                }
              }
              if (rvRest != null) {
                if (_compoundWordPairCheck(word)) return null;
                if (rules.checkCompoundRep && _compoundRepCheck(word)) {
                  return null;
                }
                // The second part's first word, with what came before.
                final end = i + rvRest.word.length;
                if (i < word.length && word.startsWith(rvRest.word, i)) {
                  final head = st.substring(
                    0,
                    end > st.length ? st.length : end,
                  );
                  if ((rules.checkCompoundRep && _compoundRepCheck(head)) ||
                      _compoundWordPairCheck(head)) {
                    continue;
                  }
                  var rvWhole = _lookup(word)?.first;
                  if (rvWhole == null && length <= word.length) {
                    rvWhole = affixCheck(word.substring(0, length));
                  }
                  if (rvWhole != null &&
                      rvWhole.has(rules.forbiddenWord) &&
                      _sameStart(rvWhole.word, head, end)) {
                    return null;
                  }
                }
                return rvFirst;
              }
            } while (striple && !checkedStriple);

            if (checkedStriple) {
              i++;
              checkedStriple = false;
              striple = false;
            }
          }

          if (soldi != 0) {
            i = soldi;
            soldi = 0;
            length = oldLength;
            cmin = oldCmin;
            cmax = oldCmax;
          }
          scpd++;
        } while (onlyCompoundRule == 0 &&
            rules.simplifiedCompound &&
            scpd <= patterns.length);

        scpd = 0;
        wordNum = oldWordNum;
        if (soldi != 0) {
          i = soldi;
          st = word;
          soldi = 0;
          length = oldLength;
          cmin = oldCmin;
          cmax = oldCmax;
        }
      } while (rules.compoundRules.isNotEmpty &&
          wordNum == 0 &&
          onlyCompoundRule++ < 1);
    }
    return null;
  }

  /// Whether the first [n] characters of [a] and [b] are the same, as C's
  /// strncmp compares them.
  static bool _sameStart(String a, String b, int n) =>
      (a.length > n ? a.substring(0, n) : a) ==
      (b.length > n ? b.substring(0, n) : b);

  List<WordEntry>? _lookup(String word) => words.lookup(word);
}
