/// The buttons, menus and galleries the ribbon is made of.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../commands/app_command.dart';
import '../../commands/editor_keys.dart';
import '../../commands/shortcuts.dart';
import '../../look/appearance.dart';
import '../../look/colour_picker.dart';
import '../../look/controls.dart';
import '../../look/marks.dart';
import '../../look/tones.dart';
import '../../spelling/dictionaries.dart';
import '../../spelling/spelling.dart';
import '../palette.dart';
import '../page_minimap.dart';
import '../text/cheat_sheet.dart';
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

  /// The widest a tall button's name is set before it breaks onto a second
  /// line.
  static const double largeLabelWidth = 76;
}

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

/// What a small button shows: its name, or for formatting the letter it
/// formats, formatted as it would be.
Widget ribbonFaceOf(RibbonItem item) => switch (item) {
  RibbonItem.bold => const Text(
    'B',
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
  ),
  RibbonItem.italic => const Text(
    'I',
    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5),
  ),
  RibbonItem.underline => const Text(
    'U',
    style: TextStyle(decoration: TextDecoration.underline, fontSize: 13.5),
  ),
  RibbonItem.strikethrough => const Text(
    'S',
    style: TextStyle(decoration: TextDecoration.lineThrough, fontSize: 13.5),
  ),
  RibbonItem.inlineCode => Text(
    'code',
    style: TextStyle(fontFamily: InterfaceFont.mono.family, fontSize: 12),
  ),
  RibbonItem.bullets => const Text('Bullets'),
  RibbonItem.numbering => const Text('Numbers'),
  _ => Text(item.label),
};

/// The widget for one ribbon item.
class RibbonItemView extends ConsumerWidget {
  const RibbonItemView({required this.item, super.key});

  final RibbonItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = RibbonScope.of(context);
    final canvas = commands.canvas;
    final text = commands.text;
    final bindings = ref.watch(shortcutsProvider);
    final face = ribbonFaceOf(item);

    Widget mark(MarkKind kind, EditorKey key) => _TextCommand(
      text: text,
      builder: (state, enabled) => RibbonButton(
        face: face,
        tooltip: key.tooltip,
        selected: state.marks.contains(kind),
        onPressed: enabled && !state.inFormula
            ? () => text.toggleMark(kind)
            : null,
      ),
    );

    Widget blockKind(TextBlockKind kind, String tooltip) => _TextCommand(
      text: text,
      builder: (state, enabled) => RibbonButton(
        face: face,
        tooltip: tooltip,
        selected: state.blockKind == kind,
        onPressed: enabled ? () => text.toggleBlockKind(kind) : null,
      ),
    );

    Widget tool(CanvasTool tool, AppCommand command, {int? colour}) =>
        _CanvasSelect<CanvasTool>(
          canvas: canvas,
          select: () => canvas.tool,
          builder: (context, current) => RibbonLargeButton(
            label: item.label,
            glyph: colour == null ? null : ColourBar(color: colour),
            tooltip: bindings.tooltip(command, describe: true),
            selected: current == tool,
            onPressed: () => commands.onToolSelected(tool),
          ),
        );

    Widget large(
      AppCommand command,
      VoidCallback? onPressed, {
      bool selected = false,
    }) => RibbonLargeButton(
      label: item.label,
      tooltip: bindings.tooltip(command, label: item.label, describe: true),
      selected: selected,
      onPressed: onPressed,
    );

