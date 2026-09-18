/// The notebook and section navigator.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Lists notebooks and, beneath the selected one, its section tree.
///
/// Sections nest arbitrarily, so the tree is assembled in one pass from the
/// flat list the store returns rather than by querying level by level.
class LibraryPane extends ConsumerWidget {
  const LibraryPane({super.key, this.width = AppTheme.libraryPaneWidth});

  /// Fixed pane width, or null to fill the available space — which is what the
  /// compact layout needs when the panes move into a drawer.
  final double? width;

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
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _PaneHeader(
              title: 'Notebooks',
              onAdd: () => _createNotebook(context, ref),
              addTooltip: 'New notebook',
            ),
            Expanded(
              child: notebooks.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _PaneError(message: '$error'),
                data: (books) => books.isEmpty
                    ? const _PaneEmpty(message: 'No notebooks yet')
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final notebook = books[index];
                          final isSelected = notebook.id == selectedNotebook;
                          return _NotebookTile(
                            notebook: notebook,
                            expanded: isSelected,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createNotebook(BuildContext context, WidgetRef ref) async {
    final title = await promptForName(context, 'New notebook', 'Notebook');
    if (title == null) return;

    final store = await ref.read(storeProvider.future);
    final notebook = await store.library.createNotebook(title: title);
    // A notebook with nowhere to write is not useful, so it starts with one
    // section and one page, the way a paper notebook starts with a first page.
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Notes',
    );
    final page = await store.pages.createPage(sectionId: section.id);

    ref.read(libraryRevisionProvider.notifier).bump();
    ref.read(selectedNotebookProvider.notifier).select(notebook.id);
    ref.read(selectedSectionProvider.notifier).select(section.id);
    ref.read(selectedPageProvider.notifier).select(page.id);
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
        ListTile(
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
          onTap: () {
            ref.read(selectedNotebookProvider.notifier).select(notebook.id);
            ref.read(selectedSectionProvider.notifier).select(null);
            ref.read(selectedPageProvider.notifier).select(null);
          },
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
      error: (error, _) => _PaneError(message: '$error'),
      data: (flat) {
        final roots = _buildSectionTree(flat);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final node in roots)
              ..._renderNode(context, ref, node, depth: 0),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _createSection(context, ref, null),
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
    _SectionNode node, {
    required int depth,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedSectionProvider) == node.section.id;

    return <Widget>[
      Padding(
        padding: EdgeInsets.only(left: 16.0 + depth * 14),
        child: ListTile(
          selected: selected,
          selectedTileColor: scheme.primary.withValues(alpha: 0.10),
          leading: Icon(
            node.children.isEmpty
                ? Icons.article_outlined
                : Icons.folder_outlined,
            size: 16,
            color: node.section.color != null
                ? Color(node.section.color!)
                : scheme.onSurfaceVariant,
          ),
          title: Text(
            node.section.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 14),
            tooltip: 'New subsection',
            onPressed: () => _createSection(context, ref, node.section.id),
          ),
          onTap: () {
            ref.read(selectedSectionProvider.notifier).select(node.section.id);
            ref.read(selectedPageProvider.notifier).select(null);
          },
        ),
      ),
      for (final child in node.children)
        ..._renderNode(context, ref, child, depth: depth + 1),
    ];
  }

  Future<void> _createSection(
    BuildContext context,
    WidgetRef ref,
    String? parentId,
  ) async {
    final title = await promptForName(
      context,
      parentId == null ? 'New section' : 'New subsection',
      'Section',
    );
    if (title == null) return;

    final store = await ref.read(storeProvider.future);
    final section = await store.library.createSection(
      notebookId: notebookId,
      title: title,
      parentId: parentId,
    );
    ref.read(libraryRevisionProvider.notifier).bump();
    ref.read(selectedSectionProvider.notifier).select(section.id);
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

/// A titled pane header with an add button.
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.title,
    required this.onAdd,
    required this.addTooltip,
  });

  final String title;
  final VoidCallback onAdd;
  final String addTooltip;

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
            icon: const Icon(Icons.add, size: 18),
            tooltip: addTooltip,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _PaneEmpty extends StatelessWidget {
  const _PaneEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _PaneError extends StatelessWidget {
  const _PaneError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}

/// Asks the user for a name, returning null if they cancel.
Future<String?> promptForName(
  BuildContext context,
  String title,
  String hint,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, hint: hint),
  );

  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// The dialog behind [promptForName].
///
/// It owns its controller rather than borrowing the caller's: `showDialog`
/// completes as soon as the route pops, but the dialog keeps rebuilding through
/// its exit animation, so a controller disposed by the caller would be used
/// after disposal.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Create'),
      ),
    ],
  );
}
