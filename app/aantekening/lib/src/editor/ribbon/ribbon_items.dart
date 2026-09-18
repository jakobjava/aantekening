/// The buttons, menus and galleries the ribbon is made of.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../palette.dart';
import '../text/math_syntax.dart';
import '../text/math_templates.dart';
import '../text/text_box_controller.dart';
import '../text/text_styles.dart';
import 'ribbon_layout.dart';
import 'ribbon_state.dart';

/// What the ribbon's buttons act on: the page, the text being edited, and
/// the page editor's commands.
@immutable
class RibbonCommands {
  const RibbonCommands({
    required this.canvas,
    required this.text,
    required this.lastInkTool,
    required this.onToolSelected,
    required this.onFormula,
    required this.onInsertTextBox,
    required this.onInsertImage,
    required this.onInsertPdf,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitPage,
    required this.onActualSize,
    required this.onMathInsert,
    this.saving,
  });

  final CanvasController canvas;
  final TextBoxEditorController text;

  /// The pen or the highlighter, whichever was used last: the one the colour
  /// and thickness galleries set while neither is in hand.
  final ValueGetter<CanvasTool> lastInkTool;

  final ValueChanged<CanvasTool> onToolSelected;
  final VoidCallback onFormula;
  final VoidCallback onInsertTextBox;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertPdf;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitPage;
  final VoidCallback onActualSize;

  /// Puts a structure or symbol into the formula being edited, or into a
  /// new one.
  final ValueChanged<MathTemplate> onMathInsert;

  /// Whether the page is being written to disk.
  final ValueListenable<bool>? saving;

  /// Pen widths offered, in page units.
  static const List<double> penWidths = <double>[1, 1.6, 2.2, 3.5, 5, 8];

  /// Highlighter nib heights offered, in page units.
  static const List<double> highlighterWidths = <double>[12, 18, 22, 30, 40];
}

/// Hands [RibbonCommands] down to the ribbon's buttons.
class RibbonScope extends InheritedWidget {
  const RibbonScope({required this.commands, required super.child, super.key});

  final RibbonCommands commands;

  static RibbonCommands of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RibbonScope>()!.commands;

  @override
  bool updateShouldNotify(RibbonScope oldWidget) =>
      !identical(commands, oldWidget.commands);
}

/// Sizes shared by everything on the ribbon.
abstract final class RibbonMetrics {
  /// A small button, and one of the two rows small buttons are stacked in.
  static const double row = 30;

  /// The height of a section's buttons: two rows.
  static const double content = row * 2;

  static const double smallIcon = 18;
  static const double largeIcon = 24;
}

