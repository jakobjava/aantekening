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

/// Suggestions for a misspelled word: Hunspell's suggestion manager, ported.
library;

import 'dart:math' as math;

import 'affix_index.dart';
import 'affix_rules.dart';
import 'casing.dart';
import 'checker.dart';
import 'flags.dart';
import 'word_table.dart';

/// Finds words a misspelling was probably meant to be.
final class Suggester {
  Suggester(this._checker, this._rules, this._words, this._affixes)
    : _maxNgram = _rules.maxNgramSuggestions >= 0
          ? _rules.maxNgramSuggestions
          : 4,
      _maxCompound = _rules.maxCompoundSuggestions >= 0
          ? _rules.maxCompoundSuggestions
          : 3,
      _dashes =
          _rules.tryCharacters.contains('-') ||
          _rules.tryCharacters.contains('a');

  final Checker _checker;
  final AffixRules _rules;
  final WordTable _words;
  final AffixIndex _affixes;

  final int _maxNgram;
  final int _maxCompound;

  /// Whether the language joins words with dashes, going by its TRY
  /// characters: Latin letters or a dash.
  final bool _dashes;

  static const int maxSuggestions = 15;
  static const int _maxCharDistance = 4;
  static const int _minTimer = 100;

  // Hunspell's time limits for a search, doubled: this port runs at about
  // half its speed, and a search cut short finds different suggestions.
  static const Duration _suggestionTimeLimit = Duration(milliseconds: 200);
  static const Duration _checkTimeLimit = Duration(milliseconds: 100);

  final Stopwatch _clock = Stopwatch();

  // -------------------------------------------------------------- entry

  /// Suggestions for [word], best first.
  List<String> suggest(String word) => _checker.timed(
    () => _suggest(word, <String>[]),
    limit: const Duration(milliseconds: 500),
  );

  List<String> _suggest(String word, List<String> stack) {
    if (stack.length > 2048 || stack.contains(word)) return <String>[];
    stack.add(word);
    final (list, capitalise, abbreviation, capType) = _suggestInternal(
      word,
      stack,
    );
    stack.removeLast();
    var suggestions = list;

    if (capitalise) {
      suggestions = <String>[
        for (final suggestion in suggestions)
          Casing.initialCapital(suggestion) == word
              ? suggestion
              : Casing.initialCapital(suggestion),
      ];
    }
    if (abbreviation > 0 &&
        _rules.suggestionsWithDots &&
        word.length >= abbreviation) {
      final dots = word.substring(word.length - abbreviation);
      suggestions = <String>[for (final s in suggestions) '$s$dots'];
    }

    // Wrong capitals and forbidden forms go.
    if (_rules.keepCase != Flags.none || _rules.forbiddenWord != Flags.none) {
      if (capType != CapType.none) {
        final kept = <String>[];
        for (final suggestion in suggestions) {
          var bad = !_checker.spell(suggestion);
          if (bad && suggestion.contains(' ')) {
            bad = suggestion
                .split(' ')
                .any((part) => part.isNotEmpty && !_checker.spell(part));
          }
          if (!bad) {
            kept.add(suggestion);
            continue;
          }
          final lower = Casing.lower(suggestion);
          if (_checker.spell(lower)) {
            kept.add(lower);
          } else {
            final capitalised = Casing.initialCapital(lower);
            if (_checker.spell(capitalised)) kept.add(capitalised);
          }
        }
        suggestions = kept;
      }
    }

    final unique = <String>[];
    for (final suggestion in suggestions) {
      if (!unique.contains(suggestion)) unique.add(suggestion);
    }
    final output = _rules.outputConversion;
    if (output == null) return unique;
    return <String>[
      for (final suggestion in unique)
        if ((output.convert(suggestion) ?? suggestion) case final converted
            when converted != word)
          converted,
    ];
  }

