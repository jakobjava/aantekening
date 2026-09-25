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
/// colour instead.
@immutable
class Tones extends ThemeExtension<Tones> {
  Tones({required this.base, required this.text, Color? accent})
    : accent = accent == null ? null : readableOn(accent, base),
      pane = _mix(base, text, 0.035),
      hover = _mix(base, text, 0.06),
      pressed = _mix(base, text, 0.11),
      line = _mix(base, text, 0.13),
      strongLine = _mix(base, text, 0.32),
      faint = _mix(base, text, 0.4),
      muted = _mix(base, text, 0.64),
      selection = accent == null
          ? _mix(base, text, 0.09)
          : Color.alphaBlend(
              readableOn(accent, base).withValues(alpha: 0.16),
              base,
            ),
      emphasis = accent == null ? text : readableOn(accent, base),
      paperEmphasis = _paperEmphasisOf(accent);

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
    );
  }

  /// The paper pages are written on, which stays white in dark mode too.
  static const Color paper = Color(0xFFFFFFFF);

  /// What everything is drawn on.
  final Color base;

  /// Text, and whatever is drawn as text is.
  final Color text;

  /// The accent, made to stand out against [base], or null for none.
  final Color? accent;

  /// Behind the panes beside the page, a shade off [base].
  final Color pane;

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

  /// Behind what is picked: the row chosen, the tab showing.
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
  Tones copyWith({Color? base, Color? text, Color? accent}) => Tones(
    base: base ?? this.base,
    text: text ?? this.text,
    accent: accent ?? this.accent,
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
