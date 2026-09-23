/// The sidebar's state: which panel is open in the tab showing, how wide
/// its columns are, and where its buttons are — all remembered between
/// sessions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../arrangement/arrangement.dart';
import '../arrangement/arrangement_controller.dart';
import '../preferences.dart';
import 'sidebar_panels.dart';
import 'tabs.dart';

export 'sidebar_panels.dart';

@immutable
class SidebarState {
  const SidebarState({
    this.open = SidebarTab.notebooks,
    this.widths = const <SidebarColumn, double>{},
  });

  /// The panel showing beside the tab showing, or null while none is.
  final SidebarTab? open;

  /// The widths the columns have been dragged to, the same in every tab.
  final Map<SidebarColumn, double> widths;

  double widthOf(SidebarColumn column) => widths[column] ?? column.initialWidth;
}

/// The sidebar of the tab showing: each tab has its own panel open, or
/// none, and the tabs share how wide the panels' columns are.
class SidebarController extends Notifier<SidebarState> {
  static const String _widthsKey = 'sidebar.widths';

  @override
  SidebarState build() {
    final widths = ref.preference(_widthsKey);
    return SidebarState(
      open: ref.watch(tabsProvider.select((tabs) => tabs.current.panel)),
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

  void _open(SidebarTab? tab) => ref
      .read(tabsProvider.notifier)
      .updateCurrent((current) => current.showing(tab));

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
