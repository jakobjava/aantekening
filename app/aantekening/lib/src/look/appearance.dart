/// How the interface looks, as chosen in the settings: light or dark, the
/// colours of each, the one accent if there is one, the typeface and the
/// size — remembered between sessions.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The typefaces the interface can be set in. Both are bundled, so the app
/// looks the same everywhere; notes keep their own fonts whichever is
/// chosen.
enum InterfaceFont {
  sans('Sans', 'IBM Plex Sans'),
  mono('Mono', 'IBM Plex Mono');

  const InterfaceFont(this.label, this.family);

  final String label;
  final String family;
}

/// A background and the text on it, from which every other shade of the
/// interface is mixed.
@immutable
class ColourPair {
  const ColourPair(this.name, this.base, this.text);

  final String name;
  final Color base;
  final Color text;

  ColourPair withBase(Color base) => ColourPair('', base, text);

  ColourPair withText(Color text) => ColourPair('', base, text);

  /// How far apart the two are in lightness, from 1 (the same) to 21
  /// (black on white).
  double get contrast => contrastBetween(base, text);

  /// Whether the text is too faint on the base to read comfortably.
  bool get hardToRead => contrast < 4.5;

  @override
  bool operator ==(Object other) =>
      other is ColourPair && other.base == base && other.text == text;

  @override
  int get hashCode => Object.hash(base, text);
}

/// Everything about how the interface looks.
@immutable
class Appearance {
  const Appearance({
    this.mode = ThemeMode.system,
    this.light = defaultLight,
    this.dark = defaultDark,
    this.accent = defaultAccent,
    this.accentOn = false,
    this.font = InterfaceFont.sans,
    this.scale = 1,
  });

  /// Light, dark, or as the system is set.
  final ThemeMode mode;

  /// The colours in light mode.
  final ColourPair light;

  /// The colours in dark mode.
  final ColourPair dark;

  /// The accent, kept while it is switched off so switching it back on
  /// brings the same one back.
  final Color accent;

  /// Whether the accent is used; without it the interface is its two
  /// colours alone.
  final bool accentOn;

  final InterfaceFont font;

  /// How large everything is drawn, 1 being as designed.
  final double scale;

  static const ColourPair defaultLight = ColourPair(
    'White',
    Color(0xFFFFFFFF),
    Color(0xFF111111),
  );
  static const ColourPair defaultDark = ColourPair(
    'Ink',
    Color(0xFF141414),
    Color(0xFFE8E8E8),
  );
  static const Color defaultAccent = Color(0xFF2F6FEB);

  /// Pairs offered for light mode, the first being where it starts.
  static const List<ColourPair> lightPresets = <ColourPair>[
    defaultLight,
    ColourPair('Paper', Color(0xFFF4F2EC), Color(0xFF1D1B17)),
    ColourPair('Grey', Color(0xFFE8E8E8), Color(0xFF121212)),
    ColourPair('Mist', Color(0xFFEEF1F4), Color(0xFF16202A)),
  ];

  /// Pairs offered for dark mode, the first being where it starts.
  static const List<ColourPair> darkPresets = <ColourPair>[
    defaultDark,
    ColourPair('Black', Color(0xFF000000), Color(0xFFDADADA)),
    ColourPair('Slate', Color(0xFF1C1F24), Color(0xFFD5D9E0)),
    ColourPair('Umber', Color(0xFF1E1B18), Color(0xFFE6DFD3)),
  ];

  /// Accents offered, the first being where it starts.
  static const List<({String name, Color color})> accentPresets =
      <({String name, Color color})>[
        (name: 'Blue', color: defaultAccent),
        (name: 'Red', color: Color(0xFFD1362F)),
        (name: 'Orange', color: Color(0xFFD9731A)),
        (name: 'Green', color: Color(0xFF2E8B57)),
        (name: 'Teal', color: Color(0xFF138A8A)),
        (name: 'Violet', color: Color(0xFF7B5CE0)),
      ];

  /// The sizes offered.
  static const List<double> scales = <double>[0.9, 1, 1.1, 1.25, 1.5];

  /// The colours of [brightness]'s mode.
  ColourPair pairFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The accent in use, or null for none.
  Color? get accentInUse => accentOn ? accent : null;

