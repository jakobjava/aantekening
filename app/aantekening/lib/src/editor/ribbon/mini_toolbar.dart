/// The Home tab's text formatting, small, for a right-click menu.
library;

import 'package:flutter/material.dart';

import 'ribbon_items.dart';
import 'ribbon_layout.dart';

/// The text formatting of the Home tab in two rows, over a right-click menu
/// as OneNote's floating toolbar is: the ribbon's own buttons, acting on the
/// text being edited or the boxes picked, as they do on the ribbon.
class MiniToolbar extends StatelessWidget {
  const MiniToolbar({required this.commands, super.key});

  final RibbonCommands commands;

  static const List<List<RibbonItem>> _rows = <List<RibbonItem>>[
    <RibbonItem>[RibbonItem.fontSize, RibbonItem.paragraphStyle],
    <RibbonItem>[
      RibbonItem.bold,
      RibbonItem.italic,
      RibbonItem.underline,
      RibbonItem.highlight,
      RibbonItem.textColor,
      RibbonItem.bullets,
      RibbonItem.numbering,
      RibbonItem.todo,
    ],
  ];

  @override
  Widget build(BuildContext context) => RibbonScope(
    commands: commands,
    // As on the ribbon, pressing a button leaves the caret where it is.
    child: ExcludeFocus(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final row in _rows)
            SizedBox(
              height: RibbonMetrics.row,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final item in row) RibbonItemView(item: item),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
