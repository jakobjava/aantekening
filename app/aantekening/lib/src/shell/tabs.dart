/// The tabs along the top of the window, each with a page of its own and a
/// sidebar that acts on it alone.
library;

import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';
import 'sidebar_panels.dart';

/// One tab: what its sidebar has chosen and is showing.
@immutable
class NoteTab {
  const NoteTab({
    required this.id,
    this.notebookId,
    this.sectionId,
    this.pageId,
    this.search = '',
    this.panel = SidebarTab.notebooks,
    this.ai = false,
  });

  /// Tells tabs apart for as long as they are open; not kept between
  /// sessions.
  final int id;

  final String? notebookId;
  final String? sectionId;

  /// The page the tab shows, or null for none.
  final String? pageId;

  /// What the tab's search panel is looking for.
  final String search;

  /// The sidebar panel open beside the tab's page, or null for none.
  final SidebarTab? panel;

  /// Whether the tab shows the AI of what it has chosen — its page, or else
  /// its section, or else its notebook — in place of the page.
  final bool ai;

  /// Whether the tab has chosen anything: a notebook, a section, a page.
  bool get hasChoice =>
      notebookId != null || sectionId != null || pageId != null;

  /// The one of this tab's notebook, section and page that [choice] names.
  String? chosen(TabChoice choice) => switch (choice) {
    TabChoice.notebook => notebookId,
    TabChoice.section => sectionId,
    TabChoice.page => pageId,
  };

  /// This tab with [id] chosen as its [choice].
  NoteTab choosing(TabChoice choice, String? id) => _copy(
    notebookId: choice == TabChoice.notebook ? id : notebookId,
    sectionId: choice == TabChoice.section ? id : sectionId,
    pageId: choice == TabChoice.page ? id : pageId,
  );

  NoteTab searching(String search) => _copy(search: search);

  NoteTab showing(SidebarTab? panel) => _copy(panel: panel);

  NoteTab inAi(bool ai) => ai == this.ai ? this : _copy(ai: ai);

  /// This tab as another, [id], opened again once this one was closed.
  NoteTab reopenedAs(int id) => NoteTab(
    id: id,
    notebookId: notebookId,
    sectionId: sectionId,
    pageId: pageId,
    search: search,
    panel: panel,
    ai: ai,
  );

  /// This tab with nothing chosen of [ids] or of what lies in them.
  NoteTab forgetting(Set<String> ids) {
    final notebook = ids.contains(notebookId);
    final section = notebook || ids.contains(sectionId);
    final page = section || ids.contains(pageId);
    return !page
        ? this
        : _copy(
            notebookId: notebook ? null : notebookId,
            sectionId: section ? null : sectionId,
            pageId: null,
          );
  }

  /// This tab with what is given changed, null included.
  NoteTab _copy({
    Object? notebookId = _same,
    Object? sectionId = _same,
    Object? pageId = _same,
    String? search,
    Object? panel = _same,
    bool? ai,
  }) => NoteTab(
    id: id,
    notebookId: _or(notebookId, this.notebookId),
    sectionId: _or(sectionId, this.sectionId),
    pageId: _or(pageId, this.pageId),
    search: search ?? this.search,
    panel: _or(panel, this.panel),
    ai: ai ?? this.ai,
  );

  static const Object _same = Object();

  static T? _or<T>(Object? given, T? kept) =>
      identical(given, _same) ? kept : given as T?;

  /// What is kept between sessions: all but the search.
  Map<String, Object?> toJson() => <String, Object?>{
    if (notebookId != null) 'notebook': notebookId,
    if (sectionId != null) 'section': sectionId,
    if (pageId != null) 'page': pageId,
    'panel': panel?.name ?? _noPanel,
    if (ai) 'ai': true,
  };

  static NoteTab fromJson(int id, Map<String, Object?> json) => NoteTab(
    id: id,
    notebookId: readStringOrNull(json, 'notebook'),
    sectionId: readStringOrNull(json, 'section'),
    pageId: readStringOrNull(json, 'page'),
    panel: panelNamed(readStringOrNull(json, 'panel')),
    ai: readBool(json, 'ai'),
  );

  /// Saved for a panel closed on purpose, rather than nothing, which opens
  /// the notebooks as a new tab does.
  static const String _noPanel = 'none';

