/// A menu of commands, as a right-click or a long press opens one.
library;

import 'package:flutter/material.dart';

import 'look/controls.dart';
import 'look/marks.dart';
import 'look/tones.dart';

/// One command in a menu; greyed out without [onSelected].
@immutable
class MenuCommand {
  const MenuCommand(
    this.label,
    this.onSelected, {
    this.shortcut,
    this.checked = false,
  });

  final String label;
  final VoidCallback? onSelected;

  /// Its keys, shown at the end of its line: "Ctrl+C".
  final String? shortcut;

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
  final tones = context.tones;
  header ??= CommandMenuHeader.of(context);
  final entries = <PopupMenuEntry<VoidCallback>>[
    if (header != null) _HeaderEntry(header),
  ];
  for (final group in groups.where((group) => group.isNotEmpty)) {
    if (entries.isNotEmpty) entries.add(const PopupMenuDivider(height: 9));
    for (final command in group) {
      final enabled = command.onSelected != null;
      entries.add(
        PopupMenuItem<VoidCallback>(
          value: command.onSelected,
          enabled: enabled,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              // A tick where it is on; the labels line up either way.
              SizedBox(
                width: 18,
                child: command.checked
                    ? Mark(MarkShape.check, color: tones.emphasis)
                    : null,
              ),
              Expanded(
                child: Text(command.label, overflow: TextOverflow.ellipsis),
              ),
              if (command.shortcut case final shortcut?) ...<Widget>[
                const SizedBox(width: 28),
                KeyHint(shortcut, color: enabled ? tones.muted : tones.faint),
              ],
            ],
          ),
        ),
      );
    }
  }
  // The menu is placed in the overlay, which the interface's size may have
  // scaled, so the point on screen is taken into it first.
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = overlay.globalToLocal(position);
  final picked = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: entries,
    constraints: header == null
        ? const BoxConstraints(minWidth: 180, maxWidth: 360)
        // Wide enough for a header of formatting controls.
        : const BoxConstraints(minWidth: 180, maxWidth: 440),
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
