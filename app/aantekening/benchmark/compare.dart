// Sets two runs of the app benchmark side by side, and says what got
// slower and what faster by more than the runs differ by themselves:
//
//   dart benchmark/compare.dart before.json after.json
//   dart benchmark/compare.dart before1.json before2.json -- after1.json after2.json
//   dart benchmark/compare.dart --noise=30 --all before.json after.json
//
// With one run a side, a number is marked once it has changed by more than
// the noise — 20%, or as `--noise` gives it — and by more than anyone would
// feel. With several, it must also have changed by more than the runs of
// either side differ among themselves. `--all` lists every number, marked
// or not. Two runs of the same code, compared, show how much is noise.
//
// It warns where the runs were not made alike: the computer on battery in
// one and plugged in for the other, say.

import 'dart:io';

import 'profile.dart';

void main(List<String> arguments) {
  var noise = 0.2;
  var all = false;
  final before = <String>[];
  final after = <String>[];
  var split = false;
  for (final argument in arguments) {
    if (argument == '--all') {
      all = true;
    } else if (argument.startsWith('--noise=')) {
      final percent = double.tryParse(argument.substring('--noise='.length));
      if (percent == null || percent < 0) _usage('--noise takes a percentage');
      noise = percent / 100;
    } else if (argument == '--') {
      split = true;
    } else if (argument.startsWith('--')) {
      _usage('No option $argument');
    } else {
      (split ? after : before).add(argument);
    }
  }
  // Two files and nothing between them: the first before, the second after.
  if (!split && before.length == 2) after.add(before.removeLast());
  if (before.isEmpty || after.isEmpty) {
    _usage('Two profiles are compared, or several with -- between them');
  }
  try {
    stdout.write(
      comparisonOf(
        before.map(readProfile).toList(),
        after.map(readProfile).toList(),
        noise: noise,
        all: all,
      ),
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(65);
  } on FileSystemException catch (error) {
    stderr.writeln('${error.path}: ${error.message}');
    exit(66);
  }
}

Never _usage(String problem) {
  stderr
    ..writeln(problem)
    ..writeln(
      'Usage: dart benchmark/compare.dart [--noise=20] [--all] '
      'before.json [more.json --] after.json [more.json]',
    );
  exit(64);
}
