/// What the benchmarks measure with: the frames drawn and the processor
/// time spent between two moments, how long the window took to show what
/// was asked of it, and the computer it was all measured on.
library;

import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show FlutterVersion;
import 'package:flutter/widgets.dart';

Future<void> wait(Duration duration) => Future<void>.delayed(duration);

/// Microseconds, on the clock frame timings are stamped by.
int now() => Timeline.now;

/// Where the widget [T] is on screen.
Rect rectOf<T extends Widget>() {
  final box = find<T>().renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The widget [T], as the window shows it.
Element find<T extends Widget>() => maybeFind<T>()!;

/// The widget [T], as the window shows it, or null while it shows none.
Element? maybeFind<T extends Widget>() {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget is T) {
      found = element;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// How a handful of times lie: the middle one, those nine in ten and
/// ninety-nine in a hundred stay under, and the worst.
class Spread {
  Spread._(this.count, this.mean, this.p50, this.p90, this.p99, this.worst);

  /// The spread of [times], or null of none.
  static Spread? of(Iterable<double> times) {
    final sorted = times.toList()..sort();
    if (sorted.isEmpty) return null;
    double at(double share) =>
        sorted[math.min(sorted.length - 1, (share * sorted.length).floor())];
    return Spread._(
      sorted.length,
      sorted.reduce((a, b) => a + b) / sorted.length,
      at(0.5),
      at(0.9),
      at(0.99),
      sorted.last,
    );
  }

  final int count;
  final double mean;
  final double p50;
  final double p90;
  final double p99;
  final double worst;

  Map<String, Object?> toJson() => <String, Object?>{
    'count': count,
    'mean': _rounded(mean),
    'p50': _rounded(p50),
    'p90': _rounded(p90),
    'p99': _rounded(p99),
    'worst': _rounded(worst),
  };

  /// The middle, the nine in ten, the ninety-nine in a hundred and the
  /// worst, as a row of a table has them.
  String get row => '${_cell(p50)} ${_cell(p90)} ${_cell(p99)} ${_cell(worst)}';

  static String _cell(double ms) =>
      ms.toStringAsFixed(ms >= 100 ? 0 : 1).padLeft(6);
}

/// [value] to a thousandth, which is all a measure here is good for.
double _rounded(double value) => (value * 1000).roundToDouble() / 1000;

/// The frames the window draws, as they are drawn: which was drawn last,
/// and when what is waited for first showed.
abstract final class Frames {
  /// The timings of the frames drawn, handed over a little after each.
  static final List<FrameTiming> timings = <FrameTiming>[];

  /// A moment in the frame drawn last, on the clock of [now]: once the
  /// window has built, laid out and painted it, and handed it over to be
  /// drawn. It tells the frame from every other — its timing, once handed
  /// over, is the last whose building began before that moment. And the
  /// same of the first frame drawn.
  static int at = 0;
  static int first = 0;

  static final List<_Awaited> _awaited = <_Awaited>[];
  static bool _started = false;

  /// Begins watching the frames; once is enough.
  static void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance
      ..addTimingsCallback(timings.addAll)
      ..addPersistentFrameCallback(_drawn);
  }

  /// Called as each frame is built, after the window has built, laid out
  /// and painted it.
  static void _drawn(Duration _) {
    final frame = at = now();
    if (first == 0) first = frame;
    if (_awaited.isEmpty) return;
    _check(frame, walks: false);
    // What has to look through the window does so once the frame is done,
    // so its looking is in no frame's time. The window changes only in
    // frames, so what it finds then is what this frame showed.
    if (_awaited.any((awaited) => awaited.walks)) {
      Timer.run(() => _check(frame, walks: true));
    }
  }

  static void _check(int frame, {required bool walks}) {
    for (final awaited in List<_Awaited>.of(_awaited)) {
      if (awaited.walks != walks || awaited.done.isCompleted) continue;
      if (awaited.test()) {
        _awaited.remove(awaited);
        awaited.done.complete(frame);
      }
    }
  }

  /// The first frame, from now, that shows [test] holding — as the moment
  /// that tells it, see [at] — or null if none does [within] that long.
  ///
  /// [test] is asked as each frame is built, so it must cost next to
  /// nothing: reading a provider, say. One that looks through the window's
  /// widgets says so with [walks], and is asked after the frame instead.
  static Future<int?> shows(
    bool Function() test, {
    bool walks = false,
    Duration within = const Duration(seconds: 20),
  }) {
    final awaited = _Awaited(test, walks: walks);
    _awaited.add(awaited);
    return awaited.done.future.timeout(
      within,
      onTimeout: () {
        _awaited.remove(awaited);
        return null;
      },
    );
  }

  /// The next frame drawn, or null if none is [within] that long: nothing
  /// changed that the window shows.
  static Future<int?> next({
    Duration within = const Duration(milliseconds: 600),
  }) => shows(() => true, within: within);

  /// Waits until no frame has been drawn, and none is asked for, for
  /// [quiet] — what was opened has been drawn whole, its printouts among
  /// it — and gives the last frame drawn; or null if the window is still
  /// drawing after [within].
  static Future<int?> settled({
    Duration quiet = const Duration(milliseconds: 400),
    Duration within = const Duration(seconds: 20),
  }) async {
    final give = now() + within.inMicroseconds;
    // When the window was last busy: a frame asked for, or drawn.
    var busy = now();
    while (now() < give) {
      await wait(const Duration(milliseconds: 10));
      if (SchedulerBinding.instance.hasScheduledFrame) busy = now();
      if (!drawsUnasked && at > busy) busy = at;
      if (now() - busy >= quiet.inMicroseconds) return at;
    }
    return null;
  }

  /// Whether the window draws frames nobody asked for, one after another,
  /// as a test's window does: then only the asking tells whether it has
  /// settled.
  static bool drawsUnasked = false;

  /// Waits for the timings of the last frames, which are handed over once
  /// a frame is drawn a while after them.
  static Future<void> handedOver() async {
    await wait(const Duration(milliseconds: 1100));
    SchedulerBinding.instance.scheduleForcedFrame();
    await wait(const Duration(milliseconds: 300));
  }

  /// The timing, among [timings] in the order they were handed over, of
  /// the frame that [frame] tells: the last whose building began before
  /// that moment — if it has been handed over, and is not the timing of a
  /// frame long before, the frame itself never timed.
  static FrameTiming? timingOf(int frame, List<FrameTiming> timings) {
    int began(int index) =>
        timings[index].timestampInMicroseconds(FramePhase.buildStart);
    var low = 0;
    var high = timings.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (began(middle) <= frame) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low == 0) return null;
    final timing = timings[low - 1];
    final built = timing.timestampInMicroseconds(FramePhase.buildFinish);
    return frame - built > _apart ? null : timing;
  }

  /// How long after a frame is handed over to be drawn the moment that
  /// tells it may lie, at most: what the window does at the end of a
  /// frame takes less.
  static const int _apart = 250000;
}

