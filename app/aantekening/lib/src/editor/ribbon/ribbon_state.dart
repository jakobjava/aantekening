/// The ribbon's state: the tab showing, whether it is collapsed, and its
/// arrangement, which are saved between sessions.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../arrangement/arrangement_controller.dart';
import '../../preferences.dart';
import 'ribbon_layout.dart';

@immutable
class RibbonState {
  const RibbonState({this.tab = RibbonTab.home, this.collapsed = false});

  final RibbonTab tab;

  /// Whether only the tab names show, leaving more room for the page.
  final bool collapsed;

  RibbonState copyWith({RibbonTab? tab, bool? collapsed}) =>
      RibbonState(tab: tab ?? this.tab, collapsed: collapsed ?? this.collapsed);
}

/// Held above the page editor, so the tab stays put when another page is
/// opened.
class RibbonController extends Notifier<RibbonState> {
  static const String _collapsedKey = 'ribbon.collapsed';

  @override
  RibbonState build() =>
      RibbonState(collapsed: ref.preference(_collapsedKey) == true);

  /// Brings [tab] forward, as a tool's shortcut does. A collapsed ribbon
  /// stays collapsed.
  void show(RibbonTab tab) {
    if (state.tab != tab) state = state.copyWith(tab: tab);
  }

  /// Opens [tab] because it was clicked, expanding a collapsed ribbon.
  void open(RibbonTab tab) {
    if (state.tab == tab && !state.collapsed) return;
    final expanding = state.collapsed;
    state = state.copyWith(tab: tab, collapsed: false);
    if (expanding) _saveCollapsed();
  }

  void toggleCollapsed() {
    state = state.copyWith(collapsed: !state.collapsed);
    _saveCollapsed();
  }

  void _saveCollapsed() =>
      ref.savePreference(_collapsedKey, state.collapsed ? true : null);
}

final ribbonProvider = NotifierProvider<RibbonController, RibbonState>(
  RibbonController.new,
);

/// Which buttons each section of the ribbon holds, as arranged.
final ribbonLayoutProvider =
    NotifierProvider<
      ArrangementController<RibbonGroup, RibbonItem>,
      RibbonLayout
    >(() => ArrangementController('ribbon.layout', RibbonGroup.values));
