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
    if (made.exitCode != 0) return null;
  }
  if (!lcov.existsSync()) return null;
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
