/// The measures of the app benchmark, each driven as a person would do
/// it: by the keys, the mouse and the pen, through the window as it is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening/src/ai/ai_state.dart';
import 'package:aantekening/src/files/notes_location.dart';
import 'package:aantekening/src/graph/note_graph.dart';
import 'package:aantekening/src/look/chooser.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/search/search_line.dart';
import 'package:aantekening/src/shell/library_actions.dart';
import 'package:aantekening/src/shell/new_page_dialog.dart';
import 'package:aantekening/src/shell/picker.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening/src/spelling/dictionaries.dart';
import 'package:aantekening/src/spelling/spelling.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'input.dart';
import 'made_up_notes.dart';
import 'measuring.dart';

/// Why a measure was not made: what was done to the window did not do
/// what it does for a person, so there was nothing honest to time.
class NotDriven implements Exception {
  const NotDriven(this.why);

  final String why;

  @override
  String toString() => why;
}

/// Counts the lists of notebooks, sections and pages read again from the
/// store, and notes when the last of them was.
final class Reloads extends ProviderObserver {
  /// How often each kind of list has been read since [reset].
  final Map<String, int> counts = <String, int>{};

  /// When the last of them had been read, on the clock of [now].
  int lastAt = 0;

  void reset() {
    counts.clear();
    lastAt = 0;
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (newValue is! AsyncData<Object?>) return;
    // What was read, if it is one of the lists of the notes.
    final provider = context.provider;
    final family = provider.from;
    final list = identical(provider, notebooksProvider)
        ? 'notebook lists read'
        : identical(provider, noteGraphProvider)
        ? 'graphs of all read'
        : identical(family, sectionTreeProvider)
        ? 'section lists read'
        : identical(family, pageTreeProvider)
        ? 'page lists read'
        : identical(family, pageProvider)
        ? 'single pages read'
        : identical(family, sectionProvider)
        ? 'single sections read'
        : null;
    if (list == null) return;
    counts[list] = (counts[list] ?? 0) + 1;
    lastAt = now();
  }
}

/// What the app runs on while it is measured: everything it keeps, kept in
/// [folder], a temporary one — the notes and their index, the settings,
/// the dictionaries — and no keychain read; the notes opened as the app
/// opens them. [reloads] counts the lists read; [more] is overridden too.
ProviderContainer measuredContainer(
  String folder,
  Reloads reloads, {
  List<Override> more = const <Override>[],
}) => ProviderContainer(
  overrides: [
    supportFolderProvider.overrideWith((ref) async => '$folder/support'),
    notesFolderProvider.overrideWith((ref) async => '$folder/notes'),
    indexFolderProvider.overrideWith((ref) async => '$folder/index'),
    dictionaryFolderProvider.overrideWith(
      (ref) async => DictionaryFolder(Directory('$folder/words')),
    ),
    aiSecretsProvider.overrideWithValue(MemorySecrets()),
    ...more,
  ],
  observers: <ProviderObserver>[reloads],
  // As the app has it: what fails is said at once, not tried again unseen.
  retry: (_, _) => null,
);

/// The settings as a session that left [pageId] open in its tab leaves
/// them, for the app to be started on: with a backup made today, so none
/// is made while it is measured.
void leaveOpen(String folder, MadeUpNotes notes, String pageId) =>
    File('$folder/support/preferences.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'tabs': <Object?>[
            <String, Object?>{
              'notebook': notes.notebook,
              'section': notes.section,
              'page': pageId,
            },
          ],
          'backups': <String, Object?>{
            'interval': 'daily',
            'keep': 10,
            'last': DateTime.now().millisecondsSinceEpoch,
          },
        }),
      );

/// Everything measured in the window once it is open on the notes.
class Measures {
  Measures({
    required this.container,
    required this.notes,
    required this.reloads,
    required this.only,
    required this.penStrokes,
    required this.idle,
    this.afterEach,
    TypedText? typed,
  }) : _typed = typed ?? BenchBinding.typed;

