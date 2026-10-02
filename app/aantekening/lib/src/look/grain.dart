/// A fine grain over the whole window, as on paper or film, as strong as
/// chosen in the settings.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance.dart';

/// [child] with the grain chosen ([Appearance.grain]) laid over it: every
/// pixel of the window a little lighter or darker than it was, at random.
class Grain extends ConsumerWidget {
  const Grain({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grain = ref.watch(
      appearanceProvider.select((appearance) => appearance.grain),
    );
    if (grain == 0) return child;
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.topLeft,
      children: <Widget>[
        child,
        // Drawn once, and only put on the screen again with each frame: what
        // changes beneath it never paints it again.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: _GrainLayer(
                strength: grain,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainLayer extends StatefulWidget {
  const _GrainLayer({required this.strength, required this.pixelRatio});

  final double strength;
  final double pixelRatio;

  @override
  State<_GrainLayer> createState() => _GrainLayerState();
}

class _GrainLayerState extends State<_GrainLayer> {
  ui.Image? _noise;

  @override
  void initState() {
    super.initState();
    unawaited(
      GrainNoise.tile.then((noise) {
        if (mounted) setState(() => _noise = noise);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noise = _noise;
    if (noise == null) return const SizedBox.expand();
    return CustomPaint(
      size: Size.infinite,
      painter: GrainPainter(
        noise: noise,
        strength: widget.strength,
        pixelRatio: widget.pixelRatio,
      ),
    );
  }
}

/// Draws [noise] over all it is given, one of its pixels to each of the
/// screen's, as opaque as [strength] has it.
class GrainPainter extends CustomPainter {
  const GrainPainter({
    required this.noise,
    required this.strength,
    required this.pixelRatio,
  });

  final ui.Image noise;

  /// From 0, nothing, to 1, the noise as it is.
  final double strength;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final shrink = Float64List(16)
      ..[0] = 1 / pixelRatio
      ..[5] = 1 / pixelRatio
      ..[10] = 1
      ..[15] = 1;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ImageShader(
          noise,
          TileMode.repeated,
          TileMode.repeated,
          shrink,
        )
        ..color = Color.fromRGBO(0, 0, 0, strength.clamp(0, 1)),
    );
  }

  @override
  bool shouldRepaint(GrainPainter old) =>
      old.noise != noise ||
      old.strength != strength ||
      old.pixelRatio != pixelRatio;
}

/// The noise the grain is made of: a tile of pixels each white or black, at
/// random, and as opaque as a bell curve has it — most faint, a few strong.
abstract final class GrainNoise {
  static const int side = 256;

  /// How opaque a pixel a standard deviation from nothing is.
  static const double _spread = 0.3;

  /// The tile, made once and kept for as long as the app runs.
  static final Future<ui.Image> tile = _make();

  static Future<ui.Image> _make() {
    // Always the same grain, so it does not change from one run to the next.
    final random = math.Random(7);
    final pixels = Uint8List(side * side * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      // A normally distributed value, by Box and Muller.
      final normal =
          math.sqrt(-2 * math.log(1 - random.nextDouble())) *
          math.cos(2 * math.pi * random.nextDouble());
      final alpha = (normal.abs() * _spread).clamp(0.0, 1.0);
      // Premultiplied, as the image is read: white is as bright as it is
      // opaque.
      final light = normal > 0 ? (alpha * 255).round() : 0;
      pixels
        ..[i] = light
        ..[i + 1] = light
        ..[i + 2] = light
        ..[i + 3] = (alpha * 255).round();
    }
    final made = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      side,
      side,
      ui.PixelFormat.rgba8888,
      made.complete,
    );
    return made.future;
  }
}
