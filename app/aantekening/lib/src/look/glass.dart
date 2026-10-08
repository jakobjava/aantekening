/// Frosted glass: what floats over the page — the status line, the guide,
/// the picker — lets the notes show through it, blurred, so it sits over
/// them without hiding them.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tones.dart';

/// How round the corners of things are.
abstract final class Corners {
  /// Panels, dialogs, menus: what floats.
  static const double panel = 12;

  /// Buttons, fields, rows: what is pressed or typed in.
  static const double control = 7;

  /// Small marks: a key, a swatch, a checkbox.
  static const double small = 4;

  static const BorderRadius panelRadius = BorderRadius.all(
    Radius.circular(panel),
  );

  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );

  static const BorderRadius smallRadius = BorderRadius.all(
    Radius.circular(small),
  );
}

/// [child] on a pane of liquid glass: what lies beneath blurred and
/// brightened through a clear wash of the base, within a fine rim whose
/// edge catches the light — brightest at one corner, glinting at the other
/// — under a sheen across its top, casting a soft shadow; or on the base
/// alone where what floats is not frosted ([Tones.frosted]).
class Glass extends StatelessWidget {
  const Glass({
    required this.child,
    this.borderRadius = Corners.panelRadius,
    this.shadow = true,
    super.key,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Whether it casts a shadow.
  final bool shadow;

  /// How far what lies beneath is blurred.
  static const double blur = 26;

  /// How much more vivid what lies beneath shows through it: its colours
  /// glow through the glass rather than greying under it.
  static const double vibrancy = 2;

  /// How much of what lies beneath shows through, in the dark: it is dimmed
  /// to this share of its light, so that light text on the glass reads over
  /// the white page as over a dark one.
  static const double _darkLight = 0.32;

  /// How far what lies beneath is lifted towards white in the light, so
  /// dark text on the glass reads over a dark picture as over the paper.
  static const double _lightLift = 0.35;

  /// What the glass does to what lies beneath, as a colour matrix: makes it
  /// [vibrancy] times as vivid, then, in [brightness], dims it or lifts it
  /// so what is on the glass always reads.
  static List<double> _filterFor(Brightness brightness) {
    const s = vibrancy;
    // The luminance of each channel, as the eye weighs them.
    const r = 0.2126;
    const g = 0.7152;
    const b = 0.0722;
    final dark = brightness == Brightness.dark;
    final scale = dark ? _darkLight : 1 - _lightLift;
    final offset = dark ? 0.0 : _lightLift * 255;
    List<double> row(double red, double green, double blue) => <double>[
      red * scale,
      green * scale,
      blue * scale,
      0,
      offset,
    ];
    return <double>[
      ...row(r * (1 - s) + s, g * (1 - s), b * (1 - s)),
      ...row(r * (1 - s), g * (1 - s) + s, b * (1 - s)),
      ...row(r * (1 - s), g * (1 - s), b * (1 - s) + s),
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// The colour matrix that changes nothing.
  static const List<double> _unchanged = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// What the glass does to what lies beneath at full strength, in each
  /// brightness, made once.
  static final Map<Brightness, ui.ImageFilter> _frosts =
      <Brightness, ui.ImageFilter>{
        for (final brightness in Brightness.values)
          brightness: _frostAt(brightness, 1),
      };

  /// What the glass does to what lies beneath at [strength], from nothing
  /// at 0 to all of it at 1: as it fades in, the blur and the colour come
  /// as it does.
  static ui.ImageFilter _frostAt(Brightness brightness, double strength) {
    final full = _filterFor(brightness);
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(<double>[
        for (var i = 0; i < full.length; i++)
          _unchanged[i] + (full[i] - _unchanged[i]) * strength,
      ]),
      inner: ui.ImageFilter.blur(
        sigmaX: blur * strength,
        sigmaY: blur * strength,
      ),
    );
  }

  static ui.ImageFilter _frost(Brightness brightness, double strength) =>
      strength >= 1 ? _frosts[brightness]! : _frostAt(brightness, strength);

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    // Floating in, it fades in by itself: never under a layer that fades
    // it, which would draw what lies beneath again, blurred, every frame.
    final arriving = GlassArriving._of(context);
    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        color: tones.glass,
        border: Border.all(color: tones.glassRim),
        borderRadius: borderRadius,
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidEdge(
          borderRadius: borderRadius,
          light: tones.glassLight,
          sheen: tones.glassSheen,
        ),
        // What is on it is pressed and set as on any surface, and any
        // glass on it arrives by itself.
        child: Material(
          type: MaterialType.transparency,
          child: GlassArriving(arriving: null, child: child),
        ),
      ),
    );
    if (arriving != null) pane = FadeTransition(opacity: arriving, child: pane);
    if (tones.frosted) {
      final brightness = tones.brightness;
      pane = arriving == null
          ? BackdropFilter(filter: _frost(brightness, 1), child: pane)
          : AnimatedBuilder(
              animation: arriving,
              child: pane,
              builder: (context, pane) => BackdropFilter(
                filter: _frost(brightness, arriving.value.clamp(0, 1)),
                child: pane,
              ),
            );
    }
    pane = ClipRRect(borderRadius: borderRadius, child: pane);
    if (!shadow) return pane;
    final cast = CustomPaint(
      painter: _ShadowOutside(
        borderRadius: borderRadius,
        shadows: tones.floatingShadows,
      ),
    );
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: arriving == null
              ? cast
              : FadeTransition(opacity: arriving, child: cast),
        ),
        pane,
      ],
    );
  }
}