  final ProviderContainer container;
  final MadeUpNotes notes;
  final Reloads reloads;

  /// Only the scenarios whose names hold this are measured.
  final String only;

  /// How many strokes the pen writes in each of its measures.
  final int penStrokes;

  /// How long nothing is done, where that is measured.
  final Duration idle;

  /// Called after each scenario measured: to keep what there is so far,
  /// say, in case a later one never ends.
  final void Function()? afterEach;

  final List<Run> runs = <Run>[];

  /// What was not measured, and why.
  final List<String> unmeasured = <String>[];

  final Keys _keys = Keys();

  /// What is typed, and into what: told of the fields by the binding.
  final TypedText _typed;
  late final Input _input = Input(_canvas);

  /// What is typed where typing is measured: words, a letter at a time.
  static const String _prose =
      'the wave bears its stored work and its moment far along the field ';

  // ------------------------------------------------------------ the window

  CanvasController? get _maybePage {
    final canvas = maybeFind<InfiniteCanvas>();
    return canvas == null ? null : (canvas.widget as InfiniteCanvas).controller;
  }

  /// The page showing.
  CanvasController get _page =>
      _maybePage ?? (throw const NotDriven('no page was showing'));

  /// Whether the window shows the page [pageId], read and laid out.
  bool _shows(String pageId) => _maybePage?.document.id == pageId;

  /// Where the page is in the window.
  Rect get _canvas => rectOf<InfiniteCanvas>();

  /// Where the page is clear of what floats over it and of its edges, to
  /// be pressed on.
  Rect get _clear {
    final canvas = _canvas;
    return Rect.fromLTRB(
      canvas.left + 20,
      canvas.top + 60,
      canvas.right - 60,
      canvas.bottom - 60,
    );
  }

  /// Where [onPage], a point of the page, is in the window.
  Offset _onScreen(Offset onPage) =>
      _canvas.topLeft + _page.viewport.toScreen(onPage);

  static int _strokesOf(PageDocument document) => document.elements
      .whereType<InkElement>()
      .fold(0, (sum, element) => sum + element.strokes.length);

  // ---------------------------------------------------------- the measuring

  /// Runs [body] as the scenario [name], if it is asked for, and leaves
  /// the window in normal mode after it. What it cannot do is noted, and
  /// the rest of it left out.
  Future<void> _scenario(String name, Future<void> Function() body) async {
    if (!name.contains(only)) return;
    stderr.writeln('measuring: $name');
    try {
      await body();
    } on Object catch (error) {
      unmeasured.add('$name: $error');
      stderr.writeln('  not measured: $error');
    }
    try {
      await _toNormal();
    } on Object {
      // The next scenario finds out, and says so.
    }
    afterEach?.call();
  }

  /// Measures [body] as [name]: the frames drawn and the processor time
  /// spent until it is done and the window has settled.
  Future<void> _measure(
    String name,
    Future<void> Function(Run run) body, {
    bool stalls = true,
    bool settles = true,
  }) async {
    final run = Run.begin(name, stalls: stalls);
    try {
      await body(run);
      if (settles) await Frames.settled(within: const Duration(seconds: 10));
    } finally {
      run.end();
    }
    runs.add(run);
  }

  /// Back to normal mode with nothing open over the page: Esc, as often as
  /// a person would press it to be sure.
  Future<void> _toNormal() async {
    for (var i = 0; i < 3; i++) {
      await _keys.press('Esc');
      await wait(const Duration(milliseconds: 150));
    }
    await Frames.settled(within: const Duration(seconds: 5));
  }

  /// Shows the page [pageId] in normal mode, settled: where a measure
  /// starts from, not itself measured — the page is opened as Go to opens
  /// it, without the typing.
  Future<void> _show(String pageId) async {
    await _toNormal();
    if (!_shows(pageId)) {
      final shown = Frames.shows(() => _shows(pageId), walks: true);
      if (!await container.read(libraryActionsProvider).openPageId(pageId) ||
          await shown == null) {
        throw const NotDriven('the page to measure on did not open');
      }
    }
    await Frames.settled();
    await wait(const Duration(milliseconds: 300));
  }

