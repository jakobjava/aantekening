/// The keys of the modes: layers of keys, each running something or
/// opening the next layer — as vim's keys are, and as the guide shows them.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A key as the modes read it: the character typed — so `G` is Shift and
/// g, on whatever layout gives it — or the name of a key that types none,
/// such as `Space`, `Enter` or `Esc`, or a letter with Ctrl: `Ctrl+r`.
abstract final class ModeKey {
  static const String space = 'Space';
  static const String enter = 'Enter';
  static const String escape = 'Esc';
  static const String backspace = 'Backspace';
  static const String delete = 'Delete';
  static const String tab = 'Tab';
  static const String up = '↑';
  static const String down = '↓';
  static const String left = '←';
  static const String right = '→';

  static final Map<LogicalKeyboardKey, String> _named =
      <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.space: space,
        LogicalKeyboardKey.enter: enter,
        LogicalKeyboardKey.numpadEnter: enter,
        LogicalKeyboardKey.escape: escape,
        LogicalKeyboardKey.backspace: backspace,
        LogicalKeyboardKey.delete: delete,
        LogicalKeyboardKey.tab: tab,
        LogicalKeyboardKey.arrowUp: up,
        LogicalKeyboardKey.arrowDown: down,
        LogicalKeyboardKey.arrowLeft: left,
        LogicalKeyboardKey.arrowRight: right,
      };

  /// The key [event] presses, as the modes name it — or null for one they
  /// leave alone: a modifier alone, or a key with Alt or Meta, which the
  /// window's commands take.
  static String? of(KeyEvent event, HardwareKeyboard keyboard) {
    if (event is KeyUpEvent ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return null;
    }
    final key = event.logicalKey;
    if (keyboard.isControlPressed) {
      final label = _named[key] ?? key.keyLabel.toLowerCase();
      return label.length == 1 || _named.containsKey(key)
          ? 'Ctrl+$label'
          : null;
    }
    if (_named[key] case final named?) {
      return keyboard.isShiftPressed && named == tab ? 'Shift+$tab' : named;
    }
    final character = event.character;
    if (character == null || character.isEmpty) return null;
    // A control character — what some keys type — names no key here.
    if (character.codeUnitAt(0) < 0x20) return null;
    return character;
  }
}

/// What a key does in a layer: runs something, or opens a further layer.
@immutable
class KeyAction {
  const KeyAction(
    this.key,
    this.label, {
    this.run,
    this.layer,
    this.also = const <String>[],
    this.enabled = true,
    this.checked,
    this.preview,
    this.stays = false,
    this.waits = false,
  }) : assert(
         (run == null) != (layer == null),
         'A key runs something or opens a layer, not both',
       );

  /// The key, as [ModeKey.of] names it.
  final String key;

  /// Other keys that do the same: the arrows beside h, j, k and l.
  final List<String> also;

  final String label;
  final VoidCallback? run;

  /// The layer it opens, made as it is opened.
  final KeyLayer Function()? layer;

  /// Whether there is anything for it to act on just now.
  final bool enabled;

  /// Whether what it turns on is on; null for what is not turned on or off.
  final bool? checked;

  /// What it gives, drawn: a colour, a formula, a shape.
  final Widget? preview;

  /// Whether the layer stays once it has run, for running again: a size
  /// stepped up and up.
  final bool stays;

  /// Whether the layer it opens is shown only once the keys pause — the
  /// start of a sequence the hand mostly knows, as vim's `g` is — rather
  /// than at once.
  final bool waits;

  bool answers(String pressed) => key == pressed || also.contains(pressed);
}

/// Keys that belong together in a layer, under a name.
@immutable
class KeyGroup {
  const KeyGroup(this.actions, {this.title});

  final String? title;
  final List<KeyAction> actions;
}

/// A layer of keys: those that do something after the keys pressed so far.
@immutable
class KeyLayer {
  const KeyLayer(this.title, this.groups, {this.tiles = false});

  /// One layer of [actions], in one group.
  KeyLayer.of(String title, List<KeyAction> actions, {bool tiles = false})
    : this(title, <KeyGroup>[KeyGroup(actions)], tiles: tiles);

  /// What the layer is of, shown as the guide's title.
  final String title;

  final List<KeyGroup> groups;

  /// Whether its actions are shown as tiles of what they give — colours,
  /// shapes, formulas — rather than as a list of names.
  final bool tiles;

  Iterable<KeyAction> get actions => groups.expand((group) => group.actions);

  /// The action [pressed] runs here, if any.
  KeyAction? actionFor(String pressed) {
    for (final action in actions) {
      if (action.answers(pressed)) return action;
    }
    return null;
  }
}

/// Keys for the choices of a gallery, in order: the digits, then the
/// letters along the keyboard's rows, leaving out [taken].
List<String> galleryKeys(int count, {Set<String> taken = const <String>{}}) {
  const order = '1234567890qwertyuiopasdfghjklzxcvbnm';
  final keys = <String>[
    for (final key in order.split(''))
      if (!taken.contains(key)) key,
  ];
  // Beyond the plain keys, the same with Shift.
  keys.addAll(<String>[
    for (final key in order.split(''))
      if (key.toUpperCase() != key && !taken.contains(key.toUpperCase()))
        key.toUpperCase(),
  ]);
  return keys.take(count).toList();
}
