/// Measures what a person feels using the app on notes of a real size —
/// thousands of pages, a few of them heavy — from the moment it is
/// started: how long it takes to open, to show a page, to answer the pen,
/// a key, a search; the frames it draws meanwhile, how long each took to
/// build and to draw and how many were late; and the processor time spent.
///
/// Built and run in profile mode, on the desktop it is to measure:
///
/// ```sh
/// cd app/aantekening
/// flutter build linux --profile -t benchmark/app_benchmark.dart
/// build/linux/x64/profile/bundle/aantekening
/// ```
///
/// The notes are made up, in a temporary folder that goes afterwards: a
/// notes folder and its index on disk, as a person's are, so what the
/// database and the folder cost is in the measures. Nothing is read from or
/// written to the person's own notes, settings or keychain. The app is
/// then started on them again and again, as a person starts it — first to
/// time its starting, then once to do everything else in: opening heavy
/// pages, writing with the pen, typing, selecting, searching, going about
/// the notebooks and changing them. Each is done through the window as it
/// is, by the events a pen, a mouse and a keyboard send; see `input.dart`.
/// What cannot be done so is left out, and named at the end, rather than
/// done some other way.
///
/// Its windows open one after another on the desktop, and each must keep
/// the keyboard for as long as it is open — a window without it takes no
/// keys, here as anywhere — so the computer is left alone meanwhile: what
/// is typed goes to the app, and is measured with the rest. Plugged in,
/// and in the performance power profile, the times are shortest and most
/// even; it warns where the computer is neither.
///
/// It ends with a table, and keeps every number — with the commit, the
/// versions of Flutter and Dart, the size of the notes and how the computer
/// was powered — in a file, named at the end, or by
/// `AANTEKENING_BENCH_JSON`: `benchmark/compare.dart` sets two such files
/// side by side.
///
/// `AANTEKENING_BENCH_SIZE=large` makes the notes of ten thousand pages and
/// their heavy pages heavier, and measures longer; `AANTEKENING_BENCH_PAGES`,
/// `_SECTIONS`, `_NOTEBOOKS`, `_STROKES`, `_PARAGRAPHS`, `_BOXES`,
/// `_PICTURES` and `_PRINTOUT` each set one size by itself, and
/// `AANTEKENING_BENCH_STARTS`, `_PEN` and `_IDLE` how often the app is
/// started, how many strokes the pen writes and how many seconds nothing
/// is done. `AANTEKENING_BENCH_ONLY=pen` measures only what its name
/// holds: `start`, `open`, `idle`, `pen`, `select`, `typing`, `search`,
/// `goto`, `picker` or `library`.
///
/// `AANTEKENING_BENCH_DRIVE=1 flutter test test/benchmark_drive_test.dart`
/// goes through the same measures without a window on the desktop, on
/// small notes, timing nothing: to see that each is still driven as it is
/// meant to be, after the app has changed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:aantekening/src/app.dart';
import 'package:aantekening/src/editor/trackpad.dart';
import 'package:aantekening/src/error_log.dart';
import 'package:aantekening/src/files/notes_keeper.dart';
import 'package:aantekening/src/input_trace.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_measures.dart';
import 'input.dart';
import 'made_up_notes.dart';
import 'measuring.dart';
import 'profile.dart';

/// What the benchmark tells the windows it starts, through their
/// environment: where to leave what they measured — which also says a
/// process is a window, not the one that starts them — the folder of the
/// notes, what to do, the name of the start measured, and when the process
/// was started.
const String _partKey = 'AANTEKENING_BENCH_PART';
const String _folderKey = 'AANTEKENING_BENCH_FOLDER';
const String _taskKey = 'AANTEKENING_BENCH_TASK';
const String _nameKey = 'AANTEKENING_BENCH_NAME';
const String _startedKey = 'AANTEKENING_BENCH_STARTED';

Future<void> main() async {
  final part = Platform.environment[_partKey];
  if (part == null) {
    await _conduct();
  } else {
    await _window(part);
  }
}

/// A number set in the environment as `AANTEKENING_BENCH_[name]`, or
/// [otherwise].
int _set(String name, int otherwise) {
  final set = int.tryParse(
    Platform.environment['AANTEKENING_BENCH_$name'] ?? '',
  );
  return set == null || set < 1 ? otherwise : set;
}

bool get _large => Platform.environment['AANTEKENING_BENCH_SIZE'] == 'large';

// ------------------------------------------------------------- conducting

