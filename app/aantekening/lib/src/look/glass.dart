/// Frosted glass: what floats over the page — the status line, the guide,
/// the picker — lets the notes show through it, blurred, so it sits over
/// them without hiding them.
library;

import 'dart:math' as math;
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
    final coming = context.dependOnInheritedWidgetOfExactType<GlassArriving>();
    final arriving = coming?.arriving;
    final growing = coming?.growing;
    // Grown the last little way to its size, as it floats in: all of it
    // but the frost, which is laid at the pane's full size throughout.
    // Laid at a new size each frame, the first pane of glass to float in
    // took 18 to 45 ms a frame to draw, in the app's benchmark; so, 2.
    Widget grown(Widget part) => growing == null
        ? part
        : ScaleTransition(scale: growing, alignment: coming!.from, child: part);
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
          child: _HeldStill(
            arriving: arriving,
            child: GlassArriving(arriving: null, child: child),
          ),
        ),
      ),
    );
    if (arriving != null) pane = FadeTransition(opacity: arriving, child: pane);
    pane = grown(pane);
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
    // The pane is held to what the glass is held to: let loose within a
    // dialog's least width, or a pane sized by hand, it would shrink to
    // what is on it, its shadow cast round the larger shape.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Positioned.fill(
          child: arriving == null
              ? cast
              : grown(FadeTransition(opacity: arriving, child: cast)),
        ),
        pane,
      ],
    );
  }
}

/// What is on a pane of glass, drawn once and kept as a picture while the
/// pane floats in or away, and as itself the rest of the time.
///
/// A pane grows the last little way to its size as it floats in, and what
/// is on it with it. Its words were set again at every size on the way —
/// each a new size to the renderer, every letter of it drawn afresh — so a
/// frame of Go to arriving took 18 to 39 ms to draw, and of the picker 44
/// to 50, where one of a pane already there takes 2. A picture of them
/// grows as cheaply as it is moved, as the framework's own pages do
/// zooming in; a quarter of a second on, the words are themselves again.
class _HeldStill extends StatefulWidget {
  const _HeldStill({required this.arriving, required this.child});

  /// How far the pane has come in, or null for one that is simply there.
  final Animation<double>? arriving;
  final Widget child;

  @override
  State<_HeldStill> createState() => _HeldStillState();
}

class _HeldStillState extends State<_HeldStill> {
  final SnapshotController _picture = SnapshotController();

  @override
  void initState() {
    super.initState();
    widget.arriving?.addStatusListener(_onStatus);
    _onStatus(widget.arriving?.status);
  }

  @override
  void didUpdateWidget(_HeldStill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arriving == widget.arriving) return;
    oldWidget.arriving?.removeStatusListener(_onStatus);
    widget.arriving?.addStatusListener(_onStatus);
    _onStatus(widget.arriving?.status);
  }

  @override
  void dispose() {
    widget.arriving?.removeStatusListener(_onStatus);
    _picture.dispose();
    super.dispose();
  }

  /// A picture while the pane is on its way in or out, and only then.
  void _onStatus(AnimationStatus? status) {
    _picture.allowSnapshotting =
        status == AnimationStatus.forward || status == AnimationStatus.reverse;
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _picture,
    // What cannot be kept as a picture is drawn as itself, as before.
    mode: SnapshotMode.permissive,
    autoresize: true,
    child: widget.child,
  );
}

/// How far the [Glass] beneath it has come in, as it floats in: from 0,
/// not there, to 1, all there — for it to fade in by itself.
class GlassArriving extends InheritedWidget {
  const GlassArriving({
    required this.arriving,
    required super.child,
    this.growing,
    this.from = Alignment.center,
    super.key,
  });

  final Animation<double>? arriving;

  /// How large the glass is on its way in, as a share of its size — it
  /// grows the last little way — or null for glass that does not grow.
  /// The glass grows itself, so that its frost need not.
  final Animation<double>? growing;

  /// Where it grows from.
  final Alignment from;

  @override
  bool updateShouldNotify(GlassArriving oldWidget) =>
      oldWidget.arriving != arriving ||
      oldWidget.growing != growing ||
      oldWidget.from != from;
}

