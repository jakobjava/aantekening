/// The picker: the notebooks, their sections and the sections' pages in
/// three columns on one pane of glass summoned over the page, gone again
/// once a page is picked — worked from the keys as a file manager's columns
/// are, or with the pointer — and the graph of them all.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../files/bin_view.dart';
import '../graph/graph_panel.dart';
import '../look/controls.dart';
import '../look/cursor_list.dart';
import '../look/floating_pane.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/key_catch.dart';
import '../modes/key_guide.dart';
import '../modes/mode_keys.dart';
import '../providers.dart';
import '../search/search_line.dart';
import 'arranging.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'list_order.dart';
import 'new_page_dialog.dart';
import 'tabs.dart';
import 'tree_rows.dart';

/// What the picker shows.
enum PickerView {
  library('Notebooks'),
  graph('Graph');

  const PickerView(this.label);

  final String label;
}

/// Opens the picker on [view], on the page open. Keys pressed as it opens
/// are kept for it, so none is lost however fast they follow.
Future<void> showPicker(BuildContext context, WidgetRef ref, PickerView view) {
  final keys = PickerKeys();
  return showAppDialog<void>(
    context: context,
    builder: (context) => Picker(initial: view, keys: keys),
  ).whenComplete(keys.release);
}

/// The keys pressed for the picker, taken straight from the keyboard and
/// kept until it is there to take them.
class PickerKeys {
  PickerKeys() {
    _catch = KeyCatch(_press);
  }

  late final KeyCatch _catch;
  final List<String> _waiting = <String>[];
  bool Function(String pressed)? _taker;

  bool _press(String pressed) {
    final taker = _taker;
    if (taker != null) return taker(pressed);
    _waiting.add(pressed);
    return true;
  }

  /// Hands the keys to [taker] from now on, those kept first.
  void attach(bool Function(String pressed) taker) {
    _taker = taker;
    for (final pressed in List<String>.of(_waiting)) {
      taker(pressed);
    }
    _waiting.clear();
  }

  void release() => _catch.release();
}

/// One of the picker's three columns.
enum _Column {
  notebooks('Notebooks'),
  sections('Sections'),
  pages('Pages');

  const _Column(this.label);

  final String label;
}

/// A row in a column: what it is, and where it stands in its tree.
typedef _Row = ({TreeNode node, TreePlace place});

/// The picker itself: its views named along the top, and the one showing
/// beneath — the columns, or the graph.
class Picker extends ConsumerStatefulWidget {
  const Picker({
    required this.keys,
    this.initial = PickerView.library,
    super.key,
  });

  final PickerView initial;

  /// The keys pressed for it, taken from the keyboard.
  final PickerKeys keys;