  /// Presses [key], which the window is to take as one of its own: a key
  /// of the mode the page is in or of what is open over it — or, with
  /// Ctrl, a shortcut that works wherever the keyboard is.
  ///
  /// Never p, y or x alone on the page: there they paste, copy and delete,
  /// and the clipboard is the person's own.
  Future<void> _command(String key, {bool control = false}) async {
    if (!await _keys.press(key, control: control)) {
      throw NotDriven(
        'the window did not take the key ${control ? 'Ctrl+' : ''}$key',
      );
    }
  }

  /// Waits for [test] to hold, looking every few milliseconds; says
  /// whether it came to within [within].
  static Future<bool> _until(
    bool Function() test, {
    Duration within = const Duration(seconds: 4),
  }) async {
    final give = now() + within.inMicroseconds;
    while (!test()) {
      if (now() > give) return false;
      await wait(const Duration(milliseconds: 20));
    }
    return true;
  }

  /// Waits for a field to have the keyboard — one told of each edit, as a
  /// text box on the page is, if [box], else one of a single line.
  Future<void> _field({required bool box}) async {
    if (!await _until(() => _typed.client != null && _typed.deltas == box)) {
      throw NotDriven(
        box
            ? 'no text box took the keyboard'
            : 'no field took the keyboard to be typed into',
      );
    }
    // Its text, and what is picked of it, told to the input method.
    await wait(const Duration(milliseconds: 150));
  }

  /// Types [text] a character at a time, each as a key pressed — which the
  /// window leaves to the input method — then as the input method's edit,
  /// then the key let go. Noted in [run]: how long the window took over
  /// each, and until it was on the screen. [between] keys the hands rest;
  /// and after every [pauseEvery] of them, long enough for the page to be
  /// saved, as it is whenever typing pauses.
  Future<void> _type(
    String text, {
    Run? run,
    String what = 'key',
    Duration between = const Duration(milliseconds: 90),
    int pauseEvery = 0,
  }) async {
    for (final (index, character) in text.split('').indexed) {
      // Only ever into a field: on the page itself a letter is a command.
      if (_typed.client == null) {
        throw const NotDriven('nothing had the keyboard to type into');
      }
      final began = now();
      final taken = await _keys.down(character);
      final next = Frames.next();
      if (!taken && !await _typed.type(character)) {
        throw const NotDriven('nothing had the keyboard to type into');
      }
      final handled = now();
      final frame = await next;
      await _keys.up(character);
      run
        ?..took('$what handled in', (handled - began) / 1000)
        ..shown('$what to pixels', began, frame)
        ..told('frame after a $what', frame);
      await wait(between);
      if (pauseEvery > 0 && (index + 1) % pauseEvery == 0) {
        await wait(const Duration(milliseconds: 900));
      }
    }
  }

  /// Presses Enter in a field of one line: left by the window to the input
  /// method, which tells the field to do what Enter does there.
  Future<void> _enter() async {
    final taken = await _keys.down('Enter');
    if (!taken && !await _typed.perform()) {
      throw const NotDriven('nothing had the keyboard to take Enter');
    }
    await _keys.up('Enter');
  }

  /// Presses [key] and notes in [run] how long the window took over it and
  /// until the next frame was on the screen.
  Future<void> _timedKey(Run run, String key, {String what = 'key'}) async {
    final began = now();
    final taken = await _keys.down(key);
    final handled = now();
    final frame = await Frames.next();
    await _keys.up(key);
    if (!taken) throw NotDriven('the window did not take the key $key');
    run
      ..took('$what handled in', (handled - began) / 1000)
      ..shown('$what to pixels', began, frame)
      ..told('frame after a $what', frame);
  }

  // ------------------------------------------------------------- everything

