/// A profile: everything one run of the app benchmark measured, as it is
/// kept in a file — written out as a table, and set beside another to say
/// what got slower and what faster.
///
/// Nothing here needs the app, or Flutter: a profile is read and compared
/// from the command line.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Reads the profile kept in [path].
Map<String, Object?> readProfile(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?> || decoded['measures'] is! List) {
    throw FormatException('$path is not a profile of the app benchmark');
  }
  return decoded;
}

/// Keeps [profile] in [path], laid out to be read and to be compared line
/// by line.
void writeProfile(String path, Map<String, Object?> profile) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(profile)}\n',
    );
}

/// The measures of [profile], in the order they were made.
List<Map<String, Object?>> measuresOf(Map<String, Object?> profile) =>
    <Map<String, Object?>>[
      for (final measure in profile['measures']! as List<Object?>)
        if (measure is Map<String, Object?>) measure,
    ];

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

double? _number(Object? value) => value is num ? value.toDouble() : null;

// ------------------------------------------------------------ the table

/// What [profile] was measured on and of, in a few lines: the code, the
/// notes, the window and how the computer was powered — with a warning
/// where that makes the times longer than they need be.
String headOf(Map<String, Object?> profile) {
  final build = _map(profile['build']);
  final notes = _map(profile['notes']);
  final window = _map(profile['window']);
  final power = _map(profile['power']);
  final commit = build['commit'];
  final out = StringBuffer()
    ..writeln(
      'App benchmark — '
      '${commit is String && commit.length > 10 ? commit.substring(0, 10) : commit ?? 'commit unknown'}'
      '${build['changedSince'] == true ? ', with changes since' : ''}, '
      'Flutter ${build['flutter'] ?? '?'}, Dart ${build['dart'] ?? '?'}',
    )
    ..writeln(
      'Notes: ${notes['notebooks']} notebooks, ${notes['sections']} '
      'sections, ${notes['pages']} pages, '
      '${notes['pagesInFullestSection']} of them in one section; heavy '
      'pages of ${notes['strokes']} strokes over a printout of '
      '${notes['printout']} pages, of ${notes['paragraphs']} paragraphs in '
      'one box, and of ${notes['boxes']} boxes with formulas and '
      '${notes['pictures']} pictures',
    );
  if (window.isNotEmpty) {
    out.writeln(
      'Window: ${window['width']}×${window['height']}, '
      '${window['pixelRatio']}× pixels',
    );
  }
  out.writeln('Power: ${powerLine(power)}');
  return out.toString();
}

/// How the computer was powered, in a few words.
String powerLine(Map<String, Object?> power) => <String>[
  switch (power['pluggedIn']) {
    true => 'plugged in',
    false => 'on battery',
    _ => 'plugged in or not, unknown',
  },
  'profile ${power['profile'] ?? 'unknown'}',
  'governor ${power['governor'] ?? 'unknown'}',
  'energy preference ${power['energyPreference'] ?? 'unknown'}',
].join(', ');

