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

/// An affix file: the rules a Hunspell dictionary's words are built by.
library;

import 'condition.dart';
import 'flags.dart';

/// A prefix or suffix: what is taken off a dictionary word and what is put
/// on in its place, for words carrying [flag].
final class Affix {
  Affix({
    required this.isPrefix,
    required this.flag,
    required this.crossProduct,
    required this.strip,
    required this.append,
    required this.continuation,
    required this.condition,
  });

  final bool isPrefix;
  final int flag;

  /// Whether this affix may combine with one of the other kind.
  final bool crossProduct;

  /// Taken off the dictionary word.
  final String strip;

  /// Put on in its place.
  final String append;

  /// Flags the affixed word carries on: further affixes it takes, and flags
  /// such as whether it may stand in a compound.
  final FlagSet continuation;

  final AffixCondition condition;

  bool continues(int flag) => continuation.contains(flag);

  /// [word] with this affix, or null if it does not apply to it.
  String? addTo(String word, {required bool fullStrip}) {
    final length = word.length;
    final fits = length > strip.length || (length == 0 && fullStrip);
    if (!fits || length < condition.length) return null;
    if (isPrefix) {
      if (!condition.matchesStart(word) || !word.startsWith(strip)) {
        return null;
      }
      return append + word.substring(strip.length);
    }
    if (!condition.matchesEnd(word) || !word.endsWith(strip)) return null;
    return word.substring(0, length - strip.length) + append;
  }
}

/// A REP line: a common misspelling, [pattern], and what it should be. The
/// replacement may depend on where the pattern is: in the middle, at the
/// start, at the end, or the whole word.
final class Replacement {
  Replacement(this.pattern);

  final String pattern;

  /// Replacements for the pattern in the middle, at the start, at the end,
  /// and as the whole word.
  final List<String> outputs = <String>['', '', '', ''];

  /// The replacement for the pattern found at [at] in a word [length] long,
  /// or '' for none.
  String outputAt(int at, int length) {
    var type = at == 0 ? 1 : 0;
    if (at + pattern.length == length) type += 2;
    while (type != 0 && outputs[type].isEmpty) {
      type = (type == 2 && at != 0) ? 0 : type - 1;
    }
    return outputs[type];
  }
}

/// ICONV or OCONV: characters written differently in the dictionary than in
/// text, such as the typographic apostrophe.
final class ConversionTable {
  ConversionTable(List<Replacement> entries)
    : _entries = List<Replacement>.of(entries)
        ..sort((a, b) => b.pattern.length.compareTo(a.pattern.length));

  final List<Replacement> _entries;

  /// [word] converted, or null if nothing in it changes.
  String? convert(String word) {
    StringBuffer? out;
    var i = 0;
    while (i < word.length) {
      String? replacement;
      var matched = 0;
      for (final entry in _entries) {
        if (!word.startsWith(entry.pattern, i)) continue;
        final output = entry.outputAt(i, word.length);
        if (output.isEmpty) continue;
        replacement = output;
        matched = entry.pattern.length;
        break;
      }
      if (replacement == null) {
        out?.writeCharCode(word.codeUnitAt(i));
        i++;
        continue;
      }
      (out ??= StringBuffer(word.substring(0, i))).write(replacement);
      i += matched;
    }
    return out?.toString();
  }
}

/// A CHECKCOMPOUNDPATTERN line: two words that may not join at [left] and
/// [right], unless [replacement] says how the join is written instead.
final class CompoundPattern {
  CompoundPattern({
    required this.left,
    required this.leftFlag,
    required this.right,
    required this.rightFlag,
    required this.replacement,
  });

  final String left;
  final int leftFlag;
  final String right;
  final int rightFlag;

  /// For a simplified compound: what the join is written as, standing for
  /// [left] followed by [right].
  final String replacement;
}

/// Everything an affix file says.
final class AffixRules {
  FlagMode flagMode = FlagMode.single;
  String? encoding;
  String? language;
  bool complexPrefixes = false;

  final List<Affix> prefixes = <Affix>[];
  final List<Affix> suffixes = <Affix>[];

  /// Flags that some affix continues with, making two suffixes possible.
  final Set<int> continuationClasses = <int>{};

  /// Flag sets numbered by AF lines, from 1.
  final List<FlagSet> flagAliases = <FlagSet>[];

  String tryCharacters = '';
  String keyboard = 'qwertyuiop|asdfghjkl|zxcvbnm';
  String wordCharacters = '';
  String ignoredCharacters = '';

  int forbiddenWord = Flags.forbiddenDefault;
  int needAffix = Flags.none;
  int onlyInCompound = Flags.none;
  int keepCase = Flags.none;
  int forceUppercase = Flags.none;
  int warn = Flags.none;
  int noSuggest = Flags.none;
  int noNgramSuggest = Flags.none;
  int substandard = Flags.none;
  int circumfix = Flags.none;

