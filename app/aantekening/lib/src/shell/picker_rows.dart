part of 'picker.dart';

/// The rows of each column, worked out from the notebooks, their sections
/// and their pages, and the cursor in each: where it is, and how the keys
/// move it.
extension _Rows on _PickerState {
  /// [tree]'s rows, those beneath folded ones left out.
  List<_Row> _treeOf(Hierarchy<TreeNode> tree, Set<String> collapsed) => <_Row>[
    for (final (:item, :place) in treeRows(tree, collapsed))
      (node: item, place: place),
  ];

  List<_Row> _rowsOf(_Column column) => _listing(column).rows;

  /// The id the cursor is on in [column]: the one it was put on, if it is
  /// there, else the first.
  String? _cursorOf(_Column column) => _listing(column).node?.id;

  TreeNode? _nodeAt(_Column column) => _listing(column).node;

  /// [column] as it is listed now. Its rows are worked out again only once
  /// what they are listed from has changed — the notebooks, or the tree of
  /// the notebook or section the column before has the cursor on, and the
  /// rows folded — and where the cursor is once it is put elsewhere.
  _Listing _listing(_Column column) {
    final Object? from = switch (column) {
      _Column.notebooks => ref.watch(notebooksProvider).value,
      _Column.sections => switch (_cursorOf(_Column.notebooks)) {
        final notebook? => ref.watch(sectionTreeProvider(notebook)).value,
        null => null,
      },
      _Column.pages => switch (_cursorOf(_Column.sections)) {
        final section? => ref.watch(pageTreeProvider(section)).value,
        null => null,
      },
    };
    final collapsed = ref.watch(collapsedRowsProvider);
    final wanted = switch (column) {
      _Column.notebooks => _notebook,
      _Column.sections => _section,
      _Column.pages => _page,
    };
    final kept = _listed[column];
    final same =
        kept != null &&
        identical(kept.from, from) &&
        identical(kept.collapsed, collapsed);
    if (same && kept.wanted == wanted) return kept;
    final rows = same
        ? kept.rows
        : switch (from) {
            final List<Notebook> notebooks => <_Row>[
              for (final notebook in notebooks)
                (node: notebook, place: TreePlace(id: notebook.id)),
            ],
            final Hierarchy<TreeNode> tree => _treeOf(tree, collapsed),
            _ => const <_Row>[],
          };
    final at =
        rows.where((row) => row.node.id == wanted).firstOrNull ??
        rows.firstOrNull;
    return _listed[column] = (
      from: from,
      collapsed: collapsed,
      wanted: wanted,
      rows: rows,
      node: at?.node,
    );
  }

  void _put(_Column column, String? id) => _update(() {
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
    _update(() => _column = _Column.values[to]);
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
}

/// The list [column] is ordered as.
OrderedList _listOf(_Column column) => switch (column) {
  _Column.notebooks => OrderedList.notebooks,
  _Column.sections => OrderedList.sections,
  _Column.pages => OrderedList.pages,
};

/// Whether [row] lies beneath [node].
bool _beneath(_Row row, TreeNode node) =>
    row.place.ancestors.any((above) => above.id == node.id);
