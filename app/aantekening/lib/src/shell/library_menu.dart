/// The right-click menus of the navigation panes, and the dialogs they open.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_actions.dart';

/// One command in a menu; greyed out without [onSelected].
@immutable
class MenuCommand {
  const MenuCommand(
    this.label,
    this.icon,
    this.onSelected, {
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onSelected;

  /// Whether it cannot be taken back, and is drawn in the error colour.
  final bool destructive;
}

/// Shows [groups] of commands as a menu at [position], in global
/// coordinates, with a line between groups, and runs the one picked once
/// the menu has closed.
Future<void> showCommandMenu(
  BuildContext context,
  Offset position,
  List<List<MenuCommand>> groups,
) async {
  final scheme = Theme.of(context).colorScheme;
  final entries = <PopupMenuEntry<VoidCallback>>[];
  for (final group in groups.where((group) => group.isNotEmpty)) {
    if (entries.isNotEmpty) entries.add(const PopupMenuDivider(height: 8));
    for (final command in group) {
      final color = command.destructive ? scheme.error : null;
      entries.add(
        PopupMenuItem<VoidCallback>(
          value: command.onSelected,
          enabled: command.onSelected != null,
          height: 36,
          child: Row(
            children: <Widget>[
              Icon(command.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Text(command.label, style: TextStyle(color: color)),
            ],
          ),
        ),
      );
    }
  }
  final picked = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: entries,
  );
  picked?.call();
}

/// The name shown for [node], which for a page without a title is a
/// stand-in.
String displayTitle(TreeNode node) =>
    node is PageRef ? pageTitleOrPlaceholder(node.title) : node.title;

/// A page's title, or a stand-in for a page without one.
String pageTitleOrPlaceholder(String title) =>
    title.trim().isEmpty ? 'Untitled page' : title;

/// Shows what can be done to a notebook, section or page at [position].
///
/// The commands come in the same order whatever [node] is: making something
/// new first, then cutting, copying and pasting, then renaming and deleting.
/// [parents] maps the ids of [node]'s kind nearby to their parents', which
/// pasting needs; see [LibraryActions.canPaste].
Future<void> showLibraryMenu(
  BuildContext context,
  WidgetRef ref,
  TreeNode node,
  Offset position, {
  Map<String, String?> parents = const {},
}) {
  final actions = ref.read(libraryActionsProvider);
  final clip = ref.read(libraryClipboardProvider);

  Future<void> rename() async {
    final title = await promptForName(
      context,
      title: 'Rename the ${_kindOf(node)}',
      hint: displayTitle(node),
      initial: node.title,
      action: 'Rename',
    );
    if (title != null) await actions.rename(node, title);
  }

  Future<void> delete() async {
    if (await confirmDeletion(context, node)) await actions.delete(node);
  }

  final create = switch (node) {
    Notebook(:final id) => <MenuCommand>[
      MenuCommand(
        'New section',
        Icons.create_new_folder_outlined,
        () => createNamedSection(context, ref, notebookId: id),
      ),
    ],
    Section(:final id, :final notebookId) => <MenuCommand>[
      MenuCommand(
        'New page',
        Icons.note_add_outlined,
        () => actions.createPage(sectionId: id),
      ),
      MenuCommand(
        'New subsection',
        Icons.create_new_folder_outlined,
        () => createNamedSection(
          context,
          ref,
          notebookId: notebookId,
          parentId: id,
        ),
      ),
    ],
    PageRef(:final id, :final sectionId) => <MenuCommand>[
      MenuCommand(
        'New page',
        Icons.note_add_outlined,
        () => actions.createPage(sectionId: sectionId),
      ),
      MenuCommand(
        'New subpage',
        Icons.subdirectory_arrow_right_rounded,
        () => actions.createPage(sectionId: sectionId, parentId: id),
      ),
    ],
    _ => const <MenuCommand>[],
  };

  final pasteLabel = switch (clip?.node) {
    PageRef() => 'Paste page',
    Section() => 'Paste section',
    _ => 'Paste',
  };
  final paste = MenuCommand(
    pasteLabel,
    Icons.content_paste_rounded,
    actions.canPaste(node, parents: parents) ? () => actions.paste(node) : null,
  );

  return showCommandMenu(context, position, <List<MenuCommand>>[
    create,
    <MenuCommand>[
      // A notebook is not moved or copied on its own; sections are pasted
      // into it.
      if (node is! Notebook) ...<MenuCommand>[
        MenuCommand('Cut', Icons.content_cut_rounded, () => actions.cut(node)),
        MenuCommand(
          'Copy',
          Icons.content_copy_rounded,
          () => actions.copy(node),
        ),
      ],
      paste,
    ],
    <MenuCommand>[
      MenuCommand('Rename', Icons.drive_file_rename_outline_rounded, rename),
      MenuCommand(
        'Delete',
        Icons.delete_outline_rounded,
        delete,
        destructive: true,
      ),
    ],
  ]);
}

/// Asks for a name and creates a notebook with it.
Future<void> createNamedNotebook(BuildContext context, WidgetRef ref) async {
  final title = await promptForName(
    context,
    title: 'New notebook',
    hint: 'Notebook',
  );
  if (title != null) {
    await ref.read(libraryActionsProvider).createNotebook(title);
  }
}

/// Asks for a name and creates a section with it in [notebookId], as a
/// subsection of [parentId] when given.
Future<void> createNamedSection(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  String? parentId,
}) async {
  final title = await promptForName(
    context,
    title: parentId == null ? 'New section' : 'New subsection',
    hint: 'Section',
  );
  if (title == null) return;
  await ref
      .read(libraryActionsProvider)
      .createSection(notebookId: notebookId, title: title, parentId: parentId);
}

/// Asks for a name, returning it trimmed, or null if the dialog is
/// cancelled or left empty.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  String action = 'Create',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(title: title, hint: hint, initial: initial, action: action),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// What [node] is called: a notebook, a section or a page.
String _kindOf(TreeNode node) => switch (node) {
  Notebook() => 'notebook',
  Section() => 'section',
  _ => 'page',
};

/// Asks whether to delete [node] and everything in it.
Future<bool> confirmDeletion(BuildContext context, TreeNode node) async {
  final kind = _kindOf(node);
  final contents = switch (node) {
    Notebook() => 'Its sections and pages are deleted with it.',
    Section() => 'Its pages and subsections are deleted with it.',
    _ => 'Any subpages are deleted with it.',
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text('Delete the $kind “${displayTitle(node)}”?'),
        content: Text(contents),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The dialog behind [promptForName].
///
/// It owns its controller rather than borrowing the caller's: `showDialog`
/// completes as soon as the route pops, but the dialog keeps rebuilding through
/// its exit animation, so a controller disposed by the caller would be used
/// after disposal.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.hint,
    required this.initial,
    required this.action,
  });

  final String title;
  final String hint;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  // The name there already is selected, so typing replaces it.
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );

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
        child: Text(widget.action),
      ),
    ],
  );
}
