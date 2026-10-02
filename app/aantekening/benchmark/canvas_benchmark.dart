/// Measures how smoothly, and at what cost, a heavy page scrolls and zooms:
/// the time each frame takes to build and to draw, and the processor time
/// spent, thread by thread, while a wheel, a touchpad and a pinch move it —
/// and while nothing does.
///
/// Built and run in profile mode, on the desktop it is to measure:
///
/// ```sh
/// cd app/aantekening
/// flutter build linux --profile -t benchmark/canvas_benchmark.dart
/// build/linux/x64/profile/bundle/aantekening
/// ```
///
/// The page is made up — printouts with handwriting over them, and some
/// text — unless `AANTEKENING_BENCH_NOTES` names a OneNote package
/// (`.onepkg`), whose heaviest page is used instead, or the page whose title
/// holds `AANTEKENING_BENCH_PAGE`. Nothing is read from or written to the
/// notes, the settings or the keychain: the page is kept in memory, its
/// files in a temporary folder. With `AANTEKENING_BENCH_LAYOUT=pages` the
/// page is shown as pages, cut into sheets.
library;

import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:aantekening/src/ai/ai_state.dart';
import 'package:aantekening/src/app.dart';
import 'package:aantekening/src/editor/trackpad.dart';
import 'package:aantekening/src/files/notes_location.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/sidebar_state.dart';
import 'package:aantekening/src/spelling/dictionaries.dart';
import 'package:aantekening/src/spelling/spelling.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  AantekeningBinding.ensureInitialized();
  final folder = Directory.systemTemp.createTempSync('aantekening_bench_');
  final store = AantekeningStore.inMemory(
    assetDirectory: Directory('${folder.path}/assets')..createSync(),
  );
  final notes = Platform.environment['AANTEKENING_BENCH_NOTES'];
  final pageId = notes == null || notes.isEmpty
      ? await _madeUpPage(store, folder)
      : await _heaviestPage(
          store,
          folder,
          notes,
          Platform.environment['AANTEKENING_BENCH_PAGE'],
        );

  final timings = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  // The whole window, as it is used: sidebar, tabs and ribbon about the
  // page. Settings are kept in memory, this computer's folder for the app
  // is the temporary one, and no keychain is read.
  final container = ProviderContainer(
    overrides: [
      storeProvider.overrideWith((ref) async => store),
      preferencesProvider.overrideWith((ref) async => Preferences.inMemory()),
      supportFolderProvider.overrideWith((ref) async => folder.path),
      dictionaryFolderProvider.overrideWith(
        (ref) async => DictionaryFolder(Directory('${folder.path}/words')),
      ),
      aiSecretsProvider.overrideWithValue(MemorySecrets()),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AantekeningApp(),
    ),
  );
  await _wait(const Duration(seconds: 1));
  await container.read(libraryActionsProvider).openPageId(pageId);
  // The page across the window, as it is read, with the sidebar closed.
  container.read(sidebarProvider.notifier).close();
  // Shown as pages, if asked: the same page, cut into sheets.
  if (Platform.environment['AANTEKENING_BENCH_LAYOUT'] == 'pages') {
    await _wait(const Duration(milliseconds: 300));
    (_canvas().widget as InfiniteCanvas).controller.setLayout(NoteLayout.pages);
  }

  // Opened, and its PDF pages drawn.
  await _wait(const Duration(seconds: 4));
  final input = _Input(_canvasRect());
  final runs = <_Run>[];
  Future<void> measure(String name, Future<void> Function() action) async {
    final run = _Run.begin(name);
    await action();
    // Coasting, gliding and rendering what the move uncovered.
    await _wait(const Duration(milliseconds: 1500));
    runs.add(run..end());
  }

  await measure('idle', () => _wait(const Duration(seconds: 4)));
  // What a frame costs with nothing in it changed: the least any frame
  // costs, however little it moves.
  await measure('frames, nothing moving', () async {
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(end)) {
      SchedulerBinding.instance.scheduleForcedFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
  });
  await measure('wheel scroll', () async {
    for (final direction in <double>[1, -1]) {
      for (var notch = 0; notch < 24; notch++) {
        input.wheel(Offset(0, 100 * direction));
        await _wait(const Duration(milliseconds: 60));
      }
    }
  });
  await measure('touchpad scroll', () async {
    await input.swipe(
      const Offset(0, -2400),
      const Duration(milliseconds: 900),
    );
    await input.swipe(const Offset(0, 1800), const Duration(milliseconds: 700));
    await input.swipe(const Offset(0, -600), const Duration(milliseconds: 500));
  });
  await measure('touchpad pinch', () async {
    await input.pinch(const <double>[
      1,
      2.5,
      2.5,
      0.4,
      1,
    ], const Duration(seconds: 3));
  });
  await measure('ctrl+wheel zoom', () async {
    input.holdControl(down: true);
    for (final direction in <double>[-1, 1]) {
      for (var notch = 0; notch < 8; notch++) {
        input.wheel(Offset(0, 100 * direction));
        await _wait(const Duration(milliseconds: 90));
      }
    }
    input.holdControl(down: false);
  });
  await input.pinch(const <double>[1, 4], const Duration(milliseconds: 800));
  await _wait(const Duration(seconds: 3));
  await measure('touchpad scroll, zoomed in', () async {
    await input.swipe(
      const Offset(0, -1500),
      const Duration(milliseconds: 900),
    );
    await input.swipe(
      const Offset(-600, 900),
      const Duration(milliseconds: 700),
    );
  });
  await measure('idle, zoomed in', () => _wait(const Duration(seconds: 3)));

  // The last timings are handed over once a frame is drawn after a while.
  await _wait(const Duration(milliseconds: 1100));
  SchedulerBinding.instance.scheduleForcedFrame();
  await _wait(const Duration(milliseconds: 300));

  final out = StringBuffer()
    ..writeln()
    ..writeln(
      'Canvas benchmark — page ${_canvasRect().width.round()}×'
      '${_canvasRect().height.round()}, '
      '${PlatformDispatcher.instance.views.first.devicePixelRatio}× pixels, '
      'shown as ${(_canvas().widget as InfiniteCanvas).controller.document.canvas.layout.label.toLowerCase()}',
    );
  for (final run in runs) {
    run.report(out, timings);
  }
  out.writeln('Memory: ${(ProcessInfo.maxRss / 1e6).round()} MB at most');
  stdout.write(out);
  await stdout.flush();
  await store.close();
  folder.deleteSync(recursive: true);
  exit(0);
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Where the page is on screen.
Rect _canvasRect() {
  final box = _canvas().renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The page, as the window shows it.
Element _canvas() {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget is InfiniteCanvas) {
      found = element;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildElements(visit);
  return found!;
}

/// One thing measured: the frames drawn and the processor time spent
/// between its [begin] and [end].
class _Run {
  _Run.begin(this.name) : _start = _now(), _cpuBefore = _threadTimes();

  final String name;
  final int _start;
  final Map<String, int> _cpuBefore;
  late final int _end;
  late final Map<String, int> _cpuAfter;

  void end() {
    _end = _now();
    _cpuAfter = _threadTimes();
  }

  /// Microseconds, on the clock frame timings are stamped by.
  static int _now() => Timeline.now;

  void report(StringBuffer out, List<FrameTiming> timings) {
    final frames = <FrameTiming>[
      for (final timing in timings)
        if (timing.timestampInMicroseconds(FramePhase.vsyncStart) >= _start &&
            timing.timestampInMicroseconds(FramePhase.vsyncStart) < _end)
          timing,
    ];
    final seconds = (_end - _start) / 1e6;
    out
      ..writeln()
      ..writeln(
        '$name: ${frames.length} frames in ${seconds.toStringAsFixed(1)} s',
      );
    if (frames.isNotEmpty) {
      String line(String what, Duration Function(FrameTiming) of) {
        final ms = <double>[
          for (final frame in frames) of(frame).inMicroseconds / 1000,
        ]..sort();
        double at(double share) =>
            ms[math.min(ms.length - 1, (share * ms.length).floor())];
        final mean = ms.reduce((a, b) => a + b) / ms.length;
        return '  $what ms: mean ${mean.toStringAsFixed(2)}  '
            'p50 ${at(0.5).toStringAsFixed(2)}  '
            'p90 ${at(0.9).toStringAsFixed(2)}  '
            'p99 ${at(0.99).toStringAsFixed(2)}  '
            'max ${ms.last.toStringAsFixed(2)}';
      }

      out
        ..writeln(line('build ', (frame) => frame.buildDuration))
        ..writeln(line('raster', (frame) => frame.rasterDuration))
        ..writeln(line('total ', (frame) => frame.totalSpan));
      final late = frames
          .where(
            (frame) => frame.totalSpan > const Duration(microseconds: 16667),
          )
          .length;
      out.writeln('  frames over 16.7 ms: $late');
    }
    final spent = <String, int>{
      for (final entry in _cpuAfter.entries)
        entry.key: entry.value - (_cpuBefore[entry.key] ?? 0),
    }..removeWhere((_, ticks) => ticks <= 0);
    final total = spent.values.fold(0, (sum, ticks) => sum + ticks);
    final perSecond = total * 10 / seconds;
    final threads =
        (spent.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map(
              (entry) => '${entry.key} ${(entry.value * 10 / seconds).round()}',
            )
            .join(', ');
    out.writeln('  processor: ${perSecond.round()} ms a second ($threads)');
  }

  /// Processor time each kind of thread of this process has spent, in
  /// clock ticks of 10 ms, by thread name.
  static Map<String, int> _threadTimes() {
    final times = <String, int>{};
    for (final task in Directory('/proc/self/task').listSync()) {
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
    return times;
  }
}

/// Sends the page what a mouse wheel, a touchpad and the keyboard would.
class _Input {
  _Input(this.view) {
    _send(PointerAddedEvent(position: _at, device: _mouse));
    _send(PointerHoverEvent(position: _at, device: _mouse));
  }

  final Rect view;
  final Stopwatch _clock = Stopwatch()..start();
  static const int _mouse = 1;
  static const int _touchpad = 2;
  int _gesture = 100;

  /// How often a touchpad reports.
  static const Duration _report = Duration(milliseconds: 8);

  Offset get _at => view.center;
  Duration get _time => _clock.elapsed;

  /// The touchpad's reports are scaled as the platform scales them, so the
  /// page moves as far as asked.
  final double _panScale = trackpadPanScale();

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  void wheel(Offset delta) => _send(
    PointerScrollEvent(
      timeStamp: _time,
      position: _at,
      device: _mouse,
      scrollDelta: delta,
    ),
  );

  void holdControl({required bool down}) {
    const physical = PhysicalKeyboardKey.controlLeft;
    const logical = LogicalKeyboardKey.controlLeft;
    HardwareKeyboard.instance.handleKeyEvent(
      down
          ? KeyDownEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: _time,
            )
          : KeyUpEvent(
              physicalKey: physical,
              logicalKey: logical,
              timeStamp: _time,
            ),
    );
  }

  /// Two fingers moving the page by [distance] over [duration], fastest in
  /// the middle, lifted while still moving, so the page coasts on.
  Future<void> swipe(Offset distance, Duration duration) async {
    final pointer = _gesture++;
    _send(
      PointerPanZoomStartEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
    final steps = duration.inMicroseconds ~/ _report.inMicroseconds;
    var pan = Offset.zero;
    for (var step = 1; step <= steps; step++) {
      await _wait(_report);
      // Speeding up, then slowing a little before the fingers lift.
      final t = step / steps;
      final along =
          (1 - math.cos(math.pi * t * 0.85)) / (1 - math.cos(math.pi * 0.85));
      final next = distance * along / _panScale;
      _send(
        PointerPanZoomUpdateEvent(
          timeStamp: _time,
          position: _at,
          device: _touchpad,
          pointer: pointer,
          pan: next,
          panDelta: next - pan,
        ),
      );
      pan = next;
    }
    _send(
      PointerPanZoomEndEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
  }

  /// Two fingers pinching through [scales], evenly over [duration].
  Future<void> pinch(List<double> scales, Duration duration) async {
    final pointer = _gesture++;
    _send(
      PointerPanZoomStartEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
    final steps = duration.inMicroseconds ~/ _report.inMicroseconds;
    for (var step = 1; step <= steps; step++) {
      await _wait(_report);
      final along = step / steps * (scales.length - 1);
      final from = math.min(along.floor(), scales.length - 2);
      final part = along - from;
      // Evenly in the logarithm, as fingers spread.
      final scale = math.exp(
        math.log(scales[from]) * (1 - part) + math.log(scales[from + 1]) * part,
      );
      _send(
        PointerPanZoomUpdateEvent(
          timeStamp: _time,
          position: _at,
          device: _touchpad,
          pointer: pointer,
          scale: scale,
        ),
      );
    }
    _send(
      PointerPanZoomEndEvent(
        timeStamp: _time,
        position: _at,
        device: _touchpad,
        pointer: pointer,
      ),
    );
  }
}

// ------------------------------------------------------------- the page

/// A page made up to be heavy: a printout of eight pages, each written over
/// in pen and marked with a highlighter, with a text box beside each.
Future<String> _madeUpPage(AantekeningStore store, Directory folder) async {
  const pages = 8;
  const width = 816.0;
  const height = width * 842 / 595;
  const gap = 40.0;
  final pdf = File('${folder.path}/printout.pdf')
    ..writeAsBytesSync(_printout(pages));
  final asset = await store.assets.importFile(pdf, mimeType: 'application/pdf');
  final random = math.Random(7);
  final elements = <NoteElement>[];
  for (var page = 0; page < pages; page++) {
    final top = 120 + page * (height + gap);
    elements
      ..add(
        PdfElement(
          id: Ulid.generate(),
          frame: Frame(x: 40, y: top, width: width, height: height),
          createdAt: 0,
          updatedAt: 0,
          assetId: asset.id,
          pageIndex: page,
          locked: true,
        ),
      )
      ..add(
        TextElement(
          id: Ulid.generate(),
          frame: Frame(x: width + 80, y: top, width: 360, height: 400),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            for (var line = 0; line < 12; line++)
              TextBlock.plain(
                'Aufgabe ${page + 1}.$line: Die Welle breitet sich mit '
                'c = λ·f aus, und ihre Energie wächst mit dem Quadrat der '
                'Amplitude.',
              ),
          ],
        ),
      );
    // Lines of handwriting, a word at a time, over the printout.
    for (var line = 0; line < 14; line++) {
      final y = top + 80 + line * 62;
      for (var word = 0; word < 5; word++) {
        elements.add(
          _handwriting(
            random,
            Offset(90 + word * 140, y),
            highlight: line % 6 == 0 && word == 0,
          ),
        );
      }
    }
  }
  final notebook = await store.library.createNotebook(title: 'Benchmark');
  final section = await store.library.createSection(
    notebookId: notebook.id,
    title: 'Benchmark',
  );
  final ref = await store.pages.createPage(
    sectionId: section.id,
    title: 'Heavy page',
  );
  var document = (await store.pages.loadDocument(ref.id))!;
  for (final element in elements) {
    document = document.withElementAdded(element);
  }
  await store.pages.saveDocument(ref.id, document);
  return ref.id;
}

/// A handwritten word at [at]: a few strokes of a hundred samples, their
/// pressure rising and falling as a pen's does.
InkElement _handwriting(
  math.Random random,
  Offset at, {
  required bool highlight,
}) {
  final strokes = <InkStroke>[
    for (var stroke = 0; stroke < (highlight ? 1 : 4); stroke++)
      () {
        final xs = <double>[];
        final ys = <double>[];
        final pressures = <double>[];
        const samples = 100;
        final start = at.dx + stroke * 28;
        for (var i = 0; i < samples; i++) {
          final t = i / samples;
          xs.add(
            start + t * (highlight ? 360 : 26) + random.nextDouble() * 0.6,
          );
          ys.add(
            at.dy +
                (highlight ? 0 : math.sin(t * math.pi * 6) * 9) +
                random.nextDouble() * 0.6,
          );
          pressures.add(0.4 + 0.5 * math.sin(t * math.pi));
        }
        return InkStroke.fromPoints(
          tool: highlight ? InkTool.highlighter : InkTool.pen,
          color: highlight ? 0x80FFE000 : 0xFF1A3C8C,
          width: highlight ? 14 : 2.2,
          xs: xs,
          ys: ys,
          pressures: highlight ? null : pressures,
        );
      }(),
  ];
  var bounds = strokes.first.bounds;
  for (final stroke in strokes.skip(1)) {
    bounds = bounds.union(stroke.bounds);
  }
  return InkElement(
    id: Ulid.generate(),
    frame: Frame(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    ),
    createdAt: 0,
    updatedAt: 0,
    strokes: strokes,
  );
}

/// A PDF of [pages] A4 pages, each a worksheet: lines of text, ruled boxes
/// and a curve plotted on axes, all drawn rather than pictured, as a
/// printout of a document is.
Uint8List _printout(int pages) {
  final kids = <String>[for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count $pages >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var page = 0; page < pages; page++) {
    final content = StringBuffer('BT /F1 10 Tf 13 TL 50 790 Td\n');
    for (var line = 0; line < 54; line++) {
      content.writeln(
        '(Aufgabe ${page + 1}.$line  Eine Welle der Frequenz '
        'f = ${line + 2} Hz breitet sich mit c = 340 m/s aus. '
        'Bestimme die Wellenlaenge.) \'',
      );
    }
    content.writeln('ET');
    for (var box = 0; box < 6; box++) {
      content.writeln('${50 + box * 85} 60 75 40 re S');
    }
    content.write('0.2 0.3 0.7 RG 1.2 w 60 200 m');
    for (var i = 0; i <= 400; i++) {
      final x = 60 + i * 1.2;
      final y = 200 + 60 * math.sin(i / 400 * math.pi * 6) * math.exp(-i / 300);
      content.write(' ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} l');
    }
    content.writeln(' S');
    final stream = content.toString();
    objects
      ..add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R >> >> '
        '/Contents ${5 + page * 2} 0 R >>',
      )
      ..add('<< /Length ${stream.length} >>\nstream\n${stream}endstream');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out
    ..write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n')
    ..writeAll(<String>[
      for (final offset in offsets)
        '${offset.toString().padLeft(10, '0')} 00000 n \n',
    ])
    ..write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    );
  return Uint8List.fromList(out.toString().codeUnits);
}

/// Imports the OneNote package at [path], and picks its page whose title
/// holds [title], or else the one with the most on it.
Future<String> _heaviestPage(
  AantekeningStore store,
  Directory folder,
  String path,
  String? title,
) async {
  final work = Directory('${folder.path}/import')..createSync();
  final draft = await Isolate.run(
    () => const OneNoteImporter().read(<String>[path], ImportWork(work)),
  );
  await store.drafts.store(draft);
  String? heaviest;
  var most = -1;
  for (final page in await store.pages.listAllPages()) {
    if (title != null && title.isNotEmpty) {
      if (page.title.contains(title)) return page.id;
      continue;
    }
    final document = await store.pages.loadDocument(page.id);
    if (document == null) continue;
    var weight = 0;
    for (final element in document.elements) {
      weight += switch (element) {
        InkElement(:final strokes) => strokes.fold(
          0,
          (sum, stroke) => sum + stroke.pointCount,
        ),
        PdfElement() => 20000,
        _ => 500,
      };
    }
    if (weight > most) {
      most = weight;
      heaviest = page.id;
    }
  }
  if (heaviest == null) throw StateError('No page in $path');
  return heaviest;
}
