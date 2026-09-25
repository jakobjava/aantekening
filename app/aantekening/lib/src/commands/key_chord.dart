/// A key pressed with modifiers, as a shortcut is written and saved.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A key and the modifiers held with it: Ctrl+Shift+P.
@immutable
class KeyChord {
  const KeyChord(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// The chord of [event], or null for a modifier pressed alone.
  static KeyChord? fromEvent(KeyEvent event, HardwareKeyboard keyboard) {
    final key = _canonical(event.logicalKey);
    if (_modifiers.contains(key)) return null;
    return KeyChord(
      key,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  /// Whether it can be caught wherever the keyboard is — even in the
  /// middle of typing — without taking a letter: Ctrl, Alt or Meta is held,
  /// or it is a function key.
  bool get worksAnywhere =>
      control || alt || meta || _functionKeys.contains(key);

  SingleActivator get activator => SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );

  /// Whether [event] is this chord being pressed.
  bool accepts(KeyEvent event, HardwareKeyboard keyboard) =>
      event is! KeyUpEvent && fromEvent(event, keyboard) == this;

  /// How it is written: "Ctrl+Shift+P".
  String get label => <String>[
    if (control) 'Ctrl',
    if (meta) 'Meta',
    if (alt) 'Alt',
    if (shift) 'Shift',
    keyName(key),
  ].join('+');

  /// How it is saved: its modifiers' initials and its key's id,
  /// "cs:112" — the same on every keyboard layout.
  String encode() =>
      '${control ? 'c' : ''}${shift ? 's' : ''}${alt ? 'a' : ''}'
      '${meta ? 'm' : ''}:${key.keyId}';

  /// What [encode] wrote, or null if it is not a chord.
  static KeyChord? decode(Object? saved) {
    if (saved is! String) return null;
    final colon = saved.indexOf(':');
    if (colon < 0) return null;
    final id = int.tryParse(saved.substring(colon + 1));
    if (id == null) return null;
    final modifiers = saved.substring(0, colon);
    return KeyChord(
      LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id),
      control: modifiers.contains('c'),
      shift: modifiers.contains('s'),
      alt: modifiers.contains('a'),
      meta: modifiers.contains('m'),
    );
  }

  /// The name of [key] on the keycap, or near enough.
  static String keyName(LogicalKeyboardKey key) =>
      _names[key] ?? (key.keyLabel.isEmpty ? '?' : key.keyLabel.toUpperCase());

  static final Map<LogicalKeyboardKey, String> _names =
      <LogicalKeyboardKey, String>{
        LogicalKeyboardKey.arrowUp: 'Up',
        LogicalKeyboardKey.arrowDown: 'Down',
        LogicalKeyboardKey.arrowLeft: 'Left',
        LogicalKeyboardKey.arrowRight: 'Right',
        LogicalKeyboardKey.pageUp: 'Page Up',
        LogicalKeyboardKey.pageDown: 'Page Down',
        LogicalKeyboardKey.equal: '=',
        LogicalKeyboardKey.minus: '−',
        LogicalKeyboardKey.add: '+',
        LogicalKeyboardKey.numpadAdd: 'Num +',
        LogicalKeyboardKey.numpadSubtract: 'Num −',
        LogicalKeyboardKey.comma: ',',
        LogicalKeyboardKey.period: '.',
        LogicalKeyboardKey.slash: '/',
        LogicalKeyboardKey.backslash: '\\',
        LogicalKeyboardKey.bracketLeft: '[',
        LogicalKeyboardKey.bracketRight: ']',
        LogicalKeyboardKey.semicolon: ';',
        LogicalKeyboardKey.quote: "'",
        LogicalKeyboardKey.backquote: '`',
        LogicalKeyboardKey.space: 'Space',
        LogicalKeyboardKey.tab: 'Tab',
        LogicalKeyboardKey.enter: 'Enter',
        LogicalKeyboardKey.escape: 'Esc',
        LogicalKeyboardKey.backspace: 'Backspace',
        LogicalKeyboardKey.delete: 'Delete',
        LogicalKeyboardKey.home: 'Home',
        LogicalKeyboardKey.end: 'End',
      };

  /// Left and right modifiers are one key as far as a chord goes.
  static LogicalKeyboardKey _canonical(LogicalKeyboardKey key) =>
      LogicalKeyboardKey.collapseSynonyms(<LogicalKeyboardKey>{key}).single;

  static final Set<LogicalKeyboardKey> _functionKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  };

  static final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.altGraph,
  };

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);

  @override
  String toString() => label;
}