  /// Measures every scenario asked for, one after another.
  Future<void> all() async {
    await _scenario('open', _open);
    await _scenario('idle', _idle);
    await _scenario('pen', _pen);
    await _scenario('select', _select);
    await _scenario('typing', _typing);
    await _scenario('search', _search);
    await _scenario('goto', _goTo);
    await _scenario('picker', _picker);
    await _scenario('library', _library);
  }

  // ----------------------------------------------------------------- opening

  /// Opening each heavy page for the first time, from Go to — its name
  /// typed, and Enter — and going back and forth between two of them.
  Future<void> _open() async {
    await _show(notes.ordinary);
    for (final (what, pageId, title) in <(String, String, String)>[
      ('a long text', notes.longText, MadeUpNotes.longTextTitle),
      ('formulas and pictures', notes.formulas, MadeUpNotes.formulasTitle),
      ('a page of handwriting', notes.ink, MadeUpNotes.inkTitle),
      ('another of handwriting', notes.inkAgain, MadeUpNotes.inkAgainTitle),
    ]) {
      await _summonGoTo();
      await _type(title, between: const Duration(milliseconds: 40));
      await Frames.settled();
      await _measure('open: $what, first time', (run) async {
        final began = now();
        final shown = Frames.shows(() => _shows(pageId), walks: true);
        await _keys.press('Enter');
        run.took('key handled in', (now() - began) / 1000);
        final frame = await shown;
        if (frame == null) {
          throw NotDriven('Go to did not open “$title” on Enter');
        }
        run
          ..shown('Enter to first frame of the page', began, frame)
          ..shown('Enter to settled', began, await Frames.settled());
      });
    }
    // Back and forward, with the keys of normal mode: both pages have been
    // drawn before.
    await _measure('open: back and forth between two of handwriting', (
      run,
    ) async {
      for (var turn = 0; turn < 6; turn++) {
        final pageId = turn.isEven ? notes.ink : notes.inkAgain;
        final began = now();
        final shown = Frames.shows(() => _shows(pageId), walks: true);
        await _command(turn.isEven ? 'H' : 'L');
        run.took('key handled in', (now() - began) / 1000);
        final frame = await shown;
        if (frame == null) {
          throw const NotDriven('H and L did not go back and forward');
        }
        run
          ..shown('key to first frame of the page', began, frame)
          ..shown('key to settled', began, await Frames.settled());
        await wait(const Duration(milliseconds: 300));
      }
    });
  }

  /// Opens Go to with its shortcut, Ctrl+P, and waits for its field.
  Future<void> _summonGoTo() async {
    await _command('p', control: true);
    if (!await _until(() => maybeFind<Chooser>() != null)) {
      throw const NotDriven('Ctrl+P did not open Go to');
    }
    await _field(box: false);
    await Frames.settled();
  }

  // -------------------------------------------------------------------- idle

  /// Nothing done, on a heavy page: what the app costs left alone.
  Future<void> _idle() async {
    await _show(notes.ink);
    await _measure(
      'idle: on a page of handwriting',
      (_) => wait(idle),
      stalls: false,
      settles: false,
    );
  }

  // ----------------------------------------------------------------- the pen

  /// Writing with the pen, on a page that holds thousands of strokes
  /// already and on a blank one, to tell what the page's weight adds.
  Future<void> _pen() async {
    for (final (what, pageId) in <(String, String)>[
      ('a page of handwriting', notes.ink),
      ('a blank page', notes.blank),
    ]) {
      await _show(pageId);
      await _command('d');
      if (!_page.tool.draws) {
        throw const NotDriven('d did not take up the pen');
      }
      final before = _strokesOf(_page.document);
      await _measure('pen: writing on $what', (run) async {
        await _write(run, penStrokes);
        final written = _strokesOf(_page.document) - before;
        if (written <= 0) throw const NotDriven('the pen drew nothing');
        run.counts['strokes on the page before'] = before;
        run.counts['strokes written'] = written;
      });
      await _toNormal();
    }
  }