  @override
  ConsumerState<Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<Picker> {
  late PickerView _view = widget.initial;

  /// The column the keys move in.
  late _Column _column;

  /// Where the cursor is in each column, by id; the first row while it is
  /// on none there is.
  String? _notebook;
  String? _section;
  String? _page;

  bool _attached = false;

  /// The tallest its rows have been, which they stay.
  double _tallest = 0;

  @override
  void initState() {
    super.initState();
    final tab = ref.read(tabsProvider).current;
    _notebook = tab.notebookId;
    _section = tab.sectionId;
    _page = tab.pageId;
    _column = _page != null
        ? _Column.pages
        : _section != null
        ? _Column.sections
        : _Column.notebooks;
  }

  @override
  void dispose() {
    // Gone with the window, as well as closed.
    widget.keys.release();
    super.dispose();
  }

  // ----------------------------------------------------------------- rows

  /// [tree]'s rows, those beneath folded ones left out.
  List<_Row> _treeOf<T extends TreeNode>(Hierarchy<T>? tree) => tree == null
      ? const <_Row>[]
      : <_Row>[
          for (final (:item, :place) in treeRows(
            tree,
            ref.watch(collapsedRowsProvider),
          ))
            (node: item, place: place),
        ];

  List<_Row> _rowsOf(_Column column) {
    switch (column) {
      case _Column.notebooks:
        return <_Row>[
          for (final notebook
              in ref.watch(notebooksProvider).value ?? const <Notebook>[])
            (node: notebook, place: TreePlace(id: notebook.id)),
        ];
      case _Column.sections:
        final notebook = _cursorOf(_Column.notebooks);
        return notebook == null
            ? const <_Row>[]
            : _treeOf(ref.watch(sectionTreeProvider(notebook)).value);
      case _Column.pages:
        final section = _cursorOf(_Column.sections);
        return section == null
            ? const <_Row>[]
            : _treeOf(ref.watch(pageTreeProvider(section)).value);
    }
  }

  String? _wanted(_Column column) => switch (column) {
    _Column.notebooks => _notebook,
    _Column.sections => _section,
    _Column.pages => _page,
  };

  /// The id the cursor is on in [column]: the one it was put on, if it is
  /// there, else the first.
  String? _cursorOf(_Column column) {
    final rows = _rowsOf(column);
    final wanted = _wanted(column);
    if (rows.any((row) => row.node.id == wanted)) return wanted;
    return rows.firstOrNull?.node.id;
  }

  TreeNode? _nodeAt(_Column column) {
    final id = _cursorOf(column);
    return _rowsOf(column).where((row) => row.node.id == id).firstOrNull?.node;
  }

  void _put(_Column column, String? id) => setState(() {
    switch (column) {
      case _Column.notebooks:
        _notebook = id;
      case _Column.sections:
        _section = id;
      case _Column.pages:
        _page = id;
    }
  });

  // ---------------------------------------------------------------- moving

  void _move(int by) {
    final rows = _rowsOf(_column);
    if (rows.isEmpty) return;
    final at = rows.indexWhere((row) => row.node.id == _cursorOf(_column));
    _put(_column, rows[(at + by).clamp(0, rows.length - 1)].node.id);
  }

  void _toEnd({required bool last}) {
    final rows = _rowsOf(_column);
    if (rows.isEmpty) return;
    _put(_column, (last ? rows.last : rows.first).node.id);
  }

  void _step(int by) {
    final to = (_column.index + by).clamp(0, _Column.values.length - 1);
    setState(() => _column = _Column.values[to]);
  }

  /// Enter: a page opens; a notebook or a section goes on to what is in it.
  void _enter() {
    if (_column != _Column.pages) {
      _step(1);
      return;
    }
    _open(_nodeAt(_Column.pages));
  }

  void _open(TreeNode? node) {
    final notebook = _cursorOf(_Column.notebooks);
    if (node is! PageRef || notebook == null) return;
    ref
        .read(libraryActionsProvider)
        .openPage(
          notebookId: notebook,
          sectionId: node.sectionId,
          pageId: node.id,
        );
  }

  /// Folds away what is beneath the row the cursor is on, or unfolds it.
  void _fold() {
    final id = _cursorOf(_column);
    final row = _rowsOf(_column).where((row) => row.node.id == id).firstOrNull;
    if (row == null || row.place.expanded == null) return;
    ref.read(collapsedRowsProvider.notifier).toggle(row.node.id);
  }

  // -------------------------------------------------------------- changing

  /// Makes something new in the column: a notebook, a section of the
  /// notebook, a page of the section — or with [beneath], a subsection or a
  /// subpage of the one the cursor is on.
  void _create({bool beneath = false}) {
    final notebook = _cursorOf(_Column.notebooks);
    final section = _cursorOf(_Column.sections);
    switch (_column) {
      case _Column.notebooks:
        unawaited(createNamedNotebook(context, ref));
      case _Column.sections:
        if (notebook == null) return;
        unawaited(
          createNamedSection(
            context,
            ref,
            notebookId: notebook,
            parentId: beneath ? section : null,
          ),
        );
      case _Column.pages:
        if (section == null) return;
        unawaited(
          createChosenPage(
            context,
            ref,
            sectionId: section,
            parentId: beneath ? _cursorOf(_Column.pages) : null,
          ),
        );
    }
  }

  Future<void> _rename() async {
    final node = _nodeAt(_column);
    if (node == null) return;
    final title = await promptForName(
      context,
      title: 'Rename',
      hint: displayTitle(node),
      initial: node.title,
      action: 'Rename',
    );
    if (title != null) {
      await ref.read(libraryActionsProvider).rename(node, title);
    }
  }

  void _delete() {
    final node = _nodeAt(_column);
    if (node != null) unawaited(deleteToBin(context, ref, node));
  }

  void _clip({required bool cut}) {
    final node = _nodeAt(_column);
    if (node == null || node is Notebook) return;
    final actions = ref.read(libraryActionsProvider);
    cut ? actions.cut(node) : actions.copy(node);
  }

  void _paste() {
    final node = _nodeAt(_column);
    final actions = ref.read(libraryActionsProvider);
    if (node != null && actions.canPaste(node)) {
      unawaited(actions.paste(node));
    }
  }

  /// The list [column] is ordered as.
  static OrderedList _listOf(_Column column) => switch (column) {
    _Column.notebooks => OrderedList.notebooks,
    _Column.sections => OrderedList.sections,
    _Column.pages => OrderedList.pages,
  };

  /// Moves the row the cursor is on [by] one, down or up, among its
  /// neighbours: past what lies beneath it.
  void _shift(int by) {
    final rows = _rowsOf(_column);
    final at = rows.indexWhere((row) => row.node.id == _cursorOf(_column));
    if (at < 0) return;
    final moved = rows[at].node;
    final to = rows
        .skip(by > 0 ? at + 1 : 0)
        .take(by > 0 ? rows.length : at)
        .where((row) => !_beneath(row, moved));
    final beside = by > 0 ? to.firstOrNull : to.lastOrNull;
    if (beside == null) return;
    unawaited(
      ref
          .read(libraryActionsProvider)
          .arrange(moved, beside.node, above: by < 0),
    );
  }

  /// Whether [row] lies beneath [node].
  static bool _beneath(_Row row, TreeNode node) =>
      row.place.ancestors.any((above) => above.id == node.id);

  /// How the column is ordered, to choose from.
  KeyLayer _orders() {
    final list = _listOf(_column);
    final order = ref.read(listOrderProvider(list));
    final keys = galleryKeys(ListOrder.values.length);
    return KeyLayer.of('Order of the ${list.name}', <KeyAction>[
      for (final (index, choice) in ListOrder.values.indexed)
        KeyAction(
          keys[index],
          choice.label,
          run: () => ref.read(listOrderProvider(list).notifier).choose(choice),
          checked: choice == order,
        ),
    ]);
  }

  /// What can be done to the row the cursor is on.
  void _menu() {
    final node = _nodeAt(_column);
    if (node != null) unawaited(showLibraryMenu(context, ref, node));
  }

  void _searchInstead() {
    Navigator.of(context).maybePop();
    ref.read(searchLineProvider.notifier).open();
  }

  void _toggleView() => setState(
    () => _view = _view == PickerView.library
        ? PickerView.graph
        : PickerView.library,
  );

  // ------------------------------------------------------------------ keys

  /// The picker's keys: what they do, and what the guide and the foot call
  /// them.
  KeyLayer _keys() {
    final pages = _column == _Column.pages;
    return KeyLayer('Picker', <KeyGroup>[
      KeyGroup(title: 'Move', <KeyAction>[
        KeyAction(
          'j',
          'Down',
          run: () => _move(1),
          also: const <String>[ModeKey.down],
        ),
        KeyAction(
          'k',
          'Up',
          run: () => _move(-1),
          also: const <String>[ModeKey.up],
        ),
        KeyAction(
          'h',
          'The column before',
          run: () => _step(-1),
          also: const <String>[ModeKey.left],
        ),
        KeyAction(
          'l',
          'The column after',
          run: () => _step(1),
          also: const <String>[ModeKey.right],
        ),
        KeyAction('g', 'The first', run: () => _toEnd(last: false)),
        KeyAction('G', 'The last', run: () => _toEnd(last: true)),
        KeyAction('z', 'Fold or unfold', run: _fold),
      ]),
      KeyGroup(title: 'Open', <KeyAction>[
        KeyAction(ModeKey.enter, pages ? 'Open' : 'Into it', run: _enter),
        KeyAction(
          't',
          'In a new tab',
          run: () {
            if (_nodeAt(_Column.pages) case final PageRef page) {
              unawaited(ref.read(libraryActionsProvider).openInNewTab(page));
            }
          },
          enabled: pages,
        ),
        KeyAction('/', 'Search instead', run: _searchInstead),
        KeyAction(ModeKey.tab, 'The graph', run: _toggleView),
      ]),
      KeyGroup(title: 'Change', <KeyAction>[
        KeyAction('n', 'New ${_newOf(_column)}', run: _create),
        if (_column != _Column.notebooks)
          KeyAction(
            'N',
            pages ? 'New subpage' : 'New subsection',
            run: () => _create(beneath: true),
          ),
        KeyAction('r', 'Rename', run: () => unawaited(_rename())),
        KeyAction(
          'd',
          'Delete',
          run: _delete,
          also: const <String>[ModeKey.delete],
        ),
        KeyAction('x', 'Cut', run: () => _clip(cut: true)),
        KeyAction('y', 'Copy', run: () => _clip(cut: false)),
        KeyAction('p', 'Paste', run: _paste),
        KeyAction('J', 'Move down', run: () => _shift(1)),
        KeyAction('K', 'Move up', run: () => _shift(-1)),
        KeyAction('o', 'Order', layer: _orders),
      ]),
      KeyGroup(<KeyAction>[
        KeyAction(ModeKey.space, 'More', run: _menu, also: const <String>['.']),
        KeyAction('b', 'Bin', run: () => unawaited(showBin(context))),
        KeyAction('?', 'These keys', layer: _keys),
        KeyAction(
          ModeKey.escape,
          'Close',
          run: () => Navigator.of(context).maybePop(),
        ),
      ]),
    ]);
  }

  static String _newOf(_Column column) => switch (column) {
    _Column.notebooks => 'notebook',
    _Column.sections => 'section',
    _Column.pages => 'page',
  };

  /// The graph's keys: back to the columns, and away.
  KeyLayer _graphKeys() => KeyLayer.of('Graph', <KeyAction>[
    KeyAction(ModeKey.tab, 'The notebooks', run: _toggleView),
    KeyAction(
      ModeKey.escape,
      'Close',
      run: () => Navigator.of(context).maybePop(),
    ),
  ]);

  /// Takes a key, saying whether it did.
  bool _press(String pressed) {
    // Under a dialog it opened — naming a notebook — the keys are its.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    final layer = _view == PickerView.library ? _keys() : _graphKeys();
    final action = layer.actionFor(pressed);
    if (action == null || !action.enabled) return false;
    if (action.layer case final next?) {
      openKeyGuide(context, pressed: pressed, layer: next, atOnce: true);
    } else {
      action.run!();
    }
    return true;
  }

  /// Takes the picker away, from under any dialog it opened too.
  void _close() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // A page picked is what the picker was for: it goes, and only it, even
    // from under a dialog it opened — the name of a notebook made in it.
    ref
      ..listen<String?>(selectedPageProvider, (previous, next) {
        if (next != null && next != previous) _close();
      })
      // So is the AI of what is picked.
      ..listen<bool>(
        tabsProvider.select((tabs) => tabs.current.ai),
        (_, ai) => ai ? _close() : null,
      );
    if (!_attached && ref.watch(notebooksProvider).hasValue) {
      _attached = true;
      // The keys pressed as it opened, once there is something for them.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.keys.attach(_press);
      });
    }
    final tones = context.tones;
    // As tall as the longest column, within the window — and never less
    // tall than it has been, so it holds still as notebooks of fewer pages
    // are gone through.
    final longest = _Column.values.fold<int>(
      _shortest,
      (most, column) => math.max(most, _rowsOf(column).length),
    );
    _tallest = math.max(_tallest, switch (_view) {
      PickerView.library => _ColumnView.chrome + longest * _PickerRow.height,
      PickerView.graph => _graphHeight,
    });
    final shown = switch (_view) {
      PickerView.library => _columns(),
      PickerView.graph => const GraphPanel(),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FloatingPane(
        pane: Pane.picker,
        natural: (area) =>
            BoxConstraints(maxWidth: math.min(area.width, _width)),
        // Its top always in the same place.
        position: (area, size) => Offset(
          (area.width - size.width) / 2,
          math.max(0, area.height * 0.12 - 24),
        ),
        minSize: const Size(360, 200),
        child: Glass(
          child: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PaneDragArea(
                  child: _Views(
                    view: _view,
                    onShow: (view) => setState(() => _view = view),
                  ),
                ),
                Divider(height: 1, color: tones.glassRim),
                // Sized by hand, its rows fill it.
                if (FloatingPane.sizedByHand(context))
                  Expanded(child: shown)
                else
                  Flexible(
                    child: SizedBox(height: _tallest, child: shown),
                  ),
                if (_view == PickerView.library) _Footer(layer: _keys()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// How wide the picker is at most.
  static const double _width = 840;

  /// How many rows tall its columns are at least.
  static const int _shortest = 6;

  static const double _graphHeight = 440;

  Widget _columns() {
    final tones = context.tones;
    final tab = ref.watch(tabsProvider.select((tabs) => tabs.current));
    final open = <String?>{tab.notebookId, tab.sectionId, tab.pageId};
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow, the column the keys are in shows, and the one after it —
        // or before it, from the last.
        final shown = constraints.maxWidth < 640
            ? _column == _Column.pages
                  ? const <_Column>[_Column.sections, _Column.pages]
                  : <_Column>[_column, _Column.values[_column.index + 1]]
            : _Column.values;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, column) in shown.indexed) ...<Widget>[
              if (index > 0) VerticalDivider(width: 1, color: tones.glassRim),
              Expanded(
                flex: switch (column) {
                  _Column.notebooks => 3,
                  _Column.sections => 4,
                  _Column.pages => 5,
                },
                child: _ColumnView(
                  // Its scroll its own, as the columns shown change.
                  key: ValueKey<_Column>(column),
                  label: column.label,
                  active: column == _column,
                  rows: _rowsOf(column),
                  cursor: _cursorOf(column),
                  open: open,
                  order: ref.watch(listOrderProvider(_listOf(column))),
                  empty: switch (column) {
                    _Column.notebooks => 'No notebooks yet — n makes one',
                    _Column.sections =>
                      _cursorOf(_Column.notebooks) == null
                          ? ''
                          : 'No sections yet — n makes one',
                    _Column.pages =>
                      _cursorOf(_Column.sections) == null
                          ? ''
                          : 'No pages yet — n makes one',
                  },
                  onTap: (node) {
                    setState(() => _column = column);
                    _put(column, node.id);
                    _open(node);
                  },
                  onMenu: (node) {
                    _put(column, node.id);
                    unawaited(showLibraryMenu(context, ref, node));
                  },
                  onFold: ref.read(collapsedRowsProvider.notifier).toggle,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The picker's views, named along its top, the one showing marked, and
/// the keys it answers to most.
class _Views extends StatelessWidget {
  const _Views({required this.view, required this.onShow});

  final PickerView view;
  final ValueChanged<PickerView> onShow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 10),
          for (final each in PickerView.values)
            DropTab(
              each.label,
              showing: each == view,
              onPressed: () => onShow(each),
            ),
          const SizedBox(width: 12),
          const Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: KeyHint(
                'Tab  switch     ?  keys     Esc  close',
                overflow: TextOverflow.fade,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// One column: its name, how it is ordered, and its rows — the cursor's
/// marked in the accent while the keys are in the column, and what the tab
/// has open marked along its edge.
class _ColumnView extends ConsumerWidget {
  const _ColumnView({
    required this.label,
    required this.active,
    required this.rows,
    required this.cursor,
    required this.open,
    required this.order,
    required this.empty,
    required this.onTap,
    required this.onMenu,
    required this.onFold,
    super.key,
  });

  final String label;
  final bool active;
  final List<_Row> rows;
  final String? cursor;
  final Set<String?> open;
  final ListOrder order;
  final String empty;
  final ValueChanged<TreeNode> onTap;
  final ValueChanged<TreeNode> onMenu;
  final ValueChanged<String> onFold;

  /// How tall a column is, but for its rows: its heading, and the space
  /// at its foot.
  static const double chrome = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final actions = ref.read(libraryActionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
          child: Row(
            children: <Widget>[
              SmallCaps(label, color: active ? tones.emphasis : tones.muted),
              const Spacer(),
              if (order != ListOrder.arranged) KeyHint(order.label),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    empty,
                    style: TextStyle(fontSize: 12.5, color: tones.faint),
                  ),
                )
              : CursorList(
                  cursor: switch (rows.indexWhere(
                    (row) => row.node.id == cursor,
                  )) {
                    -1 => null,
                    final index => index,
                  },
                  padding: const EdgeInsets.fromLTRB(5, 0, 5, 6),
                  itemCount: rows.length,
                  itemExtent: _PickerRow.height,
                  itemBuilder: (context, index) {
                    final (:node, :place) = rows[index];
                    final row = _PickerRow(
                      node: node,
                      place: place,
                      cursor: node.id == cursor,
                      active: active,
                      open: open.contains(node.id),
                      onTap: () => onTap(node),
                      onMenu: () => onMenu(node),
                      onFold: () => onFold(node.id),
                    );
                    Widget arrangeable<T extends TreeNode>(T node) =>
                        ArrangeableRow<T>(
                          item: node,
                          enabled: true,
                          accepts: (moved) =>
                              !_PickerState._beneath(rows[index], moved),
                          onArrange: (moved, {required above}) => unawaited(
                            actions.arrange(moved, node, above: above),
                          ),
                          child: row,
                        );
                    return switch (node) {
                      final Notebook notebook => arrangeable(notebook),
                      final Section section => arrangeable(section),
                      final PageRef page => arrangeable(page),
                      _ => row,
                    };
                  },
                ),
        ),
      ],
    );
  }
}

/// A row of the picker: its name, set in from the left as deep as it lies
/// in its tree, with a chevron to fold what is beneath it.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.node,
    required this.place,
    required this.cursor,
    required this.active,
    required this.open,
    required this.onTap,
    required this.onMenu,
    required this.onFold,
  });

  final TreeNode node;
  final TreePlace place;

  /// Whether the cursor of its column is on it.
  final bool cursor;

  /// Whether the keys are in its column.
  final bool active;

  /// Whether the tab has it open.
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onFold;

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final lit = cursor && active;
    final expanded = place.expanded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: lit
            ? tones.lift
            : cursor
            ? tones.veil
            : Colors.transparent,
        borderRadius: Corners.controlRadius,
        child: InkWell(
          borderRadius: Corners.controlRadius,
          hoverColor: tones.veil,
          onTap: onTap,
          onSecondaryTap: onMenu,
          onLongPress: onMenu,
          child: Row(
            children: <Widget>[
              // The cursor, a drop of the accent along the edge; what the
              // tab has open, a round one.
              SizedBox(
                width: 12,
                child: Center(
                  child: lit
                      ? const Drop()
                      : open
                      ? const Drop.dot(size: 5)
                      : null,
                ),
              ),
              SizedBox(width: place.depth * 14.0),
              SizedBox(
                width: 18,
                child: expanded == null
                    ? null
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onFold,
                        child: Mark(
                          expanded
                              ? MarkShape.chevronDown
                              : MarkShape.chevronRight,
                          size: 9,
                          color: tones.muted,
                        ),
                      ),
              ),
              Expanded(
                child: Text(
                  displayTitle(node),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: lit || open ? FontWeight.w600 : FontWeight.w400,
                    color: tones.text,
                  ),
                ),
              ),
              if (node is! PageRef)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Mark(
                    MarkShape.chevronRight,
                    size: 8,
                    color: tones.faint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The keys the picker answers to most, along its foot.
class _Footer extends StatelessWidget {
  const _Footer({required this.layer});

  final KeyLayer layer;

  /// The keys shown, and what they are called here, where shorter.
  static const List<(String, String?)> _most = <(String, String?)>[
    ('j', 'k  up and down'),
    ('h', 'l  between columns'),
    (ModeKey.enter, null),
    ('n', null),
    ('r', null),
    ('d', null),
    (ModeKey.space, null),
    ('/', null),
  ];

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tones.glassRim)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
        child: Wrap(
          spacing: 14,
          runSpacing: 4,
          children: <Widget>[
            for (final (key, called) in _most)
              if (layer.actionFor(key) case final action?)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    KeyCap(key),
                    const SizedBox(width: 6),
                    Text(
                      called ?? action.label,
                      style: TextStyle(fontSize: 12, color: tones.muted),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
