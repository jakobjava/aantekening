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

part 'picker_actions.dart';
part 'picker_columns.dart';
part 'picker_keys.dart';
part 'picker_rows.dart';

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
  /// Rebuilds the picker after [change], for the parts of it kept in other
  /// files of this library, which cannot call [setState] themselves.
  void _update(VoidCallback change) => setState(change);

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
    final notebooks = ref.watch(notebooksProvider);
    if (!_attached && (notebooks.hasValue || notebooks.hasError)) {
      _attached = true;
      // The keys pressed as it opened, once there is something for them —
      // or there will be nothing, and Esc must still take the picker away.
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
      PickerView.library =>
        _ColumnView.chrome +
            longest * CursorList.scaled(context, _PickerRow.height),
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
}