    return switch (item) {
      RibbonItem.undo => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.canUndo,
        builder: (context, can) => RibbonButton(
          face: face,
          tooltip: EditorKey.undo.tooltip,
          onPressed: can ? canvas.undo : null,
        ),
      ),
      RibbonItem.redo => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.canRedo,
        builder: (context, can) => RibbonButton(
          face: face,
          tooltip: EditorKey.redo.tooltip,
          onPressed: can ? canvas.redo : null,
        ),
      ),
      RibbonItem.fontSize => _TextCommand(
        text: text,
        builder: (state, enabled) =>
            _FontSizeMenu(controller: text, enabled: enabled),
      ),
      RibbonItem.bold => mark(MarkKind.bold, EditorKey.bold),
      RibbonItem.italic => mark(MarkKind.italic, EditorKey.italic),
      RibbonItem.underline => mark(MarkKind.underline, EditorKey.underline),
      RibbonItem.strikethrough => mark(
        MarkKind.strikethrough,
        EditorKey.strikethrough,
      ),
      RibbonItem.inlineCode => mark(MarkKind.code, EditorKey.inlineCode),
      RibbonItem.highlight => _TextCommand(
        text: text,
        builder: (state, enabled) => _ColorButton(
          face: 'ab',
          tooltip: EditorKey.highlight.tooltip,
          name: 'Highlight',
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
          face: 'A',
          tooltip: 'Text colour',
          name: 'Text colour',
          current: state.textColor,
          fallback: 0xFFD93025,
          noneLabel: 'Automatic (black)',
          enabled: enabled,
          onChanged: text.setTextColor,
        ),
      ),
      RibbonItem.bullets => blockKind(
        TextBlockKind.bulleted,
        EditorKey.bullets.tooltip,
      ),
      RibbonItem.numbering => blockKind(
        TextBlockKind.numbered,
        EditorKey.numbering.tooltip,
      ),
      RibbonItem.todo => blockKind(
        TextBlockKind.todo,
        '${EditorKey.todo.tooltip}\n${EditorKey.tick.keys} ticks it',
      ),
      RibbonItem.outdent => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonButton(
          face: face,
          tooltip: EditorKey.outdent.tooltip,
          onPressed: enabled ? () => text.indent(-1) : null,
        ),
      ),
      RibbonItem.indent => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonButton(
          face: face,
          tooltip: EditorKey.indent.tooltip,
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
        builder: (state, enabled) => RibbonButton(
          face: face,
          tooltip: state.inFormula
              ? EditorKey.finishFormula.tooltipOf('Finish the formula')
              : '${EditorKey.formula.tooltip}\nWritten in place, in the '
                    'text box',
          selected: state.inFormula,
          onPressed: commands.onFormula,
        ),
      ),
      RibbonItem.formulaSyntax => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: MathSyntaxToggle(),
      ),
      RibbonItem.mathCheatSheet => RibbonLargeButton(
        label: item.label,
        tooltip: 'Cheat sheet\nWhat to type for every structure and symbol',
        selected: ref.watch(cheatSheetProvider),
        onPressed: ref.read(cheatSheetProvider.notifier).toggle,
      ),
      RibbonItem.spelling => large(
        AppCommand.spelling,
        () => ref.read(commandHandlersProvider).run(AppCommand.spelling),
        selected: ref.watch(spellingProvider.select((s) => s.enabled)),
      ),
      RibbonItem.spellingLanguages => _LanguagesMenu(item: item),
      RibbonItem.textBox => RibbonLargeButton(
        label: item.label,
        tooltip:
            '${bindings.tooltip(AppCommand.insertTextBox, label: 'Text box')}'
            '\nOr click anywhere on the page with Select and start typing',
        onPressed: commands.onInsertTextBox,
      ),
      RibbonItem.picture => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonLargeButton(
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
          label: item.label,
          tooltip: text.isActive
              ? 'Insert PDF pages into the text box'
              : 'Insert PDF pages onto the page, one picture per page',
          onPressed: commands.onInsertPdf,
        ),
      ),
      RibbonItem.insertFormula => RibbonLargeButton(
        label: item.label,
        tooltip:
            '${EditorKey.formula.tooltip}\nWritten in place, in a text box',
        onPressed: commands.onFormula,
      ),
      RibbonItem.select => tool(CanvasTool.select, AppCommand.selectTool),
      RibbonItem.eraser => tool(CanvasTool.eraser, AppCommand.eraser),
      RibbonItem.pen => _CanvasSelect<int>(
        canvas: canvas,
        select: () => canvas.penSettings.color,
        builder: (context, color) =>
            tool(CanvasTool.pen, AppCommand.pen, colour: color),
      ),
      RibbonItem.highlighter => _CanvasSelect<int>(
        canvas: canvas,
        select: () => canvas.highlighterSettings.color,
        builder: (context, color) =>
            tool(CanvasTool.highlighter, AppCommand.highlighter, colour: color),
      ),
      RibbonItem.inkColour => _InkColourGallery(commands: commands),
      RibbonItem.inkThickness => _InkThicknessGallery(commands: commands),
      RibbonItem.zoomOut => RibbonButton(
        face: face,
        tooltip: bindings.tooltip(AppCommand.zoomOut, describe: true),
        onPressed: commands.onZoomOut,
      ),
      RibbonItem.zoomIn => RibbonButton(
        face: face,
        tooltip: bindings.tooltip(AppCommand.zoomIn, describe: true),
        onPressed: commands.onZoomIn,
      ),
      RibbonItem.zoomLevel => _CanvasSelect<int>(
        canvas: canvas,
        select: () => (canvas.viewport.zoom * 100).round(),
        builder: (context, percent) => RibbonLargeButton(
          glyph: Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          label: item.label,
          tooltip: bindings.tooltip(
            AppCommand.actualSize,
            label: 'Back to actual size',
          ),
          onPressed: commands.onActualSize,
        ),
      ),
      RibbonItem.fitPage => large(AppCommand.fitPage, commands.onFitPage),
      RibbonItem.pagePreview => large(
        AppCommand.pagePreview,
        ref.read(minimapProvider.notifier).toggle,
        selected: ref.watch(minimapProvider),
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
      RibbonItem.resetRibbon => RibbonLargeButton(
        label: item.label,
        tooltip:
            'Put every button back where it started\n'
            'Drag any button to move it, to another section or tab',
        onPressed:
            ref.watch(ribbonLayoutProvider.select((layout) => layout.isDefault))
            ? null
            : ref.read(ribbonLayoutProvider.notifier).reset,
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

/// What every ribbon button is: lit under the pointer, shaded with a line
/// beneath while what it turns on is on, and greyed out while it has
/// nothing to act on.
class _Pressable extends StatelessWidget {
  const _Pressable({
    required this.tooltip,
    required this.onPressed,
    required this.selected,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final enabled = onPressed != null;
    final foreground = enabled ? tones.text : tones.faint;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: Material(
          color: selected ? tones.selection : Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: selected
                    ? Border(
                        bottom: BorderSide(color: tones.emphasis, width: 2),
                      )
                    : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A button one row high, showing [face]: its name, or a letter.
class RibbonButton extends StatelessWidget {
  const RibbonButton({
    required this.face,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 7),
    super.key,
  });

  final Widget face;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: RibbonMetrics.row,
    child: _Pressable(
      tooltip: tooltip,
      onPressed: onPressed,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: RibbonMetrics.row),
        child: Padding(
          padding: padding,
          child: Center(widthFactor: 1, child: face),
        ),
      ),
    ),
  );
}

/// A tall button: its name, over a [glyph] where there is something to show
/// — the pen's colour, the zoom, a formula.
class RibbonLargeButton extends StatelessWidget {
  const RibbonLargeButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.glyph,
    this.selected = false,
    super.key,
  });

  final String label;
  final Widget? glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = this.glyph;
    final name = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: RibbonMetrics.largeLabelWidth,
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: glyph == null ? 12.5 : 11),
      ),
    );
    return SizedBox(
      height: RibbonMetrics.content,
      child: _Pressable(
        tooltip: tooltip,
        onPressed: onPressed,
        selected: selected,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (glyph != null) ...<Widget>[
                  SizedBox(height: 26, child: Center(child: glyph)),
                  const SizedBox(height: 3),
                ],
                name,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] over a bar of [color]: the colour a button applies, or the
/// pen's.
class ColourBar extends StatelessWidget {
  const ColourBar({required this.color, this.child, super.key});

  final int color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ?child,
      Container(
        width: 18,
        height: 4,
        margin: const EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          color: Color(color | 0xFF000000),
          border: Border.all(color: context.tones.line, width: 0.5),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------- menus

/// Paragraph style: normal, headings, code, quotation.
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static const List<(TextBlockKind, String, EditorKey?)> _styles =
      <(TextBlockKind, String, EditorKey?)>[
        (TextBlockKind.paragraph, 'Normal', EditorKey.normal),
        (TextBlockKind.heading1, 'Heading 1', EditorKey.heading1),
        (TextBlockKind.heading2, 'Heading 2', EditorKey.heading2),
        (TextBlockKind.heading3, 'Heading 3', EditorKey.heading3),
        (TextBlockKind.code, 'Code', null),
        (TextBlockKind.quote, 'Quote', EditorKey.quote),
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
        width: 72,
        tooltip: 'Paragraph style',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        for (final (kind, name, key) in _styles)
          MenuItemButton(
            // A menu sets a style rather than toggling it, so choosing the
            // current one changes nothing.
            onPressed: kind == current
                ? null
                : () => controller.toggleBlockKind(kind),
            trailingIcon: key == null
                ? null
                : KeyHint(
                    <String>[
                      if (key.chords.isNotEmpty) key.keys,
                      if (key.typed case final typed?) '"$typed"',
                    ].join('  or  '),
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
        width: 22,
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
                ? Mark(MarkShape.check, color: context.tones.emphasis)
                : null,
            child: SizedBox(width: 40, child: Text(_format(size))),
          ),
      ],
    );
  }
}

/// A drop-down's face: its current value and an arrow, in a box.
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
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      height: RibbonMetrics.row - 4,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.only(left: 7, right: 4),
          minimumSize: Size.zero,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: width,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Mark(MarkShape.dropdown, size: 10),
          ],
        ),
      ),
    ),
  );
}