class _Awaited {
  _Awaited(this.test, {required this.walks});

  final bool Function() test;
  final bool walks;
  final Completer<int?> done = Completer<int?>();
}

/// One thing measured: the frames drawn, the processor time spent and,
/// on battery, the power the computer drew between its [begin] and [end]
/// — and how long each thing done in it took to show.
class Run {
  /// Begins measuring [name]. With [stalls], the longest the window's own
  /// thread was kept from anything else is measured too, by a timer that
  /// wakes it every other millisecond — so not where idleness is measured.
  Run.begin(this.name, {bool stalls = false})
    : _start = now(),
      _cpuBefore = threadTimes(),
      _drawnBefore = Battery.readings.length {
    if (stalls) {
      _stall = 0;
      _stallSince = now();
      _stallWatch = Timer.periodic(_stallTick, (_) => _tick());
    }
  }

  /// A run that lasted from [start] to [end], on the clock of [now], with
  /// no processor time known: for what was not measured as it happened.
  Run.between(this.name, int start, int end)
    : _start = start,
      _cpuBefore = const <String, int>{},
      _drawnBefore = Battery.readings.length {
    _end = end;
    _cpuAfter = const <String, int>{};
    _drawn = const <double>[];
  }

  final String name;
  final int _start;
  final Map<String, int> _cpuBefore;
  final int _drawnBefore;
  late final int _end;
  late final Map<String, int> _cpuAfter;
  late final List<double> _drawn;

  static const Duration _stallTick = Duration(milliseconds: 2);
  Timer? _stallWatch;
  int _stallSince = 0;
  int? _stall;

  /// How long things took, in milliseconds, by what they are: one time for
  /// what was done once, many for what was done again and again.
  final Map<String, List<double>> times = <String, List<double>>{};

  /// What was counted: the elements picked, the lists read again.
  final Map<String, num> counts = <String, num>{};

  /// What could not be measured, and why.
  final List<String> notes = <String>[];

  /// What is timed until a frame is on the screen: its name, when it
  /// began, and the frame that shows it.
  final List<(String, int, int)> _untilShown = <(String, int, int)>[];

