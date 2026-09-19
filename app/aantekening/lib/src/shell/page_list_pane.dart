/// The page list for the selected section.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../providers.dart';
import '../theme.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'library_pane.dart';
import 'tree_rows.dart';

/// Lists the pages of the selected section, with subpages beneath their
/// parent, joined to it by a line a click on which collapses them. Every row
/// has a menu on a right-click or a long press, and the empty space below
/// has one for adding and pasting pages.
class PageListPane extends ConsumerWidget {
  const PageListPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sectionId = ref.watch(selectedSectionProvider);
    final actions = ref.read(libraryActionsProvider);

    // ListTile paints its selection tint and ink onto the nearest Material,
    // so the pane's background has to be one rather than a coloured box.
    return Material(
      color: AppTheme.paneColor(scheme).withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Pages',
            actionTooltip: 'New page',
            onAction: sectionId == null
                ? null
                : () => actions.createPage(sectionId: sectionId),
          ),
          Expanded(
            child: sectionId == null
                ? const PaneMessage('Select a section')
                : _PageList(sectionId: sectionId),
          ),
        ],
      ),
    );
  }
}

class _PageList extends ConsumerWidget {
  const _PageList({required this.sectionId});

  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(pageTreeProvider(sectionId));
    final collapsed = ref.watch(collapsedRowsProvider);
    final section = ref.watch(sectionProvider(sectionId)).value;
    final selected = ref.watch(selectedPageProvider);
    final actions = ref.read(libraryActionsProvider);

    return PaneBackgroundMenu(
      commands: () {
        return <MenuCommand>[
          MenuCommand(
            'New page',
            Icons.note_add_outlined,
            () => actions.createPage(sectionId: sectionId),
          ),
          MenuCommand(
            'Paste page',
            Icons.content_paste_rounded,
            section != null && actions.canPaste(section)
                ? () => actions.paste(section)
                : null,
          ),
        ];
      },
      child: pages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PaneMessage('$error', error: true),
        data: (tree) {
          if (tree.isEmpty) return const PaneMessage('No pages yet');
          final rows = treeRows(tree, collapsed);

          return TreeLines(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final (item: page, :place) = rows[index];
                return TreeRow(
                  place: place,
                  onToggle: ref.read(collapsedRowsProvider.notifier).toggle,
                  child: _PageTile(page: page, selected: page.id == selected),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PageTile extends ConsumerWidget {
  const _PageTile({required this.page, required this.selected});

  final PageRef page;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return LibraryTile(
      node: page,
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.12),
        contentPadding: TreeRow.tilePadding,
        leading: Icon(
          Icons.description_outlined,
          size: 16,
          color: selected ? null : scheme.onSurfaceVariant,
        ),
        title: Text(
          displayTitle(page),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontStyle: page.title.trim().isEmpty
                ? FontStyle.italic
                : FontStyle.normal,
          ),
        ),
        subtitle: page.preview.isEmpty
            ? null
            : Text(
                page.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
        onTap: () => ref.read(selectedPageProvider.notifier).select(page.id),
      ),
    );
  }
}
