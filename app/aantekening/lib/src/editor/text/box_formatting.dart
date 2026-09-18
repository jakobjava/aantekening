/// Formatting whole text boxes, picked with the selection tool rather than
/// opened for editing.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';

import 'math_templates.dart';
import 'text_box_controller.dart';
import 'text_styles.dart';

/// Applies formatting commands to every selected text box as a whole, as
/// OneNote does when a container rather than text inside it is selected.
///
/// Each command is one undo step, however many boxes it changes.
class BoxFormatting implements TextEditorCommands {
  BoxFormatting(this.canvas);

  final CanvasController canvas;

  /// The selected text boxes.
  List<TextElement> get boxes =>
      canvas.selectedElements.whereType<TextElement>().toList();

  static RichSelection _whole(List<TextBlock> blocks) =>
      RichSelection(RichPosition.zero, RichTextEditing.endOf(blocks));

  /// The formatting of the selected boxes: the marks every one of them has
  /// throughout, and the rest as at the start of the first.
  TextFormatState get state {
    final boxes = this.boxes;
    if (boxes.isEmpty) return TextFormatState.none;
    final first = boxes.first.blocks.firstWhere(
      (block) => !block.isEmbed,
      orElse: () => const TextBlock(),
    );
    final sample = first.runs.isEmpty ? TextMarks.none : first.runs.first.marks;
    return TextFormatState(
      marks: <MarkKind>{
        for (final kind in MarkKind.values)
          if (boxes.every(
            (box) => RichTextEditing.everyMark(
              box.blocks,
              _whole(box.blocks),
              kind.isSetIn,
            ),
          ))
            kind,
      },
      blockKind: first.kind,
      fontSize: sample.size ?? RichTextStyles.defaultPointsFor(first),
      textColor: sample.color,
      highlight: sample.highlight,
    );
  }

  void _apply(
    List<TextBlock> Function(List<TextBlock> blocks, RichSelection whole)
    change,
  ) {
    final boxes = this.boxes;
    if (boxes.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    canvas.replaceElements(<NoteElement>[
      for (final box in boxes)
        box.copyWith(
          blocks: change(box.blocks, _whole(box.blocks)),
          updatedAt: now,
        ),
    ]);
  }

  void _changeMarks(TextMarks Function(TextMarks marks) change) => _apply(
    (blocks, whole) => RichTextEditing.applyMarks(blocks, whole, change),
  );

  @override
  void toggleMark(MarkKind kind) {
    final on = !state.marks.contains(kind);
    _changeMarks((marks) => kind.setIn(marks, on: on));
  }

  @override
  void toggleBlockKind(TextBlockKind kind) {
    // Every paragraph takes the style, unless every one already has it.
    final all = boxes.every(
      (box) => box.blocks.every((block) => block.isEmbed || block.kind == kind),
    );
    final target = all ? TextBlockKind.paragraph : kind;
    _apply(
      (blocks, whole) => <TextBlock>[
        for (final block in blocks)
          block.isEmbed || block.kind == target
              ? block
              : block.copyWith(kind: target, checked: false),
      ],
    );
  }

  @override
  void indent(int delta) => _apply(
    (blocks, whole) => RichTextEditing.indentBlocks(blocks, whole, delta),
  );

  @override
  void setFontSize(double points) =>
      _changeMarks((marks) => marks.withSize(points));

  @override
  void setTextColor(int? color) =>
      _changeMarks((marks) => marks.withColor(color));

  @override
  void setHighlight(int? color) =>
      _changeMarks((marks) => marks.withHighlight(color));

  // A formula or a picture goes at a caret, which a whole box does not have.

  @override
  void toggleFormula() {}

  @override
  void insertMath(MathTemplate template) {}

  @override
  void finishFormula({bool after = true}) {}

  @override
  void insertEmbeds(List<BlockEmbed> embeds) {}
}
