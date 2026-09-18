/// The ribbon's state: the tab showing, whether it is collapsed, and its
/// arrangement, which is saved between sessions.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences.dart';
import 'ribbon_layout.dart';

@immutable
class RibbonState {
  const RibbonState({
    required this.layout,
    this.tab = RibbonTab.home,
    this.collapsed = false,
  });

  final RibbonLayout layout;
  final RibbonTab tab;

  /// Whether only the tab names show, leaving more room for the page.
  final bool collapsed;

  RibbonState copyWith({
    RibbonLayout? layout,
    RibbonTab? tab,
    bool? collapsed,
  }) => RibbonState(
    layout: layout ?? this.layout,
    tab: tab ?? this.tab,
    collapsed: collapsed ?? this.collapsed,
  );
}

/// Held above the page editor, so the tab and arrangement stay put when
/// another page is opened.
class RibbonController extends Notifier<RibbonState> {
  static const String _layoutKey = 'ribbon.layout';
  static const String _collapsedKey = 'ribbon.collapsed';

  @override
  RibbonState build() {
    final preferences = ref.watch(preferencesProvider).value;
    return RibbonState(
      layout: RibbonLayout.fromJson(preferences?[_layoutKey]),
      collapsed: preferences?[_collapsedKey] == true,
    );
  }

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
    if (expanding) _save(_collapsedKey, null);
  }

  void toggleCollapsed() {
    state = state.copyWith(collapsed: !state.collapsed);
    _save(_collapsedKey, state.collapsed ? true : null);
  }

  /// Moves [item] into [group], in front of the button now at [index].
  void move(RibbonItem item, RibbonGroup group, int index) {
    final layout = state.layout.move(item, group, index);
    if (layout == state.layout) return;
    state = state.copyWith(layout: layout);
    _saveLayout();
  }

  /// Puts every button back where it started.
  void resetLayout() {
    if (state.layout.isDefault) return;
    state = state.copyWith(layout: RibbonLayout.defaults);
    _saveLayout();
  }

  void _saveLayout() =>
      _save(_layoutKey, state.layout.isDefault ? null : state.layout.toJson());

  void _save(String key, Object? value) {
    final preferences = ref.read(preferencesProvider).value;
    if (preferences != null) unawaited(preferences.set(key, value));
  }
}

final ribbonProvider = NotifierProvider<RibbonController, RibbonState>(
  RibbonController.new,
);