  /// The frames whose own building and drawing are told apart: the first
  /// after each key, say.
  final List<(String, int)> _told = <(String, int)>[];

  /// When the run began, on the clock of [now].
  int get start => _start;

  void _tick() {
    final at = now();
    final stalled = at - _stallSince - _stallTick.inMicroseconds;
    if (stalled > (_stall ?? 0)) _stall = stalled;
    _stallSince = at;
  }

  /// Notes that [what] took [milliseconds].
  void took(String what, double milliseconds) =>
      (times[what] ??= <double>[]).add(milliseconds);

  /// Notes that [what], begun at [since], was on the screen with [frame] —
  /// once that frame's timing is known. A null [frame], which never came,
  /// is noted as nothing.
  void shown(String what, int since, int? frame) {
    if (frame != null) _untilShown.add((what, since, frame));
  }

  /// Notes how long [frame] itself took to build and to draw, as [what].
  void told(String what, int? frame) {
    if (frame != null) _told.add((what, frame));
  }

  void end() {
    _stallWatch?.cancel();
    if (_stallWatch != null) _tick();
    _end = now();
    _cpuAfter = threadTimes();
    _drawn = Battery.readings.sublist(_drawnBefore);
  }

  double get _seconds => (_end - _start) / 1e6;

  List<FrameTiming> _framesOf(List<FrameTiming> timings) => <FrameTiming>[
    for (final timing in timings)
      if (timing.timestampInMicroseconds(FramePhase.vsyncStart) >= _start &&
          timing.timestampInMicroseconds(FramePhase.vsyncStart) < _end)
        timing,
  ];

  static double _ms(Duration duration) => duration.inMicroseconds / 1000;

  static int _over(List<FrameTiming> frames, int microseconds) => frames
      .where((frame) => frame.totalSpan.inMicroseconds > microseconds)
      .length;

  /// A sixtieth of a second, and two: a frame longer than the first is a
  /// frame dropped at 60 Hz, one longer than the second is two.
  static const int _oneFrame = 16667;
  static const int _twoFrames = 33333;

  /// Processor time spent in the run by each kind of thread, in clock
  /// ticks of 10 ms, without the compositor's — which is given apart.
  (Map<String, int>, int) get _spent {
    final spent = <String, int>{
      for (final entry in _cpuAfter.entries)
        entry.key: entry.value - (_cpuBefore[entry.key] ?? 0),
    }..removeWhere((_, ticks) => ticks <= 0);
    final compositor = spent.remove('compositor') ?? 0;
    return (spent, compositor);
  }

  /// Everything the run measured, to be kept and set beside another run's:
  /// times in milliseconds, processor time in milliseconds a second.
  Map<String, Object?> toJson(List<FrameTiming> timings) {
    final frames = _framesOf(timings);
    final all = <String, List<double>>{
      for (final entry in times.entries)
        entry.key: List<double>.of(entry.value),
    };
    for (final (what, since, frame) in _untilShown) {
      // Drawn by the time its timing says; of a frame with no timing — the
      // first, on some systems — built by then, at least.
      final timing = Frames.timingOf(frame, timings);
      final drawn =
          timing?.timestampInMicroseconds(FramePhase.rasterFinish) ?? frame;
      (all[what] ??= <double>[]).add((drawn - since) / 1000);
    }
    for (final (what, frame) in _told) {
      final timing = Frames.timingOf(frame, timings);
      if (timing == null) continue;
      (all['$what, build'] ??= <double>[]).add(_ms(timing.buildDuration));
      (all['$what, raster'] ??= <double>[]).add(_ms(timing.rasterDuration));
    }
    final (spent, compositor) = _spent;
    final seconds = _seconds;
    double aSecond(int ticks) =>
        seconds <= 0 ? 0 : _rounded(ticks * 10 / seconds);
    final total = spent.values.fold(0, (sum, ticks) => sum + ticks);
    final stall = _stall;
    return <String, Object?>{
      'name': name,
      'seconds': _rounded(seconds),
      'frames': frames.length,
      'build': Spread.of(frames.map((frame) => _ms(frame.buildDuration)))
          ?.toJson(),
      'raster': Spread.of(frames.map((frame) => _ms(frame.rasterDuration)))
          ?.toJson(),
      'total': Spread.of(frames.map((frame) => _ms(frame.totalSpan)))?.toJson(),
      'over16': _over(frames, _oneFrame),
      'over33': _over(frames, _twoFrames),
      if (_cpuAfter.isNotEmpty)
        'cpu': <String, Object?>{
          'all': aSecond(total),
          'ui': aSecond(_threadOf(spent, _uiThreads)),
          'raster': aSecond(_threadOf(spent, _rasterThreads)),
          'compositor': aSecond(compositor),
          'threads': <String, Object?>{
            for (final entry in spent.entries) entry.key: aSecond(entry.value),
          },
        },
      if (stall != null) 'stall': _rounded(stall / 1000),
      if (_drawn.isNotEmpty)
        'watts': _rounded(_drawn.reduce((a, b) => a + b) / _drawn.length),
      'times': <String, Object?>{
        for (final entry in all.entries)
          entry.key: Spread.of(entry.value)!.toJson(),
      },
      if (counts.isNotEmpty) 'counts': counts,
      if (notes.isNotEmpty) 'notes': notes,
    };
  }

