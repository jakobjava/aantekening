/// The buttons, menus and galleries the ribbon is made of.
library;

import 'dart:math' as math;

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
import '../../look/icons.dart';
import '../../look/marks.dart';
import '../../look/tones.dart';
import '../../spelling/dictionaries.dart';
import '../../spelling/spelling.dart';
import '../page_minimap.dart';
import '../palette.dart';
import '../text/cheat_sheet.dart';
import '../text/math_syntax.dart';
import '../text/math_templates.dart';
import '../text/text_box_controller.dart';
import '../text/text_styles.dart';
import '../text/typefaces.dart';
import '../sheet_choices.dart';
import 'ribbon_layout.dart';
import 'ribbon_state.dart';
import 'shape_glyph.dart';

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
  RibbonItem.bullets => const _IconFace(AppIcon.bullets, 'Bullets'),
  RibbonItem.numbering => const _IconFace(AppIcon.numbers, 'Numbers'),
  _ => switch (ribbonIconOf(item)) {
    final icon? => _IconFace(icon, item.label),
    null => Text(item.label),
  },
};

/// A small button's face: its icon and its name.
class _IconFace extends StatelessWidget {
  const _IconFace(this.icon, this.label);

  final AppIcon icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      AppIconView(icon, size: 15),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}

/// The icon of a button on the ribbon, if it has one: those drawn some
/// other way — formatting as the letters it formats, a colour, a formula,
/// the zoom — have none.
AppIcon? ribbonIconOf(RibbonItem item) => switch (item) {
  RibbonItem.undo => AppIcon.undo,
  RibbonItem.redo => AppIcon.redo,
  RibbonItem.bullets => AppIcon.bullets,
  RibbonItem.numbering => AppIcon.numbers,
  RibbonItem.todo => AppIcon.todo,
  RibbonItem.outdent => AppIcon.outdent,
  RibbonItem.indent => AppIcon.indent,
  RibbonItem.formula || RibbonItem.insertFormula => AppIcon.formula,
  RibbonItem.mathCheatSheet => AppIcon.cheatSheet,
  RibbonItem.textBox => AppIcon.textBox,
  RibbonItem.picture => AppIcon.picture,
  RibbonItem.pdf => AppIcon.pdf,
  RibbonItem.addSheet => AppIcon.addSheet,
  RibbonItem.paper => AppIcon.paper,
  RibbonItem.deleteSheet => AppIcon.bin,
  RibbonItem.moveSheetUp => AppIcon.sheetUp,
  RibbonItem.moveSheetDown => AppIcon.sheetDown,
  RibbonItem.pageLayout => AppIcon.sheets,
  RibbonItem.select => AppIcon.select,
  RibbonItem.lasso => AppIcon.lasso,
  RibbonItem.eraser => AppIcon.eraser,
  RibbonItem.pen => AppIcon.pen,
  RibbonItem.highlighter => AppIcon.highlighter,
  RibbonItem.zoomIn => AppIcon.zoomIn,
  RibbonItem.zoomOut => AppIcon.zoomOut,
  RibbonItem.fitPage => AppIcon.fitPage,
  RibbonItem.pagePreview => AppIcon.pagePreview,
  RibbonItem.resetRibbon => AppIcon.reset,
  RibbonItem.spelling => AppIcon.spelling,
  RibbonItem.spellingLanguages => AppIcon.languages,
  _ => null,
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
    final icon = ribbonIconOf(item);

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
            icon: icon,
            glyph: colour == null
                ? null
                : ColourBar(
                    color: colour,
                    child: icon == null ? null : AppIconView(icon),
                  ),
            tooltip: bindings.tooltip(command, describe: true),
            selected: current == tool,
            onPressed: () => commands.onToolSelected(tool),
          ),
        );

    void run(AppCommand command) =>
        ref.read(commandHandlersProvider).run(command);

    Widget large(
      AppCommand command,
      VoidCallback? onPressed, {
      bool selected = false,
    }) => RibbonLargeButton(
      label: item.label,
      icon: icon,
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
      RibbonItem.font => _TextCommand(
        text: text,
        builder: (state, enabled) =>
            _FontMenu(controller: text, enabled: enabled),
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
          offersInverse: true,
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
        icon: icon,
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
        icon: icon,
        tooltip:
            '${bindings.tooltip(AppCommand.insertTextBox, label: 'Text box')}'
            '\nOr click anywhere on the page with Select and start typing',
        onPressed: commands.onInsertTextBox,
      ),
      RibbonItem.picture => _TextCommand(
        text: text,
        builder: (state, enabled) => RibbonLargeButton(
          label: item.label,
          icon: icon,
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
          icon: icon,
          tooltip: text.isActive
              ? 'Insert PDF pages into the text box'
              : 'Insert PDF pages onto the page, one picture per page',
          onPressed: commands.onInsertPdf,
        ),
      ),
      RibbonItem.insertFormula => RibbonLargeButton(
        label: item.label,
        icon: icon,
        tooltip:
            '${EditorKey.formula.tooltip}\nWritten in place, in a text box',
        onPressed: commands.onFormula,
      ),
      RibbonItem.select => tool(CanvasTool.select, AppCommand.selectTool),
      RibbonItem.lasso => tool(CanvasTool.lasso, AppCommand.lassoTool),
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
      RibbonItem.shapes => _ShapesGallery(
        commands: commands,
        label: item.label,
        tooltip: bindings.tooltip(AppCommand.shapes, describe: true),
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
      RibbonItem.pageLayout => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.fold != null,
        builder: (context, sheets) => large(
          AppCommand.pageLayout,
          () => run(AppCommand.pageLayout),
          selected: sheets,
        ),
      ),
      RibbonItem.addSheet => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => canvas.fold != null,
        builder: (context, sheets) => large(
          AppCommand.addSheet,
          sheets ? () => run(AppCommand.addSheet) : null,
        ),
      ),
      RibbonItem.deleteSheet => _CanvasSelect<bool>(
        canvas: canvas,
        select: () => (canvas.fold?.count ?? 0) > 1,
        builder: (context, several) => RibbonButton(
          face: face,
          tooltip: bindings.tooltip(AppCommand.deleteSheet, describe: true),
          onPressed: several ? () => run(AppCommand.deleteSheet) : null,
        ),
      ),
      RibbonItem.paper => _PaperMenu(canvas: canvas),
      RibbonItem.moveSheetUp || RibbonItem.moveSheetDown => _CanvasSelect<bool>(
        canvas: canvas,
        // Whether the sheet in view has one to go past that way.
        select: () {
          final count = canvas.fold?.count ?? 0;
          final to =
              canvas.currentSheet + (item == RibbonItem.moveSheetUp ? -1 : 1);
          return to >= 0 && to < count;
        },
        builder: (context, can) {
          final command = item == RibbonItem.moveSheetUp
              ? AppCommand.moveSheetUp
              : AppCommand.moveSheetDown;
          return RibbonButton(
            face: face,
            tooltip: bindings.tooltip(command, describe: true),
            onPressed: can ? () => run(command) : null,
          );
        },
      ),
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
        icon: icon,
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

