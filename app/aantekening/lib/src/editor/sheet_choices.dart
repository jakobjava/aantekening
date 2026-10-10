/// Choosing what is printed on a sheet.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../look/controls.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';

/// Every template, side by side, each drawn as it is printed with its name
/// beneath, the [selected] one marked.
class SheetTemplatePicker extends StatelessWidget {
  const SheetTemplatePicker({
    required this.selected,
    required this.onSelected,
    this.size = SheetSize.a4,
    this.orientation = SheetOrientation.portrait,
    super.key,
  });

  /// The template marked, if any.
  final SheetTemplate? selected;
  final ValueChanged<SheetTemplate> onSelected;
  final SheetSize size;
  final SheetOrientation orientation;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: <Widget>[
      for (final template in SheetTemplate.values)
        _TemplateTile(
          template: template,
          size: size,
          orientation: orientation,
          selected: template == selected,
          onTap: () => onSelected(template),
        ),
    ],
  );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.size,
    required this.orientation,
    required this.selected,
    required this.onTap,
  });

  final SheetTemplate template;
  final SheetSize size;
  final SheetOrientation orientation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      button: true,
      selected: selected,
      label: template.label,
      child: PickRing(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        filled: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SheetThumbnail(
              template: template,
              size: size,
              orientation: orientation,
            ),
            const SizedBox(height: 4),
            Text(
              template.label,
              style: TextStyle(fontSize: 11.5, color: tones.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet to add: what it is printed with, and which way up it is turned.
typedef SheetChoice = ({SheetTemplate template, SheetOrientation orientation});

/// Asks which template to print on a sheet, and which way up to turn it,
/// under [title], returning those chosen, or null if none is. [selected]
/// and [orientation] are marked at first: Enter, or [action], takes them;
/// a click on a template takes it, turned as marked. P and L turn it
/// upright or landscape.
Future<SheetChoice?> chooseSheet(
  BuildContext context, {
  required String title,
  required SheetTemplate selected,
  required SheetSize size,
  SheetOrientation orientation = SheetOrientation.portrait,
  String action = 'Choose',
}) => showAppDialog<SheetChoice>(
  context: context,
  builder: (context) => _SheetDialog(
    title: title,
    selected: selected,
    size: size,
    orientation: orientation,
    action: action,
  ),
);

class _SheetDialog extends StatefulWidget {
  const _SheetDialog({
    required this.title,
    required this.selected,
    required this.size,
    required this.orientation,
    required this.action,
  });

  final String title;
  final SheetTemplate selected;
  final SheetSize size;
  final SheetOrientation orientation;
  final String action;

  @override
  State<_SheetDialog> createState() => _SheetDialogState();
}

class _SheetDialogState extends State<_SheetDialog> {
  late SheetOrientation _orientation = widget.orientation;

  void _take(SheetTemplate template) =>
      Navigator.of(context)
          .pop<SheetChoice>((template: template, orientation: _orientation));

  void _turn(SheetOrientation orientation) =>
      setState(() => _orientation = orientation);

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter): () =>
          _take(widget.selected),
      const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
          _take(widget.selected),
      const SingleActivator(LogicalKeyboardKey.keyP): () =>
          _turn(SheetOrientation.portrait),
      const SingleActivator(LogicalKeyboardKey.keyL): () =>
          _turn(SheetOrientation.landscape),
    },
    child: GlassDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 3 * 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChoiceRow<SheetOrientation>(
              choices: SheetOrientation.values,
              selected: _orientation,
              labelOf: (orientation) => orientation.label,
              tooltipOf: (orientation) => switch (orientation) {
                SheetOrientation.portrait => 'Upright: P',
                SheetOrientation.landscape => 'Landscape: L',
              },
              compact: true,
              onSelected: _turn,
            ),
            const SizedBox(height: 10),
            SheetTemplatePicker(
              selected: widget.selected,
              size: widget.size,
              orientation: _orientation,
              onSelected: _take,
            ),
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
          onPressed: () => _take(widget.selected),
          child: Text(widget.action),
        ),
      ],
    ),
  );
}