/// The icon standing for [item], in its drag preview.
IconData ribbonIconOf(RibbonItem item) => switch (item) {
  RibbonItem.undo => Icons.undo_rounded,
  RibbonItem.redo => Icons.redo_rounded,
  RibbonItem.fontSize => Icons.format_size_rounded,
  RibbonItem.bold => Icons.format_bold_rounded,
  RibbonItem.italic => Icons.format_italic_rounded,
  RibbonItem.underline => Icons.format_underlined_rounded,
  RibbonItem.strikethrough => Icons.format_strikethrough_rounded,
  RibbonItem.inlineCode => Icons.code_rounded,
  RibbonItem.highlight => Icons.border_color_outlined,
  RibbonItem.textColor => Icons.format_color_text_rounded,
  RibbonItem.bullets => Icons.format_list_bulleted_rounded,
  RibbonItem.numbering => Icons.format_list_numbered_rounded,
  RibbonItem.todo => Icons.check_box_outlined,
  RibbonItem.outdent => Icons.format_indent_decrease_rounded,
  RibbonItem.indent => Icons.format_indent_increase_rounded,
  RibbonItem.paragraphStyle => Icons.title_rounded,
  RibbonItem.formula || RibbonItem.insertFormula => Icons.functions_rounded,
  RibbonItem.formulaSyntax => Icons.data_object_rounded,
  RibbonItem.textBox => Icons.text_fields_rounded,
  RibbonItem.picture => Icons.image_outlined,
  RibbonItem.pdf => Icons.picture_as_pdf_outlined,
  RibbonItem.select => Icons.highlight_alt_rounded,
  RibbonItem.eraser => Icons.auto_fix_normal_outlined,
  RibbonItem.pen => Icons.draw_rounded,
  RibbonItem.highlighter => Icons.border_color_rounded,
  RibbonItem.inkColour => Icons.palette_outlined,
  RibbonItem.inkThickness => Icons.line_weight_rounded,
  RibbonItem.zoomOut => Icons.zoom_out_rounded,
  RibbonItem.zoomLevel => Icons.crop_free_rounded,
  RibbonItem.zoomIn => Icons.zoom_in_rounded,
  RibbonItem.fitPage => Icons.fit_screen_outlined,
  RibbonItem.resetRibbon => Icons.restart_alt_rounded,
  RibbonItem.mathFraction ||
  RibbonItem.mathScript ||
  RibbonItem.mathRadical ||
  RibbonItem.mathIntegral ||
  RibbonItem.mathLargeOperator ||
  RibbonItem.mathBracket ||
  RibbonItem.mathAccent ||
  RibbonItem.mathFunction ||
  RibbonItem.mathMatrix => Icons.functions_rounded,
  RibbonItem.mathGreek ||
  RibbonItem.mathOperators ||
  RibbonItem.mathRelations ||
  RibbonItem.mathArrows ||
  RibbonItem.mathOther => Icons.emoji_symbols_rounded,
};

/// The gallery behind each Math tab button.
MathGallery? mathGalleryOf(RibbonItem item) => switch (item) {
  RibbonItem.mathFraction => MathGalleries.fraction,
  RibbonItem.mathScript => MathGalleries.script,
  RibbonItem.mathRadical => MathGalleries.radical,
  RibbonItem.mathIntegral => MathGalleries.integral,
  RibbonItem.mathLargeOperator => MathGalleries.largeOperator,
  RibbonItem.mathBracket => MathGalleries.bracket,
  RibbonItem.mathAccent => MathGalleries.accent,
  RibbonItem.mathFunction => MathGalleries.function,
  RibbonItem.mathMatrix => MathGalleries.matrix,
  RibbonItem.mathGreek => MathGalleries.greek,
  RibbonItem.mathOperators => MathGalleries.operators,
  RibbonItem.mathRelations => MathGalleries.relations,
  RibbonItem.mathArrows => MathGalleries.arrows,
  RibbonItem.mathOther => MathGalleries.other,
  _ => null,
};

/// [item]'s icon, drawn at [size].
Widget ribbonGlyphOf(
  RibbonItem item, {
  double size = RibbonMetrics.smallIcon,
}) => item == RibbonItem.eraser
    ? _EraserIcon(size: size)
    : Icon(ribbonIconOf(item), size: size);

/// The widget for one ribbon item.
class RibbonItemView extends StatelessWidget {
  const RibbonItemView({required this.item, super.key});

  final RibbonItem item;