  /// Writes [strokes] strokes across the page in view, a word's worth of
  /// loops each, the pen reporting where it is every six milliseconds and
  /// lifted between them; every thirty, the hand rests long enough for the
  /// page to be saved.
  Future<void> _write(Run run, int strokes) async {
    final canvas = _canvas;
    final area = Rect.fromLTRB(
      canvas.left + 140,
      canvas.top + 140,
      canvas.right - 220,
      canvas.bottom - 90,
    );
    const across = 28.0;
    const down = 44.0;
    const samples = 30;
    final perLine = math.max(1, (area.width / across).floor());
    final lines = math.max(1, (area.height / down).floor());
    final fifth = math.max(1, strokes ~/ 5);
    for (var stroke = 0; stroke < strokes; stroke++) {
      final line = stroke ~/ perLine;
      // Down the page, and from its top again a little lower.
      final from = Offset(
        area.left + (stroke % perLine) * across,
        area.top + (line % lines) * down + (line ~/ lines) * 13.0,
      );
      var at = from;
      run.took('pen down handled in', _input.penDown(at, 0.4) / 1000);
      for (var i = 1; i <= samples; i++) {
        await wait(const Duration(milliseconds: 6));
        final t = i / samples;
        final next = from + Offset(t * 22, math.sin(t * math.pi * 6) * 9);
        run.took(
          'pen move handled in',
          _input.penMove(next, next - at, 0.4 + 0.5 * math.sin(t * math.pi)) /
              1000,
        );
        at = next;
      }
      final began = now();
      final lift = _input.penUp(at) / 1000;
      final frame = await Frames.next();
      run
        ..took('pen lift handled in', lift)
        ..shown('pen lift to pixels', began, frame)
        ..told('frame after a lift', frame);
      // As the page grows: the first strokes written, and the last.
      if (stroke < fifth) {
        run.took('pen lift handled in, first fifth of the strokes', lift);
      }
      if (stroke >= strokes - fifth) {
        run.took('pen lift handled in, last fifth of the strokes', lift);
      }
      await wait(const Duration(milliseconds: 60));
      if ((stroke + 1) % 30 == 0) {
        await wait(const Duration(milliseconds: 900));
      }
    }
  }

  // --------------------------------------------------------------- selecting

  /// Picking things out on a heavy page, seen from far enough off that
  /// hundreds are in view: a rectangle dragged over them with the mouse,
  /// everything picked with the keys, and what is picked dragged.
  Future<void> _select() async {
    await _show(notes.ink);
    for (var i = 0; i < 4; i++) {
      await _command('-');
      await wait(const Duration(milliseconds: 150));
    }
    await Frames.settled();
    // From the page's left margin, below its title, where nothing lies —
    // a press on the printout would pick out its text instead.
    final view = _page.viewport;
    final from = _onScreen(
      Offset(15, math.max(240, view.toPage(const Offset(0, 130)).dy)),
    );
    final clear = _clear;
    if (!_canvas.contains(from)) {
      throw const NotDriven('the page’s margin was not in view to drag from');
    }
    final to = clear.bottomRight;
    await _measure('select: a rectangle dragged over the page', (run) async {
      await _input.drag(
        from,
        to - from,
        const Duration(milliseconds: 1200),
        kind: PointerDeviceKind.mouse,
        onMove: (taken) => run.took('move handled in', taken / 1000),
        onLift: (taken) => run.took('letting go handled in', taken / 1000),
      );
      final picked = _page.selection.length;
      if (picked == 0) {
        throw const NotDriven('the rectangle dragged picked nothing');
      }
      run.counts['things picked'] = picked;
    });
    await _dragPicked('select: what the rectangle picked, dragged');
    await _toNormal();

    // Select mode, and everything in it.
    await _command('v');
    await _measure('select: everything picked', (run) async {
      await _timedKey(run, 'a');
      final picked = _page.selection.length;
      if (picked == 0) throw const NotDriven('a picked nothing');
      run.counts['things picked'] = picked;
    });
    await _dragPicked('select: everything, dragged');
  }

