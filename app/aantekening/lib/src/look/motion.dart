/// The interface does not move: menus, dialogs, messages and pages appear
/// and go at once, rather than sliding, growing or fading.
library;

import 'package:flutter/material.dart';

/// Shows the dialog [builder] makes over [context], at once.
Future<T?> showPlainDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: AnimationStyle.noAnimation,
);

/// Messages along the foot of the window that appear and go at once.
extension PlainMessages on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showPlainSnackBar(
    SnackBar snackBar,
  ) => showSnackBar(
    snackBar,
    snackBarAnimationStyle: AnimationStyle.noAnimation,
  );
}

/// Pages that replace each other at once.
class PlainPageTransitions extends PageTransitionsBuilder {
  const PlainPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