  Appearance copyWith({
    ThemeMode? mode,
    ColourPair? light,
    ColourPair? dark,
    Color? accent,
    bool? accentOn,
    InterfaceFont? font,
    double? scale,
  }) => Appearance(
    mode: mode ?? this.mode,
    light: light ?? this.light,
    dark: dark ?? this.dark,
    accent: accent ?? this.accent,
    accentOn: accentOn ?? this.accentOn,
    font: font ?? this.font,
    scale: scale ?? this.scale,
  );

  /// This appearance with [brightness]'s colours changed to [pair].
  Appearance withPair(Brightness brightness, ColourPair pair) =>
      brightness == Brightness.dark
      ? copyWith(dark: pair)
      : copyWith(light: pair);

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'light': _pairToJson(light),
    'dark': _pairToJson(dark),
    'accent': accent.toARGB32(),
    'accentOn': accentOn,
    'font': font.name,
    'scale': scale,
  };

  /// Reads what [toJson] wrote, leniently: what is missing or not understood
  /// is left as it starts.
  static Appearance fromJson(Object? json) {
    if (json is! Map) return const Appearance();
    const start = Appearance();
    return Appearance(
      mode: ThemeMode.values.asNameMap()[json['mode']] ?? start.mode,
      light: _pairFromJson(json['light'], Appearance.lightPresets),
      dark: _pairFromJson(json['dark'], Appearance.darkPresets),
      accent: switch (json['accent']) {
        final int argb => Color(argb | 0xFF000000),
        _ => start.accent,
      },
      accentOn: json['accentOn'] == true,
      font: InterfaceFont.values.asNameMap()[json['font']] ?? start.font,
      scale: switch (json['scale']) {
        final num scale when scales.contains(scale.toDouble()) =>
          scale.toDouble(),
        _ => start.scale,
      },
    );
  }

  static Map<String, Object?> _pairToJson(ColourPair pair) => <String, Object?>{
    'base': pair.base.toARGB32(),
    'text': pair.text.toARGB32(),
  };

  /// A pair read back, named after the preset it is, if it is one.
  static ColourPair _pairFromJson(Object? json, List<ColourPair> presets) {
    if (json case {'base': final int base, 'text': final int text}) {
      final pair = ColourPair(
        '',
        Color(base | 0xFF000000),
        Color(text | 0xFF000000),
      );
      return presets.where((preset) => preset == pair).firstOrNull ?? pair;
    }
    return presets.first;
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.mode == mode &&
      other.light == light &&
      other.dark == dark &&
      other.accent == accent &&
      other.accentOn == accentOn &&
      other.font == font &&
      other.scale == scale;

  @override
  int get hashCode =>
      Object.hash(mode, light, dark, accent, accentOn, font, scale);
}

/// The appearance chosen, saved as it changes.
class AppearanceController extends Notifier<Appearance> {
  static const String _key = 'appearance';

  @override
  Appearance build() => Appearance.fromJson(ref.preference(_key));

  void update(Appearance Function(Appearance appearance) change) {
    final changed = change(state);
    if (changed == state) return;
    state = changed;
    ref.savePreference(
      _key,
      changed == const Appearance() ? null : changed.toJson(),
    );
  }

  /// Switches to dark mode from light, or to light from dark — [showing]
  /// being the one showing, which with the system's mode only it knows.
  void toggleBrightness(Brightness showing) => update(
    (appearance) => appearance.copyWith(
      mode: showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    ),
  );

  void reset() => update((_) => const Appearance());
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);

// ------------------------------------------------------------------ colour

/// The contrast between two colours as WCAG measures it, from 1 to 21.
double contrastBetween(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [colour], made lighter or darker as it needs to be until it stands out
/// against [background] by at least [contrast], its hue kept.
Color readableOn(Color colour, Color background, {double contrast = 3}) {
  if (contrastBetween(colour, background) >= contrast) return colour;
  final hsl = HSLColor.fromColor(colour);
  final towardsLight = background.computeLuminance() < 0.5;
  var lightness = hsl.lightness;
  for (var step = 0; step < 40; step++) {
    lightness = (lightness + (towardsLight ? 0.025 : -0.025)).clamp(0.0, 1.0);
    final adjusted = hsl.withLightness(lightness).toColor();
    if (contrastBetween(adjusted, background) >= contrast) return adjusted;
  }
  return towardsLight ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
}