  /// The names the window's own thread goes by — which builds the frames,
  /// and is the process's first where the engine has no thread apart for
  /// it — and the thread's that draws them.
  static const List<String> _uiThreads = <String>['.ui', 'aantekening'];
  static const List<String> _rasterThreads = <String>['.raster', '.rast'];

  /// The ticks [spent] by the thread whose name holds the first of [names]
  /// that any does.
  static int _threadOf(Map<String, int> spent, List<String> names) {
    for (final name in names) {
      final ticks = spent.entries
          .where((entry) => entry.key.contains(name))
          .fold(0, (sum, entry) => sum + entry.value);
      if (ticks > 0) return ticks;
    }
    return 0;
  }

  /// Writes the run out in full: its frames, its processor time and its
  /// power, a line each.
  void report(StringBuffer out, List<FrameTiming> timings) {
    final frames = _framesOf(timings);
    final seconds = _seconds;
    out
      ..writeln()
      ..writeln(
        '$name: ${frames.length} frames in ${seconds.toStringAsFixed(1)} s',
      );
    if (frames.isNotEmpty) {
      String line(String what, Duration Function(FrameTiming) of) {
        final spread = Spread.of(frames.map((frame) => _ms(of(frame))))!;
        return '  $what ms: mean ${spread.mean.toStringAsFixed(2)}  '
            'p50 ${spread.p50.toStringAsFixed(2)}  '
            'p90 ${spread.p90.toStringAsFixed(2)}  '
            'p99 ${spread.p99.toStringAsFixed(2)}  '
            'max ${spread.worst.toStringAsFixed(2)}';
      }

      out
        ..writeln(line('build ', (frame) => frame.buildDuration))
        ..writeln(line('raster', (frame) => frame.rasterDuration))
        ..writeln(line('total ', (frame) => frame.totalSpan))
        ..writeln('  frames over 16.7 ms: ${_over(frames, _oneFrame)}');
    }
    final (spent, compositor) = _spent;
    final total = spent.values.fold(0, (sum, ticks) => sum + ticks);
    final perSecond = total * 10 / seconds;
    final threads =
        (spent.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map(
              (entry) => '${entry.key} ${(entry.value * 10 / seconds).round()}',
            )
            .join(', ');
    out
      ..writeln('  processor: ${perSecond.round()} ms a second ($threads)')
      ..writeln(
        '  compositor: ${(compositor * 10 / seconds).round()} ms a second',
      );
    if (_drawn.isNotEmpty) {
      final watts = _drawn.reduce((a, b) => a + b) / _drawn.length;
      out.writeln(
        '  power: ${watts.toStringAsFixed(2)} W, all of the computer',
      );
    }
  }
}

/// The names of the desktops' compositors.
const Set<String> _compositors = <String>{
  'kwin_wayland',
  'gnome-shell',
  'sway',
  'Hyprland',
  'weston',
};

/// Processor time each kind of thread of this process has spent, in
/// clock ticks of 10 ms, by thread name, and the compositor's. Nothing,
/// where the system does not tell.
Map<String, int> threadTimes() {
  final times = <String, int>{};
  final tasks = Directory('/proc/self/task');
  if (!tasks.existsSync()) return times;
  for (final task in tasks.listSync()) {
    try {
      final stat = File('${task.path}/stat').readAsStringSync();
      final open = stat.indexOf('(');
      final close = stat.lastIndexOf(')');
      final name = stat
          .substring(open + 1, close)
          .replaceAll(RegExp('[0-9]+'), '#');
      final fields = stat.substring(close + 2).split(' ');
      final ticks = int.parse(fields[11]) + int.parse(fields[12]);
      times[name] = (times[name] ?? 0) + ticks;
    } on FileSystemException {
      // A thread that ended meanwhile.
    }
  }
  // And the desktop's compositor, which puts each frame on the screen.
  for (final process in Directory('/proc').listSync()) {
    final pid = process.path.split('/').last;
    if (int.tryParse(pid) == null) continue;
    try {
      final stat = File('${process.path}/stat').readAsStringSync();
      final open = stat.indexOf('(');
      final close = stat.lastIndexOf(')');
      final name = stat.substring(open + 1, close);
      if (!_compositors.contains(name)) continue;
      final fields = stat.substring(close + 2).split(' ');
      times['compositor'] =
          (times['compositor'] ?? 0) +
          int.parse(fields[11]) +
          int.parse(fields[12]);
    } on FileSystemException {
      // A process that ended meanwhile.
    }
  }
  return times;
}

/// The power the computer draws from its battery, read every half second
/// while it runs on it: the screen and all else with the app, so only a
/// long measure, set beside the same measure of other code, says much.
abstract final class Battery {
  /// Watts, a reading each half second.
  static final List<double> readings = <double>[];

