/// Picking any colour: for a pen, for text, or for the interface itself.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'tones.dart';

/// Shows the colour picker, [title]d, returning the chosen colour as opaque
/// ARGB, or null if cancelled.
Future<int?> showColorPicker(
  BuildContext context, {
  required int initial,
  String title = 'Colour',
}) => showDialog<int>(
  context: context,
  builder: (context) =>
      ColorPickerDialog(initial: initial | 0xFF000000, title: title),
);

/// Picks any colour: saturation and brightness on a square, hue on a strip,
/// or a hex code typed in.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    required this.initial,
    this.title = 'Colour',
    super.key,
  });

  final int initial;
  final String title;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int get _argb => _hsv.toColor().toARGB32();

  static String _hexOf(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final hex = _hexOf(_argb);
    if (_hex.text.toUpperCase() != hex) _hex.text = hex;
  }

  void _onHexChanged(String text) {
    final clean = text.replaceAll('#', '').trim();
    if (clean.length != 6) return;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | value)));
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    Widget chip(Color color, String label) => Tooltip(
      message: label,
      child: Container(
        width: 36,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: tones.line),
        ),
      ),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SaturationValueSquare(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 12),
            _HueStrip(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                chip(Color(widget.initial), 'Before'),
                chip(_hsv.toColor(), 'Now'),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(
                      prefixText: '#',
                      labelText: 'Hex',
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    style: TextStyle(fontFamily: InterfaceFont.mono.family),
                    onChanged: _onHexChanged,
                    onSubmitted: (_) => Navigator.of(context).pop(_argb),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_argb),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

/// Saturation left to right, brightness bottom to top, at the current hue.
class _SaturationValueSquare extends StatelessWidget {
  const _SaturationValueSquare({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, 180);
      void pick(Offset local) => onChanged(
        hsv
            .withSaturation((local.dx / size.width).clamp(0.0, 1.0))
            .withValue(1 - (local.dy / size.height).clamp(0.0, 1.0)),
      );
      return GestureDetector(
        onPanDown: (details) => pick(details.localPosition),
        onPanUpdate: (details) => pick(details.localPosition),
        child: CustomPaint(size: size, painter: _SaturationValuePainter(hsv)),
      );
    },
  );
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              const Color(0xFFFFFFFF),
              HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
            ],
          ).createShader(rect),
      )
      ..drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x00000000), Color(0xFF000000)],
          ).createShader(rect),
      );
    final knob = Rect.fromCenter(
      center: Offset(
        hsv.saturation * size.width,
        (1 - hsv.value) * size.height,
      ),
      width: 12,
      height: 12,
    );
    _drawKnob(canvas, knob);
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hsv != hsv;
}

/// The hue, as a rainbow strip.
class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, 16);
      void pick(Offset local) => onChanged(
        hsv.withHue((local.dx / size.width).clamp(0.0, 1.0) * 359.9),
      );
      return GestureDetector(
        onPanDown: (details) => pick(details.localPosition),
        onPanUpdate: (details) => pick(details.localPosition),
        child: CustomPaint(size: size, painter: _HuePainter(hsv.hue)),
      );
    },
  );
}

class _HuePainter extends CustomPainter {
  const _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(
                1,
                math.min(h, 359.9).toDouble(),
                1,
                1,
              ).toColor(),
          ],
        ).createShader(rect),
    );
    final x = hue / 360 * size.width;
    _drawKnob(canvas, Rect.fromLTRB(x - 3, -2, x + 3, size.height + 2));
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// A square outline, white inside black, that shows on any colour.
void _drawKnob(Canvas canvas, Rect rect) => canvas
  ..drawRect(
    rect,
    Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  )
  ..drawRect(
    rect,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
