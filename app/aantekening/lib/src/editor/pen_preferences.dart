/// How the pen draws: how much its line is steadied, what its buttons do,
/// and whether holding it still makes a shape; and the pen and the
/// highlighter as they were last set, for the next page to be drawn on
/// with.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
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

/// The pen and the highlighter as they were last set — colour, width, how
/// the pen's line is drawn and what its shapes are filled with — kept for
/// this person on this machine, so that every page is drawn on with the
/// pen the last one was.
typedef InkPens = ({PenSettings pen, PenSettings highlighter});

class InkPensController extends PreferenceNotifier<InkPens> {
  @override
  String get key => 'pen.ink';

  static const InkPens _usual = (
    pen: PenSettings.defaultPen,
    highlighter: PenSettings.defaultHighlighter,
  );

  @override
  InkPens decode(Object? saved) {
    if (saved is! Map) return _usual;
    PenSettings read(Object? kept, PenSettings usual) {
      if (kept is! Map) return usual;
      final color = kept['color'];
      final width = kept['width'];
      final fill = kept['fill'];
      final highlighter = usual.tool == InkTool.highlighter;
      return PenSettings(
        tool: usual.tool,
        color: color is int ? color : usual.color,
        width: width is num && width > 0 && width <= 200
            ? width.toDouble()
            : usual.width,
        pressureSensitive: usual.pressureSensitive,
        line: highlighter
            ? InkLine.solid
            : InkLine.values.asNameMap()[kept['line']] ?? InkLine.solid,
        fill: !highlighter && fill is int ? fill : null,
      );
    }

    return (
      pen: read(saved['pen'], _usual.pen),
      highlighter: read(saved['highlighter'], _usual.highlighter),
    );
  }

  @override
  Object? encode(InkPens value) {
    if (value == _usual) return null;
    Map<String, Object?> write(PenSettings pen) => <String, Object?>{
      'color': pen.color,
      'width': pen.width,
      if (pen.line != InkLine.solid) 'line': pen.line.name,
      if (pen.fill != null) 'fill': pen.fill,
    };
    return <String, Object?>{
      'pen': write(value.pen),
      'highlighter': write(value.highlighter),
    };
  }

  /// Keeps [pen] and [highlighter] as the ones to draw with from now on.
  void keep(PenSettings pen, PenSettings highlighter) {
    if (state.pen == pen && state.highlighter == highlighter) return;
    save((pen: pen, highlighter: highlighter));
  }
}

final inkPensProvider = NotifierProvider<InkPensController, InkPens>(
  InkPensController.new,
);
