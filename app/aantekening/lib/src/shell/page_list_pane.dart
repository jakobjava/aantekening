/// The page list for the selected section.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/shortcuts.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import '../providers.dart';
import 'library_actions.dart';
import 'library_menu.dart';
import 'library_pane.dart';
import 'panel_focus.dart';
import 'sidebar_state.dart';
import 'tree_rows.dart';

/// Lists the pages of the selected section, with subpages beneath their
/// parent, joined to it by a line a click on which collapses them. Every row
/// has a menu on a right-click or a long press, and the empty space below
/// has one for adding and pasting pages.
class PageListPane extends ConsumerWidget {
  const PageListPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionId = ref.watch(selectedSectionProvider);
    final actions = ref.read(libraryActionsProvider);
    final bindings = ref.watch(shortcutsProvider);

    // The rows paint their hover and selection on the nearest Material.
    return Material(
      color: context.tones.pane,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Pages',
            actionTooltip: bindings.tooltip(AppCommand.newPage),
            onAction: sectionId == null
                ? null
                : () => actions.createPage(sectionId: sectionId),
          ),
          Expanded(
            child: sectionId == null
                ? const EmptyMessage('Select a section')
                : _PageList(sectionId: sectionId),
          ),
        ],
      ),
    );
  }
}

/// The pages, the one open — or else the first — taking the keyboard when
/// the notebooks panel is asked to; the arrow keys go on from there.
class _PageList extends ConsumerStatefulWidget {
  const _PageList({required this.sectionId});

  final String sectionId;

  @override
  ConsumerState<_PageList> createState() => _PageListState();
}

class _PageListState extends ConsumerState<_PageList> {
  final FocusNode _row = FocusNode(debugLabel: 'Page row');

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionId = widget.sectionId;
    final pages = ref.watch(pageTreeProvider(sectionId));
    final collapsed = ref.watch(collapsedRowsProvider);
    final section = ref.watch(sectionProvider(sectionId)).value;
    final selected = ref.watch(selectedPageProvider);
    final actions = ref.read(libraryActionsProvider);

    return PaneBackgroundMenu(
      commands: () => <MenuCommand>[
        MenuCommand(
          'New page',
          () => actions.createPage(sectionId: sectionId),
          shortcut: ref
              .read(shortcutsProvider)
              .of(AppCommand.newPage)
              .firstOrNull
              ?.label,
        ),
        MenuCommand(
          'Paste page',
          section != null && actions.canPaste(section)
              ? () => actions.paste(section)
              : null,
        ),
      ],
      child: pages.when(
        loading: () => const Loading(),
        error: (error, _) =>
            EmptyMessage('The pages could not be read.', detail: '$error'),
        data: (tree) {
          if (tree.isEmpty) return const EmptyMessage('No pages yet');
          final rows = treeRows(tree, collapsed);
          final focused = rows.any((row) => row.item.id == selected)
              ? selected
              : rows.first.item.id;

          return PanelFocus(
            tab: SidebarTab.notebooks,
            node: _row,
            child: TreeLines(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final (item: page, :place) = rows[index];
                  return TreeRow(
                    place: place,
                    onToggle: ref.read(collapsedRowsProvider.notifier).toggle,
                    child: _PageTile(
                      page: page,
                      selected: page.id == selected,
                      focusNode: page.id == focused ? _row : null,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageTile extends ConsumerWidget {
  const _PageTile({
    required this.page,
    required this.selected,
    required this.focusNode,
  });

  final PageRef page;
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LibraryTile(
    node: page,
    child: RowTile(
      selected: selected,
      focusNode: focusNode,
      padding: TreeRow.tilePadding,
      titleStyle: TextStyle(
        fontStyle: page.title.trim().isEmpty
            ? FontStyle.italic
            : FontStyle.normal,
      ),
      title: Text(displayTitle(page)),
      subtitle: page.preview.isEmpty ? null : Text(page.preview),
      // Ctrl+click opens the page in a new tab, as in a browser.
      onTap: () => HardwareKeyboard.instance.isControlPressed
          ? unawaited(ref.read(libraryActionsProvider).openInNewTab(page))
          : ref.read(selectedPageProvider.notifier).select(page.id),
    ),
  );
}