  int compoundFlag = Flags.none;
  int compoundBegin = Flags.none;
  int compoundMiddle = Flags.none;
  int compoundEnd = Flags.none;
  int compoundRoot = Flags.none;
  int compoundPermit = Flags.none;
  int compoundForbid = Flags.none;
  int compoundMin = 3;
  int compoundWordMax = -1;
  bool compoundMoreSuffixes = false;
  bool checkCompoundDup = false;
  bool checkCompoundRep = false;
  bool checkCompoundTriple = false;
  bool simplifiedTriple = false;
  bool checkCompoundCase = false;
  bool simplifiedCompound = false;
  final List<CompoundPattern> compoundPatterns = <CompoundPattern>[];

  /// COMPOUNDRULE lines, as flags and the quantifiers `*` and `?`.
  final List<List<int>> compoundRules = <List<int>>[];

  bool checkSharps = false;
  bool fullStrip = false;
  bool forbidWarn = false;
  bool noSplitSuggestions = false;
  bool suggestionsWithDots = false;
  bool onlyMaxDiff = false;
  int maxNgramSuggestions = -1;
  int maxCompoundSuggestions = -1;
  int maxDiff = -1;

  final List<Replacement> replacements = <Replacement>[];
  final List<List<String>> related = <List<String>>[];
  List<String> breaks = const <String>['-', '^-', '-\$'];
  ConversionTable? inputConversion;
  ConversionTable? outputConversion;

  /// The quantifier characters of a compound rule, stored as themselves.
  static const int ruleStar = 0x2A;
  static const int ruleQuestion = 0x3F;

  bool get compounds =>
      compoundFlag != Flags.none ||
      compoundBegin != Flags.none ||
      compoundRules.isNotEmpty;

  /// Reads an affix file.
  factory AffixRules.parse(String text) {
    final rules = AffixRules._();
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.first.startsWith('\uFEFF')) {
      lines[0] = lines.first.substring(1);
    }
    // How flags are written, and their aliases, are needed before any rule
    // using them is read, wherever in the file they are.
    for (var i = 0; i < lines.length; i++) {
      final fields = _fields(lines[i]);
      if (fields.isEmpty) continue;
      switch (fields.first) {
        case 'FLAG' when fields.length > 1:
          rules.flagMode = switch (fields[1]) {
            'long' => FlagMode.long,
            'num' => FlagMode.numeric,
            'UTF-8' => FlagMode.unicode,
            _ => FlagMode.single,
          };
        case 'SET' when fields.length > 1:
          rules.encoding = fields[1];
        case 'COMPLEXPREFIXES':
          rules.complexPrefixes = true;
        case 'IGNORE' when fields.length > 1:
          rules.ignoredCharacters = fields[1];
      }
    }
    for (var i = 0; i < lines.length; i++) {
      final fields = _fields(lines[i]);
      if (fields.length > 1 && fields.first == 'AF') {
        final count = int.tryParse(fields[1]) ?? 0;
        for (final entry in _table(lines, i, count, 'AF').$1) {
          rules.flagAliases.add(
            FlagSet.of(
              Flags.decode(entry.length > 1 ? entry[1] : '', rules.flagMode),
            ),
          );
        }
        break;
      }
    }

