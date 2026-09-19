/// How touchpad scrolling is scaled on each platform.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// How far the page moves per pixel of pan a touchpad reports, so that it
/// follows the fingers.
///
/// Flutter on Linux multiplies the desktop's smooth-scroll deltas by 53, a
/// factor taken from Chromium for mouse wheels, while GTK has already scaled
/// touchpad movement down: by 10 under Wayland, and to the X server's scroll
/// increment of 15 under X11. Two-finger scrolling there moves the page three
/// to five times as far as the fingers go. Elsewhere pans are finger distance.
/// See the engine's shell/platform/linux/fl_scrolling_manager.cc.
double trackpadPanScale({
  TargetPlatform? platform,
  Map<String, String>? environment,
}) {
  if (kIsWeb) return 1;
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.linux) return 1;
  final env = environment ?? Platform.environment;
  final backend = env['GDK_BACKEND'] ?? '';
  final wayland =
      (env['WAYLAND_DISPLAY'] ?? '').isNotEmpty && !backend.startsWith('x11');
  return wayland ? 10 / 53 : 15 / 53;
}
