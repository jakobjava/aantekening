/// The sidebar's state: which panel is open, how wide its columns are, and
/// where its buttons are — all remembered between sessions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../arrangement/arrangement.dart';
import '../arrangement/arrangement_controller.dart';
import '../preferences.dart';

/// A column of a panel, as wide as it was last dragged to be.
enum SidebarColumn {
  notebooks(248, 160, 480),
  pages(268, 160, 520),
  search(320, 240, 640),
  graph(440, 260, 1600),
  assistant(340, 280, 640);

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
  assistant('Local AI', Icons.auto_awesome_outlined, <SidebarColumn>[
    SidebarColumn.assistant,
  ]);

  const SidebarTab(this.label, this.icon, this.columns);

  final String label;
  final IconData icon;

  /// The panel's columns, left to right.
  final List<SidebarColumn> columns;
}

/// Where the sidebar's buttons go: down from its top, or up from its
/// bottom.
enum SidebarGroup implements ArrangementGroup<SidebarTab> {
  top(<SidebarTab>[SidebarTab.notebooks, SidebarTab.search, SidebarTab.graph]),
  bottom(<SidebarTab>[SidebarTab.assistant]);

  const SidebarGroup(this.defaults);

  @override
  final List<SidebarTab> defaults;
}

@immutable
class SidebarState {
  const SidebarState({
    this.open = SidebarTab.notebooks,
    this.widths = const <SidebarColumn, double>{},
  });

  /// The panel showing, or null while none is.
  final SidebarTab? open;

  /// The widths the columns have been dragged to.
  final Map<SidebarColumn, double> widths;

  double widthOf(SidebarColumn column) => widths[column] ?? column.initialWidth;
}

class SidebarController extends Notifier<SidebarState> {
  static const String _openKey = 'sidebar.open';
  static const String _widthsKey = 'sidebar.widths';

  /// Saved for a sidebar closed on purpose, rather than nothing, which opens
  /// the notebooks as on the first run.
  static const String _none = 'none';

  @override
  SidebarState build() {
    final open = ref.preference(_openKey);
    final widths = ref.preference(_widthsKey);
    return SidebarState(
      open: open == _none
          ? null
          : SidebarTab.values.asNameMap()[open] ?? SidebarTab.notebooks,
      widths: <SidebarColumn, double>{
        if (widths is Map)
          for (final column in SidebarColumn.values)
            if (widths[column.name] case final num width)
              column: width.toDouble().clamp(column.minWidth, column.maxWidth),
      },
    );
  }

  /// Opens [tab]'s panel, or closes it if it is the one open.
  void toggle(SidebarTab tab) => state.open == tab ? close() : show(tab);

  void show(SidebarTab tab) => _open(tab);

  void close() => _open(null);

  void _open(SidebarTab? tab) {
    if (state.open == tab) return;
    state = SidebarState(open: tab, widths: state.widths);
    ref.savePreference(_openKey, tab?.name ?? _none);
  }

  /// Makes [column] [width] wide, within its limits. Kept to itself until
  /// [saveWidths], so dragging a column does not write on every frame.
  void resize(SidebarColumn column, double width) {
    final clamped = width.clamp(column.minWidth, column.maxWidth);
    if (clamped == state.widthOf(column)) return;
    state = SidebarState(
      open: state.open,
      widths: <SidebarColumn, double>{...state.widths, column: clamped},
    );
  }

  void saveWidths() => ref.savePreference(_widthsKey, <String, Object?>{
    for (final entry in state.widths.entries) entry.key.name: entry.value,
  });
}

final sidebarProvider = NotifierProvider<SidebarController, SidebarState>(
  SidebarController.new,
);

/// Where the sidebar's buttons are, as arranged.
final sidebarLayoutProvider =
    NotifierProvider<
      ArrangementController<SidebarGroup, SidebarTab>,
      Arrangement<SidebarGroup, SidebarTab>
    >(() => ArrangementController('sidebar.layout', SidebarGroup.values));