    var i = 0;
    while (i < lines.length) {
      final fields = _fields(lines[i]);
      final header = i;
      i++;
      if (fields.isEmpty) continue;
      final value = fields.length > 1 ? fields[1] : '';
      int flag() => Flags.decodeOne(value, rules.flagMode);
      int number() => int.tryParse(value) ?? 0;
      // A table's lines follow the line naming it and how many there are.
      List<List<String>> table(String name, [int? count]) {
        final (entries, next) = _table(lines, header, count ?? number(), name);
        i = next;
        return entries;
      }

      switch (fields.first) {
        case 'TRY':
          rules.tryCharacters = value;
        case 'KEY':
          rules.keyboard = value;
        case 'WORDCHARS':
          rules.wordCharacters = value;
        case 'LANG':
          rules.language = value;
        case 'FORBIDDENWORD':
          rules.forbiddenWord = flag();
        case 'NEEDAFFIX' || 'PSEUDOROOT':
          rules.needAffix = flag();
        case 'ONLYINCOMPOUND':
          rules.onlyInCompound = flag();
        case 'KEEPCASE':
          rules.keepCase = flag();
        case 'FORCEUCASE':
          rules.forceUppercase = flag();
        case 'WARN':
          rules.warn = flag();
        case 'FORBIDWARN':
          rules.forbidWarn = true;
        case 'NOSUGGEST':
          rules.noSuggest = flag();
        case 'NONGRAMSUGGEST':
          rules.noNgramSuggest = flag();
        case 'SUBSTANDARD':
          rules.substandard = flag();
        case 'CIRCUMFIX':
          rules.circumfix = flag();
        case 'COMPOUNDFLAG':
          rules.compoundFlag = flag();
        case 'COMPOUNDBEGIN':
          rules.compoundBegin = flag();
        case 'COMPOUNDMIDDLE':
          rules.compoundMiddle = flag();
        case 'COMPOUNDEND':
          rules.compoundEnd = flag();
        case 'COMPOUNDROOT':
          rules.compoundRoot = flag();
        case 'COMPOUNDPERMITFLAG':
          rules.compoundPermit = flag();
        case 'COMPOUNDFORBIDFLAG':
          rules.compoundForbid = flag();
        case 'COMPOUNDMIN':
          rules.compoundMin = number() < 1 ? 1 : number();
        case 'COMPOUNDWORDMAX':
          rules.compoundWordMax = number();
        case 'COMPOUNDMORESUFFIXES':
          rules.compoundMoreSuffixes = true;
        case 'CHECKCOMPOUNDDUP':
          rules.checkCompoundDup = true;
        case 'CHECKCOMPOUNDREP':
          rules.checkCompoundRep = true;
        case 'CHECKCOMPOUNDTRIPLE':
          rules.checkCompoundTriple = true;
        case 'SIMPLIFIEDTRIPLE':
          rules.simplifiedTriple = true;
        case 'CHECKCOMPOUNDCASE':
          rules.checkCompoundCase = true;
        case 'CHECKSHARPS':
          rules.checkSharps = true;
        case 'FULLSTRIP':
          rules.fullStrip = true;
        case 'NOSPLITSUGS':
          rules.noSplitSuggestions = true;
        case 'SUGSWITHDOTS':
          rules.suggestionsWithDots = true;
        case 'ONLYMAXDIFF':
          rules.onlyMaxDiff = true;
        case 'MAXNGRAMSUGS':
          rules.maxNgramSuggestions = number();
        case 'MAXCPDSUGS':
          rules.maxCompoundSuggestions = number();
        case 'MAXDIFF':
          rules.maxDiff = number();
        case 'REP':
          for (final entry in table('REP')) {
            if (entry.length < 3) continue;
            var pattern = entry[1];
            var type = 0;
            if (pattern.startsWith('^')) {
              type = 1;
              pattern = pattern.substring(1);
            }
            pattern = pattern.replaceAll('_', ' ');
            if (pattern.endsWith(r'$')) {
              type += 2;
              pattern = pattern.substring(0, pattern.length - 1);
            }
            if (pattern.isEmpty) continue;
            rules.replacements.add(
              Replacement(pattern)
                ..outputs[type] = entry[2].replaceAll('_', ' '),
            );
          }
        case 'MAP':
          for (final entry in table('MAP')) {
            if (entry.length > 1) rules.related.add(_mapGroup(entry[1]));
          }
        case 'BREAK':
          rules.breaks = <String>[
            for (final entry in table('BREAK'))
              if (entry.length > 1) entry[1],
          ];
        case 'ICONV':
          rules.inputConversion = ConversionTable(_conversions(table('ICONV')));
        case 'OCONV':
          rules.outputConversion = ConversionTable(
            _conversions(table('OCONV')),
          );
        case 'CHECKCOMPOUNDPATTERN':
          for (final entry in table('CHECKCOMPOUNDPATTERN')) {
            if (entry.length < 3) continue;
            final (left, leftFlag) = _patternSide(entry[1], rules.flagMode);
            final (right, rightFlag) = _patternSide(entry[2], rules.flagMode);
            final replacement = entry.length > 3 ? entry[3] : '';
            if (replacement.isNotEmpty) rules.simplifiedCompound = true;
            rules.compoundPatterns.add(
              CompoundPattern(
                left: left,
                leftFlag: leftFlag,
                right: right,
                rightFlag: rightFlag,
                replacement: replacement,
              ),
            );
          }
        case 'COMPOUNDRULE':
          for (final entry in table('COMPOUNDRULE')) {
            if (entry.length > 1) {
              rules.compoundRules.add(_compoundRule(entry[1], rules.flagMode));
            }
          }
        case 'AF':
          table('AF');
        case 'PFX' || 'SFX' when fields.length >= 4:
          final count = int.tryParse(fields[3]) ?? 0;
          rules._readAffixes(fields, table(fields.first, count));
      }
    }
    return rules;
  }

  AffixRules._();

  void _readAffixes(List<String> header, List<List<String>> entries) {
    final isPrefix = header.first == 'PFX';
    final flag = Flags.decodeOne(header[1], flagMode);
    final crossProduct = header[2] == 'Y';
    for (final entry in entries) {
      if (entry.length < 4) continue;
      final strip = entry[2] == '0' ? '' : entry[2];
      var append = entry[3];
      var continuation = FlagSet.empty;
      final slash = append.indexOf('/');
      if (slash >= 0) {
        final flags = append.substring(slash + 1);
        append = append.substring(0, slash);
        continuation = flagSet(flags);
        continuationClasses.addAll(continuation.flags);
      }
      if (append == '0') append = '';
      if (ignoredCharacters.isNotEmpty) append = removeIgnored(append);
      final affix = Affix(
        isPrefix: isPrefix,
        flag: flag,
        crossProduct: crossProduct,
        strip: strip,
        append: append,
        continuation: continuation,
        condition: AffixCondition.parse(entry.length > 4 ? entry[4] : '.'),
      );
      (isPrefix ? prefixes : suffixes).add(affix);
    }
  }

  /// The flags [text] names: written out, or an AF alias's number.
  FlagSet flagSet(String text) {
    if (flagAliases.isNotEmpty) {
      final index = int.tryParse(text);
      if (index != null && index >= 1 && index <= flagAliases.length) {
        return flagAliases[index - 1];
      }
      return FlagSet.empty;
    }
    return FlagSet.of(Flags.decode(text, flagMode));
  }

  /// [text] without the characters IGNORE lists.
  String removeIgnored(String text) {
    if (ignoredCharacters.isEmpty) return text;
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      if (!ignoredCharacters.codeUnits.contains(unit)) {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  static List<String> _fields(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return const <String>[];
    return trimmed.split(RegExp(r'[ \t]+'));
  }

  /// The [count] lines that follow line [header] and begin with [name], and
  /// the index of the line after the last of them.
  static (List<List<String>>, int) _table(
    List<String> lines,
    int header,
    int count,
    String name,
  ) {
    final entries = <List<String>>[];
    var i = header + 1;
    while (i < lines.length && entries.length < count) {
      final fields = _fields(lines[i]);
      if (fields.isNotEmpty) {
        if (fields.first != name) break;
        entries.add(fields);
      }
      i++;
    }
    return (entries, i);
  }

  static List<Replacement> _conversions(List<List<String>> entries) {
    final byPattern = <String, Replacement>{};
    for (final entry in entries) {
      if (entry.length < 3) continue;
      var pattern = entry[1];
      var type = 0;
      if (pattern.startsWith('_')) {
        type = 1;
        pattern = pattern.substring(1);
      }
      if (pattern.endsWith('_')) {
        type += 2;
        pattern = pattern.substring(0, pattern.length - 1);
      }
      pattern = pattern.replaceAll('_', ' ');
      if (pattern.isEmpty) continue;
      (byPattern[pattern] ??= Replacement(pattern)).outputs[type] = entry[2]
          .replaceAll('_', ' ');
    }
    return byPattern.values.toList();
  }

  /// A MAP line's characters and parenthesised strings.
  static List<String> _mapGroup(String text) {
    final group = <String>[];
    var i = 0;
    while (i < text.length) {
      if (text[i] == '(') {
        final close = text.indexOf(')', i);
        if (close > i + 1) {
          group.add(text.substring(i + 1, close));
          i = close + 1;
          continue;
        }
      }
      final unit = text.codeUnitAt(i);
      final width = unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length
          ? 2
          : 1;
      group.add(text.substring(i, i + width));
      i += width;
    }
    return group;
  }

  static (String, int) _patternSide(String text, FlagMode mode) {
    final slash = text.indexOf('/');
    if (slash < 0) return (text, Flags.none);
    return (
      text.substring(0, slash),
      Flags.decodeOne(text.substring(slash + 1), mode),
    );
  }

  /// A compound rule: its flags, with `*` and `?` kept as themselves. With
  /// no brackets the whole rule is read as flags; with brackets, each
  /// bracketed flag, `*` and `?`, and every other character, in turn.
  static List<int> _compoundRule(String text, FlagMode mode) {
    if (!text.contains('(')) return Flags.decode(text, mode);
    final rule = <int>[];
    var i = 0;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x28) {
        final close = text.indexOf(')', i);
        if (close > i) {
          rule.addAll(Flags.decode(text.substring(i + 1, close), mode));
          i = close + 1;
          continue;
        }
      }
      if (unit == ruleStar || unit == ruleQuestion) {
        rule.add(unit);
      } else {
        rule.addAll(Flags.decode(String.fromCharCode(unit), mode));
      }
      i++;
    }
    return rule;
  }
}
