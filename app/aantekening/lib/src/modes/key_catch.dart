/// Taking keys straight from the keyboard, ahead of whatever has the focus:
/// for what is shown in answer to a key and must hear the next however
/// fast it follows — before it has even been drawn.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'mode_keys.dart';

/// Takes the keys [onKey] wants, as [ModeKey.of] names them, from the
/// moment it is made until [release] — and each of their lettings go, so
/// nothing else hears half of a key. They are taken ahead of the focus:
/// what has it, and the window's shortcuts, never see them.
///
/// Catches made one after another stack: only the latest hears the keys,
/// as the guide opened over the picker does, until it is released.
class KeyCatch {
  KeyCatch(this.onKey) {
    if (_stack.isEmpty) {
      _manager = FocusManager.instance..addEarlyKeyEventHandler(_dispatch);
    }
    _stack.add(this);
  }

  /// Takes [pressed], saying whether it did: what it does not take goes on
  /// to whatever has the focus.
  final bool Function(String pressed) onKey;

  /// The catches made and not yet released, the latest last.
  static final List<KeyCatch> _stack = <KeyCatch>[];

  /// What the catches take the keys ahead of, while any is made.
  static FocusManager? _manager;

  /// Whether a catch is taking the keys: the window's shortcuts leave them
  /// to it.
  static bool get active => _stack.isNotEmpty;

  final Set<PhysicalKeyboardKey> _held = <PhysicalKeyboardKey>{};

  /// The keys down as it was made — the one that made it, say, still on its
  /// way to the focus — which are not its to take until they are let go.
  final Set<PhysicalKeyboardKey> _before = Set<PhysicalKeyboardKey>.of(
    HardwareKeyboard.instance.physicalKeysPressed,
  );

  static KeyEventResult _dispatch(KeyEvent event) {
    if (event is KeyUpEvent) {
      // To whichever took the key as it went down.
      var taken = false;
      for (final each in List<KeyCatch>.of(_stack)) {
        each._before.remove(event.physicalKey);
        taken = each._held.remove(event.physicalKey) || taken;
      }
      return taken ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (_stack.isEmpty) return KeyEventResult.ignored;
    final top = _stack.last;
    if (top._before.contains(event.physicalKey)) return KeyEventResult.ignored;
    final pressed = ModeKey.of(event, HardwareKeyboard.instance);
    if (pressed == null || !top.onKey(pressed)) return KeyEventResult.ignored;
    top._held.add(event.physicalKey);
    return KeyEventResult.handled;
  }

  /// Lets the keys go to whatever has the focus again, or the catch made
  /// before this one.
  void release() {
    if (!_stack.remove(this) || _stack.isNotEmpty) return;
    _manager?.removeEarlyKeyEventHandler(_dispatch);
    _manager = null;
  }
}

/// Characters typed ahead of what is to take them — a field, a text box —
/// while it is on its way: kept until it is there, so the first letters
/// typed after the key that opens it are not lost. Enter is kept as a new
/// line.
class TypeAhead {
  TypeAhead() {
    _catch = KeyCatch(_take);
  }

  late final KeyCatch _catch;
  final StringBuffer _typed = StringBuffer();

  bool _take(String pressed) {
    if (pressed == ModeKey.backspace) {
      final typed = _typed.toString();
      _typed
        ..clear()
        ..write(typed.isEmpty ? '' : typed.substring(0, typed.length - 1));
    } else if (pressed == ModeKey.enter) {
      _typed.write('\n');
    } else if (pressed == ModeKey.space) {
      _typed.write(' ');
    } else if (pressed.length == 1) {
      _typed.write(pressed);
    } else {
      // Esc, an arrow, a key with Ctrl: for what takes the keys once it is
      // there.
      return false;
    }
    return true;
  }

  /// What was typed, the keys going where they go from now on.
  String take() {
    _catch.release();
    return _typed.toString();
  }
}
