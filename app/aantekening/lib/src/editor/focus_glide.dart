/// A ring that glides from what had the keys to what they moved to, so the
/// eye follows the jump, and then fades.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../look/motion.dart';

/// Draws a ring round [target] — a rectangle in this widget's own
/// coordinates — each time it changes: from where the last one was, gliding
/// there, then fading away.
class FocusGlide extends StatefulWidget {
  const FocusGlide({required this.target, required this.colour, super.key});

  final ValueListenable<Rect?> target;
  final Color colour;

  @override
  State<FocusGlide> createState() => _FocusGlideState();
}

class _FocusGlideState extends State<FocusGlide> with TickerProviderStateMixin {
  late final AnimationController _glide = AnimationController(vsync: this);
  late final AnimationController _fade = AnimationController(vsync: this);
  Rect? _from;
  Rect? _to;

  /// How long the ring stays once it is there, before it fades.
  static const Duration _stay = Duration(milliseconds: 420);

  Timer? _staying;

  @override
  void initState() {
    super.initState();
    widget.target.addListener(_moved);
  }

  @override
  void didUpdateWidget(FocusGlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      oldWidget.target.removeListener(_moved);
      widget.target.addListener(_moved);
    }
  }

  @override
  void dispose() {
    widget.target.removeListener(_moved);
    _staying?.cancel();
    _glide.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Where the ring is just now.
  Rect? get _shown {
    final to = _to;
    final from = _from;
    if (to == null) return null;
    if (from == null) return to;
    return Rect.lerp(
      from,
      to,
      Motion.lively.transform(_glide.value.clamp(0, 1)),
    );
  }

  void _moved() {
    final target = widget.target.value;
    if (target == null) return;
    final motion = context.motion;
    // From where it was, if it is still showing; else it appears there.
    _from = _fade.value > 0 ? _shown : null;
    _to = target;
    _staying?.cancel();
    _fade.value = 1;
    _glide
      ..duration = motion.of(Motion.settle)
      ..value = 0;
    unawaited(
      _glide.forward().whenComplete(() {
        if (!mounted) return;
        _staying = Timer(_stay, () {
          if (!mounted) return;
          _fade.duration = motion.of(Motion.settle);
          unawaited(_fade.reverse());
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_glide, _fade]),
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _Ring(
          rect: _fade.value == 0 ? null : _shown,
          colour: widget.colour,
          opacity: _fade.value,
        ),
      ),
    ),
  );
}

class _Ring extends CustomPainter {
  const _Ring({
    required this.rect,
    required this.colour,
    required this.opacity,
  });

  final Rect? rect;
  final Color colour;
  final double opacity;

  /// How far outside what it is round the ring lies.
  static const double _outside = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = this.rect;
    if (rect == null) return;
    final ring = RRect.fromRectAndRadius(
      rect.inflate(_outside),
      const Radius.circular(8),
    );
    // The mode's colour at full strength, glowing a little: a ring, not
    // a tint over what it is round.
    canvas
      ..drawRRect(
        ring,
        Paint()
          ..color = colour.withValues(alpha: 0.4 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawRRect(
        ring,
        Paint()
          ..color = colour.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.colour != colour ||
      oldDelegate.opacity != opacity;
}