  @override
  Widget build(BuildContext context) {
    final commands = RibbonScope.of(context);
    final canvas = commands.canvas;
    final text = commands.text;

    Widget mark(MarkKind kind, String tooltip) => _TextCommand(
      text: text,
      builder: (state, enabled) => RibbonIconButton(
        icon: ribbonIconOf(item),
        tooltip: tooltip,
        selected: state.marks.contains(kind),
        onPressed: enabled && !state.inFormula
            ? () => text.toggleMark(kind)
            : null,
      ),
    );

    Widget blockKind(TextBlockKind kind, String tooltip) => _TextCommand(
      text: text,
      builder: (state, enabled) => RibbonIconButton(
        icon: ribbonIconOf(item),
        tooltip: tooltip,
        selected: state.blockKind == kind,
        onPressed: enabled ? () => text.toggleBlockKind(kind) : null,
      ),
    );

    Widget tool(CanvasTool tool, String tooltip, Widget icon) =>
        _CanvasSelect<CanvasTool>(
          canvas: canvas,
          select: () => canvas.tool,
          builder: (context, current) => RibbonLargeButton(
            icon: icon,
            label: item.label,
            tooltip: tooltip,
            selected: current == tool,
            onPressed: () => commands.onToolSelected(tool),
          ),
        );

    return switch (item) {
      RibbonItem.undo => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.canUndo,
        builder: (context, can) => RibbonIconButton(
          icon: ribbonIconOf(item),
          tooltip: 'Undo  (Ctrl+Z)',
          onPressed: can ? canvas.undo : null,
        ),
      ),
      RibbonItem.redo => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.canRedo,
        builder: (context, can) => RibbonIconButton(
          icon: ribbonIconOf(item),
          tooltip: 'Redo  (Ctrl+Shift+Z or Ctrl+Y)',
          onPressed: can ? canvas.redo : null,
        ),
      ),
      RibbonItem.fontSize => _TextCommand(
        text: text,
        builder: (state, enabled) =>
            _FontSizeMenu(controller: text, enabled: enabled),
      ),
      RibbonItem.bold => mark(MarkKind.bold, 'Bold  (Ctrl+B)'),
      RibbonItem.italic => mark(MarkKind.italic, 'Italic  (Ctrl+I)'),
      RibbonItem.underline => mark(MarkKind.underline, 'Underline  (Ctrl+U)'),
      RibbonItem.strikethrough => mark(
        MarkKind.strikethrough,
        'Strikethrough  (Ctrl+−)',
      ),
      RibbonItem.inlineCode => mark(MarkKind.code, 'Inline code  (Ctrl+E)'),
      RibbonItem.highlight => _TextCommand(
        text: text,
        builder: (state, enabled) => _ColorButton(
          icon: ribbonIconOf(item),
          tooltip: 'Highlight  (Ctrl+Shift+H)',
          current: state.highlight,
          fallback: NotePalette.presets[4].color,
          noneLabel: 'No highlight',
          enabled: enabled,
          onChanged: (color) => text.setHighlight(
            color == null ? null : RichTextStyles.highlightFor(color),
          ),
        ),
      ),
      RibbonItem.textColor => _TextCommand(
        text: text,
        builder: (state, enabled) => _ColorButton(
          icon: ribbonIconOf(item),
          tooltip: 'Text colour',
          current: state.textColor,
          fallback: 0xFFD93025,
          noneLabel: 'Automatic (black)',
          enabled: enabled,
          onChanged: text.setTextColor,
        ),
      ),
      RibbonItem.bullets => blockKind(
        TextBlockKind.bulleted,
        'Bullets  (Ctrl+.  or type "- ")',
      ),
      RibbonItem.numbering => blockKind(
        TextBlockKind.numbered,
        'Numbering  (Ctrl+/  or type "1. ")',
      ),
      RibbonItem.todo => blockKind(
        TextBlockKind.todo,
        'To-do  (Ctrl+1  or type "[] ")\nCtrl+Enter ticks it',
      ),
      RibbonItem.outdent => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonIconButton(
          icon: ribbonIconOf(item),
          tooltip: 'Outdent  (Shift+Tab)',
          onPressed: enabled ? () => text.indent(-1) : null,
        ),
      ),
      RibbonItem.indent => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonIconButton(
          icon: ribbonIconOf(item),
          tooltip: 'Indent  (Tab)',
          onPressed: enabled ? () => text.indent(1) : null,
        ),
      ),
      RibbonItem.paragraphStyle => _TextCommand(
        text: text,
        builder: (state, enabled) =>
            _StyleMenu(controller: text, enabled: enabled),
      ),
      RibbonItem.formula => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonIconButton(
          icon: ribbonIconOf(item),
          tooltip: state.inFormula
              ? 'Finish the formula  (Enter)'
              : 'Formula  (Alt+= or Ctrl+M)\nWritten in place, in the text box',
          selected: state.inFormula,
          onPressed: commands.onFormula,
        ),
      ),
      RibbonItem.formulaSyntax => Consumer(
        builder: (context, ref, _) => _FormulaSyntaxToggle(
          mode: ref.watch(mathSyntaxProvider),
          onSwitch: ref.read(mathSyntaxProvider.notifier).toggle,
        ),
      ),
      RibbonItem.textBox => RibbonLargeButton(
        icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
        label: item.label,
        tooltip:
            'Text box\nOr click anywhere on the page with Select and start '
            'typing',
        onPressed: commands.onInsertTextBox,
      ),
      RibbonItem.picture => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonLargeButton(
          icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
          label: item.label,
          tooltip: text.isActive
              ? 'Insert a picture into the text box'
              : 'Insert a picture onto the page',
          onPressed: commands.onInsertImage,
        ),
      ),
      RibbonItem.pdf => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonLargeButton(
          icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
          label: item.label,
          tooltip: text.isActive
              ? 'Insert PDF pages into the text box'
              : 'Insert PDF pages onto the page, one picture per page',
          onPressed: commands.onInsertPdf,
        ),
      ),
      RibbonItem.insertFormula => RibbonLargeButton(
        icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
        label: item.label,
        tooltip: 'Formula  (Alt+= or Ctrl+M)\nWritten in place, in a text box',
        onPressed: commands.onFormula,
      ),
      RibbonItem.select => tool(
        CanvasTool.select,
        'Type and select  (V or T)\n'
        'Click to write, drag to select; scroll or middle-drag to move '
        'around',
        Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
      ),
      RibbonItem.eraser => tool(
        CanvasTool.eraser,
        'Eraser  (E)\nRemoves whole strokes',
        ribbonGlyphOf(item, size: RibbonMetrics.largeIcon),
      ),
      RibbonItem.pen => _CanvasSelect<int>(
        canvas: canvas,
        select: () => canvas.penSettings.color,
        builder: (context, color) => tool(
          CanvasTool.pen,
          'Pen  (P)',
          ColorBarIcon(
            icon: ribbonIconOf(item),
            color: color,
            size: RibbonMetrics.largeIcon,
          ),
        ),
      ),
      RibbonItem.highlighter => _CanvasSelect<int>(
        canvas: canvas,
        select: () => canvas.highlighterSettings.color,
        builder: (context, color) => tool(
          CanvasTool.highlighter,
          'Highlighter  (H)',
          ColorBarIcon(
            icon: ribbonIconOf(item),
            color: color,
            size: RibbonMetrics.largeIcon,
          ),
        ),
      ),
      RibbonItem.inkColour => _InkColourGallery(commands: commands),
      RibbonItem.inkThickness => _InkThicknessGallery(commands: commands),
      RibbonItem.zoomOut => RibbonIconButton(
        icon: ribbonIconOf(item),
        tooltip: 'Zoom out  (Ctrl+−, or Ctrl+scroll)',
        onPressed: commands.onZoomOut,
      ),
      RibbonItem.zoomIn => RibbonIconButton(
        icon: ribbonIconOf(item),
        tooltip: 'Zoom in  (Ctrl+=, or Ctrl+scroll)',
        onPressed: commands.onZoomIn,
      ),
      RibbonItem.zoomLevel => _CanvasSelect<int>(
        canvas: canvas,
        select: () => (canvas.viewport.zoom * 100).round(),
        builder: (context, percent) => RibbonLargeButton(
          icon: SizedBox(
            height: RibbonMetrics.largeIcon,
            child: Center(
              child: Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          label: item.label,
          tooltip: 'Back to actual size  (Ctrl+0)',
          onPressed: commands.onActualSize,
        ),
      ),
      RibbonItem.fitPage => RibbonLargeButton(
        icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
        label: item.label,
        tooltip: 'Fit everything on the page into view',
        onPressed: commands.onFitPage,
      ),
      RibbonItem.mathFraction ||
      RibbonItem.mathScript ||
      RibbonItem.mathRadical ||
      RibbonItem.mathIntegral ||
      RibbonItem.mathLargeOperator ||
      RibbonItem.mathBracket ||
      RibbonItem.mathAccent ||
      RibbonItem.mathFunction ||
      RibbonItem.mathMatrix ||
      RibbonItem.mathGreek ||
      RibbonItem.mathOperators ||
      RibbonItem.mathRelations ||
      RibbonItem.mathArrows ||
      RibbonItem.mathOther => _MathGalleryButton(
        gallery: mathGalleryOf(item)!,
        onInsert: commands.onMathInsert,
      ),
      RibbonItem.resetRibbon => Consumer(
        builder: (context, ref, _) {
          final isDefault = ref.watch(
            ribbonLayoutProvider.select((layout) => layout.isDefault),
          );
          return RibbonLargeButton(
            icon: Icon(ribbonIconOf(item), size: RibbonMetrics.largeIcon),
            label: item.label,
            tooltip:
                'Put every button back where it started\n'
                'Drag any button to move it, to another section or tab',
            onPressed: isDefault
                ? null
                : ref.read(ribbonLayoutProvider.notifier).reset,
          );
        },
      ),
    };
  }
}