/// A colour button: the letter applies the colour shown beneath it; the
/// arrow opens the palette.
class _ColorButton extends StatefulWidget {
  const _ColorButton({
    required this.face,
    required this.tooltip,
    required this.name,
    required this.current,
    required this.fallback,
    required this.noneLabel,
    required this.enabled,
    required this.onChanged,
  });

  /// The letters shown over the colour.
  final String face;
  final String tooltip;

  /// What the colour is of, before its name: "Text colour: Red".
  final String name;

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
          RibbonButton(
            face: ColourBar(
              color: _last,
              child: Text(
                widget.face,
                style: const TextStyle(fontSize: 12.5, height: 1.1),
              ),
            ),
            tooltip:
                '${widget.tooltip}\n${widget.name}: '
                '${NotePalette.nameOf(_last)}',
            onPressed: widget.enabled ? () => widget.onChanged(_last) : null,
          ),
          RibbonButton(
            face: const Mark(MarkShape.dropdown, size: 10),
            padding: EdgeInsets.zero,
            tooltip: '${widget.name}: choose',
            onPressed: widget.enabled
                ? () => _menu.isOpen ? _menu.close() : _menu.open()
                : null,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- spelling

/// The languages spelling is checked in: those installed, ticked while they
/// are used — and the settings, where dictionaries are downloaded, added
/// and removed.
class _LanguagesMenu extends ConsumerWidget {
  const _LanguagesMenu({required this.item});

  final RibbonItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = ref.watch(spellingProvider.select((s) => s.languages));
    final reading = ref.watch(installedDictionariesProvider);
    final installed = reading.value ?? const <InstalledDictionary>[];

    return MenuAnchor(
      builder: (context, menu, _) => RibbonLargeButton(
        label: item.label,
        tooltip: 'Languages\nThe languages spelling is checked in',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
      menuChildren: <Widget>[
        if (installed.isEmpty)
          MenuItemButton(
            child: Text(
              reading.isLoading
                  ? 'Looking for dictionaries…'
                  : 'No dictionaries yet',
            ),
          )
        else
          for (final dictionary in installed)
            CheckboxMenuButton(
              value: used.contains(dictionary.code),
              onChanged: (value) => ref
                  .read(spellingProvider.notifier)
                  .useLanguage(dictionary.code, used: value ?? false),
              child: Text(dictionary.name),
            ),
        const Divider(height: 9),
        MenuItemButton(
          onPressed: () =>
              ref.read(commandHandlersProvider).run(AppCommand.dictionaries),
          child: const Text('Dictionaries…'),
        ),
      ],
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
                        Swatch(
                          color: Color(entry.color | 0xFF000000),
                          name: '$owner colour: ${entry.name}',
                          selected:
                              entry.color == (settings.color | 0xFF000000),
                          size: 18,
                          onTap: () => pick(entry.color),
                        ),
                    ],
                  ),
                RibbonButton(
                  face: const Mark(MarkShape.add),
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
    final tones = context.tones;
    final shown = highlighter
        ? Color(color | 0xFF000000).withValues(alpha: 0.45)
        : Color(color | 0xFF000000);
    final points = width.toStringAsFixed(width % 1 == 0 ? 0 : 1);
    // Each drawn as the stroke it makes: the pen's a line that thick, the
    // highlighter's a nib that tall.
    return Tooltip(
      message: highlighter ? 'Highlighter: $points pt' : 'Pen: $points pt',
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tones.selection : null,
            border: Border(
              bottom: BorderSide(
                color: selected ? tones.emphasis : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: highlighter
              ? Container(
                  width: (width * 0.16).clamp(2, 5),
                  height: (width * 0.7).clamp(6, 28),
                  color: shown,
                )
              : Container(
                  width: 18,
                  height: (width * 1.2).clamp(1, 10),
                  color: shown,
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
    final tones = context.tones;
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
        glyph: FittedBox(
          fit: BoxFit.scaleDown,
          child: MathView(
            source: gallery.icon,
            mode: MathMode.latex,
            displayStyle: false,
            textStyle: TextStyle(fontSize: 18, color: tones.text),
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
    final tones = context.tones;
    return Tooltip(
      message: template.name,
      child: InkWell(
        onTap: onTap,
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
              textStyle: TextStyle(fontSize: 18, color: tones.text),
            ),
          ),
        ),
      ),
    );
  }
}