/// Makes up the notes, starts the app on them — a window at a time — for
/// each thing measured, and gathers what the windows measured into one
/// profile. It opens no window itself.
Future<void> _conduct() async {
  final only = Platform.environment['AANTEKENING_BENCH_ONLY'] ?? '';
  final size = NotesSize.from(Platform.environment);
  final power = powerState();
  stdout.writeln('App benchmark');
  if (powerWarning(power) case final warning?) stdout.writeln('! $warning');
  final folder = Directory.systemTemp.createTempSync('aantekening_bench_');
  try {
    stdout.writeln('Making up notes of ${size.pages} pages…');
    final watch = Stopwatch()..start();
    final made = await _makeNotes(folder, size);
    stdout.writeln(
      'Made, and written to their folder, in '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s.',
    );

    final measures = <Object?>[];
    final unmeasured = <String>[];
    Object? window;
    Object? errors;

    void gather(Map<String, Object?>? part, String what) {
      if (part == null) {
        unmeasured.add('$what: the window did not finish');
        return;
      }
      measures.addAll(part['measures']! as List<Object?>);
      unmeasured.addAll((part['unmeasured']! as List<Object?>).cast<String>());
      window ??= part['window'];
      errors ??= part['errors'];
    }

    // Started as a person starts it: on the page left open the last time.
    for (final (name, pageId) in <(String, String)>[
      ('start: on an ordinary page', made.ordinary),
      ('start: on a page of handwriting', made.ink),
    ]) {
      if (!name.contains(only)) continue;
      for (var start = 0; start < _set('STARTS', _large ? 5 : 3); start++) {
        stdout.writeln('Starting the app: ${name.substring(7)}…');
        gather(
          await _start(
            folder,
            made,
            pageId,
            task: 'start',
            name: name,
            within: const Duration(minutes: 3),
          ),
          name,
        );
      }
    }
    // And once more, for everything done in it.
    if (!only.startsWith('start')) {
      stdout.writeln('Starting the app, to measure in…');
      gather(
        await _start(
          folder,
          made,
          made.ordinary,
          task: 'measures',
          name: 'start',
          within: Duration(minutes: _large ? 60 : 30),
        ),
        'everything but the start',
      );
    }

    final profile = <String, Object?>{
      'benchmark': 'app',
      'format': 1,
      'when': DateTime.now().toIso8601String(),
      'build': buildOf(),
      'power': power,
      'window': window,
      'notes': made.holds,
      'measures': measures,
      'unmeasured': unmeasured,
      'errors': ?errors,
    };
    final kept =
        Platform.environment['AANTEKENING_BENCH_JSON'] ??
        '${Directory.systemTemp.path}/aantekening-profile-'
            '${DateTime.now().millisecondsSinceEpoch}.json';
    writeProfile(kept, profile);
    stdout
      ..writeln()
      ..write(headOf(profile));
    if (powerWarning(power) case final warning?) stdout.writeln('! $warning');
    stdout
      ..writeln()
      ..write(tableOf(profile));
    if (errors case final String noted) {
      stdout
        ..writeln()
        ..writeln('The app noted errors while it was measured:')
        ..writeln(noted);
    }
    stdout
      ..writeln()
      ..writeln('Every number is kept in $kept');
    await stdout.flush();
  } finally {
    folder.deleteSync(recursive: true);
  }
  exit(0);
}

/// Makes up the notes in [folder] — their folder, and its index beside it
/// — writes them all to the folder, and closes them, as the app leaves
/// them when it is closed.
Future<MadeUpNotes> _makeNotes(Directory folder, NotesSize size) async {
  final store = await AantekeningStore.open(
    notesFolder: '${folder.path}/notes',
    indexFolder: '${folder.path}/index',
    automatic: false,
  );
  final MadeUpNotes made;
  try {
    made = await makeUpNotes(
      store,
      Directory('${folder.path}/made')..createSync(),
      size,
    );
    await store.mirror!.flush();
  } finally {
    await store.close();
  }
  return made;
}

