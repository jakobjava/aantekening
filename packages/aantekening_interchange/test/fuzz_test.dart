import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every importer, given a file damaged in every way a file is damaged —
/// bytes flipped, cut short, runs of bytes overwritten, repeated — reads
/// what it can or says it cannot, and finishes soon either way: it never
/// hangs, so an import can always be left.
///
/// `AANTEKENING_FUZZ=5000 dart test test/fuzz_test.dart` tries more.
void main() {
  final rounds =
      int.tryParse(Platform.environment['AANTEKENING_FUZZ'] ?? '') ?? 60;
  late Directory folder;

  setUpAll(() => folder = Directory.systemTemp.createTempSync('fuzz_'));
  tearDownAll(() => folder.deleteSync(recursive: true));

  final xournal = gzip.encode(
    utf8.encode(
      '<?xml version="1.0" standalone="no"?>'
      '<xournal creator="xournalpp 1.2.2" fileversion="4">'
      '<title>Xournal++ document</title>'
      '<page width="600" height="800">'
      '<background type="solid" color="#ffffffff" style="lined"/>'
      '<layer><stroke tool="pen" color="#ff0000ff" width="1.5 1.5 0.6">'
      '10 20 30 40 50 60</stroke>'
      '<text font="Sans" size="12" x="20" y="30" color="#000000ff">Hi'
      '</text></layer></page></xournal>',
    ),
  );
  final latex = utf8.encode(r'''
\documentclass{article}
\usepackage{amsmath,tikz}
\title{Waves}
\begin{document}
\section{Sound}
A wave $y = A \sin(kx - \omega t)$ travels, and
\begin{align}
  v &= f\lambda \\ E &= \frac{1}{2} m v^2
\end{align}
\begin{itemize}\item one \item two\end{itemize}
\begin{tikzpicture}\draw (0,0) -- (1,1) node[above] {$x$};\end{tikzpicture}
\end{document}
''');
  final onenote = File(
    p.join('test', 'fixtures', 'onenote-2016', 'OneWithFileData.one'),
  ).readAsBytesSync();

  final cases = <(String, String, List<int>)>[
    ('Xournal++', 'xopp', xournal),
    ('LaTeX', 'tex', latex),
    ('OneNote', 'one', onenote),
  ];

  for (final (name, extension, original) in cases) {
    test('$name reads damaged files and always finishes', () async {
      final random = math.Random(name.hashCode);
      final outcomes = <String, int>{};
      for (var round = 0; round < rounds; round++) {
        final damaged = _damage(Uint8List.fromList(original), random);
        final path = p.join(folder.path, '$name-$round.$extension');
        File(path).writeAsBytesSync(damaged);
        // Traced, the file read last is kept where it can be found again,
        // should reading it bring the whole process down — as running out
        // of memory does.
        if (Platform.environment['AANTEKENING_FUZZ_TRACE'] != null) {
          File(path).copySync(_kept('last', extension));
          stderr.writeln('$name round $round');
        }
        final outcome = await _readBounded(
          name,
          path,
          p.join(folder.path, 'work-$name-$round'),
        );
        expect(
          outcome,
          isNot('timeout'),
          reason:
              '$name hung on a damaged file, kept as '
              '${_kept('hung', extension)} (round $round)',
        );
        if (outcome == 'timeout') {
          // Kept, to be read again under a debugger.
          File(
            path,
          ).copySync(p.join(Directory.systemTemp.path, 'hung.$extension'));
        }
        outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
        File(path).deleteSync();
      }
      printOnFailure('$outcomes');
      if (Platform.environment['AANTEKENING_FUZZ'] != null) {
        stdout.writeln('$name: $outcomes');
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

/// Where a damaged file that went wrong is kept, to be read again.
String _kept(String what, String extension) =>
    p.join(Directory.systemTemp.path, 'aantekening-fuzz-$what.$extension');

/// [bytes] damaged one way or several.
Uint8List _damage(Uint8List bytes, math.Random random) {
  var data = bytes;
  final times = 1 + random.nextInt(4);
  for (var i = 0; i < times && data.isNotEmpty; i++) {
    switch (random.nextInt(5)) {
      case 0: // flip bits
        for (var j = 0; j < 1 + random.nextInt(8); j++) {
          final at = random.nextInt(data.length);
          data[at] ^= 1 << random.nextInt(8);
        }
      case 1: // cut short
        data = Uint8List.sublistView(data, 0, random.nextInt(data.length));
      case 2: // overwrite a run with random bytes
        final at = random.nextInt(data.length);
        final end = math.min(data.length, at + 1 + random.nextInt(64));
        for (var j = at; j < end; j++) {
          data[j] = random.nextInt(256);
        }
      case 3: // overwrite a run with extreme values, as lengths go wrong
        final at = random.nextInt(data.length);
        final end = math.min(data.length, at + 4);
        final value = random.nextBool() ? 0xFF : 0x00;
        for (var j = at; j < end; j++) {
          data[j] = value;
        }
      default: // repeat a run
        final at = random.nextInt(data.length);
        final end = math.min(data.length, at + 1 + random.nextInt(256));
        data = Uint8List.fromList(<int>[
          ...data.sublist(0, end),
          ...data.sublist(at, end),
          ...data.sublist(end),
        ]);
    }
  }
  return Uint8List.fromList(data);
}

/// Reads [path] with the importer [name] in an isolate of its own, given
/// at most a few seconds: 'read', 'refused' — it said it could not — or
/// 'timeout'.
Future<String> _readBounded(String name, String path, String work) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_read, (port.sendPort, name, path, work));
  try {
    return await port.first.timeout(
          const Duration(seconds: 20),
          onTimeout: () => 'timeout',
        )
        as String;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _read((SendPort, String, String, String) message) {
  final (port, name, path, work) = message;
  final NotesImporter importer = switch (name) {
    'Xournal++' => const XournalImporter(),
    'LaTeX' => const LatexImporter(),
    _ => const OneNoteImporter(),
  };
  final directory = Directory(work)..createSync(recursive: true);
  try {
    importer.read(<String>[path], ImportWork(directory));
    Isolate.exit(port, 'read');
  } on Object {
    // Any failure is a refusal the import says: what matters is that it
    // ends.
    Isolate.exit(port, 'refused');
  }
}
