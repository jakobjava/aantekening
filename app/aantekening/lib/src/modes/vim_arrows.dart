/// h, j, k and l as the arrow keys, as in vim, wherever there are rows to
/// go between — and letters still, wherever something is typed in.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Moves the keyboard from one thing to the next beneath [child] with h, j,
/// k and l, as the arrow keys do: left, down, up and right. While a field
/// beneath it has the keyboard, they are typed instead.
class VimArrows extends StatelessWidget {
  const VimArrows({required this.child, super.key});

  final Widget child;

  static const Map<String, TraversalDirection> _directions =
      <String, TraversalDirection>{
        'h': TraversalDirection.left,
        'j': TraversalDirection.down,
        'k': TraversalDirection.up,
        'l': TraversalDirection.right,
      };

  /// Whether what has the keyboard is typed in.
  static bool _typing(FocusNode? focus) =>
      focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final direction = _directions[event.character];
    final focus = FocusManager.instance.primaryFocus;
    if (direction == null || focus == null || _typing(focus)) {
      return KeyEventResult.ignored;
    }
    focus.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: child,
  );
}
