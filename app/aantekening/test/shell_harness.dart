/// The whole window, opened in a test over a library of long names, in a
/// window of any size, its words at any size, light or dark — and what
/// floats over it opened by the keys, as the person opens it.
library;

import 'dart:math' as math;

import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the window is drawn, for a picture of it to be taken.
final GlobalKey windowKey = GlobalKey(debugLabel: 'window');

/// Each thing that floats over the page, and the keys that open it.
final Map<String, List<LogicalKeyboardKey>> panes =
    <String, List<LogicalKeyboardKey>>{
      'the page alone': <LogicalKeyboardKey>[],
      'the picker': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyE,
      ],
      'Go to': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyP,
      ],
      'Commands': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyP,
      ],
      'the menu': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.space,
      ],
      'the search line': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyF,
      ],
      'the graph': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.keyG,
      ],
      'the AI': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyJ,
      ],
      'settings': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.comma,
      ],
      'the keyboard shortcuts': <LogicalKeyboardKey>[LogicalKeyboardKey.f1],
      'a new page': <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyN,
      ],
    };

/// The system a window of [size] is on, for a test to run as on it: a
/// phone's is Android, the rest the desktop's — with no handles to drag
/// text by, say.
TargetPlatformVariant platformFor(Size size) => TargetPlatformVariant.only(
  size.width < 600 ? TargetPlatform.android : TargetPlatform.linux,
);

/// Fills [store] with a library of long names and opens the window on a
/// page of it, [window] large, its words [scale] times their size.
Future<void> openLongLibrary(
  WidgetTester tester,
  AantekeningStore store,
  Size window, {
  double scale = 1,
  bool dark = false,
  PageDocument Function(String pageId)? contents,
}) async {
  final notebook = await store.library.createNotebook(
    title: 'Theoretische natuurkunde en wiskundige methoden',
  );
  final section = await store.library.createSection(
    notebookId: notebook.id,
    title: 'Klassieke mechanica, Lagrange en Hamilton',
  );
  for (var i = 0; i < 12; i++) {
    await store.pages.createPage(
      sectionId: section.id,
      title: 'Hoorcollege $i: behoudswetten en symmetrieën van Noether',
    );
  }
  final page = await store.pages.createPage(
    sectionId: section.id,
    title: 'Een pagina met een titel die veel te lang is voor één regel',
  );
  await store.pages.saveDocument(
    page.id,
    contents?.call(page.id) ??
        PageDocument.empty(id: page.id).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 40, y: 120, width: 500, height: 80),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('F = ma, en de rest volgt.')],
          ),
        ),
  );

  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final preferences = Preferences.inMemory(<String, Object?>{
    'tabs': <Object?>[
      <String, Object?>{
        'notebook': notebook.id,
        'section': section.id,
        'page': page.id,
      },
    ],
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: windowKey,
      child: ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          preferencesProvider.overrideWith((ref) async => preferences),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const HomeShell(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Presses [keys] together, as a chord: each but the last held while the
/// last is pressed.
Future<void> pressChord(
  WidgetTester tester,
  List<LogicalKeyboardKey> keys,
) async {
  if (keys.isEmpty) return;
  for (final key in keys.take(keys.length - 1)) {
    await tester.sendKeyDownEvent(key);
  }
  await tester.sendKeyEvent(keys.last);
  for (final key in keys.take(keys.length - 1).toList().reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pumpAndSettle();
}

/// A page holding something of every kind there is: headings, lists, to-dos,
/// code, a quotation, a formula in the line, a TikZ picture, handwriting.
PageDocument richPage(String pageId) {
  const now = 0;
  return PageDocument(
    id: pageId,
    elements: <NoteElement>[
      const TextElement(
        id: 'text',
        frame: Frame(x: 40, y: 110, width: 560, height: 520),
        createdAt: now,
        updatedAt: now,
        blocks: <TextBlock>[
          TextBlock(
            kind: TextBlockKind.heading1,
            runs: <TextRun>[TextRun('Golven')],
          ),
          TextBlock(
            runs: <TextRun>[
              TextRun('Een golf '),
              TextRun.math(r'y = A \sin(kx - \omega t)', MathMode.latex),
              TextRun(' plant zich voort met '),
              TextRun('fasesnelheid', TextMarks(bold: true)),
              TextRun(' en '),
              TextRun('groepssnelheid', TextMarks(italic: true)),
              TextRun('.'),
            ],
          ),
          TextBlock(
            kind: TextBlockKind.heading2,
            runs: <TextRun>[TextRun('Soorten')],
          ),
          TextBlock(
            kind: TextBlockKind.bulleted,
            runs: <TextRun>[TextRun('Transversaal: licht, snaren')],
          ),
          TextBlock(
            kind: TextBlockKind.bulleted,
            indent: 1,
            runs: <TextRun>[TextRun('gepolariseerd of niet')],
          ),
          TextBlock(
            kind: TextBlockKind.bulleted,
            runs: <TextRun>[TextRun('Longitudinaal: geluid')],
          ),
          TextBlock(
            kind: TextBlockKind.numbered,
            runs: <TextRun>[TextRun('Leid de golfvergelijking af')],
          ),
          TextBlock(
            kind: TextBlockKind.numbered,
            runs: <TextRun>[TextRun('Los haar op met scheiding')],
          ),
          TextBlock(
            kind: TextBlockKind.todo,
            checked: true,
            runs: <TextRun>[TextRun('Opgaven 1 tot 4')],
          ),
          TextBlock(
            kind: TextBlockKind.todo,
            runs: <TextRun>[TextRun('Opgave 5')],
          ),
          TextBlock(
            kind: TextBlockKind.quote,
            runs: <TextRun>[TextRun('Alles stroomt. — Heraclitus')],
          ),
          TextBlock(
            kind: TextBlockKind.code,
            runs: <TextRun>[TextRun('omega = 2 * pi * f')],
          ),
        ],
      ),
      const TikzElement(
        id: 'tikz',
        frame: Frame(x: 660, y: 120, width: 260, height: 160),
        createdAt: now,
        updatedAt: now,
        source:
            r'\begin{tikzpicture}\draw[->] (0,0) -- (3,0) node[right] {$x$};'
            r'\draw[thick,blue] (0,0) sin (0.75,1) cos (1.5,0) sin (2.25,-1)'
            r' cos (3,0);\end{tikzpicture}',
      ),
      InkElement(
        id: 'ink',
        frame: const Frame(x: 660, y: 330, width: 260, height: 120),
        createdAt: now,
        updatedAt: now,
        strokes: <InkStroke>[
          for (var line = 0; line < 3; line++)
            InkStroke.fromPoints(
              tool: InkTool.pen,
              color: line == 1 ? 0xFFD32F2F : 0xFF1A1A1A,
              width: 2.5,
              xs: <double>[for (var i = 0; i <= 40; i++) 670.0 + i * 6],
              ys: <double>[
                for (var i = 0; i <= 40; i++)
                  350.0 + line * 35 + 12 * math.sin(i / 3 + line),
              ],
              pressures: <double>[
                for (var i = 0; i <= 40; i++) 0.4 + 0.5 * (i % 7) / 7,
              ],
            ),
        ],
      ),
    ],
  );
}