/// The measures of [profile] as a table: a row each, with the frames it
/// drew, how long they took to build and to draw — the middle one, nine in
/// ten, ninety-nine in a hundred and the worst — how many were late, and
/// the processor time of the thread that builds and the thread that draws;
/// and beneath each, how long what was done in it took to show.
String tableOf(Map<String, Object?> profile) {
  const name = 50;
  // Four cells of six, a space between them: a spread.
  const parts = <String>['p50', 'p90', 'p99', 'worst'];
  final spreadHead = parts.map((part) => part.padLeft(6)).join(' ');
  final out = StringBuffer()
    ..writeln(
      '${''.padRight(name + 14)}'
      '  ${'frames built in, ms'.padRight(spreadHead.length)}'
      '  ${'frames drawn in, ms'.padRight(spreadHead.length)}'
      '  frames over  '
      '  thread, ms/s  '
      '   busy',
    )
    ..writeln(
      '${'measure'.padRight(name)}'
      ' ${'s'.padLeft(6)}'
      ' ${'frames'.padLeft(6)}'
      '  $spreadHead'
      '  $spreadHead'
      '  ${'16.7 ms'.padLeft(7)}'
      ' ${'33.3'.padLeft(5)}'
      '  ${'ui'.padLeft(7)}'
      ' ${'raster'.padLeft(7)}'
      ' ${'ms'.padLeft(7)}',
    );
  String spread(Object? of) {
    final spread = _map(of);
    if (spread.isEmpty) return ''.padRight(spreadHead.length);
    return <String>[for (final part in parts) _cell(_number(spread[part]), 6)]
        .join(' ');
  }

  for (final measure in measuresOf(profile)) {
    final cpu = _map(measure['cpu']);
    out.writeln(
      '${'${measure['name']}'.padRight(name)}'
      ' ${_cell(_number(measure['seconds']), 6)}'
      ' ${'${measure['frames'] ?? ''}'.padLeft(6)}'
      '  ${spread(measure['build'])}'
      '  ${spread(measure['raster'])}'
      '  ${'${measure['over16'] ?? ''}'.padLeft(7)}'
      ' ${'${measure['over33'] ?? ''}'.padLeft(5)}'
      '  ${_cell(_number(cpu['ui']), 7, places: 0)}'
      ' ${_cell(_number(cpu['raster']), 7, places: 0)}'
      ' ${_cell(_number(measure['stall']), 7)}',
    );
    for (final entry in _map(measure['times']).entries) {
      final spread = _map(entry.value);
      final count = spread['count'];
      out.writeln(
        count == 1
            ? '    ${entry.key.padRight(name)} '
                  '${_cell(_number(spread['p50']), 8)} ms'
            : '    ${entry.key.padRight(name)} '
                  'p50 ${_cell(_number(spread['p50']), 6)}  '
                  'p90 ${_cell(_number(spread['p90']), 6)}  '
                  'p99 ${_cell(_number(spread['p99']), 6)}  '
                  'worst ${_cell(_number(spread['worst']), 6)} ms'
                  '  ($count times)',
      );
    }
    for (final entry in _map(measure['counts']).entries) {
      out.writeln('    ${entry.key.padRight(name)} ${entry.value}');
    }
    final notes = measure['notes'];
    if (notes is List) {
      for (final note in notes) {
        out.writeln('    ! $note');
      }
    }
  }
  final unmeasured = profile['unmeasured'];
  if (unmeasured is List && unmeasured.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Not measured:');
    for (final what in unmeasured) {
      out.writeln('  ! $what');
    }
  }
  return out.toString();
}

/// [value] in a cell [width] wide, to [places] after the point — fewer for
/// a large one; empty for none.
String _cell(double? value, int width, {int places = 1}) => value == null
    ? ''.padLeft(width)
    : value.toStringAsFixed(value.abs() >= 100 ? 0 : places).padLeft(width);

// ------------------------------------------------------- the comparison

/// What is compared of a measure, by name: each a number where smaller is
/// better. Times are in milliseconds, processor time in milliseconds a
/// second, and late frames are counted.
Map<String, double> comparedOf(Map<String, Object?> measure) {
  final compared = <String, double>{};
  void add(String name, Object? value) {
    final number = _number(value);
    if (number != null) compared[name] = number;
  }

  for (final phase in const <String>['build', 'raster']) {
    final spread = _map(measure[phase]);
    for (final part in const <String>['p50', 'p90', 'p99', 'worst']) {
      add('frame $phase $part', spread[part]);
    }
  }
  add('frames over 16.7 ms', measure['over16']);
  add('frames over 33.3 ms', measure['over33']);
  final cpu = _map(measure['cpu']);
  add('ui thread ms/s', cpu['ui']);
  add('raster thread ms/s', cpu['raster']);
  add('thread busy at most', measure['stall']);
  for (final entry in _map(measure['times']).entries) {
    final spread = _map(entry.value);
    if (spread['count'] == 1) {
      add(entry.key, spread['p50']);
    } else {
      for (final part in const <String>['p50', 'p90', 'worst']) {
        add('${entry.key} $part', spread[part]);
      }
    }
  }
  return compared;
}

/// The least a number must change by to be worth a mark, by what it
/// counts: two frames, twenty milliseconds a second of processor time, a
/// millisecond of anything else — less than that nobody feels, however
/// many percent it is.
double _least(String compared) => compared.startsWith('frames over')
    ? 2
    : compared.endsWith('ms/s')
    ? 20
    : 1;

/// One number of one measure, before and after.
class Change {
  Change(this.measure, this.compared, this.before, this.after);

  final String measure;
  final String compared;

  /// What each run measured, on either side.
  final List<double> before;
  final List<double> after;

