/// The buttons, menus and galleries the ribbon is made of.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../sheet_choices.dart';
import '../text/cheat_sheet.dart';
import '../text/math_syntax.dart';
import '../text/math_templates.dart';
import '../text/text_box_controller.dart';
import '../text/text_styles.dart';
import '../text/typefaces.dart';
import 'ribbon_layout.dart';
import 'ribbon_state.dart';
import 'shape_glyph.dart';

part 'ribbon_buttons.dart';
part 'ribbon_galleries.dart';
part 'ribbon_menus.dart';

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
  _ => switch (item.icon) {
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
    final icon = item.icon;

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
