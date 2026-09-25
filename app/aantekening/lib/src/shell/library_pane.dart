/// The notebook and section navigator.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/shortcuts.dart';
import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import '../providers.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'panel_focus.dart';
import 'sidebar_state.dart';
import 'tree_rows.dart';

/// Lists notebooks and, beneath the selected one, its tree of sections.
///
/// Lines join each row to the rows beneath it, and a click on a line, or on
/// a row's chevron, collapses what lies beneath. Every row has a menu on a
/// right-click, or on a long press.
///
/// Asked to take the keyboard with no section open, it gives it to the
/// notebook open, or else the first; the arrow keys go on from there.
class LibraryPane extends ConsumerStatefulWidget {
  const LibraryPane({super.key});

  @override
  ConsumerState<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends ConsumerState<LibraryPane> {
  final FocusNode _row = FocusNode(debugLabel: 'Notebook row');

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notebooks = ref.watch(notebooksProvider);
    final bindings = ref.watch(shortcutsProvider);
    final open = ref.watch(selectedNotebookProvider);

    // A Material, not a plain coloured box: the rows paint their hover and
    // selection on the nearest Material.
    return Material(
      color: context.tones.pane,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Notebooks',
            actionTooltip: bindings.tooltip(AppCommand.newNotebook),
            onAction: () => createNamedNotebook(context, ref),
          ),
          Expanded(
            child: PaneBackgroundMenu(
              commands: () => <MenuCommand>[
                MenuCommand(
                  'New notebook',
                  () => createNamedNotebook(context, ref),
                ),
              ],
              child: notebooks.when(
                loading: () => const Loading(),
                error: (error, _) => EmptyMessage(
                  'The notebooks could not be read.',
                  detail: '$error',
                ),
                data: (books) => books.isEmpty
                    ? const EmptyMessage('No notebooks yet')
                    : PanelFocus(
                        tab: SidebarTab.notebooks,
                        node: _row,
                        wanted: () => ref.read(selectedSectionProvider) == null,
                        child: TreeLines(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: books.length,
                            itemBuilder: (context, index) => _NotebookRows(
                              notebook: books[index],
                              focusNode:
                                  books[index].id == open ||
                                      (index == 0 &&
                                          !books.any((b) => b.id == open))
                                  ? _row
                                  : null,
                            ),
                          ),
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
  const _NotebookRows({required this.notebook, this.focusNode});

  final Notebook notebook;

  /// Given to the notebook's row, to take the keyboard.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            child: RowTile(
              selected: selected && ref.watch(selectedSectionProvider) == null,
              focusNode: focusNode,
              padding: TreeRow.tilePadding,
              titleStyle: const TextStyle(fontWeight: FontWeight.w600),
              title: Text(notebook.title),
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
      loading: () =>
          const Padding(padding: EdgeInsets.all(12), child: Busy(width: 48)),
      error: (error, _) =>
          EmptyMessage('The sections could not be read.', detail: '$error'),
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
              start: TreeRow.indent * 2 - 2,
              top: 2,
              bottom: 6,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SmallButton(
                'New section',
                onPressed: () =>
                    createNamedSection(context, ref, notebookId: notebookId),
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
  Widget build(BuildContext context, WidgetRef ref) => LibraryTile(
    node: section,
    child: RowTile(
      selected: selected,
      padding: TreeRow.tilePadding,
      title: Text(section.title),
      // Only the section open offers a subsection, so the list stays quiet.
      trailing: selected
          ? MarkButton(
              MarkShape.add,
              tooltip: 'New subsection',
              size: 20,
              markSize: 10,
              onPressed: () => createNamedSection(
                context,
                ref,
                notebookId: section.notebookId,
                parentId: section.id,
              ),
            )
          : null,
      onTap: () => ref
          .read(libraryActionsProvider)
          .openSection(section.notebookId, section.id),
    ),
  );
}

/// A row for a notebook, section or page: its menu on a right-click or a
/// long press, a page opened in a new tab by a middle-click, and faded while
/// it is cut, waiting to be pasted elsewhere.
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
    final page = node;
    return GestureDetector(
      onTertiaryTapUp: page is PageRef
          ? (_) =>
                unawaited(ref.read(libraryActionsProvider).openInNewTab(page))
          : null,
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
