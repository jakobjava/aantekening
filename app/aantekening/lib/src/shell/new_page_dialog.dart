/// Starting a page: as one paper without end, or as sheets — and, as
/// sheets, on what paper.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/sheet_choices.dart';
import '../look/controls.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import 'library_actions.dart';
import 'new_page_choice.dart';

/// Asks whether the page to make is one paper or sheets, and on what paper,
/// then makes it at the end of [sectionId] — or of [parentId]'s subpages —
/// and opens it. The choice last made is offered first: Enter makes another
/// such page.
Future<void> createChosenPage(
  BuildContext context,
  WidgetRef ref, {
  required String sectionId,
  String? parentId,
}) async {
  final choice = await showPlainDialog<NewPageChoice>(
    context: context,
    builder: (context) =>
        NewPageDialog(initial: ref.read(newPageChoiceProvider)),
  );
  if (choice == null) return;
  ref.read(newPageChoiceProvider.notifier).remember(choice);
  await ref
      .read(libraryActionsProvider)
      .createPage(
        sectionId: sectionId,
        parentId: parentId,
        canvas: choice.canvas,
      );
}

/// The dialog behind [createChosenPage].
class NewPageDialog extends StatefulWidget {
  const NewPageDialog({required this.initial, super.key});

  final NewPageChoice initial;

  @override
  State<NewPageDialog> createState() => _NewPageDialogState();
}

class _NewPageDialogState extends State<NewPageDialog> {
  late NewPageChoice _choice = widget.initial;

  void _set(NewPageChoice choice) => setState(() => _choice = choice);

  void _create() => Navigator.of(context).pop(_choice);

  @override
  Widget build(BuildContext context) {
    final pages = _choice.layout == NoteLayout.pages;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _create,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _create,
        const SingleActivator(LogicalKeyboardKey.keyC): () =>
            _set(_choice.copyWith(layout: NoteLayout.canvas)),
        const SingleActivator(LogicalKeyboardKey.keyP): () =>
            _set(_choice.copyWith(layout: NoteLayout.pages)),
      },
      child: AlertDialog(
        title: const Text('New page'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (final layout in NoteLayout.values) ...<Widget>[
                    if (layout != NoteLayout.values.first)
                      const SizedBox(width: 10),
                    Expanded(
                      child: _LayoutCard(
                        layout: layout,
                        selected: layout == _choice.layout,
                        onTap: () => _set(_choice.copyWith(layout: layout)),
                      ),
                    ),
                  ],
                ],
              ),
              if (pages) ...<Widget>[
                const SizedBox(height: 16),
                const SmallCaps('Paper'),
                const SizedBox(height: 6),
                SheetTemplatePicker(
                  selected: _choice.template,
                  size: _choice.size,
                  onSelected: (template) =>
                      _set(_choice.copyWith(template: template)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const SmallCaps('Size'),
                    const SizedBox(width: 12),
                    ChoiceRow<SheetSize>(
                      choices: SheetSize.values,
                      selected: _choice.size,
                      labelOf: (size) => size.label,
                      compact: true,
                      onSelected: (size) => _set(_choice.copyWith(size: size)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: _create,
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// One of the two ways a page is shown, to choose: what it is and what it
/// is like.
class _LayoutCard extends StatelessWidget {
  const _LayoutCard({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final NoteLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final (key, about) = switch (layout) {
      NoteLayout.canvas => (
        'C',
        'One paper without end, to the right and down: write anywhere.',
      ),
      NoteLayout.pages => (
        'P',
        'Sheets of paper, one after another, added to as the notes grow.',
      ),
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? tones.selection : null,
            border: Border.all(
              color: selected ? tones.emphasis : tones.strongLine,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      layout.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  KeyHint(key),
                ],
              ),
              const SizedBox(height: 6),
              Text(about, style: TextStyle(fontSize: 12, color: tones.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
