// Checks words against a Hunspell dictionary: one word per line on standard
// input, 1 or 0 for each on standard output; with -s, the suggestions,
// separated by tabs.
//
//   dart run tool/check_words.dart dictionary.aff dictionary.dic [-s] < words
import 'dart:convert';
import 'dart:io';

import 'package:aantekening_spell/aantekening_spell.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('usage: check_words.dart affix-file word-list [-s]');
    exit(2);
  }
  final dictionary = HunspellDictionary.fromBytes(
    File(arguments[0]).readAsBytesSync(),
    File(arguments[1]).readAsBytesSync(),
  );
  final suggest = arguments.length > 2 && arguments[2] == '-s';
  final out = StringBuffer();
  final input = await stdin.transform(utf8.decoder).join();
  for (final word in const LineSplitter().convert(input)) {
    out.writeln(
      suggest
          ? dictionary.suggest(word).join('\t')
          : (dictionary.check(word) ? '1' : '0'),
    );
  }
  stdout.write(out);
}
