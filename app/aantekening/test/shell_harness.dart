/// The whole window, opened in a test over a library of long names, in a
/// window of any size, its words at any size, light or dark — and what
/// floats over it opened by the keys, as the person opens it.
library;

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

/// Fills [store] with a library of long names and opens the window on a
/// page of it, [window] large, its words [scale] times their size.
Future<void> openLongLibrary(
  WidgetTester tester,
  AantekeningStore store,
  Size window, {
  double scale = 1,
  bool dark = false,
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
