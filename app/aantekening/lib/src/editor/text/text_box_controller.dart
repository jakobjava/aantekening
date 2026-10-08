/// The link between the toolbar and whichever text box is being edited.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Widget;

import 'formula_window.dart';
import 'math_templates.dart';
import 'text_styles.dart';

/// Inline formatting the toolbar and shortcuts can toggle.
enum MarkKind { bold, italic, underline, strikethrough, code, highlight }

/// What each [MarkKind] means for a run's [TextMarks].
extension MarkKinds on MarkKind {
  /// The kinds of formatting [marks] has.
  static Set<MarkKind> of(TextMarks marks) => <MarkKind>{
    for (final kind in MarkKind.values)
      if (kind.isSetIn(marks)) kind,
  };

  /// Whether [marks] has this formatting.
  bool isSetIn(TextMarks marks) => switch (this) {
    MarkKind.bold => marks.bold,
    MarkKind.italic => marks.italic,
    MarkKind.underline => marks.underline,
    MarkKind.strikethrough => marks.strikethrough,
    MarkKind.code => marks.code,
    MarkKind.highlight => marks.highlight != null,
  };

  /// [marks] with this formatting turned on or off, and the rest of it as
  /// it was. Turning the highlight on uses yellow.
  TextMarks setIn(TextMarks marks, {required bool on}) => switch (this) {
    MarkKind.bold => marks.copyWith(bold: on),
    MarkKind.italic => marks.copyWith(italic: on),
    MarkKind.underline => marks.copyWith(underline: on),
    MarkKind.strikethrough => marks.copyWith(strikethrough: on),
    MarkKind.code => marks.copyWith(code: on),
    MarkKind.highlight => marks.withHighlight(
      on ? RichTextStyles.highlightYellow : null,
    ),
  };
}

/// What the toolbar shows about the text under the caret.
@immutable
class TextFormatState {
  const TextFormatState({
    this.marks = const <MarkKind>{},
    this.blockKind = TextBlockKind.paragraph,
    this.inFormula = false,
    this.latexOnly = false,
    this.fontSize = 11,
    this.font,
    this.textColor,
    this.highlight,
  });

  static const TextFormatState none = TextFormatState();

  /// The marks that apply to the whole selection, or that typing will use.
  final Set<MarkKind> marks;

  /// The kind of the block holding the caret.
  final TextBlockKind blockKind;

  /// Whether a formula is being edited.
  final bool inFormula;

  /// Whether the formula being edited can only be typed as LaTeX: a TikZ
  /// picture.
  final bool latexOnly;

  /// The font size under the caret, in points.
  final double fontSize;

  /// The typeface under the caret, or null for the page's own.
  final String? font;

  /// The text colour under the caret, or null for the default black.
  final int? textColor;

  /// The highlight under the caret, or null for none.
  final int? highlight;

  @override
  bool operator ==(Object other) =>
      other is TextFormatState &&
      setEquals(other.marks, marks) &&
      other.blockKind == blockKind &&
      other.inFormula == inFormula &&
      other.latexOnly == latexOnly &&
      other.fontSize == fontSize &&
      other.font == font &&
      other.textColor == textColor &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(marks),
    blockKind,
    inFormula,
    latexOnly,
    fontSize,
    font,
    textColor,
    highlight,
  );
}

/// Commands a text box accepts from outside itself.
abstract interface class TextEditorCommands {
  void toggleMark(MarkKind kind);

  /// Sets the kind of the selected blocks, or returns them to paragraphs if
  /// they already have it.
  void toggleBlockKind(TextBlockKind kind);

  void indent(int delta);

  /// Starts a formula at the caret, or finishes the one being edited.
  void toggleFormula();

  /// Puts [template] into the formula being edited, at the caret, starting
  /// a formula first if none is.
  void insertMath(MathTemplate template);

  /// Finishes the formula being edited, putting the caret back in the text
  /// after it, or before it.
  void finishFormula({bool after = true});

  /// Finishes whatever is left open — the formula being edited — and
  /// reports the text as it is then, as typing in the box ends: so the page
  /// knows what the box holds before it lets go of it, rather than while it
  /// rebuilds, when nothing on the page may change.
  void finishEditing();

  /// Places pictures or PDF pages at the caret, each on its own line.
  void insertEmbeds(List<BlockEmbed> embeds);

  /// Puts [blocks] in place of the selection: text, formulas, lists and
  /// tables read from elsewhere.
  void insertBlocks(List<TextBlock> blocks);

  /// Types [text] at the caret as the keyboard would — a new line starting
  /// a paragraph, and what typing turns into lists or formulas turning so.
  void typeText(String text);

  /// Sets the font size, in points.
  void setFontSize(double points);

  /// Sets the typeface, or returns it to the page's own with null.
  void setFont(String? family);

  /// Sets the text colour, or returns it to the default with null.
  void setTextColor(int? color);

