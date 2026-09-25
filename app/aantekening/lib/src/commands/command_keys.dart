/// Catching the shortcuts that work wherever the keyboard is.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'key_chord.dart';
import 'shortcuts.dart';

/// Runs the command each shortcut with Ctrl, Alt or Meta — or each
/// function key — is bound to, wherever the keyboard is beneath [child]
/// (so long as typing does not take it, see [caughtAnywhere]):
/// in a text box, in a field, or nowhere at all, as it is once the panel
/// that had it goes with the tab left.
///
/// The keys are taken from the keyboard itself rather than through the
/// focus, so a command runs once however the focus lies; not while a
/// dialog is over [child].
class CommandKeys extends ConsumerStatefulWidget {
  const CommandKeys({required this.child, this.onChord, super.key});

  final Widget child;

  /// Asked first about each chord, saying whether it took it: for keys
  /// that are not a command's, such as Alt and a digit for a tab.
  final bool Function(KeyChord chord)? onChord;

  @override
  ConsumerState<CommandKeys> createState() => _CommandKeysState();
}

class _CommandKeysState extends ConsumerState<CommandKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    final chord = KeyChord.fromEvent(event, HardwareKeyboard.instance);
    if (chord == null || !caughtAnywhere(chord)) return false;
    if (widget.onChord?.call(chord) ?? false) return true;
    final command = ref.read(shortcutsProvider).commandFor(chord);
    return command != null && ref.read(commandHandlersProvider).run(command);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
