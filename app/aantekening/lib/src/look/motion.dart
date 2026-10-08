/// How the interface moves: what floats in settles into place with a
/// little give, what goes fades quickly, and the focus glides from one
/// thing to the next — all as fast as chosen in the settings, and not at
/// all where the system asks for less motion.
library;

import 'dart:ui' as ui;

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

/// Shows the dialog [builder] makes over [context]: it settles in over the
/// window, which frosts behind it while what floats is frosted — unless it
/// is glass itself, [overGlass], which the window shows through.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool overGlass = false,
}) {
  final motion = context.motion;
  final tones = context.tones;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: overGlass ? tones.scrim.withValues(alpha: 0.04) : tones.scrim,
    transitionDuration: motion.of(Motion.settle),
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) => FloatingIn(
      animation: animation,
      frostsBehind: tones.frosted && !overGlass,
      glass: overGlass,
      child: child,
    ),
  );
}

/// [child] floating in as [animation] runs: fading in and growing the last
/// little way to its size, with a little give — and, with [frostsBehind],
/// frosting what lies behind it as it comes. A [glass] child fades in by
/// itself, its frost coming as it does ([GlassArriving]): faded as a whole,
/// what lies beneath it would be drawn again, blurred, every frame.
class FloatingIn extends StatelessWidget {
  const FloatingIn({
    required this.animation,
    required this.child,
    this.frostsBehind = false,
    this.glass = false,
    this.alignment = Alignment.center,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final bool frostsBehind;

  /// Whether [child] is a pane of [Glass], which fades in by itself.
  final bool glass;

  /// Where it grows from.
  final Alignment alignment;

  /// How far behind it is blurred, once it is in.
  static const double _frost = 6;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: Motion.ease,
      reverseCurve: Curves.easeIn,
    );
    final grow = CurvedAnimation(
      parent: animation,
      curve: Motion.lively,
      reverseCurve: Curves.easeIn,
    );
    final grown = ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(grow),
      alignment: alignment,
      child: child,
    );
    final floating = glass
        ? GlassArriving(arriving: fade, child: grown)
        : FadeTransition(opacity: fade, child: grown);
    if (!frostsBehind) return floating;
    return AnimatedBuilder(
      animation: fade,
      child: floating,
      builder: (context, floating) => fade.value == 0
          ? floating!
          : BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: _frost * fade.value,
                sigmaY: _frost * fade.value,
              ),
              child: floating,
            ),
    );
  }
}

/// Messages along the foot of the window.
extension AppMessages on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    SnackBar snackBar,
  ) {
    final motion = context.motion;
    return showSnackBar(
      snackBar,
      snackBarAnimationStyle: AnimationStyle(
        duration: motion.of(Motion.settle),
        reverseDuration: motion.of(Motion.leave),
      ),
    );
  }

  /// Says [message] in place of what was said before, with a way to [undo]
  /// what it tells of. It goes by itself after a while, as any message
  /// does: one with an action otherwise stays until it is closed.
  void showUndoable(String message, VoidCallback undo) {
    hideCurrentSnackBar();
    showAppSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
        persist: false,
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
