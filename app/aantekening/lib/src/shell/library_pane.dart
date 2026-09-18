/// The notebook and section navigator.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'library_actions.dart';
import 'library_menu.dart';

/// Lists notebooks and, beneath the selected one, its section tree.
///
/// Sections nest arbitrarily, so the tree is assembled in one pass from the
/// flat list the store returns rather than by querying level by level. Every
/// row has a menu on a right-click, or on a long press.
class LibraryPane extends ConsumerWidget {
  const LibraryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notebooks = ref.watch(notebooksProvider);
    final selectedNotebook = ref.watch(selectedNotebookProvider);

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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final notebook = books[index];
                          return _NotebookTile(
                            notebook: notebook,
                            expanded: notebook.id == selectedNotebook,
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookTile extends ConsumerWidget {
  const _NotebookTile({required this.notebook, required this.expanded});

  final Notebook notebook;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LibraryTile(
          node: notebook,
          child: ListTile(
            selected: expanded,
            selectedTileColor: scheme.primary.withValues(alpha: 0.10),
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
            onTap: () =>
                ref.read(libraryActionsProvider).openNotebook(notebook.id),
          ),
        ),
        if (expanded) _SectionTree(notebookId: notebook.id),
      ],
    );
  }
}

/// One node of the assembled section hierarchy.
class _SectionNode {
  _SectionNode(this.section);

  final Section section;
  final List<_SectionNode> children = <_SectionNode>[];
}

class _SectionTree extends ConsumerWidget {
  const _SectionTree({required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionsProvider(notebookId));

    return sections.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => PaneMessage('$error', error: true),
      data: (flat) {
        final roots = _buildSectionTree(flat);
        final parents = <String, String?>{
          for (final section in flat) section.id: section.parentId,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final node in roots)
              ..._renderNode(context, ref, node, parents, depth: 0),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
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
        );
      },
    );
  }

  List<Widget> _renderNode(
    BuildContext context,
    WidgetRef ref,
    _SectionNode node,
    Map<String, String?> parents, {
    required int depth,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final section = node.section;
    final selected = ref.watch(selectedSectionProvider) == section.id;

    return <Widget>[
      Padding(
        padding: EdgeInsets.only(left: 16.0 + depth * 14),
        child: LibraryTile(
          node: section,
          parents: parents,
          child: ListTile(
            selected: selected,
            selectedTileColor: scheme.primary.withValues(alpha: 0.10),
            leading: Icon(
              node.children.isEmpty
                  ? Icons.article_outlined
                  : Icons.folder_outlined,
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
                notebookId: notebookId,
                parentId: section.id,
              ),
            ),
            onTap: () => ref
                .read(libraryActionsProvider)
                .openSection(notebookId, section.id),
          ),
        ),
      ),
      for (final child in node.children)
        ..._renderNode(context, ref, child, parents, depth: depth + 1),
    ];
  }
}

/// Assembles a flat section list into a hierarchy.
///
/// Orphans — a section whose parent is filtered out or missing — are promoted
/// to the top level rather than dropped, so a section can never become
/// unreachable from the interface.
List<_SectionNode> _buildSectionTree(List<Section> sections) {
  final nodes = <String, _SectionNode>{
    for (final section in sections) section.id: _SectionNode(section),
  };
  final roots = <_SectionNode>[];

  for (final section in sections) {
    final node = nodes[section.id]!;
    final parent = section.parentId == null ? null : nodes[section.parentId];
    if (parent == null) {
      roots.add(node);
    } else {
      parent.children.add(node);
    }
  }
  return roots;
}

/// A row for a notebook, section or page: its menu on a right-click or a
/// long press, and faded while it is cut, waiting to be pasted elsewhere.
class LibraryTile extends ConsumerWidget {
  const LibraryTile({
    required this.node,
    required this.child,
    this.parents = const {},
    super.key,
  });

  final TreeNode node;

  /// The parents of the nodes of [node]'s kind nearby; see
  /// [LibraryActions.canPaste].
  final Map<String, String?> parents;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cut = ref.watch(
      libraryClipboardProvider.select(
        (clip) => clip != null && clip.cut && clip.node.id == node.id,
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => showLibraryMenu(
        context,
        ref,
        node,
        details.globalPosition,
        parents: parents,
      ),
      onLongPressStart: (details) => showLibraryMenu(
        context,
        ref,
        node,
        details.globalPosition,
        parents: parents,
      ),
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