/// The light liquid glass catches: along its edge, brightest at the top
/// left, dim at the other two corners, glinting again at the bottom right;
/// and a sheen across its top that fades as it goes down.
///
/// Drawn on what clips it to its shape: in strips and corners of one colour
/// or two, a pane sized by hand is drawn again at each step as cheaply as
/// it is moved — a gradient across a rounded shape, or along a line round
/// it, takes many times as long.
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

  /// How thick the edge's light is, and how far in from the very edge its
  /// middle lies.
  static const double _rim = 1.2;
  static const double _inset = 0.75;

  /// How much of [light] each corner catches.
  static const double _topLeft = 1;
  static const double _bottomRight = 0.55;
  static const double _dim = 0.15;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, _sheenDepth),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(0, _sheenDepth),
          <Color>[sheen, sheen.withValues(alpha: 0)],
        ),
    );
    Color of(double share) => light.withValues(alpha: light.a * share);
    final (w, h) = (size.width, size.height);
    final (tl, tr, br, bl) = (
      borderRadius.topLeft.x,
      borderRadius.topRight.x,
      borderRadius.bottomRight.x,
      borderRadius.bottomLeft.x,
    );
    // Each side, from one corner to the next, in the light of each.
    void side(Offset from, Offset to, double a, double b) {
      final across = from.dx == to.dx
          ? const Offset(_rim / 2, 0)
          : const Offset(0, _rim / 2);
      canvas.drawRect(
        Rect.fromPoints(from - across, to + across),
        Paint()..shader = ui.Gradient.linear(from, to, <Color>[of(a), of(b)]),
      );
    }

    const i = _inset;
    side(Offset(tl, i), Offset(w - tr, i), _topLeft, _dim);
    side(Offset(i, tl), Offset(i, h - bl), _topLeft, _dim);
    side(Offset(bl, h - i), Offset(w - br, h - i), _dim, _bottomRight);
    side(Offset(w - i, tr), Offset(w - i, h - br), _dim, _bottomRight);
    // Each corner, round, in its own light.
    void corner(Offset centre, double radius, double start, double share) {
      if (radius <= i) return;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius - i),
        start,
        math.pi / 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _rim
          ..color = of(share),
      );
    }

    corner(Offset(tl, tl), tl, math.pi, _topLeft);
    corner(Offset(w - tr, tr), tr, -math.pi / 2, _dim);
    corner(Offset(w - br, h - br), br, 0, _bottomRight);
    corner(Offset(bl, h - bl), bl, math.pi / 2, _dim);
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

/// A dialog on [Glass], laid out as an [AlertDialog] lays one out: its
/// [title] over its [content], with its [actions] along its foot — or, made
/// [GlassDialog.bare], [child] alone, laid out as it lays itself out.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    this.title,
    this.content,
    this.actions = const <Widget>[],
    this.actionsAlignment = MainAxisAlignment.end,
    super.key,
  }) : child = null;

  const GlassDialog.bare({required Widget this.child, super.key})
    : title = null,
      content = null,
      actions = const <Widget>[],
      actionsAlignment = MainAxisAlignment.end;

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final MainAxisAlignment actionsAlignment;
  final Widget? child;

  /// The narrowest a dialog is.
  static const double minWidth = 280;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialog = theme.dialogTheme;
    final title = this.title;
    final content = this.content;
    final body =
        child ??
        IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    content == null ? 20 : 16,
                  ),
                  child: DefaultTextStyle(
                    style: dialog.titleTextStyle ?? theme.textTheme.titleLarge!,
                    child: Semantics(
                      namesRoute: true,
                      container: true,
                      child: title,
                    ),
                  ),
                ),
              if (content != null)
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      title == null ? 20 : 0,
                      24,
                      24,
                    ),
                    child: DefaultTextStyle(
                      style:
                          dialog.contentTextStyle ??
                          theme.textTheme.bodyMedium!,
                      child: content,
                    ),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding:
                      dialog.actionsPadding ??
                      const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: OverflowBar(
                    alignment: actionsAlignment,
                    spacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions,
                  ),
                ),
            ],
          ),
        );
    return Padding(
      padding:
          (dialog.insetPadding ?? const EdgeInsets.all(24)) +
          MediaQuery.viewInsetsOf(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: minWidth),
          child: Glass(child: body),
        ),
      ),
    );
  }
}
