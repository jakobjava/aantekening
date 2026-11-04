part of 'picker.dart';

/// What the picker does to the notebooks, sections and pages in it —
/// making, renaming, deleting, moving them — and to itself.
extension _Actions on _PickerState {
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

  /// What can be done to the row the cursor is on.
  void _menu() {
    final node = _nodeAt(_column);
    if (node != null) unawaited(showLibraryMenu(context, ref, node));
  }

  void _searchInstead() {
    Navigator.of(context).maybePop();
    ref.read(searchLineProvider.notifier).open();
  }

  void _toggleView() => _update(
    () => _view = _view == PickerView.library
        ? PickerView.graph
        : PickerView.library,
  );

  /// Takes the picker away, from under any dialog it opened too.
  void _close() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }
}
