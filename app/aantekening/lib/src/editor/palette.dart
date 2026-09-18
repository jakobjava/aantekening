/// One palette for everything coloured on a page: pens, highlighters, text and
/// text highlights, plus a picker for any other colour.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The colours offered everywhere a colour is chosen.
///
/// Sharing one palette means the blue of a pen stroke is the blue of the text
/// next to it, and the yellow highlighter matches the yellow text highlight.
abstract final class NotePalette {
  static const List<({int color, String name})> presets =
      <({int color, String name})>[
        (color: 0xFF000000, name: 'Black'),
        (color: 0xFF5F6368, name: 'Grey'),
        (color: 0xFFD93025, name: 'Red'),
        (color: 0xFFF57C00, name: 'Orange'),
        (color: 0xFFFFD60A, name: 'Yellow'),
        (color: 0xFF34A853, name: 'Green'),
        (color: 0xFF00897B, name: 'Teal'),
        (color: 0xFF1A73E8, name: 'Blue'),
        (color: 0xFF283593, name: 'Navy'),
        (color: 0xFF8E24AA, name: 'Purple'),
        (color: 0xFFE91E63, name: 'Pink'),
        (color: 0xFF795548, name: 'Brown'),
      ];

  /// Colours picked with the colour picker this session, most recent first,
  /// offered alongside the presets.
  static final ValueNotifier<List<int>> recent = ValueNotifier<List<int>>(
    const <int>[],
  );

  static const int _maxRecent = 6;

  /// Remembers [color] as recently used, if it is not a preset.
  static void remember(int color) {
    final opaque = color | 0xFF000000;
    if (presets.any((preset) => preset.color == opaque)) return;
    recent.value = <int>[
      opaque,
      ...recent.value.where((c) => c != opaque),
    ].take(_maxRecent).toList();
  }

  /// The name of a preset colour, or its hex code.
  static String nameOf(int color) {
    final opaque = color | 0xFF000000;
    for (final preset in presets) {
      if (preset.color == opaque) return preset.name;
    }
    return '#${(opaque & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// A grid of the palette's colours, the recently picked ones, and a way to
/// pick any other colour.
class ColorSwatchPanel extends StatelessWidget {
  const ColorSwatchPanel({
    required this.selected,
    required this.onSelected,
    super.key,
    this.noneLabel,
    this.onNone,
    this.onPickerOpened,
  });

  /// The current colour, marked in the grid; compared without alpha.
  final int? selected;

  final ValueChanged<int> onSelected;

  /// An extra first choice — "Automatic" or "No highlight" — and what it does.
  final String? noneLabel;
  final VoidCallback? onNone;

  /// Called before the colour picker opens, so a menu holding this panel can
  /// close first.
  final VoidCallback? onPickerOpened;

  static const int _columns = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedOpaque = selected == null ? null : selected! | 0xFF000000;

    Widget swatch(int color, String name) => PaletteSwatch(
      color: color,
      name: name,
      selected: color == selectedOpaque,
      onTap: () => onSelected(color),
    );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: _columns * 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (noneLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: onNone,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          selected == null
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(noneLabel!, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            Wrap(
              children: <Widget>[
                for (final preset in NotePalette.presets)
                  swatch(preset.color, preset.name),
              ],
            ),
            ValueListenableBuilder<List<int>>(
              valueListenable: NotePalette.recent,
              builder: (context, recent, _) => recent.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        children: <Widget>[
                          for (final color in recent)
                            swatch(color, NotePalette.nameOf(color)),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () async {
                onPickerOpened?.call();
                final picked = await showColorPicker(
                  context,
                  initial: selected ?? 0xFF1A73E8,
                );
                if (picked != null) {
                  NotePalette.remember(picked);
                  onSelected(picked);
                }
              },
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('More colours…'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One colour to pick: a disc, ticked when it is the current colour.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
    super.key,
    this.diameter = 24,
  });

  final int color;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(diameter / 8),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: Color(color | 0xFF000000),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : const Color(0x33000000),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: diameter * 0.6,
                    color: _contrastOn(Color(color | 0xFF000000)),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

Color _contrastOn(Color color) =>
    color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// Shows the colour picker, returning the chosen colour as opaque ARGB, or
/// null if cancelled.
Future<int?> showColorPicker(BuildContext context, {required int initial}) =>
    showDialog<int>(
      context: context,
      builder: (context) => ColorPickerDialog(initial: initial | 0xFF000000),
    );

/// Picks any colour: saturation and brightness on a square, hue on a strip,
/// or a hex code typed in.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({required this.initial, super.key});

  final int initial;

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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Colour'),
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(widget.initial),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(8),
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(
                      prefixText: '#',
                      isDense: true,
                      labelText: 'Hex',
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    style: const TextStyle(fontFamily: 'monospace'),
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
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas
      ..save()
      ..clipRRect(rounded)
      ..drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              Colors.white,
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
      )
      ..restore();

    final knob = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas
      ..drawCircle(
        knob,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      )
      ..drawCircle(
        knob,
        8,
        Paint()
          ..color = const Color(0x66000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
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
      final size = Size(constraints.maxWidth, 18);
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
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
    canvas.drawCircle(
      Offset(x, size.height / 2),
      size.height / 2 + 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}