  /// The panel saved as [name].
  static SidebarTab? panelNamed(String? name) => name == _noPanel
      ? null
      : switch (SidebarTab.values.asNameMap()[name]) {
          final tab? when tab.opensPanel => tab,
          _ => SidebarTab.notebooks,
        };
}

/// The notebook, section and page a tab has chosen.
enum TabChoice { notebook, section, page }

@immutable
class TabsState {
  const TabsState(this.tabs, this.active);

  /// Left to right; never empty.
  final List<NoteTab> tabs;

  /// The index of the tab showing.
  final int active;

  NoteTab get current => tabs[active];
}

/// The open tabs, and which one is showing, remembered between sessions.
class TabsController extends Notifier<TabsState> {
  static const String _tabsKey = 'tabs';
  static const String _activeKey = 'tabs.active';

  /// Where the panel open was kept before there were tabs.
  static const String _legacyPanelKey = 'sidebar.open';

  int _nextId = 0;

  /// How many pages back each tab remembers, and how many closed tabs are
  /// kept to be reopened.
  static const int _remembered = 50;

  /// The pages each tab has left, by tab, the most recent last; and those
  /// gone back from, to go forward to again.
  final Map<int, List<String>> _back = <int, List<String>>{};
  final Map<int, List<String>> _forward = <int, List<String>>{};

  /// The page being gone back or forward to, whose opening is not itself
  /// remembered as a step.
  String? _travellingTo;

  /// The tabs closed, the most recent last.
  final List<NoteTab> _closed = <NoteTab>[];

  /// The tabs as last saved, so a change to what is not saved — a search —
  /// writes nothing.
  String? _saved;

  @override
  TabsState build() {
    final saved = ref.preference(_tabsKey);
    final tabs = <NoteTab>[
      if (saved is List)
        for (final tab in saved.whereType<Map<Object?, Object?>>())
          NoteTab.fromJson(_nextId++, tab.cast<String, Object?>()),
    ];
    if (tabs.isEmpty) {
      final legacy = ref.preference(_legacyPanelKey);
      tabs.add(
        NoteTab(
          id: _nextId++,
          panel: NoteTab.panelNamed(legacy is String ? legacy : null),
        ),
      );
    }
    final active = ref.preference(_activeKey);
    return TabsState(
      tabs,
      active is int ? active.clamp(0, tabs.length - 1) : 0,
    );
  }

  /// Opens a tab after the one showing and shows it: with [pageId] and the
  /// section and notebook it is in, or else on the notebooks and pages the
  /// tab showing has chosen, with no page yet.
  void open({String? notebookId, String? sectionId, String? pageId}) {
    final from = state.current;
    final tab = pageId == null
        ? NoteTab(
            id: _nextId++,
            notebookId: from.notebookId,
            sectionId: from.sectionId,
          )
        : NoteTab(
            id: _nextId++,
            notebookId: notebookId,
            sectionId: sectionId,
            pageId: pageId,
            panel: from.panel,
          );
    final at = state.active + 1;
    _set(TabsState(<NoteTab>[...state.tabs]..insert(at, tab), at));
  }

  /// Closes the tab at [index]. Closing the last one opens a new, empty tab
  /// in its place, so there is always one.
  void close(int index) {
    _closed.add(state.tabs[index]);
    if (_closed.length > _remembered) _closed.removeAt(0);
    final tabs = <NoteTab>[...state.tabs]..removeAt(index);
    if (tabs.isEmpty) tabs.add(NoteTab(id: _nextId++));
    final active = index < state.active || state.active >= tabs.length
        ? state.active - 1
        : state.active;
    _set(TabsState(tabs, active.clamp(0, tabs.length - 1)));
  }

  /// Closes the tab showing.
  void closeShowing() => close(state.active);

  bool get canReopen => _closed.isNotEmpty;

  /// Opens the tab closed last again, after the one showing, as it was.
  void reopen() {
    if (_closed.isEmpty) return;
    final tab = _closed.removeLast().reopenedAs(_nextId++);
    final at = state.active + 1;
    _set(TabsState(<NoteTab>[...state.tabs]..insert(at, tab), at));
  }

  /// Shows the [number]th tab from the left, counting from 1; 9 is the last,
  /// however many there are.
  void showNumber(int number) {
    final count = state.tabs.length;
    if (number == 9) {
      activate(count - 1);
    } else if (number <= count) {
      activate(number - 1);
    }
  }

  bool get canGoBack => _back[state.current.id]?.isNotEmpty ?? false;