  (List<String>, bool, int, CapType) _suggestInternal(
    String word,
    List<String> stack,
  ) {
    final list = <String>[];
    if (word.length >= 300) return (list, false, 0, CapType.none);
    final converted = _rules.inputConversion?.convert(word) ?? word;
    var (scw, abbreviation) = _clean(converted);
    if (scw.isEmpty) return (list, false, 0, CapType.none);
    final capType = Casing.of(scw);
    var capitalise = false;
    var good = false;
    final onlyCompound = <bool>[false];

    // A word only ever written with a capital first letter.
    if (capType == CapType.none && _rules.forceUppercase != Flags.none) {
      final info = InfoBox(SpellInfo.originalCapitals);
      if (_checker.checkWord(scw, info) != null) {
        return (<String>[Casing.initialCapital(scw)], false, 0, capType);
      }
    }

    switch (capType) {
      case CapType.none:
        good |= suggestInto(list, scw, onlyCompound);
        if (abbreviation > 0) good |= suggestInto(list, '$scw.', onlyCompound);
      case CapType.initial:
        capitalise = true;
        good |= suggestInto(list, scw, onlyCompound);
        good |= suggestInto(list, Casing.lower(scw), onlyCompound);
      case CapType.mixedInitial:
      case CapType.mixed:
        if (capType == CapType.mixedInitial) capitalise = true;
        good |= suggestInto(list, scw, onlyCompound);
        // something.The -> something. The
        final dot = scw.indexOf('.');
        if (dot >= 0 && Casing.of(scw.substring(dot + 1)) == CapType.initial) {
          list.insert(
            0,
            '${scw.substring(0, dot + 1)} ${scw.substring(dot + 1)}',
          );
        }
        if (capType == CapType.mixedInitial) {
          // TheOpenOffice.org -> The OpenOffice.org
          good |= suggestInto(list, Casing.initialSmall(scw), onlyCompound);
        }
        var lowered = Casing.lower(scw);
        if (_checker.spell(lowered)) list.insert(0, lowered);
        final before = list.length;
        good |= suggestInto(list, lowered, onlyCompound);
        if (capType == CapType.mixedInitial) {
          lowered = Casing.initialCapital(lowered);
          if (_checker.spell(lowered)) list.insert(0, lowered);
          good |= suggestInto(list, lowered, onlyCompound);
        }
        // aNew -> "a New" rather than "a new".
        for (var j = before; j < list.length; j++) {
          final space = list[j].indexOf(' ');
          if (space < 0) continue;
          final after = list[j].substring(space + 1);
          if (after.length < scw.length && !scw.endsWith(after)) {
            final fixed =
                list[j].substring(0, space + 1) + Casing.initialCapital(after);
            list
              ..removeAt(j)
              ..insert(0, fixed);
          }
        }
      case CapType.all:
        var lowered = Casing.lower(scw);
        good |= suggestInto(list, lowered, onlyCompound);
        if (_rules.keepCase != Flags.none && _checker.spell(lowered)) {
          list.insert(0, lowered);
        }
        lowered = Casing.initialCapital(lowered);
        good |= suggestInto(list, lowered, onlyCompound);
        for (var j = 0; j < list.length; j++) {
          var upper = Casing.upper(list[j]);
          if (_rules.checkSharps) upper = upper.replaceAll('ß', 'SS');
          list[j] = upper;
        }
    }

    // Poorly misspelled words get ngram suggestions.
    if (!good && (list.isEmpty || onlyCompound.first) && _maxNgram != 0) {
      switch (capType) {
        case CapType.none:
          _ngramSuggest(list, scw, capType);
        case CapType.mixedInitial:
        case CapType.mixed:
          if (capType == CapType.mixedInitial) capitalise = true;
          _ngramSuggest(list, Casing.lower(scw), CapType.mixed);
        case CapType.initial:
          capitalise = true;
          _ngramSuggest(list, Casing.lower(scw), capType);
        case CapType.all:
          final before = list.length;
          _ngramSuggest(list, Casing.lower(scw), capType);
          for (var j = before; j < list.length; j++) {
            list[j] = Casing.upper(list[j]);
          }
      }
    }

    // A misspelled part of a dashed word: Afo-American -> Afro-American.
    var dash = scw.indexOf('-');
    if (dash >= 0 && !list.any((suggestion) => suggestion.contains('-'))) {
      var previous = 0;
      var last = false;
      var noDashSuggestion = true;
      while (!good && noDashSuggestion && !last) {
        if (dash == scw.length) last = true;
        final chunk = scw.substring(previous, dash);
        if (chunk != word && !_checker.spell(chunk)) {
          final inner = _suggest(chunk, stack);
          for (final suggestion in inner.reversed) {
            var candidate = scw.substring(0, previous) + suggestion;
            if (!last) candidate += '-${scw.substring(dash + 1)}';
            final info = InfoBox();
            if (_rules.forbiddenWord != Flags.none) {
              _checker.checkWord(candidate, info);
            }
            if (!info.has(SpellInfo.forbidden)) list.insert(0, candidate);
          }
          noDashSuggestion = false;
        }
        if (!last) {
          previous = dash + 1;
          dash = scw.indexOf('-', previous);
        }
        if (dash < 0) dash = scw.length;
      }
    }
    return (list, capitalise, abbreviation, capType);
  }

