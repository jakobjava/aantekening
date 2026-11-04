import 'package:aantekening_spell/src/affix_index.dart';
import 'package:aantekening_spell/src/affix_rules.dart';
import 'package:aantekening_spell/src/checker.dart';
import 'package:aantekening_spell/src/word_table.dart';
import 'package:test/test.dart';

void main() {
  test('a check that runs out of time says so, and the next does not', () {
    final rules = AffixRules.parse('SET UTF-8\n');
    final words = WordTable(rules)..read('1\ncat\n');
    final checker = Checker(rules, words, AffixIndex(rules));

    expect(
      checker.timed(() => checker.spell('cat'), limit: Duration.zero),
      isFalse,
      reason: 'no time at all to look',
    );
    expect(checker.timedOut, isTrue);

    expect(checker.spell('cat'), isTrue);
    expect(checker.timedOut, isFalse);
    expect(checker.spell('dog'), isFalse);
    expect(checker.timedOut, isFalse, reason: 'wrong, and sure of it');
  });
}