// ------------------------------------------------------------ listening

/// Rebuilds when the text formatting, or whether there is text to format,
/// changes.
class _TextCommand extends StatelessWidget {
  const _TextCommand({required this.text, required this.builder});

  final TextBoxEditorController text;
  final Widget Function(TextFormatState state, bool enabled) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: text,
    builder: (context, _) => builder(text.state, text.hasTarget),
  );
}

/// Rebuilds when one value read from the page changes, rather than on every
/// change — the page notifies on every frame of scrolling.
class _CanvasSelect<T> extends StatefulWidget {
  const _CanvasSelect({
    required this.canvas,
    required this.select,
    required this.builder,
    super.key,
  });

  final CanvasController canvas;
  final ValueGetter<T> select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_CanvasSelect<T>> createState() => _CanvasSelectState<T>();
}

class _CanvasSelectState<T> extends State<_CanvasSelect<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.canvas.addListener(_changed);
  }

  @override
  void didUpdateWidget(_CanvasSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.canvas, widget.canvas)) {
      oldWidget.canvas.removeListener(_changed);
      widget.canvas.addListener(_changed);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.canvas.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.select();
    if (value != _value) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

// -------------------------------------------------------------- buttons

/// A button showing an icon alone, one row high.
class RibbonIconButton extends StatelessWidget {
  const RibbonIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.selected = false,
    this.child,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Shown instead of [icon].
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: RibbonMetrics.row,
      height: RibbonMetrics.row,
      child: IconButton(
        icon: child ?? Icon(icon, size: RibbonMetrics.smallIcon),
        tooltip: tooltip,
        isSelected: selected,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : null,
          foregroundColor: selected ? scheme.primary : null,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// A tall button with its name under the icon.
class RibbonLargeButton extends StatelessWidget {
  const RibbonLargeButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.selected = false,
  });

  final Widget icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
        ? scheme.primary
        : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: RibbonMetrics.content,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? scheme.primary.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  icon,
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon with a bar of colour beneath it: the pen's colour, or the colour
/// a text button applies.
class ColorBarIcon extends StatelessWidget {
  const ColorBarIcon({
    required this.icon,
    required this.color,
    super.key,
    this.size = RibbonMetrics.smallIcon,
  });

  final IconData icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 2,
    height: size + 4,
    child: Stack(
      alignment: Alignment.topCenter,
      children: <Widget>[
        Icon(icon, size: size - 2),
        Positioned(
          left: 1,
          right: 1,
          bottom: 1,
          height: math.max(3, size / 5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(color | 0xFF000000),
              borderRadius: BorderRadius.circular(1),
              border: Border.all(color: const Color(0x33000000), width: 0.5),
            ),
          ),
        ),
      ],
    ),
  );
}