  static (String, int) _clean(String word) {
    var start = 0;
    while (start < word.length && word.codeUnitAt(start) == 0x20) {
      start++;
    }
    var end = word.length;
    var dots = 0;
    while (end > start && word.codeUnitAt(end - 1) == 0x2E) {
      end--;
      dots++;
    }
    return (word.substring(start, end), dots);
  }

  // ---------------------------------------------------------- the search

  /// Adds suggestions for [word] to [list], trying compounds only when
  /// nothing simpler turns up; [testOnly] stops at the first found. Returns
  /// whether a good suggestion — a REP match or a pair of dictionary words
  /// — was found. [onlyCompound] is set when all there is are compounds.
  bool suggestInto(
    List<String> list,
    String word,
    List<bool>? onlyCompound, {
    bool testOnly = false,
  }) {
    _clock
      ..reset()
      ..start();
    final originalLength = list.length;
    var oldLength = 0;
    var good = false;
    var noMoreCompounds = false;
    final info = InfoBox();

    bool timeUp() => _clock.elapsed > _suggestionTimeLimit;
    bool room(int cpd) =>
        list.length < maxSuggestions &&
        (cpd == 0 || list.length < oldLength + _maxCompound);

    for (var cpd = 0; cpd < 3 && !noMoreCompounds; cpd++) {
      if (cpd > 0) oldLength = list.length;

      if (list.length < maxSuggestions) {
        final before = list.length;
        _capitals(list, word, cpd, info);
        if (list.length > before) good = true;
      }
      if (room(cpd)) {
        final before = list.length;
        _replacements(list, word, cpd, info);
        if (list.length > before) {
          good = true;
          if (info.has(SpellInfo.bestSuggestion)) return true;
        }
      }
      if (timeUp()) return good;
      if (testOnly && list.isNotEmpty) return true;

      if (room(cpd)) _related(list, word, cpd, info);
      if (timeUp()) return good;
      if (testOnly && list.isNotEmpty) return true;

      // Compounds only when nothing better turned up.
      if (cpd == 0 && list.length > originalLength) noMoreCompounds = true;

      for (final generate
          in <void Function(List<String>, String, int, InfoBox)>[
            _swapped,
            _swappedApart,
            _badKey,
            _extra,
            _forgotten,
            _moved,
            _badCharacter,
            _doubledPair,
          ]) {
        if (room(cpd)) generate(list, word, cpd, info);
        if (timeUp()) return good;
        if (testOnly && list.isNotEmpty) return true;
      }

      if (cpd == 0 ||
          (!_rules.noSplitSuggestions &&
              list.length < oldLength + _maxCompound)) {
        good = _twoWords(list, word, cpd, good, info);
        if (info.has(SpellInfo.bestSuggestion)) return true;
      }
      if (timeUp()) return good;
      if (testOnly) return list.isNotEmpty;

      if (cpd == 1 &&
          (list.length > oldLength || info.has(SpellInfo.compound))) {
        noMoreCompounds = true;
      }
    }
    if (!noMoreCompounds && list.isNotEmpty && onlyCompound != null) {
      onlyCompound[0] = true;
    }
    return good;
  }

  /// Whether a simpler word is a likely spelling of [word], a compound of
  /// three or more words.
  bool hasSimpleSuggestion(String word) =>
      suggestInto(<String>[], word, null, testOnly: true);

  // ---------------------------------------------------------- candidates

  int _timer = _minTimer;
  final Stopwatch _timerClock = Stopwatch();

  void _startTimer() {
    _timer = _minTimer;
    _timerClock
      ..reset()
      ..start();
  }