/// How far the [Glass] beneath it has come in, as it floats in: from 0,
/// not there, to 1, all there — for it to fade in by itself.
class GlassArriving extends InheritedWidget {
  const GlassArriving({
    required this.arriving,
    required super.child,
    super.key,
  });

  final Animation<double>? arriving;

  static Animation<double>? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassArriving>()?.arriving;

  @override
  bool updateShouldNotify(GlassArriving oldWidget) =>
      oldWidget.arriving != arriving;
}

/// The light liquid glass catches: along its edge, brightest at the top
/// left, gone along the middle, glinting again at the foot and right; and
/// a sheen across its top that fades as it goes down.
class _LiquidEdge extends CustomPainter {
  const _LiquidEdge({
    required this.borderRadius,
    required this.light,
    required this.sheen,
  });

  final BorderRadius borderRadius;
  final Color light;
  final Color sheen;

  /// How far down the sheen reaches.
  static const double _sheenDepth = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    final shape = borderRadius.toRRect(area);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[sheen, sheen.withValues(alpha: 0)],
          stops: <double>[0, (_sheenDepth / size.height).clamp(0, 1)],
        ).createShader(area),
    );
    Color of(double share) => light.withValues(alpha: light.a * share);
    canvas.drawRRect(
      shape.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[of(1), of(0.25), of(0.08), of(0.55)],
          stops: const <double>[0, 0.35, 0.7, 1],
        ).createShader(area),
    );
  }

  @override
  bool shouldRepaint(_LiquidEdge oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.light != light ||
      oldDelegate.sheen != sheen;
}

/// Shadows cast by a pane of glass, drawn only outside it: beneath the
/// glass they would show through it and grey it.
class _ShadowOutside extends CustomPainter {
  const _ShadowOutside({required this.borderRadius, required this.shadows});

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = borderRadius.toRRect(Offset.zero & size);
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect((Offset.zero & size).inflate(200)),
          Path()..addRRect(shape),
        ),
      );
    for (final shadow in shadows) {
      canvas.drawRRect(
        shape.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowOutside oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      !listEquals(oldDelegate.shadows, shadows);
}

/// [child] on a solid panel floating over the window — the settings, a
/// dialog of its own making — rounded, edged and casting a soft shadow, as
/// the theme's dialogs are.
class RaisedPanel extends StatelessWidget {
  const RaisedPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Corners.panelRadius,
        boxShadow: tones.floatingShadows,
      ),
      child: Material(
        color: tones.raised,
        shape: RoundedRectangleBorder(
          borderRadius: Corners.panelRadius,
          side: BorderSide(color: tones.glassRim),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
