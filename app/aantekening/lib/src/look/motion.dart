/// How the interface moves: what floats in settles into place with a
/// little give, what goes fades quickly, and the focus glides from one
/// thing to the next — all as fast as chosen in the settings, and not at
/// all where the system asks for less motion.
library;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'tones.dart';

/// The speed the interface moves at, and the durations and curves it moves
/// by.
@immutable
class Motion extends ThemeExtension<Motion> {
  const Motion(this.speed);

  /// A multiple of the usual speed; 0 for none at all.
  final double speed;

  /// A colour or a highlight changing: hover, a press, a mode.
  static const Duration quick = Duration(milliseconds: 140);

  /// Something floating in — a menu, a dialog, the guide — or the focus
  /// moving to the next thing.
  static const Duration settle = Duration(milliseconds: 260);

  /// Something floating away.
  static const Duration leave = Duration(milliseconds: 140);

  /// Settles with a little give past where it is going, and back.
  static const Curve lively = Cubic(0.3, 1.25, 0.5, 1);

  /// Slows to a stop, without going past.
  static const Curve ease = Curves.easeOutCubic;

  bool get still => speed == 0;

  /// [base] at this speed: none while [still].
  Duration of(Duration base) => still ? Duration.zero : base * (1 / speed);

  @override
  Motion copyWith({double? speed}) => Motion(speed ?? this.speed);

  @override
  Motion lerp(Motion? other, double t) => t < 0.5 ? this : other ?? this;
}

extension MotionAccess on BuildContext {
  /// How the interface moves here: still wherever the system asks for less
  /// motion, whatever is chosen.
  Motion get motion {
    if (MediaQuery.maybeDisableAnimationsOf(this) ?? false) {
      return const Motion(0);
    }
    return Theme.of(this).extension<Motion>() ?? const Motion(1);
  }
}

/// Shows the dialog [builder] makes — on [Glass], as every one is — over
/// [context]: it settles in over the window, which shows through it.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final motion = context.motion;
  final tones = context.tones;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: tones.scrim.withValues(alpha: 0.04),
    transitionDuration: motion.of(Motion.settle),
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) =>
        FloatingIn(animation: animation, child: child),
  );
}

/// [child], a pane of [Glass], floating in as [animation] runs: fading in
/// and growing the last little way to its size, with a little give. The
/// glass fades in by itself, its frost coming as it does
/// ([GlassArriving]): faded as a whole, what lies beneath it would be drawn
/// again, blurred, every frame.
class FloatingIn extends StatelessWidget {
  const FloatingIn({
    required this.animation,
    required this.child,
    this.alignment = Alignment.center,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;

  /// Where it grows from.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(
      parent: animation,
      curve: Motion.lively,
      reverseCurve: Curves.easeIn,
    );
    return GlassArriving(
      arriving: CurvedAnimation(
        parent: animation,
        curve: Motion.ease,
        reverseCurve: Curves.easeIn,
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(grow),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// Messages along the foot of the window, on glass.
extension AppMessages on ScaffoldMessengerState {
  /// Says [message] along the foot of the window, with [action], if given,
  /// beside it — named as its label says. It goes by itself after a while.
  void showMessage(
    String message, {
    ({String label, VoidCallback run})? action,
  }) {
    final motion = context.motion;
    showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        persist: false,
        content: _Message(
          message: message,
          action: action == null
              ? null
              : (
                  label: action.label,
                  run: () {
                    hideCurrentSnackBar();
                    action.run();
                  },
                ),
        ),
      ),
      snackBarAnimationStyle: AnimationStyle(
        duration: motion.of(Motion.settle),
        reverseDuration: motion.of(Motion.leave),
      ),
    );
  }

  /// Says [message] in place of what was said before, with a way to [undo]
  /// what it tells of.
  void showUndoable(String message, VoidCallback undo) {
    hideCurrentSnackBar();
    showMessage(message, action: (label: 'Undo', run: undo));
  }
}

/// A message on glass, and what can be done about it.
class _Message extends StatelessWidget {
  const _Message({required this.message, this.action});

  final String message;
  final ({String label, VoidCallback run})? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Glass(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, action == null ? 16 : 6, 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  style: TextStyle(color: context.tones.text),
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: action.run, child: Text(action.label)),
          ],
        ),
      ),
    );
  }
}

/// Pages that fade into each other, as fast as the interface moves.
class FadingPageTransitions extends PageTransitionsBuilder {
  const FadingPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => context.motion.still
      ? child
      : FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Motion.ease),
          child: child,
        );
}