  /// Checks [candidate] and adds it if it is a word: 1 for a word, 2 for a
  /// compound part, 3 for a compound; 0 for none.
  int _check(String candidate, int cpd, {bool timed = false}) {
    if (_clock.elapsed > _suggestionTimeLimit) return 0;
    if (timed) {
      _timer--;
      if (_timer == 0) {
        if (_timerClock.elapsed > _checkTimeLimit) return 0;
        _timer = _minTimer;
      }
    }
    if (cpd >= 1) {
      if (_rules.compounds) {
        final info = InfoBox(cpd == 1 ? SpellInfo.twoWordCompound : 0);
        final rv = _checker.compoundCheck(
          candidate,
          0,
          100,
          0,
          null,
          List<WordEntry?>.filled(100, null),
          true,
          info,
        );
        if (rv != null) {
          final whole = _words.lookup(candidate)?.first;
          if (whole == null ||
              !(whole.has(_rules.forbiddenWord) ||
                  whole.has(_rules.noSuggest))) {
            return 3;
          }
        }
      }
      return 0;
    }

    var suffixless = false;
    WordEntry? rv;
    final homonyms = _words.lookup(candidate);
    if (homonyms != null) {
      final first = homonyms.first;
      if (first.has(_rules.forbiddenWord) ||
          first.has(_rules.noSuggest) ||
          first.has(_rules.substandard)) {
        return 0;
      }
      for (final entry in homonyms) {
        if (entry.has(_rules.needAffix) ||
            entry.has(Flags.onlyUpcase) ||
            entry.has(_rules.onlyInCompound)) {
          continue;
        }
        rv = entry;
        break;
      }
    } else {
      rv = _checker.prefixCheck(candidate, InCompound.not);
    }
    if (rv != null) {
      suffixless = true;
    } else {
      rv = _checker.suffixCheck(candidate);
    }
    if (rv == null && _rules.continuationClasses.isNotEmpty) {
      rv =
          _checker.suffixCheckTwoSuffixes(candidate) ??
          _checker.prefixCheckTwoSuffixes(candidate, InCompound.not);
    }
    if (rv != null &&
        (rv.has(_rules.forbiddenWord) ||
            rv.has(Flags.onlyUpcase) ||
            rv.has(_rules.noSuggest) ||
            rv.has(_rules.onlyInCompound))) {
      return 0;
    }
    if (rv == null) return 0;
    if (_rules.compoundFlag != Flags.none && rv.has(_rules.compoundFlag)) {
      return suffixless ? 3 : 2;
    }
    return 1;
  }

  void _test(
    List<String> list,
    String candidate,
    int cpd,
    InfoBox info, {
    bool timed = false,
  }) {
    if (list.length >= maxSuggestions || list.contains(candidate)) return;
    final result = _check(candidate, cpd, timed: timed);
    if (result == 0) return;
    if (cpd == 0 && result >= 2) info.value |= SpellInfo.compound;
    list.add(candidate);
  }

  /// html -> HTML
  void _capitals(List<String> list, String word, int cpd, InfoBox info) =>
      _test(list, Casing.upper(word), cpd, info);

