/// The link between the toolbar and whichever text box is being edited.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

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

  /// [marks] with this formatting turned on or off. Turning the highlight on
  /// uses yellow.
  TextMarks setIn(TextMarks marks, {required bool on}) => TextMarks(
    bold: this == MarkKind.bold ? on : marks.bold,
    italic: this == MarkKind.italic ? on : marks.italic,
    underline: this == MarkKind.underline ? on : marks.underline,
    strikethrough: this == MarkKind.strikethrough ? on : marks.strikethrough,
    code: this == MarkKind.code ? on : marks.code,
    color: marks.color,
    highlight: this == MarkKind.highlight
        ? (on ? RichTextStyles.highlightYellow : null)
        : marks.highlight,
    link: marks.link,
    size: marks.size,
  );
}

/// What the toolbar shows about the text under the caret.
@immutable
class TextFormatState {
  const TextFormatState({
    this.marks = const <MarkKind>{},
    this.blockKind = TextBlockKind.paragraph,
    this.inFormula = false,
    this.fontSize = 11,
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

  /// The font size under the caret, in points.
  final double fontSize;

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
      other.fontSize == fontSize &&
      other.textColor == textColor &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(marks),
    blockKind,
    inFormula,
    fontSize,
    textColor,
    highlight,
  );
}

/// The formula being edited, as its preview beneath it needs it.
@immutable
class FormulaSession {
  const FormulaSession({required this.latex, this.error});

  /// The formula as it stands, in LaTeX, as it is stored.
  final String latex;

  /// Why the Simple syntax typed so far cannot be read in full, if it cannot.
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is FormulaSession && other.latex == latex && other.error == error;

  @override
  int get hashCode => Object.hash(latex, error);
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

  /// Places pictures or PDF pages at the caret, each on its own line.
  void insertEmbeds(List<BlockEmbed> embeds);

  /// Sets the font size, in points.
  void setFontSize(double points);

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
    _setFormula(null, null);
    _notify();
  }

  /// The formula being edited, for the preview beneath it; null when none
  /// is.
  final ValueNotifier<FormulaSession?> formula = ValueNotifier<FormulaSession?>(
    null,
  );

  /// Where the source of the formula being edited sits in its text box, in
  /// the box's own page units, once it has been laid out.
  final ValueNotifier<Rect?> formulaAnchor = ValueNotifier<Rect?>(null);

  /// The syntax formulas are typed in. Kept in step with the person's
  /// preference by the page; a text box switching it translates the formula
  /// being edited.
  final ValueNotifier<MathMode> formulaSyntax = ValueNotifier<MathMode>(
    MathMode.linear,
  );

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

  /// Called by the attached text box as a formula opens, changes and closes,
  /// with where its source is laid out — null until it has been, so that
  /// nothing is placed by where the last formula was.
  void reportFormula(
    TextEditorCommands editor,
    FormulaSession? session, [
    Rect? anchor,
  ]) {
    if (!identical(_editor, editor)) return;
    _setFormula(session, session == null ? null : anchor);
  }

  void _setFormula(FormulaSession? session, Rect? anchor) {
    void apply() {
      if (_disposed) return;
      formula.value = session;
      formulaAnchor.value = anchor;
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
    formula.dispose();
    formulaAnchor.dispose();
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
  void insertMath(MathTemplate template) => _editor?.insertMath(template);

  @override
  void finishFormula({bool after = true}) =>
      _editor?.finishFormula(after: after);

  @override
  void insertEmbeds(List<BlockEmbed> embeds) => _editor?.insertEmbeds(embeds);

  @override
  void setFontSize(double points) => _target?.setFontSize(points);

  @override
  void setTextColor(int? color) => _target?.setTextColor(color);

  @override
  void setHighlight(int? color) => _target?.setHighlight(color);
}
