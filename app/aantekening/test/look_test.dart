import 'package:aantekening/src/commands/app_command.dart';
import 'package:aantekening/src/commands/editor_keys.dart';
import 'package:aantekening/src/commands/fuzzy.dart';
import 'package:aantekening/src/commands/key_chord.dart';
import 'package:aantekening/src/commands/shortcuts.dart';
import 'package:aantekening/src/look/appearance.dart';
import 'package:aantekening/src/look/tones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fuzzyScore', () {
    test('finds letters in order, and nothing out of order', () {
      expect(fuzzyScore('npg', 'New page'), isNotNull);
      expect(fuzzyScore('gpn', 'New page'), isNull);
      expect(fuzzyScore('', 'anything'), 0);
    });

    test('prefers the starts of words, and shorter names', () {
      expect(
        fuzzyScore('np', 'New page')!,
        greaterThan(fuzzyScore('np', 'Snapping')!),
      );
      expect(
        fuzzyScore('mech', 'Mechanics')!,
        greaterThan(fuzzyScore('mech', 'Quantum mechanics')!),
      );
    });

    test('ignores case and spaces', () {
      expect(fuzzyScore('NEW PAGE', 'new page'), isNotNull);
    });
  });

  group('KeyChord', () {
    const chord = KeyChord(LogicalKeyboardKey.keyP, control: true, shift: true);

    test('is written as it is typed', () {
      expect(chord.label, 'Ctrl+Shift+P');
      expect(
        const KeyChord(LogicalKeyboardKey.arrowUp, alt: true).label,
        'Alt+Up',
      );
    });

    test('is saved and read back', () {
      expect(KeyChord.decode(chord.encode()), chord);
      expect(KeyChord.decode('not a chord'), isNull);
      expect(KeyChord.decode(3), isNull);
    });

    test('works anywhere only with a modifier, or as a function key', () {
      expect(chord.worksAnywhere, isTrue);
      expect(const KeyChord(LogicalKeyboardKey.keyP).worksAnywhere, isFalse);
      expect(const KeyChord(LogicalKeyboardKey.f2).worksAnywhere, isTrue);
    });
  });

  group('ShortcutBindings', () {
    const bindings = ShortcutBindings();
    const ctrlK = KeyChord(LogicalKeyboardKey.keyK, control: true);

    test('start with every command\'s own shortcuts', () {
      for (final command in AppCommand.values) {
        expect(bindings.of(command), command.defaults);
      }
      expect(
        bindings.commandFor(
          const KeyChord(LogicalKeyboardKey.keyP, control: true),
        ),
        AppCommand.goTo,
      );
    });

    test('give no two commands the same chord', () {
      final seen = <KeyChord, AppCommand>{};
      for (final command in AppCommand.values) {
        for (final chord in command.defaults) {
          expect(seen[chord], isNull, reason: '$chord: $command');
          seen[chord] = command;
        }
      }
    });

    test('leave to typing the chords it takes', () {
      const ctrlMinus = KeyChord(LogicalKeyboardKey.minus, control: true);
      expect(EditorKey.reserved, contains(ctrlMinus));
      expect(caughtAnywhere(ctrlMinus), isFalse, reason: 'strikethrough');
      expect(
        caughtAnywhere(const KeyChord(LogicalKeyboardKey.keyP, control: true)),
        isTrue,
      );
      expect(caughtAnywhere(const KeyChord(LogicalKeyboardKey.keyP)), isFalse);
      expect(
        caughtAnywhere(EditorKey.showTab.chords.first),
        isTrue,
        reason: 'the window shows a tab',
      );
    });

    test('take a chord from the command that had it', () {
      final ctrlP = AppCommand.goTo.defaults.first;
      final changed = bindings.binding(AppCommand.settings, <KeyChord>[ctrlP]);
      expect(changed.commandFor(ctrlP), AppCommand.settings);
      expect(changed.of(AppCommand.goTo), isEmpty);
      expect(changed.isDefault(AppCommand.goTo), isFalse);

      final reset = changed.resetting(AppCommand.goTo);
      expect(reset.commandFor(ctrlP), AppCommand.goTo);
      expect(reset.of(AppCommand.settings), isEmpty);
    });

    test('forget a change put back as it was', () {
      final changed = bindings
          .binding(AppCommand.settings, <KeyChord>[ctrlK])
          .binding(AppCommand.settings, AppCommand.settings.defaults);
      expect(changed.allDefault, isTrue);
    });

    test('are saved and read back, leniently', () {
      final changed = bindings.binding(AppCommand.graph, <KeyChord>[ctrlK]);
      final read = ShortcutBindings.fromJson(<String, Object?>{
        ...changed.toJson(),
        'no such command': <String>['c:1'],
        AppCommand.search.name: <Object?>['garbage', 7],
      });
      expect(read.of(AppCommand.graph), <KeyChord>[ctrlK]);
      expect(read.of(AppCommand.search), isEmpty);
      expect(ShortcutBindings.fromJson('nonsense').allDefault, isTrue);
    });

    test('write tooltips with their keys', () {
      expect(bindings.tooltip(AppCommand.newTab), 'New tab  (Ctrl+T)');
      expect(
        bindings.tooltip(AppCommand.zoomIn, describe: true),
        'Zoom in  (Ctrl+= or Ctrl++)\nOr Ctrl and scroll',
      );
      expect(bindings.tooltip(AppCommand.fitPage), 'Fit page');
    });
  });

  group('Appearance', () {
    test('is saved and read back', () {
      final appearance = const Appearance().copyWith(
        mode: ThemeMode.dark,
        light: Appearance.lightPresets[2],
        dark: const ColourPair('', Color(0xFF101820), Color(0xFFF0E0D0)),
        accentOn: true,
        accent: const Color(0xFF7B5CE0),
        font: InterfaceFont.mono,
        scale: 1.25,
      );
      expect(Appearance.fromJson(appearance.toJson()), appearance);
    });

    test('reads what it does not understand as it starts', () {
      expect(Appearance.fromJson(null), const Appearance());
      expect(
        Appearance.fromJson(<String, Object?>{
          'mode': 'sideways',
          'scale': 7,
          'font': 'Comic',
        }),
        const Appearance(),
      );
    });

    test('names a pair read back after its preset', () {
      final read = Appearance.fromJson(
        const Appearance(dark: Appearance.defaultDark).toJson(),
      );
      expect(read.dark.name, Appearance.defaultDark.name);
    });

    test('knows text too faint to read', () {
      expect(Appearance.defaultLight.hardToRead, isFalse);
      expect(
        const ColourPair('', Color(0xFFFFFFFF), Color(0xFFDDDDDD)).hardToRead,
        isTrue,
      );
    });
  });

  group('Tones', () {
    test('without an accent, mark in the text colour', () {
      final tones = Tones.of(const Appearance(), Brightness.light);
      expect(tones.emphasis, Appearance.defaultLight.text);
      expect(tones.accent, isNull);
    });

    test('make an accent stand out on the base, and on the paper', () {
      // A pale yellow, chosen for a dark base, on a white one.
      const pale = Color(0xFFFFF2A8);
      final light = Tones(
        base: const Color(0xFFFFFFFF),
        text: const Color(0xFF111111),
        accent: pale,
      );
      expect(
        contrastBetween(light.emphasis, light.base),
        greaterThanOrEqualTo(3),
      );
      final dark = Tones(
        base: const Color(0xFF141414),
        text: const Color(0xFFE8E8E8),
        accent: pale,
      );
      expect(dark.emphasis, pale, reason: 'stands out as it is');
      expect(
        contrastBetween(dark.paperEmphasis, Tones.paper),
        greaterThanOrEqualTo(3.5),
        reason: 'the paper is white in dark mode too',
      );
    });

    test('put readable text on the emphasis', () {
      for (final appearance in <Appearance>[
        const Appearance(),
        const Appearance(accentOn: true),
      ]) {
        for (final brightness in Brightness.values) {
          final tones = Tones.of(appearance, brightness);
          expect(
            contrastBetween(tones.onEmphasis, tones.emphasis),
            greaterThanOrEqualTo(3),
            reason: '$brightness',
          );
        }
      }
    });
  });
}
