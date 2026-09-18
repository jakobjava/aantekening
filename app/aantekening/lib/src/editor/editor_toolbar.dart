/// The canvas toolbar.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

/// Tools, pen settings and view controls for the open page.
///
/// Kept to one row of icons with the pen's own options behind the pen button:
/// the toolbar is next to the writing surface all the time, so it earns its
/// space only by staying small.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    required this.controller,
    required this.onZoomToFit,
    required this.onResetZoom,
    super.key,
    this.isSaving = false,
  });

  final CanvasController controller;
  final VoidCallback onZoomToFit;
  final VoidCallback onResetZoom;
  final bool isSaving;

  /// The pens offered in the toolbar.
  static const List<({String label, PenSettings settings})> pens =
      <({String label, PenSettings settings})>[
        (label: 'Black pen', settings: PenSettings.blackPen),
        (label: 'Blue pen', settings: PenSettings.bluePen),
        (label: 'Red pen', settings: PenSettings.redPen),
        (label: 'Highlighter', settings: PenSettings.yellowHighlighter),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          // The tool group scrolls rather than overflowing, so the toolbar
          // survives a narrow window and a phone-width screen; the view
          // controls on the right stay reachable at any width.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _ToolButton(
                    icon: Icons.near_me_outlined,
                    tooltip: 'Select  (V)',
                    tool: CanvasTool.select,
                    controller: controller,
                  ),
                  _ToolButton(
                    icon: Icons.pan_tool_outlined,
                    tooltip: 'Pan  (H, or hold space)',
                    tool: CanvasTool.pan,
                    controller: controller,
                  ),
                  _PenButton(controller: controller),
                  _ToolButton(
                    icon: Icons.cleaning_services_outlined,
                    tooltip: 'Eraser  (E)',
                    tool: CanvasTool.eraser,
                    controller: controller,
                  ),
                  const _Separator(),
                  _ToolButton(
                    icon: Icons.text_fields_rounded,
                    tooltip: 'Text box  (T)',
                    tool: CanvasTool.text,
                    controller: controller,
                  ),
                  _ToolButton(
                    icon: Icons.functions_rounded,
                    tooltip: 'Formula  (M)',
                    tool: CanvasTool.math,
                    controller: controller,
                  ),
                  const _Separator(),
                  IconButton(
                    icon: const Icon(Icons.undo_rounded, size: 18),
                    tooltip: 'Undo  (Ctrl+Z)',
                    onPressed: controller.canUndo ? controller.undo : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo_rounded, size: 18),
                    tooltip: 'Redo  (Ctrl+Shift+Z)',
                    onPressed: controller.canRedo ? controller.redo : null,
                  ),
                ],
              ),
            ),
          ),
          if (isSaving)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Saving',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            '${(controller.viewport.zoom * 100).round()}%',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_outlined, size: 18),
            tooltip: 'Fit page',
            onPressed: onZoomToFit,
          ),
          IconButton(
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            tooltip: 'Actual size  (Ctrl+0)',
            onPressed: onResetZoom,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.tool,
    required this.controller,
  });

  final IconData icon;
  final String tooltip;
  final CanvasTool tool;
  final CanvasController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = controller.tool == tool;

    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      isSelected: active,
      style: IconButton.styleFrom(
        backgroundColor: active ? scheme.primary.withValues(alpha: 0.14) : null,
        foregroundColor: active ? scheme.primary : null,
      ),
      onPressed: () => controller.setTool(tool),
    );
  }
}

/// The drawing tool, with its pens behind a menu.
class _PenButton extends StatelessWidget {
  const _PenButton({required this.controller});

  final CanvasController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = controller.tool == CanvasTool.draw;

    return MenuAnchor(
      builder: (context, menu, _) => GestureDetector(
        onSecondaryTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: IconButton(
          icon: Icon(
            controller.pen.tool == InkTool.highlighter
                ? Icons.brush_rounded
                : Icons.edit_rounded,
            size: 18,
          ),
          tooltip: 'Draw  (P) — right-click for pens',
          isSelected: active,
          style: IconButton.styleFrom(
            backgroundColor: active
                ? Color(controller.pen.color).withValues(alpha: 0.18)
                : null,
            foregroundColor: active ? Color(controller.pen.color) : null,
          ),
          onPressed: () {
            if (active) {
              menu.open();
            } else {
              controller.setTool(CanvasTool.draw);
            }
          },
        ),
      ),
      menuChildren: <Widget>[
        for (final pen in EditorToolbar.pens)
          MenuItemButton(
            leadingIcon: Icon(
              Icons.circle,
              size: 14,
              color: Color(pen.settings.color),
            ),
            trailingIcon: controller.pen == pen.settings
                ? Icon(Icons.check, size: 14, color: scheme.primary)
                : null,
            onPressed: () {
              controller
                ..setPen(pen.settings)
                ..setTool(CanvasTool.draw);
            },
            child: Text(pen.label),
          ),
        const Divider(height: 8),
        for (final width in const <double>[1.0, 2.2, 4.0, 8.0])
          MenuItemButton(
            leadingIcon: SizedBox(
              width: 16,
              child: Center(
                child: Container(
                  width: 14,
                  height: width.clamp(1, 8),
                  decoration: BoxDecoration(
                    color: Color(controller.pen.color),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            onPressed: () =>
                controller.setPen(controller.pen.copyWith(width: width)),
            child: Text('${width}pt'),
          ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(
      height: 20,
      child: VerticalDivider(
        width: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
}