/// An eraser, which the icon font lacks.
class _EraserIcon extends StatelessWidget {
  const _EraserIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _EraserPainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class _EraserPainter extends CustomPainter {
  _EraserPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-math.pi / 4);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 18 * s, height: 9 * s),
      Radius.circular(2 * s),
    );
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s;
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(
        Rect.fromLTRB(-9 * s, -4.5 * s, -2 * s, 4.5 * s),
        Paint()..color = color,
      )
      ..restore()
      ..drawRRect(body, outline)
      ..restore();
    // The line it leaves behind.
    canvas.drawLine(
      Offset(4 * s, 21 * s),
      Offset(21 * s, 21 * s),
      outline..strokeWidth = 1.4 * s,
    );
  }

  @override
  bool shouldRepaint(_EraserPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------- menus

/// Paragraph style: normal, headings, code, quotation.
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static const List<(TextBlockKind, String, String)> _styles =
      <(TextBlockKind, String, String)>[
        (TextBlockKind.paragraph, 'Normal', 'Ctrl+Shift+N'),
        (TextBlockKind.heading1, 'Heading 1', 'Ctrl+Alt+1  or "# "'),
        (TextBlockKind.heading2, 'Heading 2', 'Ctrl+Alt+2  or "## "'),
        (TextBlockKind.heading3, 'Heading 3', 'Ctrl+Alt+3  or "### "'),
        (TextBlockKind.code, 'Code', ''),
        (TextBlockKind.quote, 'Quote', '"> "'),
      ];

  @override
  Widget build(BuildContext context) {
    final current = controller.state.blockKind;
    final label = _styles
        .firstWhere((style) => style.$1 == current, orElse: () => _styles.first)
        .$2;

    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: label,
        width: 76,
        tooltip: 'Paragraph style',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        for (final (kind, name, shortcut) in _styles)
          MenuItemButton(
            // A menu sets a style rather than toggling it, so choosing the
            // current one changes nothing.
            onPressed: kind == current
                ? null
                : () => controller.toggleBlockKind(kind),
            trailingIcon: shortcut.isEmpty
                ? null
                : Text(
                    shortcut,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
            child: Text(name),
          ),
      ],
    );
  }
}

