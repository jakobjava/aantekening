/// A menu of commands, as a right-click or a long press opens one: the
/// guide, at the point pressed, each command a key away.
library;

import 'package:flutter/material.dart';

import 'look/icons.dart';
import 'modes/key_guide.dart';
import 'modes/mode_keys.dart';

/// One command in a menu; greyed out without [onSelected].
@immutable
class MenuCommand {
  const MenuCommand(
    this.label,
    this.onSelected, {
    this.shortcut,
    this.checked = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onSelected;

  /// Drawn before its label, where it has one.
  final AppIcon? icon;

  /// Its keys elsewhere, as a tooltip names them: "Ctrl+C".
  final String? shortcut;

  /// Whether what it turns on and off is on, drawn with a tick.
  final bool checked;
}

/// More to offer in every menu opened beneath it, after its own commands:
/// the page's layers — formatting the text, formulas — in a text box's
/// menu, say.
class MenuExtras extends InheritedWidget {
  const MenuExtras({required this.extras, required super.child, super.key});

  /// What is offered, made as a menu opens.
  final List<KeyAction> Function() extras;

  static List<KeyAction> Function()? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MenuExtras>()?.extras;

  @override
  bool updateShouldNotify(MenuExtras oldWidget) =>
      !identical(extras, oldWidget.extras);
}

/// Shows [groups] of commands in the guide, after them any [MenuExtras] —
/// each command on a key of a letter of its name — and runs the one taken.
Future<void> showCommandMenu(
  BuildContext context,
  List<List<MenuCommand>> groups,
) async {
  final extras = MenuExtras.of(context);
  openKeyGuide(
    context,
    pressed: 'Menu',
    atOnce: true,
    layer: () => commandLayer(groups, extras: extras?.call() ?? const []),
  );
}

/// [groups] as a layer of keys, then [extras] in a group of their own: each
/// command on the first letter of its name not already taken, so a menu's
/// keys are as easily guessed as they are read.
KeyLayer commandLayer(
  List<List<MenuCommand>> groups, {
  List<KeyAction> extras = const <KeyAction>[],
}) {
  final taken = <String>{for (final extra in extras) extra.key};
  String keyFor(String label) {
    for (final letter in label.toLowerCase().split('')) {
      if (RegExp('[a-z0-9]').hasMatch(letter) && taken.add(letter)) {
        return letter;
      }
    }
    final spare = galleryKeys(1, taken: taken).single;
    taken.add(spare);
    return spare;
  }

  return KeyLayer('Menu', <KeyGroup>[
    for (final group in groups)
      if (group.isNotEmpty)
        KeyGroup(<KeyAction>[
          for (final command in group)
            if (command.onSelected case final run?)
              KeyAction(
                keyFor(command.label),
                command.label,
                run: run,
                checked: command.checked ? true : null,
                preview: command.icon == null
                    ? null
                    : AppIconView(command.icon!, size: 14),
              )
            else
              KeyAction(
                '·',
                command.label,
                run: () {},
                enabled: false,
                preview: command.icon == null
                    ? null
                    : AppIconView(command.icon!, size: 14),
              ),
        ]),
    if (extras.isNotEmpty) KeyGroup(extras),
  ]);
}
