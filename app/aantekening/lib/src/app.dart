/// The application root.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'look/appearance.dart';
import 'look/theme.dart';
import 'preferences.dart';
import 'shell/home_shell.dart';

/// The root widget.
class AantekeningApp extends ConsumerWidget {
  const AantekeningApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nothing is drawn until the appearance chosen is known, so the window
    // does not open in one and change to another.
    if (ref.watch(preferencesProvider).isLoading) return const SizedBox();
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'aantekening',
      debugShowCheckedModeBanner: false,
      themeMode: appearance.mode,
      theme: AppTheme.build(appearance, Brightness.light),
      darkTheme: AppTheme.build(appearance, Brightness.dark),
      // Scroll behaviour is widened so that the canvas and the navigation panes
      // respond to a trackpad and a stylus, not only to a mouse wheel.
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) =>
          InterfaceScale(scale: appearance.scale, child: child!),
      home: const HomeShell(),
    );
  }
}

/// Draws [child] [scale] times the size it is laid out at, all of it —
/// menus, dialogs and the page among it — as a browser zooms a page.
class InterfaceScale extends StatelessWidget {
  const InterfaceScale({required this.scale, required this.child, super.key});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final media = MediaQuery.of(context);
    final size = media.size / scale;
    return MediaQuery(
      data: media.copyWith(
        size: size,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}

/// Registers the licence of the typefaces the interface is set in.
void registerFontLicence() => LicenseRegistry.addLicense(() async* {
  yield LicenseEntryWithLineBreaks(<String>[
    InterfaceFont.sans.family,
    InterfaceFont.mono.family,
  ], await rootBundle.loadString('fonts/OFL.txt'));
});

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