  /// Common misspellings the REP table lists.
  void _replacements(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 2) return;
    final start = Stopwatch()..start();
    for (final replacement in _rules.replacements) {
      var at = word.indexOf(replacement.pattern);
      while (at >= 0) {
        if (start.elapsed > _suggestionTimeLimit) return;
        final output = replacement.outputAt(at, word.length);
        if (output.isEmpty) {
          at = word.indexOf(replacement.pattern, at + 1);
          continue;
        }
        final candidate = word.replaceRange(
          at,
          at + replacement.pattern.length,
          output,
        );
        final before = list.length;
        _test(list, candidate, cpd, info);
        if (list.length > before) info.value |= SpellInfo.bestSuggestion;

        // A replacement with a space is good if its parts are.
        var space = candidate.indexOf(' ');
        var previous = 0;
        while (space >= 0) {
          if (_check(candidate.substring(previous, space), 0) != 0) {
            final count = list.length;
            _test(list, candidate.substring(space + 1), cpd, info);
            if (list.length > count) list[list.length - 1] = candidate;
          }
          previous = space + 1;
          space = candidate.indexOf(' ', previous);
        }
        at = word.indexOf(replacement.pattern, at + 1);
      }
    }
  }

  /// A character from a related set, as MAP lists them: a for á.
  void _related(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 2 || _rules.related.isEmpty) return;
    _startTimer();
    void visit(String candidate, int at, int depth) {
      if (_timer == 0 || _clock.elapsed > _suggestionTimeLimit) return;
      if (depth > 0x3F00) {
        _timer = 0;
        return;
      }
      if (at == word.length) {
        if (candidate != word &&
            !list.contains(candidate) &&
            _check(candidate, cpd, timed: true) != 0 &&
            list.length < maxSuggestions) {
          list.add(candidate);
        }
        return;
      }
      var inMap = false;
      for (final group in _rules.related) {
        for (final member in group) {
          if (member.isEmpty || !word.startsWith(member, at)) continue;
          inMap = true;
          for (final other in group) {
            visit(candidate + other, at + member.length, depth + 1);
            if (_timer == 0) return;
          }
        }
      }
      if (!inMap) visit(candidate + word[at], at + 1, depth + 1);
    }

    visit('', 0, 0);
  }

  /// Two neighbouring letters swapped; for short words, two pairs.
  void _swapped(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 2) return;
    final units = word.codeUnits.toList();
    for (var i = 0; i < units.length - 1; i++) {
      _swap(units, i, i + 1);
      _test(list, String.fromCharCodes(units), cpd, info);
      _swap(units, i, i + 1);
    }
    if (units.length == 4 || units.length == 5) {
      final original = word.codeUnits;
      units[0] = original[1];
      units[1] = original[0];
      units[2] = original[2];
      units[units.length - 2] = original[units.length - 1];
      units[units.length - 1] = original[units.length - 2];
      _test(list, String.fromCharCodes(units), cpd, info);
      if (units.length == 5) {
        units[0] = original[0];
        units[1] = original[2];
        units[2] = original[1];
        _test(list, String.fromCharCodes(units), cpd, info);
      }
    }
  }

  /// Two letters a little apart swapped.
  void _swappedApart(List<String> list, String word, int cpd, InfoBox info) {
    final units = word.codeUnits.toList();
    for (var p = 0; p < units.length; p++) {
      for (var q = 0; q < units.length; q++) {
        final distance = (q - p).abs();
        if (distance > 1 &&
            distance <= _maxCharDistance &&
            units[p] != units[q]) {
          _swap(units, p, q);
          _test(list, String.fromCharCodes(units), cpd, info);
          _swap(units, p, q);
        }
      }
    }
  }

  /// A capital, or a key beside the right one on the keyboard, in place of
  /// a letter.
  void _badKey(List<String> list, String word, int cpd, InfoBox info) {
    final units = word.codeUnits.toList();
    final keyboard = _rules.keyboard.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final original = units[i];
      units[i] = Casing.upperUnit(original);
      if (units[i] != original) {
        _test(list, String.fromCharCodes(units), cpd, info);
        units[i] = original;
      }
      if (keyboard.isEmpty) continue;
      var at = keyboard.indexOf(original);
      while (at >= 0) {
        if (_clock.elapsed > _suggestionTimeLimit) return;
        if (at > 0 && keyboard[at - 1] != 0x7C) {
          units[i] = keyboard[at - 1];
          _test(list, String.fromCharCodes(units), cpd, info);
        }
        if (at + 1 < keyboard.length && keyboard[at + 1] != 0x7C) {
          units[i] = keyboard[at + 1];
          _test(list, String.fromCharCodes(units), cpd, info);
        }
        at = keyboard.indexOf(original, at + 1);
      }
      units[i] = original;
    }
  }

  /// A letter too many.
  void _extra(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 2) return;
    for (var i = word.length - 1; i >= 0; i--) {
      _test(list, word.substring(0, i) + word.substring(i + 1), cpd, info);
    }
  }

  /// A letter missing.
  void _forgotten(List<String> list, String word, int cpd, InfoBox info) {
    _startTimer();
    for (final unit in _rules.tryCharacters.codeUnits) {
      final letter = String.fromCharCode(unit);
      for (var i = word.length; i >= 0; i--) {
        _test(
          list,
          word.substring(0, i) + letter + word.substring(i),
          cpd,
          info,
          timed: true,
        );
        if (_timer == 0) return;
      }
    }
  }

  /// A letter moved a few places.
  void _moved(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 2) return;
    final original = word.codeUnits;
    final units = original.toList();
    for (var p = 0; p < units.length; p++) {
      for (var q = p + 1; q < units.length && q - p <= _maxCharDistance; q++) {
        _swap(units, q, q - 1);
        if (q - p < 2) continue;
        _test(list, String.fromCharCodes(units), cpd, info);
      }
      units.setAll(0, original);
    }
    for (var p = units.length - 1; p > 0; p--) {
      for (var q = p - 1; q >= 0 && p - q <= _maxCharDistance; q--) {
        _swap(units, q, q + 1);
        if (p - q < 2) continue;
        _test(list, String.fromCharCodes(units), cpd, info);
      }
      units.setAll(0, original);
    }
  }

  /// A wrong letter, trying each of the TRY characters in its place.
  void _badCharacter(List<String> list, String word, int cpd, InfoBox info) {
    _startTimer();
    final units = word.codeUnits.toList();
    for (final replacement in _rules.tryCharacters.codeUnits) {
      for (var i = units.length - 1; i >= 0; i--) {
        final original = units[i];
        if (original == replacement) continue;
        units[i] = replacement;
        _test(list, String.fromCharCodes(units), cpd, info, timed: true);
        units[i] = original;
        if (_timer == 0) return;
      }
    }
  }

  /// Two letters doubled: vacacation -> vacation.
  void _doubledPair(List<String> list, String word, int cpd, InfoBox info) {
    if (word.length < 5) return;
    var state = 0;
    for (var i = 2; i < word.length; i++) {
      if (word.codeUnitAt(i) == word.codeUnitAt(i - 2)) {
        state++;
        if (state == 3 || (state == 2 && i >= 4)) {
          _test(
            list,
            word.substring(0, i - 1) + word.substring(i + 1),
            cpd,
            info,
          );
          state = 0;
        }
      } else {
        state = 0;
      }
    }
  }

  /// Two words run together. A pair listed in the dictionary is the best
  /// suggestion there can be.
  bool _twoWords(
    List<String> list,
    String word,
    int cpd,
    bool good,
    InfoBox info,
  ) {
    if (word.length < 3) return false;
    var result = good;
    for (var i = 1; i < word.length; i++) {
      if (_isLowSurrogate(word.codeUnitAt(i))) continue;
      final first = word.substring(0, i);
      final second = word.substring(i);
      for (final joiner in <String>[' ', if (_dashes) '-']) {
        final pair = '$first$joiner$second';
        if (cpd == 0 && _check(pair, cpd) != 0) {
          info.value |= SpellInfo.bestSuggestion;
          if (!result) {
            result = true;
            list.clear();
          }
          list.insert(0, pair);
        }
      }
      if (list.length < maxSuggestions &&
          !_rules.noSplitSuggestions &&
          !result &&
          _check(first, cpd) != 0 &&
          _check(second, cpd) != 0) {
        final spaced = '$first $second';
        if (!list.contains(spaced) && list.length < maxSuggestions) {
          list.add(spaced);
        }
        if (_dashes && second.length > 1 && first.length > 1) {
          final dashed = '$first-$second';
          if (!list.contains(dashed) && list.length < maxSuggestions) {
            list.add(dashed);
          }
        }
      }
    }
    return result;
  }

  static void _swap(List<int> units, int a, int b) {
    final kept = units[a];
    units[a] = units[b];
    units[b] = kept;
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  // --------------------------------------------------------------- ngram

  static const int _maxRoots = 100;
  static const int _maxGuesses = 200;
  static const int _maxWords = 100;

  static const int _longerWorse = 1 << 0;
  static const int _anyMismatch = 1 << 1;
  static const int _weighted = 1 << 3;

  /// Suggestions for a word too misspelled for the simpler ways: the
  /// dictionary words most like it, with the affixes that make them most
  /// like it.
  void _ngramSuggest(List<String> list, String word, CapType capType) {
    final n = word.length;
    if (n > 1200) return;
    final roots = List<WordEntry?>.filled(_maxRoots, null);
    final scores = List<int>.generate(_maxRoots, (i) => -100 * i);
    var lowest = _maxRoots - 1;
    var hasRoots = false;
    final german = _rules.language?.startsWith('de') ?? false;

    for (final entry in _words.entries) {
      if ((n - entry.word.length).abs() > 4) continue;
      if (capType == CapType.none && entry.initialCapital && !german) {
        continue;
      }
      if (entry.has(_rules.forbiddenWord) ||
          entry.has(Flags.onlyUpcase) ||
          entry.has(_rules.noSuggest) ||
          entry.has(_rules.noNgramSuggest) ||
          entry.has(_rules.onlyInCompound)) {
        continue;
      }
      final score =
          _ngram(3, word, Casing.lower(entry.word), _longerWorse) +
          _leftCommon(word, entry.word);
      if (score > scores[lowest]) {
        scores[lowest] = score;
        roots[lowest] = entry;
        hasRoots = true;
        var least = score;
        for (var j = 0; j < _maxRoots; j++) {
          if (scores[j] < least) {
            lowest = j;
            least = scores[j];
          }
        }
      }
    }
    if (!hasRoots) return;

    // The least a guess must score: the word mangled three ways.
    var threshold = 0;
    for (var sp = 1; sp < 4; sp++) {
      final mangled = word.codeUnits.toList();
      for (var k = sp; k < n; k += 4) {
        mangled[k] = 0x2A;
      }
      threshold += _ngram(
        n,
        word,
        Casing.lower(String.fromCharCodes(mangled)),
        _anyMismatch,
      );
    }
    threshold = threshold ~/ 3 - 1;

    final guesses = List<String?>.filled(_maxGuesses, null);
    final guessScores = List<int>.generate(_maxGuesses, (i) => -100 * i);
    lowest = _maxGuesses - 1;
    for (final root in roots) {
      if (root == null) continue;
      for (final form in _expand(root, word)) {
        final score =
            _ngram(n, word, Casing.lower(form), _anyMismatch) +
            _leftCommon(word, form);
        if (score <= threshold || score <= guessScores[lowest]) continue;
        guessScores[lowest] = score;
        guesses[lowest] = form;
        var least = score;
        for (var j = 0; j < _maxGuesses; j++) {
          if (guessScores[j] < least) {
            lowest = j;
            least = guessScores[j];
          }
        }
      }
    }
    _sortByScore(guesses, guessScores);

    // Weigh the guesses by their longest common subsequence and resort.
    final factor = _rules.maxDiff >= 0 ? (10.0 - _rules.maxDiff) / 5.0 : 1.0;
    for (var i = 0; i < _maxGuesses; i++) {
      final guess = guesses[i];
      if (guess == null) continue;
      final lowered = Casing.lower(guess);
      final length = guess.length;
      final common = _longestCommonSubsequence(word, lowered);
      // The same letters, differently capitalised.
      if (n == length && n == common) {
        guessScores[i] += 2000;
        break;
      }
      var weighted = _ngram(2, word, lowered, _anyMismatch | _weighted);
      weighted += _ngram(
        2,
        lowered,
        Casing.lower(word),
        _anyMismatch | _weighted,
      );
      final (positions, swapped) = _commonPositions(word, lowered);
      guessScores[i] =
          2 * common -
          (n - length).abs() +
          _leftCommon(word, lowered) +
          (positions > 0 ? 1 : 0) +
          (swapped ? 10 : 0) +
          _ngram(4, word, lowered, _anyMismatch) +
          weighted +
          (weighted < (n + length) * factor ? -1000 : 0);
    }
    _sortByScore(guesses, guessScores);

    final before = list.length;
    var same = false;
    for (var i = 0; i < _maxGuesses; i++) {
      final guess = guesses[i];
      if (guess == null) continue;
      if (list.length >= before + _maxNgram ||
          list.length >= maxSuggestions ||
          (same && guessScores[i] <= 1000)) {
        continue;
      }
      if (guessScores[i] > 1000) {
        same = true;
      } else if (guessScores[i] < -100) {
        same = true;
        if (list.length > before || _rules.onlyMaxDiff) continue;
      }
      var unique = true;
      for (final existing in list) {
        if (guess.contains(existing) || _check(guess, 0) == 0) {
          unique = false;
          break;
        }
      }
      if (unique) list.add(guess);
    }
  }

  /// [root] with its affixes, the ones that could bring it close to [bad].
  List<String> _expand(WordEntry root, String bad) {
    final forms = <(String, bool)>[];
    final flags = root.flags;
    if (!(root.has(_rules.needAffix) || root.has(_rules.onlyInCompound))) {
      forms.add((root.word, false));
    }
    bool barred(Affix affix) =>
        affix.continues(_rules.needAffix) ||
        affix.continues(_rules.circumfix) ||
        affix.continues(_rules.onlyInCompound);

    for (final flag in flags.flags) {
      for (final suffix in _affixes.withFlag(flag)) {
        if (suffix.isPrefix || forms.length >= _maxWords) continue;
        final append = suffix.append;
        if (append.isNotEmpty &&
            !(bad.length > append.length && bad.endsWith(append))) {
          continue;
        }
        if (barred(suffix)) continue;
        final form = suffix.addTo(root.word, fullStrip: _rules.fullStrip);
        if (form != null && form.isNotEmpty) {
          forms.add((form, suffix.crossProduct));
        }
      }
    }
    final suffixed = forms.length;
    for (var j = 1; j < suffixed; j++) {
      if (!forms[j].$2) continue;
      for (final flag in flags.flags) {
        for (final prefix in _affixes.withFlag(flag)) {
          if (!prefix.isPrefix ||
              !prefix.crossProduct ||
              forms.length >= _maxWords) {
            continue;
          }
          final append = prefix.append;
          if (append.isNotEmpty &&
              !(bad.length > append.length && bad.startsWith(append))) {
            continue;
          }
          final form = prefix.addTo(forms[j].$1, fullStrip: _rules.fullStrip);
          if (form != null && form.isNotEmpty) {
            forms.add((form, prefix.crossProduct));
          }
        }
      }
    }
    for (final flag in flags.flags) {
      for (final prefix in _affixes.withFlag(flag)) {
        if (!prefix.isPrefix || forms.length >= _maxWords) continue;
        final append = prefix.append;
        if (append.isNotEmpty &&
            !(bad.length > append.length && bad.startsWith(append))) {
          continue;
        }
        if (barred(prefix)) continue;
        final form = prefix.addTo(root.word, fullStrip: _rules.fullStrip);
        if (form != null && form.isNotEmpty) {
          forms.add((form, prefix.crossProduct));
        }
      }
    }
    return <String>[for (final (form, _) in forms) form];
  }

  static void _sortByScore(List<String?> words, List<int> scores) {
    for (var m = 1; m < words.length; m++) {
      var j = m;
      while (j > 0 && scores[j - 1] < scores[j]) {
        final score = scores[j - 1];
        scores[j - 1] = scores[j];
        scores[j] = score;
        final word = words[j - 1];
        words[j - 1] = words[j];
        words[j] = word;
        j--;
      }
    }
  }

  /// How many of the pieces of [a], one to [n] long, [b] has.
  static int _ngram(int n, String a, String b, int options) {
    final l1 = a.length;
    final l2 = b.length;
    if (l2 == 0) return 0;
    var score = 0;
    for (var j = 1; j <= n; j++) {
      var found = 0;
      for (var i = 0; i <= l1 - j; i++) {
        if (b.contains(a.substring(i, i + j))) {
          found++;
        } else if (options & _weighted != 0) {
          found--;
          if (i == 0 || i == l1 - j) found--;
        }
      }
      score += found;
      if (found < 2 && options & _weighted == 0) break;
    }
    var penalty = 0;
    if (options & _longerWorse != 0) penalty = (l2 - l1) - 2;
    if (options & _anyMismatch != 0) penalty = (l2 - l1).abs() - 2;
    return score - math.max(penalty, 0);
  }

  /// How long a start [a] and [b] share, [b]'s first letter compared in
  /// lower case too.
  static int _leftCommon(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final first = b.codeUnitAt(0);
    final other = a.codeUnitAt(0);
    if (other != first && other != Casing.lowerUnit(first)) return 0;
    var i = 1;
    while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  /// How many positions [a] and [b] have the same letter at, and whether
  /// they differ by two letters swapped.
  static (int, bool) _commonPositions(String a, String b) {
    if (a.isEmpty || b.isEmpty) return (0, false);
    final lowered = Casing.initialSmall(b);
    var same = 0;
    final differences = <int>[];
    for (var i = 0; i < a.length && i < lowered.length; i++) {
      if (a.codeUnitAt(i) == lowered.codeUnitAt(i)) {
        same++;
      } else {
        differences.add(i);
      }
    }
    final swapped =
        differences.length == 2 &&
        a.length == lowered.length &&
        a.codeUnitAt(differences[0]) == lowered.codeUnitAt(differences[1]) &&
        a.codeUnitAt(differences[1]) == lowered.codeUnitAt(differences[0]);
    return (same, swapped);
  }

  static int _longestCommonSubsequence(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var previous = List<int>.filled(b.length + 1, 0);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        current[j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? previous[j - 1] + 1
            : math.max(previous[j], current[j - 1]);
      }
      final kept = previous;
      previous = current;
      current = kept;
    }
    return previous[b.length];
  }
}
