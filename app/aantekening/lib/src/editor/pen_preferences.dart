/// How the pen draws: how much its line is steadied, what its buttons do,
/// and whether holding it still makes a shape.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// How much the line of a pen is steadied: how far, in screen pixels, it
/// trails the pen (see [CanvasController.inkSmoothing]).
enum PenSmoothing {
  off('Off', 0),
  light('Light', 3),
  medium('Medium', 6),
  strong('Strong', 12);

  const PenSmoothing(this.label, this.pixels);

  final String label;
  final double pixels;
}

/// How the pen draws, kept for this person on this machine.
@immutable
class PenPreferences {
  const PenPreferences({
    this.smoothing = PenSmoothing.off,
    this.buttons = const PenButtons(),
    this.shapesOnHold = true,
  });

  final PenSmoothing smoothing;
  final PenButtons buttons;

  /// Whether a stroke held still at its end becomes the shape it was drawn
  /// as.
  final bool shapesOnHold;
}

/// The pen's preferences, read from and saved to [Preferences].
class PenPreferencesController extends Notifier<PenPreferences> {
  static const String _smoothing = 'pen.smoothing';
  static const String _firstButton = 'pen.firstButton';
  static const String _secondButton = 'pen.secondButton';
  static const String _shapesOnHold = 'pen.shapesOnHold';

  @override
  PenPreferences build() {
    const defaults = PenPreferences();
    T named<T extends Enum>(String key, List<T> values, T fallback) {
      final name = ref.preference(key);
      return values.where((value) => value.name == name).firstOrNull ??
          fallback;
    }

    return PenPreferences(
      smoothing: named(_smoothing, PenSmoothing.values, defaults.smoothing),
      buttons: PenButtons(
        first: named(
          _firstButton,
          PenButtonAction.values,
          defaults.buttons.first,
        ),
        second: named(
          _secondButton,
          PenButtonAction.values,
          defaults.buttons.second,
        ),
      ),
      shapesOnHold: ref.preference(_shapesOnHold) != false,
    );
  }

  void setSmoothing(PenSmoothing smoothing) {
    state = PenPreferences(
      smoothing: smoothing,
      buttons: state.buttons,
      shapesOnHold: state.shapesOnHold,
    );
    ref.savePreference(_smoothing, smoothing.name);
  }

  /// Gives the pen's [first] or second button [action].
  void setButton({required bool first, required PenButtonAction action}) {
    final buttons = state.buttons;
    state = PenPreferences(
      smoothing: state.smoothing,
      buttons: PenButtons(
        first: first ? action : buttons.first,
        second: first ? buttons.second : action,
      ),
      shapesOnHold: state.shapesOnHold,
    );
    ref.savePreference(first ? _firstButton : _secondButton, action.name);
  }

  void setShapesOnHold(bool on) {
    state = PenPreferences(
      smoothing: state.smoothing,
      buttons: state.buttons,
      shapesOnHold: on,
    );
    ref.savePreference(_shapesOnHold, on ? null : false);
  }
}

final penPreferencesProvider =
    NotifierProvider<PenPreferencesController, PenPreferences>(
      PenPreferencesController.new,
    );