  /// Drags what is picked a little way with the mouse, by the band along
  /// the top of a text box among it, and puts it back with undo.
  Future<void> _dragPicked(String name) async {
    final clear = _clear;
    Offset? grip;
    for (final element in _page.selectedElements) {
      if (element is! TextElement) continue;
      final at = _onScreen(
        Offset(element.frame.x + element.frame.width / 2, element.frame.y + 5),
      );
      // The one nearest the middle, clear of the handles about them all.
      if (clear.contains(at) &&
          (grip == null ||
              (at - clear.center).distance < (grip - clear.center).distance)) {
        grip = at;
      }
    }
    if (grip == null) {
      throw const NotDriven('nothing picked was in view to be dragged by');
    }
    final held = grip;
    final before = _page.document;
    await _measure(name, (run) async {
      await _input.drag(
        held,
        const Offset(90, 60),
        const Duration(milliseconds: 800),
        kind: PointerDeviceKind.mouse,
        onMove: (taken) => run.took('move handled in', taken / 1000),
        onLift: (taken) => run.took('letting go handled in', taken / 1000),
      );
      if (identical(_page.document, before)) {
        throw const NotDriven('the drag moved nothing');
      }
      run.counts['things dragged'] = _page.selection.length;
    });
    // Put back, in normal or select mode alike.
    await _keys.press('u');
    await Frames.settled();
  }

  // ------------------------------------------------------------------ typing

  /// Typing in a text box of hundreds of paragraphs — near its top, where
  /// all of them lie below what is typed, and at its foot — Enter near its
  /// top, and the same typing in a short box.
  Future<void> _typing() async {
    await _show(notes.longText);
    final boxes = _page.document.elements.whereType<TextElement>().toList()
      ..sort((a, b) => a.blocks.length.compareTo(b.blocks.length));
    if (boxes.length < 2) {
      throw const NotDriven('the page of text did not hold its two boxes');
    }
    final short = boxes.first;
    final long = boxes.last;

    // A click on a line of the box puts the caret there.
    Future<void> clickInto(TextElement box, double down) async {
      final at = _onScreen(Offset(box.frame.x + 60, box.frame.y + down));
      if (!_clear.contains(at)) {
        throw NotDriven(
          'the text box of ${box.blocks.length} paragraphs was not in view '
          'to click into: it lay at $at of $_clear',
        );
      }
      await _input.click(at);
      await _field(box: true);
    }

    // What the box [id] holds now: its paragraphs, and their letters.
    List<TextBlock> blocksOf(String id) =>
        (_page.elementById(id) as TextElement?)?.blocks ?? const <TextBlock>[];
    int lettersOf(String id) => blocksOf(id).fold(
      0,
      (sum, block) =>
          sum + block.runs.fold(0, (sum, run) => sum + run.text.length),
    );

    /// Types the prose into the box [id], measured as [name].
    Future<void> typeInto(String id, String name) =>
        _measure(name, (run) async {
          final before = lettersOf(id);
          await _type(_prose, run: run, pauseEvery: 18);
          if (lettersOf(id) - before < _prose.length - 2) {
            throw const NotDriven('what was typed did not reach the box');
          }
          run.counts['paragraphs in the box'] = blocksOf(id).length;
        });

    await clickInto(long, TextElement.grabBand + 70);
    await typeInto(long.id, 'typing: near the top of a long box');
    await _measure('typing: Enter near the top of a long box', (run) async {
      final before = blocksOf(long.id).length;
      for (var i = 0; i < 6; i++) {
        await _timedKey(run, 'Enter', what: 'Enter');
        await wait(const Duration(milliseconds: 250));
        await _type('and so ', between: const Duration(milliseconds: 70));
      }
      if (blocksOf(long.id).length != before + 6) {
        throw const NotDriven('Enter did not start a paragraph each time');
      }
      run.counts['paragraphs in the box'] = before + 6;
    });
    // Ctrl+End: the caret to the end of the box, and the page with it.
    await _keys.press('End', control: true);
    await Frames.settled();
    await typeInto(long.id, 'typing: at the foot of a long box');
    await _toNormal();

    // Back to the top of the page, where the short box is: g, and g.
    await _command('g');
    await _keys.press('g');
    await Frames.settled();
    await clickInto(short, TextElement.grabBand + 20);
    await typeInto(short.id, 'typing: in a short box');
  }

