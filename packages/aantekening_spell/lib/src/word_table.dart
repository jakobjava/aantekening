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

/// The words of a Hunspell dictionary.
library;

import 'affix_rules.dart';
import 'casing.dart';
import 'flags.dart';

/// A dictionary word and the flags it carries. One word may have several
/// entries, homonyms with different flags.
final class WordEntry {
  WordEntry(this.word, this.flags, {required this.initialCapital});

  final String word;
  FlagSet flags;

  /// Whether the word is written with a capital first letter alone.
  final bool initialCapital;

  bool has(int flag) => flags.contains(flag);
}

/// The words of a dictionary, each with its homonyms in the order they were
/// listed.
final class WordTable {
  WordTable(this._rules);

  final AffixRules _rules;
  final Map<String, List<WordEntry>> _words = <String, List<WordEntry>>{};

  /// The entries for [word], or null if it is not in the dictionary.
  List<WordEntry>? lookup(String word) => _words[word];

  /// Every entry, homonyms included.
  Iterable<WordEntry> get entries => _words.values.expand((list) => list);

  int get length => _words.length;

  /// Reads a .dic file's lines into the table.
  void read(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    // The first line only estimates how many words follow.
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final (word, flags) = _split(line);
      if (word.isEmpty) continue;
      add(word, flags);
    }
  }

  /// Adds [word] with [flags], and, for a word in mixed case or in capitals
  /// with affixes, the capitalised form the word takes when a whole text is
  /// written in capitals.
  void add(String word, FlagSet flags) {
    final cleaned = _rules.removeIgnored(word);
    final capType = Casing.of(cleaned);
    _addEntry(
      cleaned,
      flags,
      hidden: false,
      initialCapital: capType == CapType.initial,
    );
    final hides =
        capType == CapType.mixed ||
        capType == CapType.mixedInitial ||
        (capType == CapType.all && !flags.isEmpty);
    if (hides && !flags.contains(_rules.forbiddenWord)) {
      _addEntry(
        Casing.capitalised(cleaned),
        flags.withFlag(Flags.onlyUpcase),
        hidden: true,
        initialCapital: true,
      );
    }
  }

  void _addEntry(
    String word,
    FlagSet flags, {
    required bool hidden,
    required bool initialCapital,
  }) {
    final existing = _words[word];
    if (existing == null) {
      _words[word] = <WordEntry>[
        WordEntry(word, flags, initialCapital: initialCapital),
      ];
      return;
    }
    // A hidden capitalised form never displaces a word, and a word takes the
    // place of a hidden form made for another.
    if (hidden) return;
    final last = existing.last;
    if (last.has(Flags.onlyUpcase)) {
      last.flags = flags;
      return;
    }
    if (last.flags.isEmpty && flags.isEmpty) return;
    existing.add(WordEntry(word, flags, initialCapital: initialCapital));
  }

  /// Marks [word] as forbidden, as removing it from a dictionary does.
  void forbid(String word) {
    final entries = _words[word];
    if (entries == null) {
      add(word, FlagSet.of(<int>[_rules.forbiddenWord]));
      return;
    }
    for (final entry in entries) {
      entry.flags = entry.flags.withFlag(_rules.forbiddenWord);
    }
  }

  /// A line's word and flags, without the morphological fields that may
  /// follow: `word/flags po:noun`.
  (String, FlagSet) _split(String line) {
    var end = line.length;
    var colon = line.indexOf(':');
    while (colon >= 0) {
      if (colon > 3 && _isBlank(line.codeUnitAt(colon - 3))) {
        var at = colon - 3;
        while (at > 0 && _isBlank(line.codeUnitAt(at - 1))) {
          at--;
        }
        if (at > 0) end = at;
        break;
      }
      colon = line.indexOf(':', colon + 1);
    }
    final tab = line.indexOf('\t');
    if (tab >= 0 && tab < end) end = tab;
    var entry = line.substring(0, end).trimRight();

    // A slash starts the flags, unless it is escaped or the line's first
    // character.
    var slash = entry.indexOf('/');
    while (slash >= 0) {
      if (slash == 0) {
        slash = entry.indexOf('/', 1);
        continue;
      }
      if (entry.codeUnitAt(slash - 1) != 0x5C) break;
      entry = entry.substring(0, slash - 1) + entry.substring(slash);
      slash = entry.indexOf('/', slash);
    }
    if (slash < 0 || slash == entry.length) return (entry, FlagSet.empty);
    return (
      entry.substring(0, slash),
      _rules.flagSet(entry.substring(slash + 1)),
    );
  }

  static bool _isBlank(int unit) => unit == 0x20 || unit == 0x09;
}
