/// The page list for the selected section.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Lists the pages of the selected section, with subpages indented beneath
/// their parent.
class PageListPane extends ConsumerWidget {
  const PageListPane({super.key, this.width = AppTheme.pageListPaneWidth});

  /// Fixed pane width, or null to fill the available space — which is what the
  /// compact layout needs when the panes move into a drawer.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sectionId = ref.watch(selectedSectionProvider);

    // ListTile paints its selection tint and ink onto the nearest Material,
    // so the pane's background has to be one rather than a coloured box.
    return Material(
      color: AppTheme.paneColor(scheme).withValues(alpha: 0.6),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'PAGES',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'New page',
                    onPressed: sectionId == null
                        ? null
                        : () => _createPage(ref, sectionId),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sectionId == null
                  ? const _Hint(message: 'Select a section')
                  : _PageList(sectionId: sectionId),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPage(
    WidgetRef ref,
    String sectionId, {
    String? parentId,
  }) async {
    final store = await ref.read(storeProvider.future);
    final page = await store.pages.createPage(
      sectionId: sectionId,
      parentId: parentId,
    );
    ref.read(libraryRevisionProvider.notifier).bump();
    ref.read(selectedPageProvider.notifier).select(page.id);
  }
}

class _PageList extends ConsumerWidget {
  const _PageList({required this.sectionId});

  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(pagesProvider(sectionId));
    final selected = ref.watch(selectedPageProvider);

    return pages.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Hint(message: '$error'),
      data: (all) {
        if (all.isEmpty) return const _Hint(message: 'No pages yet');

        // Subpages are drawn under their parent, so the list is ordered by
        // parent first rather than by raw sibling position.
        final ordered = orderPagesWithSubpages(all);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          itemCount: ordered.length,
          itemBuilder: (context, index) {
            final entry = ordered[index];
            return _PageTile(
              page: entry.page,
              depth: entry.depth,
              selected: entry.page.id == selected,
            );
          },
        );
      },
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
  });

  final PageRef page;
  final int depth;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final title = page.title.trim().isEmpty ? 'Untitled page' : page.title;

    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0),
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.12),
        title: Text(
          title,
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

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
