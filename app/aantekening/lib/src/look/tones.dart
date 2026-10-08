/// The shades of the interface, every one mixed from its two colours — the
/// base and the text — and the accent, if there is one.
library;

import 'package:flutter/material.dart';

import 'appearance.dart';

/// The colours of the interface by what they are for.
///
/// Everything drawn around the notes takes its colour from here, so the
/// interface is one colour and its text, in shades between them, and at
/// most one accent. Without an accent, what an accent would mark — the tab
/// showing, the row picked, the button pressed in — is marked in the text's
/// colour instead. What floats over the page is [glass]: the base, frosted
/// and let through a little, or solid where it is not [frosted].
@immutable
class Tones extends ThemeExtension<Tones> {
  Tones({
    required this.base,
    required this.text,
    Color? accent,
    this.frosted = true,
  }) : accent = accent == null ? null : _readable(accent, base),
       pane = _mix(base, text, 0.035),
       hover = _mix(base, text, 0.06),
       pressed = _mix(base, text, 0.11),
       line = _mix(base, text, 0.13),
       strongLine = _mix(base, text, 0.32),
       faint = _mix(base, text, 0.42),
       muted = _mix(base, text, 0.7),
       selection = _mix(base, text, 0.09),
       emphasis = accent == null ? text : _readable(accent, base),
       paperEmphasis = _paperEmphasisOf(accent);

  /// [accent], made light or dark enough to read on [base] — and on the
  /// glass over it, which in the dark lets the white paper through grey,
  /// so there it is made lighter still.
  static Color _readable(Color accent, Color base) => readableOn(
    accent,
    base,
    contrast: base.computeLuminance() < 0.5 ? 5.5 : 3,
  );

  static Color _paperEmphasisOf(Color? accent) => accent == null
      ? const Color(0xFF1A1A1A)
      : readableOn(accent, paper, contrast: 3.5);

  /// The tones of [appearance] in [brightness].
  factory Tones.of(Appearance appearance, Brightness brightness) {
    final pair = appearance.pairFor(brightness);
    return Tones(
      base: pair.base,
      text: pair.text,
      accent: appearance.accentInUse,
      frosted: appearance.frosted,
    );
  }

  /// The paper pages are written on, which stays white in dark mode too.
  static const Color paper = Color(0xFFFFFFFF);

  /// What everything is drawn on.
  final Color base;

  /// Whether what floats is frosted glass, or solid.
  final bool frosted;

  /// Text, and whatever is drawn as text is.
  final Color text;

  /// The accent, made to stand out against [base], or null for none.
  final Color? accent;

  /// Behind the panes beside the page, a shade off [base].
  final Color pane;

  /// What sheets of paper lie on, for a page shown as pages: dark enough
  /// that white paper stands out on it, touched with the accent.
  Color get desk => Color.alphaBlend(
    (accent ?? text).withValues(alpha: 0.08),
    _mix(base, text, 0.1),
  );

  /// Behind what the pointer is over.
  final Color hover;

  /// Behind what is being pressed.
  final Color pressed;

  /// Lines between things.
  final Color line;

  /// The edges of fields and of buttons with an outline.
  final Color strongLine;

  /// Text of what cannot be used just now.
  final Color faint;

  /// Text that says less: hints, counts, shortcuts, paths.
  final Color muted;

  /// Behind what is picked: the row chosen, the tab showing — the same in
  /// any accent, which marks it with a drop of its own ([emphasis]).
  final Color selection;

  /// What marks what is picked or pressed in: the accent, or the text.
  final Color emphasis;

  /// What marks things on the white paper of a page, where [emphasis] may
  /// not show: the accent darkened as it needs to be, or near-black. The
  /// caret, a link, the formula being edited and a word spelled wrongly are
  /// drawn in it.
  final Color paperEmphasis;

  /// Behind text selected on the page.
  Color get paperSelection => paperEmphasis.withValues(alpha: 0.2);

