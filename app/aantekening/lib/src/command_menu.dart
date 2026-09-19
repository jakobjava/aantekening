/// A menu of commands, as a right-click or a long press opens one.
library;

import 'package:flutter/material.dart';

/// One command in a menu; greyed out without [onSelected].
@immutable
class MenuCommand {
  const MenuCommand(
    this.label,
    this.icon,
    this.onSelected, {
    this.destructive = false,
  });

  final String label;

  /// Drawn before the label; without one, the label lines up with those of
  /// the commands that have one.
  final IconData? icon;
  final VoidCallback? onSelected;

  /// Whether it cannot be taken back, and is drawn in the error colour.
  final bool destructive;
}

/// Shows [groups] of commands as a menu at [position], in global
/// coordinates, with a line between groups, and runs the one picked once
/// the menu has closed.
Future<void> showCommandMenu(
  BuildContext context,
  Offset position,
  List<List<MenuCommand>> groups,
) async {
  final scheme = Theme.of(context).colorScheme;
  final entries = <PopupMenuEntry<VoidCallback>>[];
  for (final group in groups.where((group) => group.isNotEmpty)) {
    if (entries.isNotEmpty) entries.add(const PopupMenuDivider(height: 8));
    for (final command in group) {
      final color = command.destructive ? scheme.error : null;
      entries.add(
        PopupMenuItem<VoidCallback>(
          value: command.onSelected,
          enabled: command.onSelected != null,
          height: 36,
          child: Row(
            children: <Widget>[
              if (command.icon case final icon?)
                Icon(icon, size: 18, color: color)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  command.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  final picked = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: entries,
  );
  picked?.call();
}
