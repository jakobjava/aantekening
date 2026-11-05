part of 'picker.dart';

/// What the picker shows of the notebooks: its views named along its top,
/// the columns and their rows, and the keys it answers to most along its
/// foot.
extension _Columns on _PickerState {
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
                    _update(() => _column = column);
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
    // At least as tall as its words, however large they are.
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 10),
            // As wide as they are; in a window too narrow for them, they
            // scroll.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, constraints.maxWidth - 38),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final each in PickerView.values)
                      DropTab(
                        each.label,
                        showing: each == view,
                        onPressed: () => onShow(each),
                      ),
                  ],
                ),
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SmallCaps(
                  label,
                  color: active ? tones.emphasis : tones.muted,
                ),
              ),
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
                          accepts: (moved) => !_beneath(rows[index], moved),
                          onArrange: (moved, {required above}) =>
                              arrangeReported(
                                context,
                                ref,
                                moved,
                                node,
                                above: above,
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
                    Flexible(
                      child: Text(
                        called ?? action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tones.muted),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
