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

/// Asks which template to print, under [title], returning the one chosen,
/// or null if none is. [selected] is marked at first: Enter, or [action],
/// takes it; a click takes another.
Future<SheetTemplate?> chooseSheetTemplate(
  BuildContext context, {
  required String title,
  required SheetTemplate selected,
  required SheetSize size,
  SheetOrientation orientation = SheetOrientation.portrait,
  String action = 'Choose',
}) => showAppDialog<SheetTemplate>(
  context: context,
  builder: (context) {
    void take(SheetTemplate template) => Navigator.of(context).pop(template);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): () => take(selected),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            take(selected),
      },
      child: GlassDialog(
        title: Text(title),
        content: SizedBox(
          width: 3 * 78,
          child: SheetTemplatePicker(
            selected: selected,
            size: size,
            orientation: orientation,
            onSelected: take,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => take(selected),
            child: Text(action),
          ),
        ],
      ),
    );
  },
);
