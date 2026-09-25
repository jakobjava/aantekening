/// How the interface looks: light or dark, its colours, the accent, the
/// typeface and the size.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/appearance.dart';
import '../look/colour_picker.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import 'settings_view.dart';

/// The appearance page of the settings. Every change shows at once, the
/// settings themselves included.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    void update(Appearance Function(Appearance appearance) change) =>
        controller.update(change);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Mode',
          children: <Widget>[
            SettingRow(
              label: 'Light or dark',
              description: 'Pages stay white paper in either',
              child: ChoiceRow<ThemeMode>(
                choices: ThemeMode.values,
                selected: appearance.mode,
                labelOf: (mode) => switch (mode) {
                  ThemeMode.system => 'As the system',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                },
                onSelected: (mode) =>
                    update((appearance) => appearance.copyWith(mode: mode)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Colours',
          description:
              'The interface is drawn in two colours — a base and the text '
              'on it — and the shades between them. Each mode has its own.',
          children: <Widget>[
            for (final brightness in Brightness.values.reversed)
              _PairChooser(
                brightness: brightness,
                pair: appearance.pairFor(brightness),
                onChanged: (pair) => update(
                  (appearance) => appearance.withPair(brightness, pair),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: 'Accent',
          description:
              'One colour for what is picked, pressed in or has the '
              'keyboard — or none, and those are marked in the text colour.',
          children: <Widget>[
            SettingRow(
              label: 'Accent',
              child: ChoiceRow<bool>(
                choices: const <bool>[false, true],
                selected: appearance.accentOn,
                labelOf: (on) => on ? 'One accent' : 'None',
                onSelected: (on) =>
                    update((appearance) => appearance.copyWith(accentOn: on)),
              ),
            ),
            if (appearance.accentOn)
              SettingRow(
                label: 'Colour',
                child: _SwatchRow(
                  presets: <({String name, Color color})>[
                    ...Appearance.accentPresets,
                  ],
                  selected: appearance.accent,
                  pickerTitle: 'Accent',
                  onPicked: (accent) => update(
                    (appearance) => appearance.copyWith(accent: accent),
                  ),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: 'Type',
          children: <Widget>[
            SettingRow(
              label: 'Typeface',
              description: 'Of the interface; notes keep their own',
              child: ChoiceRow<InterfaceFont>(
                choices: InterfaceFont.values,
                selected: appearance.font,
                labelOf: (font) => font.label,
                onSelected: (font) =>
                    update((appearance) => appearance.copyWith(font: font)),
              ),
            ),
            SettingRow(
              label: 'Size',
              description: 'Of everything, the page included',
              child: ChoiceRow<double>(
                choices: Appearance.scales,
                selected: appearance.scale,
                labelOf: (scale) => '${(scale * 100).round()}%',
                onSelected: (scale) =>
                    update((appearance) => appearance.copyWith(scale: scale)),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: appearance == const Appearance()
                ? null
                : controller.reset,
            child: const Text('Back to how it started'),
          ),
        ),
      ],
    );
  }
}

/// The colours of one mode: pairs to pick from, and the base and the text
/// to pick one by one.
class _PairChooser extends StatelessWidget {
  const _PairChooser({
    required this.brightness,
    required this.pair,
    required this.onChanged,
  });

  final Brightness brightness;
  final ColourPair pair;
  final ValueChanged<ColourPair> onChanged;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final dark = brightness == Brightness.dark;
    final presets = dark ? Appearance.darkPresets : Appearance.lightPresets;
    final name = dark ? 'Dark' : 'Light';

    Future<void> pick(
      String what,
      Color current,
      ColourPair Function(Color) apply,
    ) async {
      final picked = await showColorPicker(
        context,
        initial: current.toARGB32(),
        title: '$name mode: $what',
      );
      if (picked != null) onChanged(apply(Color(picked)));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final preset in presets)
                _PairTile(
                  pair: preset,
                  selected: preset == pair,
                  onTap: () => onChanged(preset),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _ColourField(
                label: 'Base',
                color: pair.base,
                onTap: () => unawaited(pick('base', pair.base, pair.withBase)),
              ),
              _ColourField(
                label: 'Text',
                color: pair.text,
                onTap: () => unawaited(pick('text', pair.text, pair.withText)),
              ),
              if (pair.hardToRead)
                Text(
                  'Hard to read: the text and the base are close in '
                  'lightness',
                  style: TextStyle(fontSize: 12, color: tones.text),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A pair of colours to pick, drawn as it looks: text on its base.
class _PairTile extends StatelessWidget {
  const _PairTile({
    required this.pair,
    required this.selected,
    required this.onTap,
  });

  final ColourPair pair;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      selected: selected,
      button: true,
      label: pair.name,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tones.emphasis : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Container(
            width: 96,
            height: 54,
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
            decoration: BoxDecoration(
              color: pair.base,
              border: Border.all(color: tones.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: pair.text,
                  ),
                ),
                Text(
                  pair.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color.lerp(pair.base, pair.text, 0.64),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A colour and what it is, which a click changes.
class _ColourField extends StatelessWidget {
  const _ColourField({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final hex = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return Tooltip(
      message: 'Choose the ${label.toLowerCase()} colour',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: tones.strongLine),
                ),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              KeyHint('#$hex'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colours to pick from in a row, and any other through the picker.
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.presets,
    required this.selected,
    required this.pickerTitle,
    required this.onPicked,
  });

  final List<({String name, Color color})> presets;
  final Color selected;
  final String pickerTitle;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    final custom = !presets.any((preset) => preset.color == selected);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final preset in presets)
          Swatch(
            color: preset.color,
            name: preset.name,
            selected: preset.color == selected,
            onTap: () => onPicked(preset.color),
          ),
        if (custom)
          Swatch(
            color: selected,
            name: 'Your own',
            selected: true,
            onTap: null,
          ),
        const SizedBox(width: 6),
        SmallButton(
          'Other…',
          onPressed: () async {
            final picked = await showColorPicker(
              context,
              initial: selected.toARGB32(),
              title: pickerTitle,
            );
            if (picked != null) onPicked(Color(picked));
          },
        ),
      ],
    );
  }
}
