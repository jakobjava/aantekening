/// Jump labels: a letter or two over everything on the page in view, typed
/// to go to it — as Vimium does a page's links.
library;

import 'package:flutter/material.dart';

import '../look/appearance.dart';
import '../modes/key_catch.dart';
import '../modes/mode_keys.dart';

/// The labels for [count] things, in the order given: a letter each while
/// there are letters enough — those under the fingers first — else two
/// each, so no label starts another.
List<String> jumpLabels(int count) {
  const letters = 'asdfjklghqwertyuiopzxcvbnm';
  if (count <= letters.length) return letters.split('').take(count).toList();
  return <String>[
    for (final first in letters.split(''))
      for (final second in letters.split('')) '$first$second',
  ].take(count).toList();
}

/// Something the labels are over: its id, and where it is, in the
/// labels' coordinates.
typedef JumpTarget = ({String id, Rect rect});

/// Labels showing over [targets], taking the letters typed straight from
/// the keyboard — so none is lost, however fast it follows — and narrowing
/// them down until one is left, which [onPicked] is told of. Esc, or a
/// letter no label has, gives up, telling [onDone]. Backspace takes back a
/// letter.
class Jump extends ChangeNotifier {
  Jump({required this.targets, required this.onPicked, required this.onDone})
    : labels = jumpLabels(targets.length) {
    _catch = KeyCatch(_press);
  }

  final List<JumpTarget> targets;
  final List<String> labels;
  final ValueChanged<String> onPicked;
  final VoidCallback onDone;
  late final KeyCatch _catch;

  /// The letters typed so far.
  String get typed => _typed;
  String _typed = '';

  bool _press(String pressed) {
    if (pressed == ModeKey.backspace && _typed.isNotEmpty) {
      _typed = _typed.substring(0, _typed.length - 1);
      notifyListeners();
      return true;
    }
    final typed = '$_typed$pressed';
    final matching = <int>[
      for (var i = 0; i < labels.length; i++)
        if (labels[i].startsWith(typed)) i,
    ];
    if (matching.isEmpty || pressed.length != 1) {
      end();
      onDone();
    } else if (matching.length == 1 && labels[matching.single] == typed) {
      end();
      onPicked(targets[matching.single].id);
    } else {
      _typed = typed;
      notifyListeners();
    }
    return true;
  }

  /// Stops taking the keys.
  void end() => _catch.release();
}

/// A label over each of [jump]'s targets, those the letters typed have
/// ruled out gone.
class JumpLabels extends StatelessWidget {
  const JumpLabels({required this.jump, required this.colour, super.key});

  final Jump jump;

  /// What the labels are drawn in: the mode's colour.
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final on = ThemeData.estimateBrightnessForColor(colour) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    return ListenableBuilder(
      listenable: jump,
      builder: (context, _) => Stack(
        children: <Widget>[
          for (var i = 0; i < jump.targets.length; i++)
            if (jump.labels[i].startsWith(jump.typed))
              Positioned(
                left: jump.targets[i].rect.left - 4,
                top: jump.targets[i].rect.top - 4,
                child: _Label(
                  label: jump.labels[i],
                  typed: jump.typed.length,
                  colour: colour,
                  on: on,
                ),
              ),
        ],
      ),
    );
  }
}

/// One label: the letters still to type bright, those typed faded.
class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.typed,
    required this.colour,
    required this.on,
  });

  final String label;
  final int typed;
  final Color colour;
  final Color on;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // A drop of the mode's colour, glowing a little.
    decoration: BoxDecoration(
      color: colour,
      borderRadius: const BorderRadius.all(Radius.circular(9)),
      boxShadow: <BoxShadow>[
        BoxShadow(color: colour.withValues(alpha: 0.5), blurRadius: 6),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: label.substring(0, typed),
              style: TextStyle(color: on.withValues(alpha: 0.45)),
            ),
            TextSpan(text: label.substring(typed)),
          ],
        ),
        style: TextStyle(
          fontFamily: InterfaceFont.mono.family,
          fontSize: 12,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: on,
        ),
      ),
    ),
  );
}