  static void start() {
    final batteries = Directory('/sys/class/power_supply').existsSync()
        ? Directory('/sys/class/power_supply')
              .listSync()
              .where((entry) => entry.path.split('/').last.startsWith('BAT'))
              .toList()
        : const <FileSystemEntity>[];
    if (batteries.isEmpty) return;
    final battery = batteries.first.path;
    Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        final status = File('$battery/status').readAsStringSync().trim();
        if (status != 'Discharging') return;
        final microwatts = int.parse(
          File('$battery/power_now').readAsStringSync().trim(),
        );
        readings.add(microwatts / 1e6);
      } on Exception {
        // A battery that says nothing of its power.
      }
    });
  }
}

/// How the computer is powered, which decides how fast it runs: whether it
/// is plugged in, the power profile chosen, and what the processor is told
/// to save. Each is null where the computer does not say.
Map<String, Object?> powerState() {
  String? read(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync().trim() : null;
    } on FileSystemException {
      return null;
    }
  }

  String? profile;
  try {
    final asked = Process.runSync('powerprofilesctl', const <String>['get']);
    final said = '${asked.stdout}'.trim();
    if (asked.exitCode == 0 && said.isNotEmpty) profile = said;
  } on ProcessException {
    // No power profiles on this computer.
  }
  bool? plugged;
  try {
    final supplies = Directory('/sys/class/power_supply');
    if (supplies.existsSync()) {
      for (final supply in supplies.listSync()) {
        if (!supply.path.split('/').last.startsWith('A')) continue;
        final online = read('${supply.path}/online');
        if (online != null) plugged = (plugged ?? false) || online == '1';
      }
    }
  } on FileSystemException {
    // A computer that does not say what powers it.
  }
  const cpu = '/sys/devices/system/cpu/cpu0/cpufreq';
  return <String, Object?>{
    'profile': profile,
    'pluggedIn': plugged,
    'governor': read('$cpu/scaling_governor'),
    'energyPreference': read('$cpu/energy_performance_preference'),
  };
}

/// What about [power] makes a measure slower and less even than the
/// computer can be, in a line — or null if nothing does.
String? powerWarning(Map<String, Object?> power) {
  final against = <String>[
    if (power['pluggedIn'] == false) 'on battery',
    if (power['profile'] case final String profile
        when profile != 'performance')
      'in the $profile power profile, not performance',
  ];
  return against.isEmpty
      ? null
      : 'The computer is ${against.join(' and ')}: it runs slower and less '
            'evenly than it can, so the times are longer and vary more.';
}

/// What the code measured was built from and with: the commit — and
/// whether anything was changed since — and Flutter's and Dart's versions.
Map<String, Object?> buildOf() {
  String? git(List<String> arguments) {
    try {
      final asked = Process.runSync('git', arguments);
      return asked.exitCode == 0 ? '${asked.stdout}'.trim() : null;
    } on ProcessException {
      return null;
    }
  }

  final changed = git(const <String>['status', '--porcelain']);
  return <String, Object?>{
    'commit':
        Platform.environment['AANTEKENING_BENCH_COMMIT'] ??
        git(const <String>['rev-parse', 'HEAD']),
    'changedSince': changed?.isNotEmpty,
    'flutter': FlutterVersion.version,
    'flutterRevision': FlutterVersion.frameworkRevision,
    'engineRevision': FlutterVersion.engineRevision,
    'dart': Platform.version.split(' ').first,
    'system': Platform.operatingSystemVersion,
    'processors': Platform.numberOfProcessors,
  };
}
