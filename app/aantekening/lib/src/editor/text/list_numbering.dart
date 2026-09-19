/// The numbers of numbered lists.
library;

import 'package:aantekening_core/aantekening_core.dart';

abstract final class ListNumbering {
  /// The number of each block of [blocks] in its numbered list, counting
  /// afresh for each list and each level of nesting; 0 for a block in none.
  static List<int> ordinals(List<TextBlock> blocks) {
    final ordinals = List<int>.filled(blocks.length, 0);
    final counters = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final level = block.indent;
      if (block.kind == TextBlockKind.numbered && !block.isEmbed) {
        while (counters.length <= level) {
          counters.add(0);
        }
        counters.length = level + 1;
        counters[level]++;
        ordinals[i] = counters[level];
      } else if (counters.length > level) {
        counters.length = level;
      }
    }
    return ordinals;
  }

  /// How number [n] is written at nesting [level]: 1, 2, 3 at the top; a, b,
  /// c beneath; i, ii, iii beneath that; then round again.
  static String label(int n, int level) => switch (level % 3) {
    1 => _letters(n),
    2 => _roman(n),
    _ => '$n',
  };

  static String _letters(int n) {
    var value = n;
    final letters = <String>[];
    while (value > 0) {
      value--;
      letters.insert(0, String.fromCharCode(0x61 + value % 26));
      value ~/= 26;
    }
    return letters.join();
  }

  static String _roman(int n) {
    const numerals = <(int, String)>[
      (1000, 'm'),
      (900, 'cm'),
      (500, 'd'),
      (400, 'cd'),
      (100, 'c'),
      (90, 'xc'),
      (50, 'l'),
      (40, 'xl'),
      (10, 'x'),
      (9, 'ix'),
      (5, 'v'),
      (4, 'iv'),
      (1, 'i'),
    ];
    var value = n;
    final out = StringBuffer();
    for (final (amount, symbol) in numerals) {
      while (value >= amount) {
        out.write(symbol);
        value -= amount;
      }
    }
    return out.toString();
  }
}
