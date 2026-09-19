/// The notebook and section navigator.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../providers.dart';
import '../theme.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'tree_rows.dart';

/// Lists notebooks and, beneath the selected one, its tree of sections.
///
/// Lines join each row to the rows beneath it, and a click on a line, or on
/// a row's chevron, collapses what lies beneath. Every row has a menu on a
/// right-click, or on a long press.
class LibraryPane extends ConsumerWidget {
  const LibraryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notebooks = ref.watch(notebooksProvider);

    // A Material ancestor, not a plain coloured box: ListTile paints its
    // selection tint and ink onto the nearest Material, and a ColoredBox in
    // between would cover both.
    return Material(
      color: AppTheme.paneColor(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Notebooks',
            onAction: () => createNamedNotebook(context, ref),
            actionTooltip: 'New notebook',
          ),
          Expanded(
            child: PaneBackgroundMenu(
              commands: () => <MenuCommand>[
                MenuCommand(
                  'New notebook',
                  Icons.library_add_outlined,
                  () => createNamedNotebook(context, ref),
                ),
              ],
              child: notebooks.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => PaneMessage('$error', error: true),
                data: (books) => books.isEmpty
                    ? const PaneMessage('No notebooks yet')
                    : TreeLines(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          itemCount: books.length,
                          itemBuilder: (context, index) =>
                              _NotebookRows(notebook: books[index]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A notebook's row and, while it is open and expanded, its sections'.
class _NotebookRows extends ConsumerWidget {
  const _NotebookRows({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final actions = ref.read(libraryActionsProvider);
    final selected = ref.watch(
      selectedNotebookProvider.select((id) => id == notebook.id),
    );
    final expanded =
        selected &&
        !ref.watch(
          collapsedRowsProvider.select((ids) => ids.contains(notebook.id)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TreeRow(
          place: TreePlace(id: notebook.id, expanded: expanded),
          // Only the open notebook shows its sections, so expanding another
          // opens it.
          onToggle: (id) => selected
              ? ref.read(collapsedRowsProvider.notifier).toggle(id)
              : actions.openNotebook(id),
          child: LibraryTile(
            node: notebook,
            child: ListTile(
              selected: selected,
              selectedTileColor: scheme.primary.withValues(alpha: 0.10),
              contentPadding: TreeRow.tilePadding,
              leading: Icon(
                expanded ? Icons.menu_book_rounded : Icons.book_outlined,
                size: 18,
                color: notebook.color != null ? Color(notebook.color!) : null,
              ),
              title: Text(
                notebook.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: () => actions.openNotebook(notebook.id),
            ),
          ),
        ),
        if (expanded) _SectionRows(notebookId: notebook.id),
      ],
    );
  }
}

class _SectionRows extends ConsumerWidget {
  const _SectionRows({required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionTreeProvider(notebookId));
    final collapsed = ref.watch(collapsedRowsProvider);
    final selected = ref.watch(selectedSectionProvider);

    return sections.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => PaneMessage('$error', error: true),
      data: (tree) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (item: section, :place) in treeRows(
            tree,
            collapsed,
            root: notebookId,
          ))
            TreeRow(
              place: place,
              onToggle: ref.read(collapsedRowsProvider.notifier).toggle,
              child: _SectionTile(
                section: section,
                selected: section.id == selected,
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: TreeRow.indent * 2,
              top: 2,
              bottom: 6,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    createNamedSection(context, ref, notebookId: notebookId),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Section'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends ConsumerWidget {
  const _SectionTile({required this.section, required this.selected});

  final Section section;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return LibraryTile(
      node: section,
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.10),
        contentPadding: TreeRow.tilePadding,
        // Every section holds pages, and may hold sections, as a folder
        // does; the open one shows its pages beside it.
        leading: Icon(
          selected ? Icons.folder_open_outlined : Icons.folder_outlined,
          size: 16,
          color: section.color != null
              ? Color(section.color!)
              : scheme.onSurfaceVariant,
        ),
        title: Text(
          section.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add, size: 14),
          tooltip: 'New subsection',
          onPressed: () => createNamedSection(
            context,
            ref,
            notebookId: section.notebookId,
            parentId: section.id,
          ),
        ),
        onTap: () => ref
            .read(libraryActionsProvider)
            .openSection(section.notebookId, section.id),
      ),
    );
  }
}

/// A row for a notebook, section or page: its menu on a right-click or a
/// long press, and faded while it is cut, waiting to be pasted elsewhere.
class LibraryTile extends ConsumerWidget {
  const LibraryTile({required this.node, required this.child, super.key});

  final TreeNode node;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cut = ref.watch(
      libraryClipboardProvider.select(
        (clip) => clip != null && clip.cut && clip.node.id == node.id,
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          showLibraryMenu(context, ref, node, details.globalPosition),
      onLongPressStart: (details) =>
          showLibraryMenu(context, ref, node, details.globalPosition),
      child: Opacity(opacity: cut ? 0.45 : 1, child: child),
    );
  }
}

/// A pane whose empty space has a menu of [commands] on a right-click or a
/// long press.
class PaneBackgroundMenu extends StatelessWidget {
  const PaneBackgroundMenu({
    required this.commands,
    required this.child,
    super.key,
  });

  /// The commands, worked out when the menu opens.
  final List<MenuCommand> Function() commands;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (details) => showCommandMenu(
      context,
      details.globalPosition,
      <List<MenuCommand>>[commands()],
    ),
    onLongPressStart: (details) => showCommandMenu(
      context,
      details.globalPosition,
      <List<MenuCommand>>[commands()],
    ),
    child: child,
  );
}

/// A pane's title, with a button for the pane's main command: adding
/// something, unless [actionIcon] says otherwise.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    required this.title,
    required this.onAction,
    required this.actionTooltip,
    this.actionIcon = Icons.add,
    super.key,
  });

  final String title;

  /// Carries out the command, or null while it has nothing to act on.
  final VoidCallback? onAction;
  final String actionTooltip;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: Icon(actionIcon, size: 18),
            tooltip: actionTooltip,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// A short message filling a pane: that it is empty, or what went wrong.
class PaneMessage extends StatelessWidget {
  const PaneMessage(this.message, {this.error = false, super.key});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: error ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
