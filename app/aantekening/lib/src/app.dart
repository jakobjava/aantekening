/// The application root.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell/home_shell.dart';
import 'theme.dart';

/// The root widget.
class AantekeningApp extends ConsumerWidget {
  const AantekeningApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'aantekening',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Scroll behaviour is widened so that the canvas and the navigation panes
      // respond to a trackpad and a stylus, not only to a mouse wheel.
      scrollBehavior: const _AppScrollBehavior(),
      home: const HomeShell(),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
