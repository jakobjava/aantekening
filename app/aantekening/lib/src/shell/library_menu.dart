/// The right-click menus of the navigation panes, and the dialogs they open.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import 'library_actions.dart';

/// The name shown for [node], which for a page without a title is a
/// stand-in.
String displayTitle(TreeNode node) =>
    node is PageRef ? pageTitleOrPlaceholder(node.title) : node.title;

/// A page's title, or a stand-in for a page without one.
String pageTitleOrPlaceholder(String title) =>
    title.trim().isEmpty ? 'Untitled page' : title;

/// Shows what can be done to a notebook, section or page at [position].
///
/// The commands come in the same order whatever [node] is: opening it —
/// a page in a tab of its own, or its AI — and copying a link to it first,
/// then making something new, then cutting, copying and pasting, then
/// renaming and deleting.
Future<void> showLibraryMenu(
  BuildContext context,
  WidgetRef ref,
  TreeNode node,
  Offset position,
) {
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
        () => createNamedSection(context, ref, notebookId: id),
      ),
    ],
    Section(:final id, :final notebookId) => <MenuCommand>[
      MenuCommand('New page', () => actions.createPage(sectionId: id)),
      MenuCommand(
        'New subsection',
        () => createNamedSection(
          context,
          ref,
          notebookId: notebookId,
          parentId: id,
        ),
      ),
    ],
    PageRef(:final id, :final sectionId) => <MenuCommand>[
      MenuCommand('New page', () => actions.createPage(sectionId: sectionId)),
      MenuCommand(
        'New subpage',
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
    actions.canPaste(node) ? () => actions.paste(node) : null,
  );

  final link = switch (node) {
    Notebook(:final id) => NoteLink.notebook(id),
    Section(:final id) => NoteLink.section(id),
    _ => NoteLink.page(node.id),
  };

  return showCommandMenu(context, position, <List<MenuCommand>>[
    <MenuCommand>[
      if (node is PageRef)
        MenuCommand(
          'Open in new tab',
          () => unawaited(actions.openInNewTab(node)),
        ),
      MenuCommand('Ask AI', () => unawaited(actions.openAi(node))),
      MenuCommand(
        'Copy link',
        () => unawaited(Clipboard.setData(ClipboardData(text: '$link'))),
      ),
    ],
    create,
    <MenuCommand>[
      // A notebook is not moved or copied on its own; sections are pasted
      // into it.
      if (node is! Notebook) ...<MenuCommand>[
        MenuCommand('Cut', () => actions.cut(node)),
        MenuCommand('Copy', () => actions.copy(node)),
      ],
      paste,
    ],
    <MenuCommand>[MenuCommand('Rename', rename), MenuCommand('Delete', delete)],
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
    builder: (context) => AlertDialog(
      title: Text('Delete the $kind “${displayTitle(node)}”?'),
      content: Text(contents),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
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
