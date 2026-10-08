/// Opening the page editor in a test, and typing and pressing keys in it the
/// way a desktop delivers them.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:aantekening/src/commands/command_keys.dart';
import 'package:aantekening/src/editor/page_editor.dart';
import 'package:aantekening/src/editor/text/text_box_controller.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Makes an in-memory store holding one empty page before each test, and
/// closes it after; [use] is told of each store and page as it is made. The
/// caret does not blink, so waiting for the page to settle does not wait on
/// it.
void useTestPage(void Function(AantekeningStore store, String pageId) use) {
  late AantekeningStore store;
  late Directory assets;
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    assets = Directory.systemTemp.createTempSync('aantekening_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    final notebook = await store.library.createNotebook(title: 'Notes');
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Section',
    );
    use(store, (await store.pages.createPage(sectionId: section.id)).id);
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });
}

/// The page editor over an in-memory workspace, filling a 1200×800 window.
Future<void> openEditor(
  WidgetTester tester,
  AantekeningStore store,
  String pageId, {
  Preferences? preferences,
  Size size = const Size(1200, 800),
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWith((ref) async => store),
        preferencesProvider.overrideWith(
          (ref) async => preferences ?? Preferences.inMemory(),
        ),
        _readAssetsAtOnce,
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: CommandKeys(
          child: Scaffold(body: PageEditor(pageId: pageId)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Reads pictures from the store at once. A read left waiting on the test's
/// fake clock keeps its file open, and Windows will not delete an open file
/// when the test clears its folder away.
final Override _readAssetsAtOnce = assetBytesProvider.overrideWith((
  ref,
  assetId,
) async {
  final store = await ref.watch(storeProvider.future);
  final asset = await store.assets.find(assetId);
  if (asset == null) return null;
  final file = store.assets.fileFor(asset);
  return file.existsSync() ? file.readAsBytesSync() : null;
});

/// A picture's file: one white pixel, as a PNG.
final Uint8List pngBytes = Uint8List.fromList(<int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  2,
  0,
  0,
  0,
  144,
  119,
  83,
  222,
  0,
  0,
  0,
  12,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  255,
  255,
  63,
  0,
  5,
  254,
  2,
  254,
  13,
  239,
  70,
  184,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

/// What formats the text on the page, as the menu and the keys do: shared
/// by every text box on it.
TextBoxEditorController pageText(WidgetTester tester) =>
    tester.widget<TextBoxEditor>(find.byType(TextBoxEditor).first).controller!;

/// Whether the caret is in a formula.
bool inFormula(WidgetTester tester) => pageText(tester).state.inFormula;

/// The one text box on the page.
TextBoxEditor textBox(WidgetTester tester) =>
    tester.widget<TextBoxEditor>(find.byType(TextBoxEditor));

List<TextBlock> blocksOf(WidgetTester tester) => textBox(tester).element.blocks;

String textOf(WidgetTester tester) =>
    blocksOf(tester).map((block) => block.plainText).join('\n');

/// Types [text] the way a desktop input method delivers it: a key event the
/// framework does not handle, then the character as an editing delta.
Future<void> type(WidgetTester tester, String text) async {
  for (final char in text.characters) {
    final key = _keyFor(char);
    if (key != null) await tester.sendKeyDownEvent(key, character: char);
    _sendDelta(tester, char);
    if (key != null) await tester.sendKeyUpEvent(key);
    await tester.pump();
  }
}

LogicalKeyboardKey? _keyFor(String char) {
  final lower = char.toLowerCase();
  if (lower.length == 1 &&
      lower.codeUnitAt(0) >= 0x61 &&
      lower.codeUnitAt(0) <= 0x7A) {
    return LogicalKeyboardKey(
      LogicalKeyboardKey.keyA.keyId + lower.codeUnitAt(0) - 0x61,
    );
  }
  if (char == ' ') return LogicalKeyboardKey.space;
  return null;
}

/// Sends the input method's replacement of the current selection by [text].
void _sendDelta(WidgetTester tester, String text) {
  final state = tester.testTextInput.editingState!;
  final old = state['text'] as String;
  final base = state['selectionBase'] as int;
  final extent = state['selectionExtent'] as int;
  final start = math.min(base, extent);
  final end = math.max(base, extent);
  final caret = start + text.length;
  final setClient = tester.testTextInput.log.lastWhere(
    (call) => call.method == 'TextInput.setClient',
  );
  final arguments = setClient.arguments as List<Object?>;
  final client = arguments[0]! as int;
  final configuration = arguments[1]! as Map<Object?, Object?>;

  // A plain text field, such as the formula panel's, takes whole values.
  if (configuration['enableDeltaModel'] != true) {
    final updated = old.replaceRange(start, end, text);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: caret),
      ),
    );
    tester.testTextInput.editingState = <String, dynamic>{
      ...state,
      'text': updated,
      'selectionBase': caret,
      'selectionExtent': caret,
      'composingBase': -1,
      'composingExtent': -1,
    };
    return;
  }

  final logged = tester.testTextInput.log.length;
  // Delivered at once: the message is handled before it returns.
  unawaited(
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.textInput.name,
          SystemChannels.textInput.codec.encodeMethodCall(
            MethodCall(
              'TextInputClient.updateEditingStateWithDeltas',
              <dynamic>[
                client,
                <String, dynamic>{
                  'deltas': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'oldText': old,
                      'deltaText': text,
                      'deltaStart': start,
                      'deltaEnd': end,
                      'selectionBase': caret,
                      'selectionExtent': caret,
                      'selectionAffinity': 'TextAffinity.downstream',
                      'selectionIsDirectional': false,
                      'composingBase': -1,
                      'composingExtent': -1,
                    },
                  ],
                },
              ],
            ),
          ),
          (_) {},
        ),
  );

  // A platform input method applies its own deltas, so it knows the new text
  // without being told; the editor only sends its state when that differs —
  // as when "$$" turns into a formula — and then what it sent stands.
  final resynced = tester.testTextInput.log
      .skip(logged)
      .any((call) => call.method == 'TextInput.setEditingState');
  if (resynced) return;
  tester.testTextInput.editingState = <String, dynamic>{
    ...state,
    'text': old.replaceRange(start, end, text),
    'selectionBase': caret,
    'selectionExtent': caret,
    'composingBase': -1,
    'composingExtent': -1,
  };
}

Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Clicks empty canvas, which starts a new text box there.
Future<void> startTextBox(WidgetTester tester) async {
  await tester.tapAt(const Offset(300, 300), kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

/// Stands in for the system clipboard, holding text as the platform would,
/// for the rest of the test.
void mockClipboard(WidgetTester tester) {
  String? held;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        held = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return held == null ? null : <String, Object?>{'text': held};
      case 'Clipboard.hasStrings':
        return <String, Object?>{'value': held?.isNotEmpty ?? false};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

/// Right-clicks at [position], as a mouse does.
Future<void> rightClick(WidgetTester tester, Offset position) async {
  await tester.tapAt(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

/// The keys that type each symbol the modes use, and whether with Shift.
final Map<String, (LogicalKeyboardKey, bool)> _symbolKeys =
    <String, (LogicalKeyboardKey, bool)>{
      ' ': (LogicalKeyboardKey.space, false),
      '[': (LogicalKeyboardKey.bracketLeft, false),
      ']': (LogicalKeyboardKey.bracketRight, false),
      '/': (LogicalKeyboardKey.slash, false),
      '?': (LogicalKeyboardKey.slash, true),
      ':': (LogicalKeyboardKey.semicolon, true),
      r'$': (LogicalKeyboardKey.digit4, true),
      '+': (LogicalKeyboardKey.equal, true),
      '=': (LogicalKeyboardKey.equal, false),
      '-': (LogicalKeyboardKey.minus, false),
      '<': (LogicalKeyboardKey.comma, true),
      '>': (LogicalKeyboardKey.period, true),
      ',': (LogicalKeyboardKey.comma, false),
      '.': (LogicalKeyboardKey.period, false),
    };

/// Presses the key that types [character], as a keyboard delivers it: a
/// capital, or a symbol on a shifted key, with Shift held.
Future<void> typeKey(WidgetTester tester, String character) async {
  await _sendKey(tester, character);
  await tester.pump();
}

/// Types [keys] faster than a frame: one after another, nothing drawn
/// between them, as fingers that know the keys do.
Future<void> typeKeysAtOnce(WidgetTester tester, String keys) async {
  for (final character in keys.split('')) {
    await _sendKey(tester, character);
  }
}

/// Sends the key that types [character], as [typeKey] does, drawing
/// nothing after it.
Future<void> _sendKey(WidgetTester tester, String character) async {
  final LogicalKeyboardKey key;
  final bool shift;
  if (_symbolKeys[character] case (final symbol, final shifted)) {
    (key, shift) = (symbol, shifted);
  } else {
    final lower = character.toLowerCase();
    final code = lower.codeUnitAt(0);
    final letter = code >= 0x61 && code <= 0x7a;
    key = letter
        ? LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + code - 0x61)
        : LogicalKeyboardKey(
            LogicalKeyboardKey.digit0.keyId + int.parse(character),
          );
    shift = character != lower;
  }
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key, character: character);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

/// Types [keys] one after another, as [typeKey] does each.
Future<void> typeKeys(WidgetTester tester, String keys) async {
  for (final character in keys.split('')) {
    await typeKey(tester, character);
  }
  await tester.pumpAndSettle();
}
