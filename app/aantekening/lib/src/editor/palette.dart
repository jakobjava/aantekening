/// One palette for everything coloured on a page: pens, highlighters, text and
/// text highlights.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

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
