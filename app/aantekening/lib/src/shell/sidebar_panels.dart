/// The sidebar's buttons and the panels they open, and the columns those
/// panels are made of.
library;

import 'package:flutter/material.dart';

import '../arrangement/arrangement.dart';

/// A column of a panel, as wide as it was last dragged to be.
enum SidebarColumn {
  notebooks(248, 160, 480),
  pages(268, 160, 520),
  search(320, 240, 640),
  graph(440, 260, 1600);

  const SidebarColumn(this.initialWidth, this.minWidth, this.maxWidth);

  final double initialWidth;
  final double minWidth;
  final double maxWidth;
}

/// A button on the sidebar, and the panel it opens beside it.
enum SidebarTab {
  notebooks('Notebooks', Icons.menu_book_outlined, <SidebarColumn>[
    SidebarColumn.notebooks,
    SidebarColumn.pages,
  ]),
  search('Search', Icons.search_rounded, <SidebarColumn>[SidebarColumn.search]),
  graph('Graph', Icons.hub_outlined, <SidebarColumn>[SidebarColumn.graph]),

  /// Not a panel: turns the tab to the AI of what it shows, and back.
  ai('AI', Icons.auto_awesome_outlined, <SidebarColumn>[]);

  const SidebarTab(this.label, this.icon, this.columns);

  final String label;
  final IconData icon;

  /// The panel's columns, left to right; none for a button that opens no
  /// panel.
  final List<SidebarColumn> columns;

  bool get opensPanel => columns.isNotEmpty;
}

/// Where the sidebar's buttons go: down from its top, or up from its
/// bottom.
enum SidebarGroup implements ArrangementGroup<SidebarTab> {
  top(<SidebarTab>[
    SidebarTab.notebooks,
    SidebarTab.search,
    SidebarTab.graph,
    SidebarTab.ai,
  ]),
  bottom(<SidebarTab>[]);

  const SidebarGroup(this.defaults);

  @override
  final List<SidebarTab> defaults;
}
