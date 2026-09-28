/// One palette for everything coloured on a page: pens, highlighters, text and
/// text highlights, plus a picker for any other colour.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import '../look/colour_picker.dart';
import '../look/controls.dart';

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

  /// No colour but the inverse of what lies beneath, offered for text and
  /// the pen.
  static const ({int color, String name}) inverse = (
    color: NoteColors.inverse,
    name: 'Inverted',
  );

  /// [color] as it is kept: opaque, unless it is [inverse].
  static int opaque(int color) =>
      color == NoteColors.inverse ? color : color | 0xFF000000;

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
    if (color == NoteColors.inverse) return inverse.name;
    final opaque = color | 0xFF000000;
    for (final preset in presets) {
      if (preset.color == opaque) return preset.name;
    }
    return '#${(opaque & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// A swatch of a colour on a page, [NoteColors.inverse] among them.
class NoteSwatch extends StatelessWidget {
  const NoteSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
    this.size = 20,
    super.key,
  });

  final int color;
  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => color == NoteColors.inverse
      ? Swatch.inverse(name: name, selected: selected, onTap: onTap, size: size)
      : Swatch(
          color: Color(color | 0xFF000000),
          name: name,
          selected: selected,
          onTap: onTap,
          size: size,
        );
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
    this.offersInverse = false,
  });

  /// The current colour, marked in the grid; compared without alpha.
  final int? selected;

  /// Whether [NotePalette.inverse] is offered, beneath [noneLabel].
  final bool offersInverse;

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
    final selectedOpaque = selected == null
        ? null
        : NotePalette.opaque(selected!);

    Widget swatch(int color, String name) => NoteSwatch(
      color: color,
      name: name,
      selected: color == selectedOpaque,
      onTap: () => onSelected(color),
    );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: _columns * 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (noneLabel case final noneLabel?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CheckRow(
                  title: noneLabel,
                  value: selected == null,
                  onChanged: (_) => onNone?.call(),
                ),
              ),
            if (offersInverse)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CheckRow(
                  title: NotePalette.inverse.name,
                  description: 'The opposite of what is beneath',
                  value: selected == NoteColors.inverse,
                  onChanged: (_) => onSelected(NoteColors.inverse),
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
            SmallButton(
              'More colours…',
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
            ),
          ],
        ),
      ),
    );
  }
}
