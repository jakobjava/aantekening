/// The tabs on the status line, each with a page of its own, and the
/// notebook and section it is in.
library;

import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// One tab: the notebook, section and page it has chosen, and its search.
@immutable
class NoteTab {
  const NoteTab({
    required this.id,
    this.notebookId,
    this.sectionId,
    this.pageId,
    this.search = '',
    this.ai = false,
  });

  /// Tells tabs apart for as long as they are open; not kept between
  /// sessions.
  final int id;

  final String? notebookId;
  final String? sectionId;

  /// The page the tab shows, or null for none.
  final String? pageId;

  /// What the tab is searching for.
  final String search;

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

  NoteTab inAi(bool ai) => ai == this.ai ? this : _copy(ai: ai);

  /// This tab as another, [id], opened again once this one was closed.
  NoteTab reopenedAs(int id) => NoteTab(
    id: id,
    notebookId: notebookId,
    sectionId: sectionId,
    pageId: pageId,
    search: search,
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
    bool? ai,
  }) => NoteTab(
    id: id,
    notebookId: _or(notebookId, this.notebookId),
    sectionId: _or(sectionId, this.sectionId),
    pageId: _or(pageId, this.pageId),
    search: search ?? this.search,
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
    if (ai) 'ai': true,
  };

  static NoteTab fromJson(int id, Map<String, Object?> json) => NoteTab(
    id: id,
    notebookId: readStringOrNull(json, 'notebook'),
    sectionId: readStringOrNull(json, 'section'),
    pageId: readStringOrNull(json, 'page'),
    ai: readBool(json, 'ai'),
  );
}

/// The notebook, section and page a tab has chosen.
enum TabChoice { notebook, section, page }

@immutable
class TabsState {
  const TabsState(this.tabs, this.active, {this.beside, this.stacked = false});

  /// Left to right; never empty.
  final List<NoteTab> tabs;

  /// The index of the tab showing, which has the keys.
  final int active;

  /// The index of the tab shown beside it, the window split between the
  /// two, or null while it is not split.
  final int? beside;

  /// Whether the split puts one above the other, rather than side by side.
  final bool stacked;

  NoteTab get current => tabs[active];

  /// The tab shown beside the one showing, if the window is split.
  NoteTab? get besideTab => switch (beside) {
    final index? => tabs[index],
    null => null,
  };
}