  // --------------------------------------------------------------- searching

  /// Searching all the notes as the words are typed: each key until the
  /// pages found are listed, and until the best match is open and drawn.
  /// The search waits a quarter of a second for typing to pause, which is
  /// in every one of these times.
  Future<void> _search() async {
    await _show(notes.ordinary);
    await _command('/');
    if (!await _until(() => maybeFind<SearchLine>() != null)) {
      throw const NotDriven('/ did not open the search line');
    }
    await _field(box: false);
    await _measure('search: as the words are typed', (run) async {
      var typed = '';
      for (final character in 'schwingung energie'.split('')) {
        typed += character;
        final text = typed;
        final began = now();
        await _type(character, run: run, between: Duration.zero);
        final found = await Frames.shows(() {
          final results = container.read(searchResultsProvider);
          return container.read(searchQueryProvider) == text &&
              results.hasValue &&
              !results.isLoading;
        }, within: const Duration(seconds: 6));
        if (found == null) {
          throw NotDriven('the search for “$text” never listed its pages');
        }
        run
          ..shown('key to the pages found', began, found)
          ..shown('key to the best match drawn', began, await Frames.settled());
      }
      run.counts['pages found at the end'] =
          container.read(searchResultsProvider).value?.length ?? 0;
    });
  }

  /// Go to: opened, and a name typed into it, each key matched against
  /// every notebook, section and page.
  Future<void> _goTo() async {
    await _show(notes.ordinary);
    Future<void> open(Run run) async {
      final began = now();
      final shown = Frames.shows(
        () => maybeFind<Chooser>() != null,
        walks: true,
        within: const Duration(seconds: 5),
      );
      await _command('p', control: true);
      run.took('key handled in', (now() - began) / 1000);
      final frame = await shown;
      if (frame == null) throw const NotDriven('Ctrl+P did not open Go to');
      final listed = await Frames.shows(
        () => container.read(noteGraphProvider).hasValue,
        within: const Duration(seconds: 10),
      );
      run
        ..shown('key to first frame', began, frame)
        ..shown('key to the pages listed', began, listed)
        ..shown('key to settled', began, await Frames.settled());
    }

    // The first time glass floats in, in a window just opened, and again:
    // what the first costs alone is paid once a session.
    await _measure('goto: opened', open);
    await _command('Esc');
    await Frames.settled();
    await wait(const Duration(milliseconds: 300));
    await _measure('goto: opened again', open);
    await _field(box: false);
    await _measure('goto: a name typed', (run) async {
      await _type(
        'vorlesung 12 wellen',
        run: run,
        between: const Duration(milliseconds: 110),
      );
      run.counts['names matched against'] =
          container.read(noteGraphProvider).value?.nodes.length ?? 0;
    });
  }

  /// The picker: opened on a section of hundreds of pages, the cursor
  /// moved down its pages, and from section to section, each listing its
  /// pages.
  Future<void> _picker() async {
    await _show(notes.ordinary);
    await _measure('picker: opened', _openPicker);
    await _measure('picker: down the pages', (run) async {
      for (var i = 0; i < 25; i++) {
        await _timedKey(run, 'j');
        await wait(const Duration(milliseconds: 80));
      }
    });
    await _command('h');
    await Frames.settled();
    await _measure('picker: from section to section', (run) async {
      for (var i = 0; i < 12; i++) {
        final began = now();
        await _timedKey(run, 'j');
        run.shown('key to settled', began, await Frames.settled());
      }
    });
    await _command('Esc');
    await Frames.settled();
    await wait(const Duration(milliseconds: 300));
    await _measure('picker: opened again', _openPicker);
    await _command('Esc');
    await Frames.settled();
  }