/// Font size, in points.
class _FontSizeMenu extends StatelessWidget {
  const _FontSizeMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static String _format(double points) => points == points.roundToDouble()
      ? points.toStringAsFixed(0)
      : points.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final current = controller.state.fontSize;
    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: _format(current),
        width: 26,
        tooltip: 'Font size',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        for (final size in RichTextStyles.pointSizes)
          MenuItemButton(
            onPressed: () => controller.setFontSize(size),
            trailingIcon: size == current
                ? const Icon(Icons.check, size: 14)
                : null,
            child: SizedBox(width: 40, child: Text(_format(size))),
          ),
      ],
    );
  }
}

/// A drop-down's face: its current value and an arrow.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.width,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final double width;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: RibbonMetrics.row - 2,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.only(left: 8, right: 2),
            minimumSize: Size.zero,
            side: BorderSide(color: scheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: Theme.of(context).textTheme.labelMedium,
            foregroundColor: scheme.onSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: width,
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.arrow_drop_down_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// A colour button: the icon applies the colour shown beneath it; the arrow
/// opens the palette.
class _ColorButton extends StatefulWidget {
  const _ColorButton({
    required this.icon,
    required this.tooltip,
    required this.current,
    required this.fallback,
    required this.noneLabel,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String tooltip;

  /// The colour of the text under the caret, or null for none.
  final int? current;

  /// What the button applies before any colour has been chosen here.
  final int fallback;

  final String noneLabel;
  final bool enabled;

  /// Called with the chosen colour, opaque, or null for [noneLabel].
  final ValueChanged<int?> onChanged;

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  final MenuController _menu = MenuController();
  late int _last = widget.fallback;

  void _apply(int? color) {
    if (color != null) setState(() => _last = color | 0xFF000000);
    _menu.close();
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: <Widget>[
        ColorSwatchPanel(
          selected: widget.current,
          onSelected: _apply,
          noneLabel: widget.noneLabel,
          onNone: () => _apply(null),
          onPickerOpened: _menu.close,
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RibbonIconButton(
            icon: widget.icon,
            tooltip: '${widget.tooltip}: ${NotePalette.nameOf(_last)}',
            onPressed: widget.enabled ? () => widget.onChanged(_last) : null,
            child: ColorBarIcon(icon: widget.icon, color: _last),
          ),
          SizedBox(
            width: 14,
            height: RibbonMetrics.row,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_drop_down_rounded, size: 18),
              tooltip: '${widget.tooltip}: choose',
              onPressed: widget.enabled
                  ? () => _menu.isOpen ? _menu.close() : _menu.open()
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Which syntax formulas are typed in. Switching it translates the formula
/// being edited.
class _FormulaSyntaxToggle extends StatelessWidget {
  const _FormulaSyntaxToggle({required this.mode, required this.onSwitch});

  final MathMode mode;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget segment(MathMode value, String label, String tooltip) {
      final selected = mode == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: selected ? null : onSwitch,
          child: Container(
            height: RibbonMetrics.row - 6,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            color: selected ? scheme.primary.withValues(alpha: 0.14) : null,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                segment(
                  MathMode.linear,
                  'Simple',
                  'Simple syntax: x^2/3, sqrt(x), alpha',
                ),
                segment(
                  MathMode.latex,
                  'LaTeX',
                  r'LaTeX syntax: x^{2}/3, \sqrt{x}, \alpha',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ galleries

PenSettings _inkSettings(RibbonCommands commands) =>
    commands.lastInkTool() == CanvasTool.highlighter
    ? commands.canvas.highlighterSettings
    : commands.canvas.penSettings;

/// Changes the pen or highlighter and takes it up, as picking a pen colour in
/// OneNote does.
void _changeInk(RibbonCommands commands, PenSettings settings) {
  commands.canvas.setPen(settings);
  commands.onToolSelected(
    settings.tool == InkTool.highlighter
        ? CanvasTool.highlighter
        : CanvasTool.pen,
  );
}

/// The palette, for the pen or highlighter in hand.
class _InkColourGallery extends StatelessWidget {
  const _InkColourGallery({required this.commands});

  final RibbonCommands commands;

  /// Custom colours shown after the presets.
  static const int _recent = 4;

  @override
  Widget build(BuildContext context) {
    final canvas = commands.canvas;
    return _CanvasSelect<PenSettings>(
      canvas: canvas,
      select: () => _inkSettings(commands),
      builder: (context, settings) => ValueListenableBuilder<List<int>>(
        valueListenable: NotePalette.recent,
        builder: (context, recent, _) {
          final owner = settings.tool == InkTool.highlighter
              ? 'Highlighter'
              : 'Pen';
          final colours = <({int color, String name})>[
            ...NotePalette.presets,
            for (final color in recent.take(_recent))
              (color: color, name: NotePalette.nameOf(color)),
          ];
          void pick(int color) => _changeInk(
            commands,
            settings.copyWith(color: color | 0xFF000000),
          );

          return SizedBox(
            height: RibbonMetrics.content,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < colours.length; i += 2)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (final entry in colours.skip(i).take(2))
                        PaletteSwatch(
                          color: entry.color,
                          name: '$owner colour: ${entry.name}',
                          selected:
                              entry.color == (settings.color | 0xFF000000),
                          diameter: 18,
                          onTap: () => pick(entry.color),
                        ),
                    ],
                  ),
                RibbonIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'More colours…',
                  onPressed: () async {
                    final picked = await showColorPicker(
                      context,
                      initial: settings.color,
                    );
                    if (picked == null) return;
                    NotePalette.remember(picked);
                    pick(picked);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Line widths, for the pen or highlighter in hand.
class _InkThicknessGallery extends StatelessWidget {
  const _InkThicknessGallery({required this.commands});

  final RibbonCommands commands;

  @override
  Widget build(BuildContext context) => _CanvasSelect<PenSettings>(
    canvas: commands.canvas,
    select: () => _inkSettings(commands),
    builder: (context, settings) {
      final highlighter = settings.tool == InkTool.highlighter;
      return SizedBox(
        height: RibbonMetrics.content,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final width
                in highlighter
                    ? RibbonCommands.highlighterWidths
                    : RibbonCommands.penWidths)
              _WidthChoice(
                width: width,
                color: settings.color,
                highlighter: highlighter,
                selected: width == settings.width,
                onTap: () =>
                    _changeInk(commands, settings.copyWith(width: width)),
              ),
          ],
        ),
      );
    },
  );
}

/// One width choice, drawn as the line it would make.
class _WidthChoice extends StatelessWidget {
  const _WidthChoice({
    required this.width,
    required this.color,
    required this.highlighter,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final int color;
  final bool highlighter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = highlighter
        ? Color(color | 0xFF000000).withValues(alpha: 0.45)
        : Color(color | 0xFF000000);
    final points = width.toStringAsFixed(width % 1 == 0 ? 0 : 1);
    return Tooltip(
      message: highlighter ? 'Highlighter: $points pt' : 'Pen: $points pt',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: highlighter
              ? Container(
                  width: (width * 0.16).clamp(2, 5),
                  height: (width * 0.7).clamp(6, 28),
                  color: shown,
                )
              : Container(
                  width: (width * 1.6).clamp(3, 18),
                  height: (width * 1.6).clamp(3, 18),
                  decoration: BoxDecoration(
                    color: shown,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A Math tab button: a structure or symbol family, whose variants drop down
/// in a grid, each drawn as it will look.
class _MathGalleryButton extends StatefulWidget {
  const _MathGalleryButton({required this.gallery, required this.onInsert});

  final MathGallery gallery;
  final ValueChanged<MathTemplate> onInsert;

  @override
  State<_MathGalleryButton> createState() => _MathGalleryButtonState();
}

class _MathGalleryButtonState extends State<_MathGalleryButton> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gallery = widget.gallery;
    final tileWidth = gallery.columns >= 7 ? 40.0 : 64.0;
    return MenuAnchor(
      controller: _menu,
      menuChildren: <Widget>[
        Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: tileWidth * gallery.columns,
            child: Wrap(
              children: <Widget>[
                for (final template in gallery.templates)
                  _MathTile(
                    template: template,
                    width: tileWidth,
                    onTap: () {
                      _menu.close();
                      widget.onInsert(template);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
      child: RibbonLargeButton(
        icon: SizedBox(
          height: RibbonMetrics.largeIcon,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MathView(
              source: gallery.icon,
              mode: MathMode.latex,
              displayStyle: false,
              textStyle: TextStyle(fontSize: 18, color: scheme.onSurface),
            ),
          ),
        ),
        label: gallery.name,
        tooltip: gallery.name,
        onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
      ),
    );
  }
}

/// One variant in a Math tab gallery.
class _MathTile extends StatelessWidget {
  const _MathTile({
    required this.template,
    required this.width,
    required this.onTap,
  });

  final MathTemplate template;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: template.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: width,
          height: width >= 60 ? 52 : 40,
          padding: const EdgeInsets.all(6),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MathView(
              source: template.preview,
              mode: MathMode.latex,
              displayStyle: false,
              textStyle: TextStyle(fontSize: 18, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