/// The open tabs, and which one is showing, remembered between sessions.
class TabsController extends Notifier<TabsState> {
  static const String _tabsKey = 'tabs';
  static const String _activeKey = 'tabs.active';
  static const String _besideKey = 'tabs.beside';
  static const String _stackedKey = 'tabs.stacked';

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
    if (tabs.isEmpty) tabs.add(NoteTab(id: _nextId++));
    final shown = ref.preference(_activeKey);
    final active = shown is int ? shown.clamp(0, tabs.length - 1) : 0;
    final beside = ref.preference(_besideKey);
    return TabsState(
      tabs,
      active,
      beside: beside is int && beside != active && beside < tabs.length
          ? beside
          : null,
      stacked: ref.preference(_stackedKey) == true,
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
          );
    final at = state.active + 1;
    _set(<NoteTab>[...state.tabs]..insert(at, tab), at);
  }

  /// Closes the tab at [index]. Closing the last one opens a new, empty tab
  /// in its place, so there is always one.
  void close(int index) {
    _closed.add(state.tabs[index]);
    if (_closed.length > _remembered) _closed.removeAt(0);
    final beside = state.besideTab;
    final tabs = <NoteTab>[...state.tabs]..removeAt(index);
    if (tabs.isEmpty) tabs.add(NoteTab(id: _nextId++));
    // The tab beside one closed takes the window, whole.
    if (index == state.active && beside != null) {
      _set(tabs, tabs.indexOf(beside), besideId: null);
      return;
    }
    final active = index < state.active || state.active >= tabs.length
        ? state.active - 1
        : state.active;
    _set(tabs, active.clamp(0, tabs.length - 1));
  }

  /// Closes the tab showing.
  void closeShowing() => close(state.active);

  bool get canReopen => _closed.isNotEmpty;

  /// Opens the tab closed last again, after the one showing, as it was.
  void reopen() {
    if (_closed.isEmpty) return;
    final tab = _closed.removeLast().reopenedAs(_nextId++);
    final at = state.active + 1;
    _set(<NoteTab>[...state.tabs]..insert(at, tab), at);
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
      _set(<NoteTab>[state.tabs[index]], 0, besideId: null);

  /// Shows the tab at [index]. The tab beside the one showing, it takes
  /// the keys, and the one showing goes beside it.
  void activate(int index) {
    if (index == state.active) return;
    _set(
      state.tabs,
      index,
      besideId: index == state.beside ? state.current.id : _keep,
    );
  }

  /// Splits the window, the tab showing beside another — [stacked], one
  /// above the other: the next tab, or a new one on the same notebook and
  /// section, which takes the keys. Split already, it only turns.
  void split({required bool stacked}) {
    if (state.beside != null) {
      _set(state.tabs, state.active, stacked: stacked);
      return;
    }
    final showing = state.current;
    if (state.tabs.length > 1) {
      _set(
        state.tabs,
        (state.active + 1) % state.tabs.length,
        besideId: showing.id,
        stacked: stacked,
      );
      return;
    }
    final tab = NoteTab(
      id: _nextId++,
      notebookId: showing.notebookId,
      sectionId: showing.sectionId,
    );
    _set(
      <NoteTab>[...state.tabs, tab],
      state.tabs.length,
      besideId: showing.id,
      stacked: stacked,
    );
  }

  /// Shows the tab showing alone, the one beside it a tab again.
  void unsplit() => _set(state.tabs, state.active, besideId: null);

  /// Gives the keys to the tab beside the one showing.
  void toBeside() {
    if (state.beside case final beside?) activate(beside);
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
    _set(tabs, tabs.indexOf(showing));
  }

  /// Changes the tab showing.
  void updateCurrent(NoteTab Function(NoteTab tab) change) {
    final changed = change(state.current);
    if (identical(changed, state.current)) return;
    _step(changed, state.current.pageId, changed.pageId);
    _set(<NoteTab>[...state.tabs]..[state.active] = changed, state.active);
  }

  /// Unchooses [ids] — notebooks, sections or pages deleted — and what lies
  /// in them, in every tab.
  void forget(Iterable<String> ids) {
    final gone = ids.toSet();
    final tabs = <NoteTab>[for (final tab in state.tabs) tab.forgetting(gone)];
    if (!listEquals(tabs, state.tabs)) _set(tabs, state.active);
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

  /// Stands for the tab beside the one showing kept as it is.
  static const Object _keep = Object();

  /// Shows [tabs], the one at [active] showing and [besideId]'s beside it —
  /// by default the tab beside it now, wherever it has gone among [tabs] —
  /// and saves them.
  void _set(
    List<NoteTab> tabs,
    int active, {
    Object? besideId = _keep,
    bool? stacked,
  }) {
    final id = identical(besideId, _keep) ? state.besideTab?.id : besideId;
    final beside = id == null ? -1 : tabs.indexWhere((tab) => tab.id == id);
    final next = TabsState(
      tabs,
      active,
      beside: beside < 0 || beside == active ? null : beside,
      stacked: stacked ?? state.stacked,
    );
    state = next;
    final saving = <Object?>[for (final tab in next.tabs) tab.toJson()];
    final saved = jsonEncode(<Object?>[
      saving,
      next.active,
      next.beside,
      next.stacked,
    ]);
    if (saved == _saved) return;
    _saved = saved;
    ref
      ..savePreference(_tabsKey, saving)
      ..savePreference(_activeKey, next.active)
      ..savePreference(_besideKey, next.beside)
      ..savePreference(_stackedKey, next.stacked ? true : null);
  }
}

final tabsProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);
