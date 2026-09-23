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
    this.checked = false,
  });

  final String label;

  /// Drawn before the label; without one, the label lines up with those of
  /// the commands that have one.
  final IconData? icon;
  final VoidCallback? onSelected;

  /// Whether it cannot be taken back, and is drawn in the error colour.
  final bool destructive;

  /// Whether what it turns on and off is on, drawn with a tick.
  final bool checked;
}

/// Controls shown across the top of every command menu opened beneath it:
/// the page's text formatting, say, as OneNote shows it over its menus.
class CommandMenuHeader extends InheritedWidget {
  const CommandMenuHeader({
    required this.header,
    required super.child,
    super.key,
  });

  final Widget header;

  static Widget? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CommandMenuHeader>()?.header;

  @override
  bool updateShouldNotify(CommandMenuHeader oldWidget) =>
      !identical(header, oldWidget.header);
}

/// Shows [groups] of commands as a menu at [position], in global
/// coordinates, with a line between groups and [header] above them — by
/// default any [CommandMenuHeader] — and runs the one picked once the menu
/// has closed.
Future<void> showCommandMenu(
  BuildContext context,
  Offset position,
  List<List<MenuCommand>> groups, {
  Widget? header,
}) async {
  final scheme = Theme.of(context).colorScheme;
  header ??= CommandMenuHeader.of(context);
  final entries = <PopupMenuEntry<VoidCallback>>[
    if (header != null) _HeaderEntry(header),
  ];
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
              if (command.checked) ...<Widget>[
                const SizedBox(width: 12),
                Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
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
    // Wide enough for a header of formatting controls.
    constraints: header == null
        ? null
        : const BoxConstraints(minWidth: 112, maxWidth: 440),
  );
  picked?.call();
}

/// A [CommandMenuHeader]'s controls at the top of a menu. They act where
/// they are, so pressing one leaves the menu open.
class _HeaderEntry extends PopupMenuEntry<VoidCallback> {
  const _HeaderEntry(this.child);

  final Widget child;

  @override
  double get height => 72;

  @override
  bool represents(VoidCallback? value) => false;

  @override
  State<_HeaderEntry> createState() => _HeaderEntryState();
}

class _HeaderEntryState extends State<_HeaderEntry> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: widget.child,
  );
}
