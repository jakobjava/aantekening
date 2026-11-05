// Everything that must hold before a change lands, in one command, on every
// platform the app is built on:
//
//   dart tool/check.dart            format, analysis, every package's tests
//   dart tool/check.dart --deep     and the fuzzers and the simulation of two
//                                   computers sharing a folder, run long
//   dart tool/check.dart --coverage and how much of each package the tests
//                                   reach
//   dart tool/check.dart store app  only the packages named
//
// It stops at nothing: every step runs, and what failed is listed at the end,
// so one run says everything that is wrong.

import 'dart:io';

/// Each package, where it is, and whether its tests need Flutter.
const List<(String, String, bool)> _packages = <(String, String, bool)>[
  ('core', 'packages/aantekening_core', false),
  ('store', 'packages/aantekening_store', false),
  ('interchange', 'packages/aantekening_interchange', false),
  ('ai', 'packages/aantekening_ai', false),
  ('spell', 'packages/aantekening_spell', false),
  ('math', 'packages/aantekening_math', true),
  ('canvas', 'packages/aantekening_canvas', true),
  ('app', 'app/aantekening', true),
];

/// How long a file of code may grow before the check names it: a file past
/// this most likely holds more than one thing, and is better split by what
/// each part does (see docs/adr/0034-large-states-in-parts.md).
const int _longFile = 1000;

/// Files long on purpose, not named: Hunspell's checker and suggester,
/// ported as they are written, so they can be held to Hunspell's own.
const Set<String> _longOnPurpose = <String>{
  'packages/aantekening_spell/lib/src/checker.dart',
  'packages/aantekening_spell/lib/src/suggester.dart',
};

/// The tests that try many ways things can go, and how many each tries in
/// a deep run.
const Map<String, String> _deep = <String, String>{
  'AANTEKENING_FUZZ': '20000',
  'AANTEKENING_SEEDS': '1000',
};

Future<void> main(List<String> arguments) async {
  final deep = arguments.contains('--deep');
  final coverage = arguments.contains('--coverage');
  final named = arguments.where((argument) => !argument.startsWith('--'));
  final unknown = named.where(
    (name) => !_packages.any((package) => package.$1 == name),
  );
  if (unknown.isNotEmpty) {
    stderr.writeln(
      'No package ${unknown.join(', ')}; the packages are '
      '${_packages.map((package) => package.$1).join(', ')}.',
    );
    exit(64);
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final failed = <String>[];
  final watch = Stopwatch()..start();

  Future<void> step(
    String name,
    String executable,
    List<String> arguments, {
    String? inside,
    Map<String, String>? environment,
  }) async {
    stdout.writeln('\n── $name');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: inside == null ? root : '$root/$inside',
      environment: environment,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await process.exitCode != 0) failed.add(name);
  }

  if (named.isEmpty) {
    await step('format', 'dart', <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'app',
      'packages',
      'tool',
    ]);
    await step('analysis', 'dart', <String>[
      'analyze',
      '--fatal-infos',
      '--fatal-warnings',
    ]);
    _nameLongFiles(root);
  }

  final reached = <String, (int, int)>{};
  for (final (name, path, flutter) in _packages) {
    if (named.isNotEmpty && !named.contains(name)) continue;
    await step(
      'tests: $name',
      flutter ? 'flutter' : 'dart',
      <String>[
        'test',
        if (coverage && flutter) '--coverage',
        if (coverage && !flutter) ...<String>[
          '--coverage=coverage',
          '--chain-stack-traces',
        ],
      ],
      inside: path,
      environment: deep ? _deep : null,
    );
    if (coverage) {
      final lines = await _coverageOf('$root/$path', flutter: flutter);
      if (lines != null) reached[name] = lines;
    }
  }

  if (reached.isNotEmpty) {
    stdout.writeln('\n── coverage: lines of each package the tests reach');
    for (final MapEntry(key: name, value: (hit, total)) in reached.entries) {
      final share = total == 0 ? 100.0 : 100 * hit / total;
      stdout.writeln(
        '  ${name.padRight(12)} ${share.toStringAsFixed(1).padLeft(5)}%'
        '   $hit of $total',
      );
    }
  }

  final took = (watch.elapsed.inSeconds / 60).toStringAsFixed(1);
  if (failed.isEmpty) {
    stdout.writeln('\nAll checks passed, in $took minutes.');
  } else {
    stderr.writeln('\nFailed, in $took minutes: ${failed.join(', ')}.');
    exit(1);
  }
}

/// How many of the lines of the package at [path] its tests reached, and
/// of how many: read from Flutter's lcov file, or made one from the Dart
/// test runner's raw coverage first.
Future<(int, int)?> _coverageOf(String path, {required bool flutter}) async {
  final lcov = File('$path/coverage/lcov.info');
  if (!flutter) {
    final made = await Process.run(
      'dart',
      <String>[
        'run',
        'coverage:format_coverage',
        '--lcov',
        '--in=coverage',
        '--out=coverage/lcov.info',
        '--report-on=lib',
        '--check-ignore',
      ],
      workingDirectory: path,
      runInShell: Platform.isWindows,
    );
    if (made.exitCode != 0) {
      stderr.writeln(
        'No coverage of $path: coverage:format_coverage failed.\n'
        '${made.stdout}${made.stderr}',
      );
      return null;
    }
  }
  if (!lcov.existsSync()) {
    stderr.writeln('No coverage of $path: the tests left no ${lcov.path}.');
    return null;
  }
  var hit = 0;
  var total = 0;
  var inLib = false;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final file = line.substring(3).replaceAll(r'\', '/');
      inLib = file.contains('/lib/') || file.startsWith('lib/');
    } else if (inLib && line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    } else if (inLib && line.startsWith('LF:')) {
      total += int.parse(line.substring(3));
    }
  }
  return (hit, total);
}

/// Names the files of code under [root] longer than [_longFile] lines, to be
/// split by what each part does as they are worked on. It fails nothing:
/// length alone is no fault, only a sign of one.
void _nameLongFiles(String root) {
  final long = <(String, int)>[];
  for (final (_, path, _) in _packages) {
    final lib = Directory('$root/$path/lib');
    if (!lib.existsSync()) continue;
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final relative = file.path
          .substring(root.length + 1)
          .replaceAll(r'\', '/');
      if (_longOnPurpose.contains(relative)) continue;
      final lines = file.readAsLinesSync().length;
      if (lines > _longFile) long.add((relative, lines));
    }
  }
  if (long.isEmpty) return;
  long.sort((a, b) => b.$2.compareTo(a.$2));
  stdout
    ..writeln(
      '\n── long files: past $_longFile lines, to split by what each '
      'part does',
    )
    ..writeln(
      <String>[
        for (final (path, lines) in long) '  ${'$lines'.padLeft(5)}  $path',
      ].join('\n'),
    );
}