  bool get canGoForward => _forward[state.current.id]?.isNotEmpty ?? false;

  /// The page the tab showing had open before this one, taken as the page
  /// it is going to, or null if there is none.
  String? goBack() => _travel(from: _back, to: _forward);

  /// The page the tab showing went back from, taken as the page it is going
  /// to, or null if there is none.
  String? goForward() => _travel(from: _forward, to: _back);

  String? _travel({
    required Map<int, List<String>> from,
    required Map<int, List<String>> to,
  }) {
    final tab = state.current;
    final steps = from[tab.id];
    if (steps == null || steps.isEmpty) return null;
    final target = steps.removeLast();
    if (tab.pageId case final here?) (to[tab.id] ??= <String>[]).add(here);
    return _travellingTo = target;
  }

  /// Forgets the page being gone to, which could not be opened.
  void cancelTravel() => _travellingTo = null;

  /// Remembers that the tab showing is leaving [from] for [to], unless it is
  /// going back or forward.
  void _step(NoteTab tab, String? from, String? to) {
    if (from == to) return;
    if (to != null && to == _travellingTo) {
      _travellingTo = null;
      return;
    }
    if (from == null) return;
    final back = _back[tab.id] ??= <String>[];
    back.add(from);
    if (back.length > _remembered) back.removeAt(0);
    _forward[tab.id]?.clear();
  }

  /// Shows the AI of what the tab showing has chosen in place of its page,
  /// or the page again — so long as it has chosen something.
  void toggleAi() {
    if (!state.current.hasChoice) return;
    updateCurrent((tab) => tab.inAi(!tab.ai));
  }

  /// Closes every tab but the one at [index], and shows that one.
  void closeOthers(int index) =>
      _set(TabsState(<NoteTab>[state.tabs[index]], 0));

  /// Shows the tab at [index].
  void activate(int index) {
    if (index == state.active) return;
    _set(TabsState(state.tabs, index));
  }

  /// Shows the tab [by] places to the right of the one showing, or to the
  /// left for a negative [by], going round from either end.
  void step(int by) => activate((state.active + by) % state.tabs.length);

  /// Moves the tab at [from] to [to], the tab showing still showing.
  void move(int from, int to) {
    if (from == to) return;
    final showing = state.current;
    final tabs = <NoteTab>[...state.tabs];
    final tab = tabs.removeAt(from);
    tabs.insert(to.clamp(0, tabs.length), tab);
    _set(TabsState(tabs, tabs.indexOf(showing)));
  }

  /// Changes the tab showing.
  void updateCurrent(NoteTab Function(NoteTab tab) change) {
    final changed = change(state.current);
    if (identical(changed, state.current)) return;
    _step(changed, state.current.pageId, changed.pageId);
    _set(
      TabsState(
        <NoteTab>[...state.tabs]..[state.active] = changed,
        state.active,
      ),
    );
  }

  /// Unchooses [ids] — notebooks, sections or pages deleted — and what lies
  /// in them, in every tab.
  void forget(Iterable<String> ids) {
    final gone = ids.toSet();
    final tabs = <NoteTab>[for (final tab in state.tabs) tab.forgetting(gone)];
    if (!listEquals(tabs, state.tabs)) _set(TabsState(tabs, state.active));
  }

  /// Unchooses what tabs kept from an earlier session that is no longer in
  /// [store], or is in its recycle bin.
  Future<void> forgetMissing(AantekeningStore store) async {
    final gone = <String>{};
    for (final tab in state.tabs) {
      if (tab.notebookId case final id?) {
        final notebook = await store.library.findNotebook(id);
        if (notebook == null || notebook.isDeleted) gone.add(id);
      }
      if (tab.sectionId case final id?) {
        final section = await store.library.findSection(id);
        if (section == null || section.isDeleted) gone.add(id);
      }
      if (tab.pageId case final id?) {
        final page = await store.pages.findPage(id);
        if (page == null || page.isDeleted) gone.add(id);
      }
    }
    if (gone.isNotEmpty) forget(gone);
  }

  void _set(TabsState next) {
    state = next;
    final tabs = <Object?>[for (final tab in next.tabs) tab.toJson()];
    final saved = jsonEncode(<Object?>[tabs, next.active]);
    if (saved == _saved) return;
    _saved = saved;
    ref
      ..savePreference(_tabsKey, tabs)
      ..savePreference(_activeKey, next.active);
  }
}

final tabsProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);
