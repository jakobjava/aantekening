/// How the pen draws: steadying its line, what its buttons do, and shapes.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/pen_preferences.dart';
import '../look/controls.dart';
import 'settings_view.dart';

/// The pen page of the settings.
class PenSettingsPage extends ConsumerStatefulWidget {
  const PenSettingsPage({super.key});

  @override
  ConsumerState<PenSettingsPage> createState() => _PenSettingsPageState();
}

class _PenSettingsPageState extends ConsumerState<PenSettingsPage> {
  /// The button last pressed with the pen over the page, to tell which is
  /// which: true for the first, false for the second.
  bool? _pressed;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.stylus) return;
    final pressed = event.buttons & kPrimaryStylusButton != 0
        ? true
        : event.buttons & kSecondaryStylusButton != 0
        ? false
        : null;
    if (pressed != null) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final pen = ref.watch(penPreferencesProvider);
    final change = ref.read(penPreferencesProvider.notifier);

    Widget button({required bool first}) => SettingRow(
      label: first ? 'First button' : 'Second button',
      description: _pressed == first ? 'Just pressed' : null,
      child: ChoiceRow<PenButtonAction>(
        choices: PenButtonAction.values,
        selected: first ? pen.buttons.first : pen.buttons.second,
        labelOf: (action) => action.label,
        onSelected: (action) => change.setButton(first: first, action: action),
      ),
    );

    return Listener(
      onPointerDown: _onPointerDown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSection(
            title: 'Smoothing',
            description:
                'The line trails the pen a little, as if pulled along on a '
                'string, so a shaking hand draws it steady; it catches up '
                'where the pen lifts. The stronger, the steadier, and the '
                'rounder small letters come out.',
            children: <Widget>[
              SettingRow(
                label: 'Smoothing',
                child: ChoiceRow<PenSmoothing>(
                  choices: PenSmoothing.values,
                  selected: pen.smoothing,
                  labelOf: (smoothing) => smoothing.label,
                  onSelected: change.setSmoothing,
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Buttons',
            description:
                'What the pen does touching the page with a button held, '
                'whatever tool is in hand. Press a button with the pen over '
                'this page to see which it is. The other end of a pen, '
                'where it has one, always erases.',
            children: <Widget>[button(first: true), button(first: false)],
          ),
          SettingsSection(
            title: 'Shapes',
            children: <Widget>[
              CheckRow(
                title: 'Hold the pen still to make a shape',
                description:
                    'Held still for half a second at the end of a stroke, '
                    'the stroke becomes the line, arrow or outline it was '
                    'drawn as, and the pen then reshapes it until it lifts.',
                value: pen.shapesOnHold,
                onChanged: change.setShapesOnHold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