  static double _mean(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  double get was => _mean(before);
  double get now => _mean(after);

  /// How much it changed, as a share of what it was; a number that was
  /// nothing and is something has changed without measure.
  double get share =>
      was == 0 ? (now == 0 ? 0 : double.infinity) : (now - was) / was;

  /// Whether it changed by more than [noise], a share, and by more than
  /// anyone would feel — and, where a side was run more than once, by more
  /// than its runs differ among themselves: every run after is on the same
  /// side of every run before.
  bool isBeyond(double noise) {
    if ((now - was).abs() < _least(compared) || share.abs() <= noise) {
      return false;
    }
    if (before.length == 1 && after.length == 1) return true;
    return now > was
        ? after.reduce(math.min) > before.reduce(math.max)
        : after.reduce(math.max) < before.reduce(math.min);
  }
}

/// Every number the profiles [before] and [after] both hold, measure by
/// measure, in the order of the first of [after].
List<Change> changesBetween(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after,
) {
  Map<String, Map<String, List<double>>> gathered(
    List<Map<String, Object?>> profiles,
  ) {
    final all = <String, Map<String, List<double>>>{};
    for (final profile in profiles) {
      for (final measure in measuresOf(profile)) {
        final of = all['${measure['name']}'] ??= <String, List<double>>{};
        for (final entry in comparedOf(measure).entries) {
          (of[entry.key] ??= <double>[]).add(entry.value);
        }
      }
    }
    return all;
  }

  final was = gathered(before);
  final now = gathered(after);
  return <Change>[
    for (final measure in now.entries)
      for (final compared in measure.value.entries)
        if (was[measure.key]?[compared.key] case final earlier?)
          Change(measure.key, compared.key, earlier, compared.value),
  ];
}

/// What makes [before] and [after] unlike enough that their difference
/// may not be the code's: the computer powered otherwise, other notes, a
/// window of another size, another Flutter.
List<String> unlikeBetween(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after,
) {
  final all = <Map<String, Object?>>[...before, ...after];
  Set<String> said(String Function(Map<String, Object?> profile) of) =>
      all.map(of).toSet();
  final warnings = <String>[];
  final powers = said((profile) => powerLine(_map(profile['power'])));
  if (powers.length > 1) {
    warnings.add(
      'The computer was not powered alike: ${powers.join('; ')}. On '
      'battery, or out of the performance profile, everything is slower '
      'and less even — what differs below may be that, not the code.',
    );
  }
  for (final (what, key) in const <(String, String)>[
    ('notes', 'notes'),
    ('window', 'window'),
  ]) {
    if (said((profile) => jsonEncode(profile[key])).length > 1) {
      warnings.add('The $what were not the same in every run.');
    }
  }
  final flutters = said((profile) => '${_map(profile['build'])['flutter']}');
  if (flutters.length > 1) {
    warnings.add('Flutter was not the same: ${flutters.join(', ')}.');
  }
  return warnings;
}

/// The comparison of [before] with [after], written out: each number that
/// got slower or faster by more than [noise], a share — or with [all],
/// every number — and what was measured on one side only.
String comparisonOf(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after, {
  double noise = 0.2,
  bool all = false,
}) {
  final out = StringBuffer();
  for (final warning in unlikeBetween(before, after)) {
    out.writeln('! $warning');
  }
  String commitOf(Map<String, Object?> profile) {
    final commit = _map(profile['build'])['commit'];
    return commit is String && commit.length > 10
        ? commit.substring(0, 10)
        : '${commit ?? 'unknown'}';
  }

  out
    ..writeln(
      'Before: ${before.map(commitOf).toSet().join(', ')} '
      '(${before.length} ${before.length == 1 ? 'run' : 'runs'})   '
      'After: ${after.map(commitOf).toSet().join(', ')} '
      '(${after.length} ${after.length == 1 ? 'run' : 'runs'})',
    )
    ..writeln(
      'Marked: what changed by more than ${(noise * 100).round()}% — and, '
      'where a side was run more than once, by more than its runs differ.',
    )
    ..writeln();
  final changes = changesBetween(before, after);
  var slower = 0;
  var faster = 0;
  String? measure;
  for (final change in changes) {
    final beyond = change.isBeyond(noise);
    if (beyond) change.now > change.was ? slower++ : faster++;
    if (!beyond && !all) continue;
    if (change.measure != measure) {
      measure = change.measure;
      out.writeln(measure);
    }
    final share = change.share;
    out.writeln(
      '  ${beyond ? (change.now > change.was ? 'SLOWER' : 'faster') : '      '}'
      '  ${change.compared.padRight(40)}'
      ' ${_cell(change.was, 9)} → ${_cell(change.now, 9)}'
      '  ${share.isFinite ? '${share >= 0 ? '+' : ''}${(share * 100).round()}%' : 'new'}',
    );
  }
  out
    ..writeln()
    ..writeln(
      '$slower slower, $faster faster, '
      '${changes.length - slower - faster} within the noise, of '
      '${changes.length} numbers compared.',
    );
  Set<String> named(List<Map<String, Object?>> profiles) => <String>{
    for (final profile in profiles)
      for (final measure in measuresOf(profile)) '${measure['name']}',
  };
  final gone = named(before).difference(named(after));
  final come = named(after).difference(named(before));
  if (gone.isNotEmpty) out.writeln('Only before: ${gone.join('; ')}');
  if (come.isNotEmpty) out.writeln('Only after: ${come.join('; ')}');
  return out.toString();
}