  /// Behind the formula being edited, and round it.
  Color get paperFill =>
      Color.alphaBlend(paperEmphasis.withValues(alpha: 0.07), paper);
  Color get paperOutline =>
      Color.alphaBlend(paperEmphasis.withValues(alpha: 0.4), paper);

  /// Behind words a search found on the page.
  Color get paperMatch => paperEmphasis.withValues(alpha: 0.24);

  /// What floats over the page — the status line, the guide, the picker —
  /// is filled with: the base, touched with the accent, let through over
  /// the notes blurred beneath it where it is [frosted].
  Color get glass {
    if (!frosted) return base;
    // Clear as liquid glass, a little denser in the dark: over the white
    // paper it is still dark.
    return base.withValues(alpha: brightness == Brightness.dark ? 0.5 : 0.3);
  }

  /// What is picked, or where the keys are, among what floats: a little
  /// more of the glass's light — the same in any accent, which marks it
  /// with a drop of its own.
  Color get lift => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.1)
      : text.withValues(alpha: 0.07);

  /// What the pointer is over, among what floats.
  Color get veil => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.06)
      : text.withValues(alpha: 0.04);

  /// What a menu or a dialog is filled with: the base, or in the dark a
  /// shade lighter, as what is nearer the light is.
  Color get raised =>
      brightness == Brightness.dark ? _mix(base, text, 0.06) : base;

  /// The fine line round what floats, setting it off what lies beneath.
  Color get glassRim =>
      text.withValues(alpha: brightness == Brightness.dark ? 0.2 : 0.08);

  /// The light caught along the edge of the glass, where it is brightest.
  Color get glassLight => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.4)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.95);

  /// The sheen across the top of the glass.
  Color get glassSheen => brightness == Brightness.dark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.07)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.4);

  /// The shadow what floats casts on the page.
  Color get shadow =>
      const Color(0xFF000000)
          .withValues(alpha: brightness == Brightness.dark ? 0.4 : 0.14);

  /// Over the window, behind a dialog.
  Color get scrim =>
      text.withValues(alpha: brightness == Brightness.dark ? 0.1 : 0.14);

  /// The shadows what floats casts: a soft one far out, and a close one
  /// that sets its edge off the page.
  List<BoxShadow> get floatingShadows => <BoxShadow>[
    BoxShadow(color: shadow, blurRadius: 32, offset: const Offset(0, 12)),
    BoxShadow(
      color: shadow.withValues(alpha: shadow.a / 2),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  /// Text on [emphasis].
  Color get onEmphasis => contrastBetween(emphasis, base) >= 3
      ? base
      : (emphasis.computeLuminance() > 0.4
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF));

  Brightness get brightness => ThemeData.estimateBrightnessForColor(base);

  /// [text] and [base] mixed, [amount] of the way from base to text.
  Color mix(double amount) => _mix(base, text, amount);

  static Color _mix(Color base, Color text, double amount) =>
      Color.lerp(base, text, amount)!;

  @override
  Tones copyWith({Color? base, Color? text, Color? accent, bool? frosted}) =>
      Tones(
        base: base ?? this.base,
        text: text ?? this.text,
        accent: accent ?? this.accent,
        frosted: frosted ?? this.frosted,
      );

  @override
  Tones lerp(Tones? other, double t) {
    if (other == null) return this;
    final accent = this.accent ?? other.accent;
    return Tones(
      base: Color.lerp(base, other.base, t)!,
      text: Color.lerp(text, other.text, t)!,
      accent: accent == null
          ? null
          : Color.lerp(this.accent ?? text, other.accent ?? other.text, t),
      frosted: t < 0.5 ? frosted : other.frosted,
    );
  }
}

extension ToneAccess on BuildContext {
  /// The tones of the theme here, or those of the appearance the app starts
  /// with where a theme has none — a widget tested on its own, say.
  Tones get tones =>
      Theme.of(this).extension<Tones>() ??
      Tones.of(const Appearance(), Theme.of(this).brightness);
}
