/// Which keys set off which command — as they start out, or as changed in
/// the settings — and what each command does wherever it is run from.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';
import 'app_command.dart';
import 'editor_keys.dart';
import 'key_chord.dart';

/// Whether [chord] is caught wherever the keyboard is: it has Ctrl, Alt or
/// Meta, or is a function key, and typing does not take it. One that typing
/// takes — Ctrl+− strikes text through, and zooms out elsewhere — reaches
/// its command only through the page, after a text box has had it.
bool caughtAnywhere(KeyChord chord) =>
    chord.worksAnywhere && !EditorKey.reserved.contains(chord);

/// The shortcuts of every command: those it started with, unless they have
/// been changed.
@immutable
class ShortcutBindings {
  const ShortcutBindings([
    this._changed = const <AppCommand, List<KeyChord>>{},
  ]);

  final Map<AppCommand, List<KeyChord>> _changed;

  /// [command]'s shortcuts, the first being the one shown beside it.
  List<KeyChord> of(AppCommand command) =>
      _changed[command] ?? command.defaults;

  /// Whether [command] has the shortcuts it started with.
  bool isDefault(AppCommand command) => !_changed.containsKey(command);

  bool get allDefault => _changed.isEmpty;

  /// The command [chord] sets off, if any.
  AppCommand? commandFor(KeyChord chord) {
    for (final command in AppCommand.values) {
      if (of(command).contains(chord)) return command;
    }
    return null;
  }

  /// [label] with [command]'s shortcuts after it, as a tooltip gives them:
  /// "Search  (Ctrl+F or Ctrl+Shift+F)" — and with [describe], what the
  /// command does beneath. [label] is the command's own name if not given.
  String tooltip(AppCommand command, {String? label, bool describe = false}) {
    final text = label ?? command.label;
    final chords = of(command);
    final keys = chords.take(2).map((chord) => chord.label).join(' or ');
    final description = command.description;
    return <String>[
      if (keys.isEmpty) text else '$text  ($keys)',
      if (describe && description != null) description,
    ].join('\n');
  }

  /// This with [command]'s shortcuts made [chords], and those chords taken
  /// from any other command they belonged to: a chord does one thing.
  ShortcutBindings binding(AppCommand command, List<KeyChord> chords) {
    final changed = <AppCommand, List<KeyChord>>{..._changed};
    for (final other in AppCommand.values) {
      if (other == command) continue;
      final kept = of(other).where((chord) => !chords.contains(chord));
      if (kept.length != of(other).length) changed[other] = kept.toList();
    }
    changed[command] = chords;
    // A command given back its first shortcuts is no longer changed.
    changed.removeWhere((each, chords) => listEquals(chords, each.defaults));
    return ShortcutBindings(
      Map<AppCommand, List<KeyChord>>.unmodifiable(changed),
    );
  }

  /// This with [command]'s first shortcuts back, taken from whichever
  /// command had since been given them.
  ShortcutBindings resetting(AppCommand command) =>
      binding(command, command.defaults);

  Map<String, Object?> toJson() => <String, Object?>{
    for (final MapEntry(key: command, value: chords) in _changed.entries)
      command.name: <String>[for (final chord in chords) chord.encode()],
  };

  static ShortcutBindings fromJson(Object? json) {
    if (json is! Map) return const ShortcutBindings();
    final commands = AppCommand.values.asNameMap();
    return ShortcutBindings(<AppCommand, List<KeyChord>>{
      for (final MapEntry(:key, :value) in json.entries)
        if (commands[key] case final command? when value is List)
          command: <KeyChord>[
            for (final saved in value) ?KeyChord.decode(saved),
          ],
    });
  }
}

/// The shortcuts, saved as they are changed.
class ShortcutsController extends Notifier<ShortcutBindings> {
  static const String _key = 'shortcuts';

  @override
  ShortcutBindings build() => ShortcutBindings.fromJson(ref.preference(_key));

  void bind(AppCommand command, List<KeyChord> chords) =>
      _set(state.binding(command, chords));

  void reset(AppCommand command) => _set(state.resetting(command));

  void resetAll() => _set(const ShortcutBindings());

  void _set(ShortcutBindings bindings) {
    state = bindings;
    ref.savePreference(_key, bindings.allDefault ? null : bindings.toJson());
  }
}

final shortcutsProvider =
    NotifierProvider<ShortcutsController, ShortcutBindings>(
      ShortcutsController.new,
    );

/// What a command does, and whether it can be done just now.
@immutable
class CommandAction {
  const CommandAction(this.run, {this.enabled});

  final VoidCallback run;

  /// Whether there is anything for it to act on; always, if not given.
  final ValueGetter<bool>? enabled;

  bool get isEnabled => enabled?.call() ?? true;
}

/// What each command does, as the parts of the window that carry them out
/// have said: the window its own commands, the page editor the page's.
///
/// The keyboard, the command palette and the menus all run a command
/// through here, so it does the same thing however it is started.
class CommandHandlers {
  final Map<AppCommand, CommandAction> _actions = <AppCommand, CommandAction>{};

  /// Carries out [actions] from now until the function returned is called.
  VoidCallback register(Map<AppCommand, CommandAction> actions) {
    _actions.addAll(actions);
    return () {
      for (final MapEntry(key: command, value: action) in actions.entries) {
        if (identical(_actions[command], action)) _actions.remove(command);
      }
    };
  }

  /// What [command] does, if anything here carries it out.
  CommandAction? operator [](AppCommand command) => _actions[command];

  /// Runs [command] if it can be run, saying whether it was.
  bool run(AppCommand command) {
    final action = _actions[command];
    if (action == null || !action.isEnabled) return false;
    action.run();
    return true;
  }
}

final commandHandlersProvider = Provider<CommandHandlers>(
  (ref) => CommandHandlers(),
);