  /// Sets the highlight colour, or removes the highlight with null.
  void setHighlight(int? color);
}

/// Forwards toolbar commands to the text box being edited and reports its
/// formatting back, so the toolbar never needs to know which box that is.
///
/// With no box being edited, commands go to a fallback instead, if one is
/// set: the text boxes picked with the selection tool, formatted whole.
class TextBoxEditorController extends ChangeNotifier
    implements TextEditorCommands {
  TextEditorCommands? _editor;
  TextFormatState _state = TextFormatState.none;
  TextEditorCommands? _fallback;
  TextFormatState _fallbackState = TextFormatState.none;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Whether a text box is being edited.
  bool get isActive => _editor != null;

  /// Whether formatting commands have anywhere to go: a box being edited, or
  /// the fallback.
  bool get hasTarget => _editor != null || _fallback != null;

  /// The formatting of the text being edited, or of the fallback's.
  TextFormatState get state => _editor != null ? _state : _fallbackState;

  TextEditorCommands? get _target => _editor ?? _fallback;

  /// Sets where commands go while no box is being edited, and the formatting
  /// to show for it; null for nowhere.
  void setFallback(
    TextEditorCommands? commands, [
    TextFormatState state = TextFormatState.none,
  ]) {
    if (identical(commands, _fallback) && state == _fallbackState) return;
    _fallback = commands;
    _fallbackState = state;
    if (_editor == null) _notify();
  }

  /// Called by a text box when it starts editing.
  void attach(TextEditorCommands editor) {
    if (identical(_editor, editor)) return;
    _editor = editor;
    _notify();
  }

  /// Called by a text box when it stops editing. Ignored if another box has
  /// already taken over.
  void detach(TextEditorCommands editor) {
    if (!identical(_editor, editor)) return;
    _editor = null;
    _state = TextFormatState.none;
    _setFormula(null);
    _notify();
  }

  /// The source of the formula being edited, for the page to draw over
  /// everything on it; null when no formula is.
  final ValueNotifier<Widget?> formulaField = ValueNotifier<Widget?>(null);

  /// The syntax formulas are typed in. Kept in step with the person's
  /// preference by the page; a text box switching it translates the formula
  /// being edited.
  final ValueNotifier<MathMode> formulaSyntax = ValueNotifier<MathMode>(
    MathMode.linear,
  );

  /// How long a formula's source grows before it is typed in a window. Kept
  /// in step with the person's setting by the page.
  FormulaWindow formulaWindow = const FormulaWindow();

  MathTemplate? _queuedMath;

  /// Holds [template] for the next text box to start editing a formula, when
  /// none is being edited yet.
  void queueMath(MathTemplate template) => _queuedMath = template;

  /// The template waiting for a formula to start, taken so it is used once.
  MathTemplate? takeQueuedMath() {
    final template = _queuedMath;
    _queuedMath = null;
    return template;
  }

  /// Called by the attached text box as a formula opens, with the [field]
  /// its source is typed in, and as it closes, with null.
  void reportFormula(TextEditorCommands editor, Widget? field) {
    if (identical(_editor, editor)) _setFormula(field);
  }

  void _setFormula(Widget? field) {
    void apply() {
      if (_disposed) return;
      formulaField.value = field;
    }

    // Like [_notify], never in the middle of a build.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  /// Called by the attached text box whenever its caret or formatting moves.
  void report(TextEditorCommands editor, TextFormatState state) {
    if (!identical(_editor, editor) || state == _state) return;
    _state = state;
    _notify();
  }

  /// Notifies now, or after the frame if the change was made while widgets
  /// are being built — a text box attaches as it is built, and the toolbar
  /// listening here must not be marked dirty in the middle of that.
  void _notify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final building =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!building) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    formulaField.dispose();
    formulaSyntax.dispose();
    super.dispose();
  }

  @override
  void toggleMark(MarkKind kind) => _target?.toggleMark(kind);

  @override
  void toggleBlockKind(TextBlockKind kind) => _target?.toggleBlockKind(kind);

  @override
  void indent(int delta) => _target?.indent(delta);

  @override
  void toggleFormula() => _editor?.toggleFormula();

  @override
  void finishEditing() => _editor?.finishEditing();

  @override
  void insertMath(MathTemplate template) => _editor?.insertMath(template);

  @override
  void finishFormula({bool after = true}) =>
      _editor?.finishFormula(after: after);

  @override
  void insertEmbeds(List<BlockEmbed> embeds) => _editor?.insertEmbeds(embeds);

  @override
  void insertBlocks(List<TextBlock> blocks) => _editor?.insertBlocks(blocks);

  @override
  void typeText(String text) => _editor?.typeText(text);

  @override
  void setFontSize(double points) => _target?.setFontSize(points);

  @override
  void setFont(String? family) => _target?.setFont(family);

  @override
  void setTextColor(int? color) => _target?.setTextColor(color);

  @override
  void setHighlight(int? color) => _target?.setHighlight(color);
}
