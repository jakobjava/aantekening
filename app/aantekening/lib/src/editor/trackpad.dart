/// The touchpad's quirks: how far its scrolling goes, and where the platform
/// says its gestures happened.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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

/// Aims scrolling and touchpad gestures at the pointer, wherever they are
/// reported.
///
/// GTK reports a wheel turn, a two-finger scroll or a pinch at the place last
/// clicked rather than at the pointer, so scrolling or zooming over the page
/// after a click on the ribbon was delivered to the ribbon, which neither
/// scrolls nor zooms: the page did nothing until it was clicked. Moving each
/// of those to the pointer before it is routed hands it to whatever the
/// pointer is over, as every desktop does.
///
/// Only what the mouse itself reports — its hovering, its presses — says
/// where the pointer is; a scroll or a gesture never does, since that is the
/// reading in question.
class TrackpadAim {
  Offset? _pointer;
  int? _view;

  /// Notes where [event] happened and hands back the event to route: a
  /// scroll or a touchpad gesture aimed at the pointer, anything else
  /// unchanged.
  ///
  /// Only a gesture's start is moved; the framework routes the rest of a
  /// gesture to wherever its start went.
  PointerEvent aim(PointerEvent event) {
    switch (event) {
      case PointerPanZoomStartEvent():
        // Built afresh rather than with copyWith, which leaves out the
        // pointer's id: the framework files a gesture's target under that id
        // and looks it up for each update, which then went nowhere.
        return _atPointer(
          event,
          ({required Offset position}) => PointerPanZoomStartEvent(
            viewId: event.viewId,
            timeStamp: event.timeStamp,
            device: event.device,
            pointer: event.pointer,
            position: position,
            embedderId: event.embedderId,
            synthesized: event.synthesized,
          ),
        );
      case PointerScrollEvent():
        return _atPointer(event, event.copyWith);
      case PointerScaleEvent():
        return _atPointer(event, event.copyWith);
      case PointerHoverEvent() ||
              PointerDownEvent() ||
              PointerMoveEvent() ||
              PointerUpEvent()
          when event.kind == PointerDeviceKind.mouse:
        _pointer = event.position;
        _view = event.viewId;
        return event;
      case PointerRemovedEvent() when event.kind == PointerDeviceKind.mouse:
        _pointer = null;
        _view = null;
        return event;
      case _:
        return event;
    }
  }

  /// [event] moved to where the pointer is, or as it is where that is not
  /// known, or where it is in another window.
  PointerEvent _atPointer(
    PointerEvent event,
    PointerEvent Function({required Offset position}) moved,
  ) {
    final at = _pointer;
    return at == null || at == event.position || _view != event.viewId
        ? event
        : moved(position: at);
  }
}

/// The binding the app runs on: the usual one, with the touchpad's gestures
/// aimed at the pointer ([TrackpadAim]).
class AantekeningBinding extends WidgetsFlutterBinding {
  static AantekeningBinding? _instance;

  final TrackpadAim _aim = TrackpadAim();

  /// Starts the binding, or hands back the one already running.
  static WidgetsBinding ensureInitialized() =>
      _instance ??= AantekeningBinding();

  @override
  void handlePointerEvent(PointerEvent event) =>
      super.handlePointerEvent(_aim.aim(event));
}
