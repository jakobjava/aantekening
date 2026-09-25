/// Every shortcut: those that can be changed, changing them, and those of
/// typing, which are fixed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commands/app_command.dart';
import '../commands/editor_keys.dart';
import '../commands/fuzzy.dart';
import '../commands/key_chord.dart';
import '../commands/shortcuts.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import 'settings_view.dart';

/// The keyboard page of the settings.
class KeyboardSettings extends ConsumerStatefulWidget {
  const KeyboardSettings({super.key});

  @override
  ConsumerState<KeyboardSettings> createState() => _KeyboardSettingsState();
}

class _KeyboardSettingsState extends ConsumerState<KeyboardSettings> {
  String _filter = '';

  bool _shows(String label, String keys) =>
      _filter.isEmpty ||
      fuzzyScore(_filter, label) != null ||
      keys.toLowerCase().contains(_filter.toLowerCase());

  Future<void> _change(AppCommand command) async {
    final chord = await showDialog<_Captured>(
      context: context,
      builder: (context) => _CaptureDialog(command: command),
    );
    if (chord == null) return;
    ref.read(shortcutsProvider.notifier).bind(command, <KeyChord>[
      ?chord.chord,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bindings = ref.watch(shortcutsProvider);
    final controller = ref.read(shortcutsProvider.notifier);
    final tones = context.tones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'A shortcut with Ctrl, Alt or Meta works wherever the keyboard is. '
          'A plain key works while the page has the keyboard and nothing on '
          'it is being typed in. Ctrl+Shift+P finds any command by name.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: tones.muted),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Find a shortcut by what it does or its keys',
                ),
                onChanged: (text) => setState(() => _filter = text.trim()),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: bindings.allDefault ? null : controller.resetAll,
              child: const Text('Reset all'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final group in CommandGroup.values)
          if (<AppCommand>[
                for (final command in AppCommand.values)
                  if (command.group == group &&
                      _shows(command.label, _keysOf(bindings, command)))
                    command,
              ]
              case final commands when commands.isNotEmpty)
            SettingsSection(
              title: group.label,
              children: <Widget>[
                for (final command in commands)
                  _CommandRow(
                    command: command,
                    keys: _keysOf(bindings, command),
                    changed: !bindings.isDefault(command),
                    onChange: () => _change(command),
                    onReset: () => controller.reset(command),
                  ),
              ],
            ),
        if (<EditorKey>[
              for (final key in EditorKey.values)
                if (_shows(key.label, key.keys)) key,
            ]
            case final keys when keys.isNotEmpty)
          SettingsSection(
            title: 'Typing and the page',
            description:
                'These are the same in every text box, and fixed, so they '
                'can be learnt once; a command above cannot take them.',
            children: <Widget>[
              for (final key in keys)
                _Line(
                  label: key.label,
                  keys: <String>[
                    if (key.chords.isNotEmpty || key.written != null) key.keys,
                    if (key.typed case final typed?) 'type "$typed"',
                  ].join('   or   '),
                ),
            ],
          ),
      ],
    );
  }

  static String _keysOf(ShortcutBindings bindings, AppCommand command) =>
      bindings.of(command).map((chord) => chord.label).join('   ');
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.keys,
    required this.changed,
    required this.onChange,
    required this.onReset,
  });

  final AppCommand command;
  final String keys;
  final bool changed;
  final VoidCallback onChange;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => _Line(
    label: command.label,
    description: command.description,
    keys: keys.isEmpty ? '—' : keys,
    trailing: <Widget>[
      SmallButton('Change', onPressed: onChange),
      SizedBox(
        width: 52,
        child: changed ? SmallButton('Reset', onPressed: onReset) : null,
      ),
    ],
  );
}

/// A line of the list: what a shortcut does, and its keys.
class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.keys,
    this.description,
    this.trailing = const <Widget>[],
  });

  final String label;
  final String? description;
  final String keys;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 13)),
                if (description case final description?)
                  Text(
                    description,
                    style: TextStyle(fontSize: 11.5, color: tones.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Text(
              keys,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: tones.text,
              ),
            ),
          ),
          if (trailing.isNotEmpty) const SizedBox(width: 10),
          ...trailing,
        ],
      ),
    );
  }
}

/// A shortcut pressed in [_CaptureDialog], or none, to take its shortcut
/// away.
typedef _Captured = ({KeyChord? chord});

/// Asks for [command]'s new shortcut by having it pressed.
class _CaptureDialog extends ConsumerStatefulWidget {
  const _CaptureDialog({required this.command});

  final AppCommand command;

  @override
  ConsumerState<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends ConsumerState<_CaptureDialog> {
  KeyChord? _chord;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final chord = KeyChord.fromEvent(event, HardwareKeyboard.instance);
    if (chord == null) return KeyEventResult.handled;
    // Escape and Enter, alone, answer the dialog rather than being taken.
    if (chord == const KeyChord(LogicalKeyboardKey.escape)) {
      Navigator.of(context).pop();
    } else if (chord == const KeyChord(LogicalKeyboardKey.enter)) {
      _use();
    } else {
      setState(() => _chord = chord);
    }
    return KeyEventResult.handled;
  }

  bool get _reserved => _chord != null && EditorKey.reserved.contains(_chord);

  void _use() {
    final chord = _chord;
    if (chord == null || _reserved) return;
    Navigator.of(context).pop<_Captured>((chord: chord));
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final chord = _chord;
    final taken = chord == null
        ? null
        : ref.watch(shortcutsProvider).commandFor(chord);
    final note = switch (chord) {
      null => 'Press the keys, together.',
      _ when _reserved => 'Typing uses ${chord.label}; choose another.',
      _ when taken != null && taken != widget.command =>
        '${chord.label} is “${taken.label}”’s now, and will be taken from it.',
      final chord when !chord.worksAnywhere =>
        'Without Ctrl, Alt or Meta it works only while the page has the '
            'keyboard.',
      _ => ' ',
    };
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: Text('Shortcut for “${widget.command.label}”'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: tones.strongLine),
                ),
                child: Text(
                  chord?.label ?? '…',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(note, style: TextStyle(fontSize: 12.5, color: tones.muted)),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop<_Captured>((chord: null)),
            child: const Text('No shortcut'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: chord == null || _reserved ? null : _use,
            child: const Text('Use'),
          ),
        ],
      ),
    );
  }
}
