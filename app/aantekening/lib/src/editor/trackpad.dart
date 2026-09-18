/// How touchpad scrolling is scaled on each platform.
library;

import 'dart:io';
import 'dart:ui' show PlatformDispatcher, PointerData;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Whether to print the input that reaches the app and every change of view
/// with what made it: run with `AANTEKENING_TRACE_INPUT=1` to see what a
/// trackpad or wheel actually sends.
final bool traceInput =
    !kIsWeb && (Platform.environment['AANTEKENING_TRACE_INPUT'] ?? '') == '1';

/// Prints every pointer event as the engine delivers it, before the
/// framework has converted or routed it, and every key event, when
/// [traceInput] is on. Called once the binding exists.
void installInputTrace() {
  if (!traceInput) return;
  final dispatcher = PlatformDispatcher.instance;
  final handle = dispatcher.onPointerDataPacket;
  dispatcher.onPointerDataPacket = (packet) {
    for (final data in packet.data) {
      traceLine(_describePointer(data));
    }
    handle?.call(packet);
  };
  HardwareKeyboard.instance.addHandler((event) {
    traceLine(
      'key ${event.timeStamp.inMicroseconds} ${event.runtimeType} '
      '${event.logicalKey.debugName} '
      'pressed=${HardwareKeyboard.instance.logicalKeysPressed.map((key) => key.debugName).join('+')}',
    );
    return false;
  });
}

/// Writes one line of the input trace, unthrottled so the order is exact.
void traceLine(String line) => stdout.writeln('input $line');

String _describePointer(PointerData data) {
  String pair(double x, double y) =>
      '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
  return 'ptr ${data.timeStamp.inMicroseconds} ${data.change.name} '
      '${data.kind.name} signal=${data.signalKind?.name} '
      'device=${data.device} id=${data.pointerIdentifier} '
      'at=${pair(data.physicalX, data.physicalY)} '
      'pan=${pair(data.panX, data.panY)} '
      'panDelta=${pair(data.panDeltaX, data.panDeltaY)} '
      'scale=${data.scale.toStringAsFixed(4)} '
      'rotation=${data.rotation.toStringAsFixed(4)} '
      'scroll=${pair(data.scrollDeltaX, data.scrollDeltaY)} '
      'buttons=${data.buttons} synthesized=${data.synthesized}';
}

/// Describes where a change of view came from: the first few calls in the
/// app and canvas packages that led to it.
String traceCaller() {
  final frames = StackTrace.current
      .toString()
      .split('\n')
      .where(
        (line) =>
            line.contains('package:aantekening') &&
            !line.contains('trackpad.dart') &&
            !line.contains('_onCanvasChanged'),
      )
      .take(4)
      .map((line) => line.replaceFirst(RegExp(r'^#\d+\s+'), '').trim());
  return frames.join(' < ');
}