  /// Opens the picker with its shortcut, Ctrl+Shift+E, noting in [run], if
  /// given, how long until it showed and until its columns were listed.
  Future<void> _openPicker([Run? run]) async {
    final began = now();
    final shown = Frames.shows(
      () => maybeFind<Picker>() != null,
      walks: true,
      within: const Duration(seconds: 5),
    );
    await _command('E', control: true);
    run?.took('key handled in', (now() - began) / 1000);
    final frame = await shown;
    if (frame == null) {
      throw const NotDriven('Ctrl+Shift+E did not open the picker');
    }
    final settled = await Frames.settled();
    run
      ?..shown('key to first frame', began, frame)
      ..shown('key to settled', began, settled);
  }

  // ------------------------------------------------------------- the library

  /// Renaming a page, making one and deleting one, in a section of
  /// hundreds, from the picker as a person does: how long until the window
  /// has settled, until the last list was read again, and how many were.
  Future<void> _library() async {
    await _show(notes.ordinary);
    await _openPicker();

    await _command('r');
    await _field(box: false);
    await _type(
      'Renamed in the benchmark',
      between: const Duration(milliseconds: 40),
    );
    await _measure('library: a page renamed', (run) async {
      reloads.reset();
      final began = now();
      await _enter();
      run.took('Enter handled in', (now() - began) / 1000);
      await _listsSettled(run, began, 'Enter');
      final page = await container.read(pageProvider(notes.ordinary).future);
      if (page?.title != 'Renamed in the benchmark') {
        throw const NotDriven('the page was not renamed');
      }
    });

    final pages = await _pagesInSection();
    await _command('n');
    if (!await _until(() => maybeFind<NewPageDialog>() != null)) {
      throw const NotDriven('n did not ask what page to make');
    }
    await Frames.settled();
    String? made;
    await _measure('library: a page made', (run) async {
      reloads.reset();
      final began = now();
      final shown = Frames.shows(() {
        final open = container.read(tabsProvider).current.pageId;
        return open != null && open != notes.ordinary && _shows(open);
      }, walks: true);
      await _keys.press('Enter');
      run.took('Enter handled in', (now() - began) / 1000);
      final frame = await shown;
      if (frame == null) throw const NotDriven('no page was made and opened');
      made = container.read(tabsProvider).current.pageId;
      run.shown('Enter to first frame of the page', began, frame);
      await _listsSettled(run, began, 'Enter');
      run.counts['pages in the section'] = pages + 1;
    });

    // The page just made is the one the picker opens on.
    await _toNormal();
    await _openPicker();
    await _measure('library: a page moved to the bin', (run) async {
      reloads.reset();
      final began = now();
      await _command('d');
      run.took('key handled in', (now() - began) / 1000);
      await _listsSettled(run, began, 'key');
      if (await _pagesInSection() != pages) {
        throw const NotDriven('d did not delete the page');
      }
      if (container.read(tabsProvider).current.pageId == made) {
        throw const NotDriven('the page deleted was still open');
      }
      run.counts['pages in the section'] = pages;
    });
  }

  Future<int> _pagesInSection() async {
    final store = await container.read(storeProvider.future);
    return (await store.pages.listPages(notes.section)).length;
  }

  /// Notes in [run] how long from [began] until the window settled and
  /// until the last list was read again, and how many lists were.
  Future<void> _listsSettled(Run run, int began, String from) async {
    run.shown('$from to settled', began, await Frames.settled());
    if (reloads.lastAt > began) {
      run.took(
        '$from to the last list read again',
        (reloads.lastAt - began) / 1000,
      );
    }
    run.counts.addAll(reloads.counts);
  }
}
