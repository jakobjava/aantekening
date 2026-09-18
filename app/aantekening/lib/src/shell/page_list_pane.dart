/// The page list for the selected section.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'library_pane.dart';

/// Lists the pages of the selected section, with subpages indented beneath
/// their parent. Every row has a menu on a right-click or a long press, and
/// the empty space below has one for adding and pasting pages.
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
    final pages = ref.watch(pagesProvider(sectionId));
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
        data: (all) {
          if (all.isEmpty) return const PaneMessage('No pages yet');

          // Subpages are drawn under their parent, so the list is ordered by
          // parent first rather than by raw sibling position.
          final ordered = orderPagesWithSubpages(all);
          final parents = <String, String?>{
            for (final page in all) page.id: page.parentId,
          };

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              final entry = ordered[index];
              return _PageTile(
                page: entry.page,
                depth: entry.depth,
                selected: entry.page.id == selected,
                parents: parents,
              );
            },
          );
        },
      ),
    );
  }
}

/// A page and how deeply it is nested.
typedef OrderedPage = ({PageRef page, int depth});

/// Orders pages so each subpage follows its parent.
///
/// Pages whose parent is missing are shown at the top level rather than hidden,
/// so no page can become unreachable.
List<OrderedPage> orderPagesWithSubpages(List<PageRef> pages) {
  final byParent = <String?, List<PageRef>>{};
  final ids = <String>{for (final page in pages) page.id};

  for (final page in pages) {
    final parent = (page.parentId != null && ids.contains(page.parentId))
        ? page.parentId
        : null;
    (byParent[parent] ??= <PageRef>[]).add(page);
  }

  final ordered = <OrderedPage>[];
  void visit(String? parent, int depth) {
    for (final page in byParent[parent] ?? const <PageRef>[]) {
      ordered.add((page: page, depth: depth));
      visit(page.id, depth + 1);
    }
  }

  visit(null, 0);
  return ordered;
}

class _PageTile extends ConsumerWidget {
  const _PageTile({
    required this.page,
    required this.depth,
    required this.selected,
    required this.parents,
  });

  final PageRef page;
  final int depth;
  final bool selected;
  final Map<String, String?> parents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0),
      child: LibraryTile(
        node: page,
        parents: parents,
        child: ListTile(
          selected: selected,
          selectedTileColor: scheme.primary.withValues(alpha: 0.12),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          onTap: () => ref.read(selectedPageProvider.notifier).select(page.id),
        ),
      ),
    );
  }
}
