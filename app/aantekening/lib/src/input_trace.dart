/// Printing the input that reaches the app, to see what a trackpad or a
/// wheel actually sends.
library;

import 'dart:io';
import 'dart:ui' show PlatformDispatcher, PointerData;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// Prints each change of the view [controller] shows, how far it moved and
/// what moved it, when [traceInput] is on. Returns what stops it.
VoidCallback traceViewOf(CanvasController controller) {
  if (!traceInput) return () {};
  var before = controller.viewport;
  void trace() {
    final view = controller.viewport;
    if (view == before) return;
    final moved = view.toScreen(before.origin);
    before = view;
    traceLine(
      'view origin=(${view.origin.dx.toStringAsFixed(1)}, '
      '${view.origin.dy.toStringAsFixed(1)}) '
      'zoom=${view.zoom.toStringAsFixed(4)} '
      'moved=(${moved.dx.toStringAsFixed(1)}, ${moved.dy.toStringAsFixed(1)}) '
      'by ${traceCaller()}',
    );
  }

  controller.addListener(trace);
  return () => controller.removeListener(trace);
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
            !line.contains('input_trace.dart'),
      )
      .take(4)
      .map((line) => line.replaceFirst(RegExp(r'^#\d+\s+'), '').trim());
  return frames.join(' < ');
}