/// A tall button: its name, under its icon, or under a [glyph] where there
/// is more to show — the pen's colour, the zoom, a formula.
class RibbonLargeButton extends StatelessWidget {
  const RibbonLargeButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.glyph,
    this.icon,
    this.selected = false,
    super.key,
  });

  final String label;

  /// What is shown over the name: [icon], unless something more is to be
  /// shown.
  final Widget? glyph;
  final AppIcon? icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final glyph =
        this.glyph ?? (icon == null ? null : AppIconView(icon, size: 20));
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
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: context.tones.line, width: 0.5),
        ),
        child: color == NoteColors.inverse
            ? const CustomPaint(painter: InverseHalves())
            : ColoredBox(color: Color(color | 0xFF000000)),
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

/// The typeface: the page's own, those the app brings, and those installed
/// on this computer, each named in itself.
class _FontMenu extends ConsumerWidget {
  const _FontMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static const String _default = 'Default';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = controller.state.font;
    final installed = ref.watch(installedTypefacesProvider).value;
    final others = <String>[
      for (final family in installed ?? Typefaces.common)
        if (!Typefaces.bundled.contains(family)) family,
    ];
    final sections = <(String, List<String>)>[
      if (current != null &&
          !Typefaces.bundled.contains(current) &&
          !others.contains(current))
        ('In this text', <String>[current]),
      ('In the app', Typefaces.bundled),
      (installed == null ? 'Common' : 'On this computer', others),
    ];
    // One list, headings among the families, built as it is scrolled: a
    // computer can have hundreds.
    final rows = <({String? heading, String? family})>[
      (heading: null, family: null),
      for (final (heading, families) in sections) ...[
        (heading: heading, family: null),
        for (final family in families) (heading: null, family: family),
      ],
    ];

    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: current ?? _default,
        width: 92,
        tooltip: 'Font',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        SizedBox(
          width: 260,
          height: math.min(420, rows.length * _rowHeight),
          child: ListView.builder(
            // The menu scrolls itself; this list scrolls apart from it.
            primary: false,
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) {
              final (:heading, :family) = rows[index];
              if (heading != null) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SmallCaps(heading),
                );
              }
              return MenuItemButton(
                onPressed: () => controller.setFont(family),
                trailingIcon: family == current
                    ? Mark(MarkShape.check, color: context.tones.emphasis)
                    : null,
                child: Text(
                  family ?? _default,
                  overflow: TextOverflow.ellipsis,
                  style: family == null
                      ? null
                      : TextStyle(
                          fontFamily: family,
                          fontFamilyFallback: RichTextStyles.typefacesFor(
                            family,
                          ),
                          fontSize: 14,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static const double _rowHeight = 32;
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
    this.offersInverse = false,
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

  /// Whether the inverse of what is beneath is offered too.
  final bool offersInverse;

  /// Called with the chosen colour, opaque, or null for [noneLabel].
  final ValueChanged<int?> onChanged;

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  final MenuController _menu = MenuController();
  late int _last = widget.fallback;

  void _apply(int? color) {
    if (color != null) setState(() => _last = NotePalette.opaque(color));
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
          offersInverse: widget.offersInverse,
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
        icon: ribbonIconOf(item),
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
/// OneNote does — unless the shape tool, which draws in the pen's ink, is in
/// hand.
void _changeInk(RibbonCommands commands, PenSettings settings) {
  commands.canvas.setPen(settings);
  if (commands.canvas.tool == CanvasTool.shape &&
      settings.tool != InkTool.highlighter) {
    return;
  }
  commands.onToolSelected(
    settings.tool == InkTool.highlighter
        ? CanvasTool.highlighter
        : CanvasTool.pen,
  );
}

/// The shapes: the one the shape tool drags out, which the button takes
/// up, and every shape, family by family, to choose another.
class _ShapesGallery extends StatefulWidget {
  const _ShapesGallery({
    required this.commands,
    required this.label,
    required this.tooltip,
  });

  final RibbonCommands commands;
  final String label;
  final String tooltip;

  @override
  State<_ShapesGallery> createState() => _ShapesGalleryState();
}

class _ShapesGalleryState extends State<_ShapesGallery> {
  final MenuController _menu = MenuController();

  static const double _tile = 40;
  static const int _columns = 6;

  void _choose(ShapeKind kind) {
    _menu.close();
    widget.commands.canvas.setShapeKind(kind);
    widget.commands.onToolSelected(CanvasTool.shape);
  }

  @override
  Widget build(BuildContext context) {
    final canvas = widget.commands.canvas;
    return _CanvasSelect<(CanvasTool, ShapeKind)>(
      canvas: canvas,
      select: () => (canvas.tool, canvas.shapeKind),
      builder: (context, value) {
        final (tool, chosen) = value;
        final inHand = tool == CanvasTool.shape;
        return MenuAnchor(
          controller: _menu,
          menuChildren: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: _tile * _columns,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final family in ShapeFamily.values) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                        child: SmallCaps(family.label),
                      ),
                      Wrap(
                        children: <Widget>[
                          for (final kind in ShapeKind.of(family))
                            _ShapeTile(
                              kind: kind,
                              size: _tile,
                              selected: inHand && kind == chosen,
                              onTap: () => _choose(kind),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          child: RibbonLargeButton(
            glyph: ShapeGlyph(chosen, size: 22),
            label: widget.label,
            tooltip:
                '${widget.tooltip}\nShift keeps it square, or its '
                'lines to steps of 15°',
            selected: inHand,
            onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
          ),
        );
      },
    );
  }
}

/// What is printed on the sheet in view, to choose, and the choice to
/// print that on every sheet.
class _PaperMenu extends StatefulWidget {
  const _PaperMenu({required this.canvas});

  final CanvasController canvas;

  @override
  State<_PaperMenu> createState() => _PaperMenuState();
}

class _PaperMenuState extends State<_PaperMenu> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final canvas = widget.canvas;
    return _CanvasSelect<(Sheets?, int)>(
      canvas: canvas,
      select: () => (canvas.document.canvas.sheetsShown, canvas.currentSheet),
      builder: (context, value) {
        final (sheets, sheet) = value;
        final current = sheets?.templates[sheet];
        return MenuAnchor(
          controller: _menu,
          menuChildren: <Widget>[
            if (sheets != null && current != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SmallCaps('Sheet ${sheet + 1}'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 3 * 78,
                  child: SheetTemplatePicker(
                    selected: current,
                    size: sheets.size,
                    onSelected: (template) {
                      _menu.close();
                      canvas.setSheetTemplate(template, sheet: sheet);
                    },
                  ),
                ),
              ),
              const Divider(height: 12),
              MenuItemButton(
                onPressed: sheets.templates.every((t) => t == current)
                    ? null
                    : () => canvas.setSheetTemplate(current),
                child: Text('${current.label} on every sheet'),
              ),
            ],
          ],
          child: RibbonButton(
            face: ribbonFaceOf(RibbonItem.paper),
            tooltip: 'Paper\nWhat is printed on the sheet in view',
            onPressed: sheets == null
                ? null
                : () => _menu.isOpen ? _menu.close() : _menu.open(),
          ),
        );
      },
    );
  }
}

/// One shape in the gallery, drawn as it is drawn on the page.
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.kind,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final ShapeKind kind;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Tooltip(
      message: kind.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
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
          child: ShapeGlyph(kind, size: size - 14),
        ),
      ),
    );
  }
}

/// The palette, for the pen or highlighter in hand.
class _InkColourGallery extends StatelessWidget {
  const _InkColourGallery({required this.commands});

  final RibbonCommands commands;

  /// Custom colours shown after the presets.
  static const int _recent = 4;

  /// How large a colour's swatch is.
  static const double _swatch = 18;

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
            settings.copyWith(color: NotePalette.opaque(color)),
          );
          Widget swatch(({int color, String name}) entry) => NoteSwatch(
            color: entry.color,
            name: '$owner colour: ${entry.name}',
            selected: entry.color == NotePalette.opaque(settings.color),
            size: _swatch,
            onTap: () => pick(entry.color),
          );

          return SizedBox(
            height: RibbonMetrics.content,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // No colour of its own, the inverse stands apart, in a
                    // column of its own, the place beneath it left empty.
                    if (settings.tool != InkTool.highlighter)
                      swatch(NotePalette.inverse),
                    for (var i = 0; i < colours.length; i += 2)
                      Column(
                        children: <Widget>[
                          for (final entry in colours.skip(i).take(2))
                            swatch(entry),
                        ],
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
        : color == NoteColors.inverse
        ? tones.text
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