/// Starts the app in a window of its own, on the notes in [folder], as it
/// was left with the page [pageId] open, to do [task]; and gives what it
/// measured — all of it, or what it had by the time it was closed for not
/// finishing [within] that long — or null if it left nothing.
Future<Map<String, Object?>?> _start(
  Directory folder,
  MadeUpNotes made,
  String pageId, {
  required String task,
  required String name,
  required Duration within,
}) async {
  leaveOpen(folder.path, made, pageId);
  File('${folder.path}/made.json').writeAsStringSync(jsonEncode(made.toJson()));
  final part = File('${folder.path}/part.json');
  if (part.existsSync()) part.deleteSync();
  final process = await Process.start(
    Platform.resolvedExecutable,
    const <String>[],
    environment: <String, String>{
      _partKey: part.path,
      _folderKey: folder.path,
      _taskKey: task,
      _nameKey: name,
      _startedKey: '${DateTime.now().microsecondsSinceEpoch}',
    },
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode.timeout(
    within,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  if (!part.existsSync()) return null;
  final Map<String, Object?> measured;
  try {
    measured = jsonDecode(part.readAsStringSync()) as Map<String, Object?>;
  } on FormatException {
    // Closed while it was writing.
    return null;
  }
  // Closed before it was done, it has left what it had measured by then.
  if (code != 0) {
    (measured['unmeasured']! as List<Object?>).add(
      '${task == 'start' ? name : 'the rest'}: the window stopped before '
      'it was done',
    );
  }
  return measured;
}

// ------------------------------------------------------------- the window

/// Opens the app's window on the notes made up, as its own `main` does but
/// for where it keeps things; times its starting; does what it was
/// started for; and leaves what it measured in [part].
Future<void> _window(String part) async {
  final environment = Platform.environment;
  // When the process was started, on the clock the frames are timed by.
  final atMain = now();
  final started = int.tryParse(environment[_startedKey] ?? '');
  final began = started == null
      ? atMain
      : atMain - (DateTime.now().microsecondsSinceEpoch - started);
  final folder = environment[_folderKey]!;
  final made = MadeUpNotes.fromJson(
    jsonDecode(File('$folder/made.json').readAsStringSync())
        as Map<String, Object?>,
  );
  final preferences = jsonDecode(
    File('$folder/support/preferences.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final opens =
      ((preferences['tabs']! as List<Object?>).first!
              as Map<String, Object?>)['page']!
          as String;

  BenchBinding.start();
  ErrorLog.install();
  ErrorLog.keepIn('$folder/support');
  installInputTrace();
  listenToTouchpadFingers();
  registerFontLicence();
  Frames.start();
  Battery.start();

  final reloads = Reloads();
  final container = measuredContainer(folder, reloads);
  final start = Run.begin(environment[_nameKey] ?? 'start');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AantekeningApp(),
    ),
  );

  // Started: the page it was left on read, laid out and drawn.
  final shown = await Frames.shows(
    () {
      final canvas = maybeFind<InfiniteCanvas>();
      return canvas != null &&
          (canvas.widget as InfiniteCanvas).controller.document.id == opens;
    },
    walks: true,
    within: const Duration(seconds: 90),
  );
  final settled = await Frames.settled(within: const Duration(seconds: 30));
  start
    ..took('process start to the app’s own code', (atMain - began) / 1000)
    ..shown(
      'process start to first frame',
      began,
      Frames.first == 0 ? null : Frames.first,
    )
    ..shown('process start to the page shown', began, shown)
    ..shown('process start to settled', began, settled)
    ..end();

  var runs = <Run>[];
  var unmeasured = <String>[];

  /// Leaves what has been measured so far in [part].
  void leave() {
    final view = PlatformDispatcher.instance.views.first;
    final errors = ErrorLog.file;
    writeProfile(part, <String, Object?>{
      'measures': <Object?>[for (final run in runs) run.toJson(Frames.timings)],
      'unmeasured': unmeasured,
      'window': <String, Object?>{
        'width': (view.physicalSize.width / view.devicePixelRatio).round(),
        'height': (view.physicalSize.height / view.devicePixelRatio).round(),
        'pixelRatio': view.devicePixelRatio,
      },
      if (errors != null && errors.existsSync())
        'errors': _startOf(errors.readAsStringSync()),
    });
  }

  if (shown == null) {
    unmeasured.add('${start.name}: the page the app was left on never showed');
  } else if (environment[_taskKey] == 'start') {
    runs.add(start);
  } else {
    final measures = Measures(
      container: container,
      notes: made,
      reloads: reloads,
      only: environment['AANTEKENING_BENCH_ONLY'] ?? '',
      penStrokes: _set('PEN', _large ? 480 : 120),
      idle: Duration(seconds: _set('IDLE', _large ? 12 : 6)),
      // Kept after each scenario, in case a later one never ends and the
      // window is closed for it.
      afterEach: leave,
    );
    // The same lists, filled as each scenario is measured.
    runs = measures.runs;
    unmeasured = measures.unmeasured;
    await measures.all();
  }

  await Frames.handedOver();
  leave();

  // Closed as the app closes: what is open saved, and the notes closed,
  // so the next window finds them as a person's are found.
  try {
    await container.read(openSavesProvider).saveAll();
    await (await container.read(storeProvider.future)).close();
  } on Object {
    // Left as a crash leaves them, which the next start mends.
  }
  exit(0);
}

/// The first of [noted], if it is long.
String _startOf(String noted) => noted.length <= 4000
    ? noted
    : '${noted.substring(0, 4000)}\n… and '
          '${noted.length - 4000} characters more';
