/// Which edits share one step of undo.
library;

/// What kind of change an edit is: edits of one kind made one soon after
/// another share a step of undo.
enum EditKind { typing, deleting, resizing, other }

/// Decides which edits start a new step of undo, as words typed in a run
/// are undone together and a pause, or a change of kind, starts another.
class UndoSteps {
  static const Duration _pause = Duration(milliseconds: 1500);

  EditKind? _lastKind;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _broken = true;

  /// Whether an edit of [kind], made now, starts a step of its own.
  bool startsStep(EditKind kind) {
    final now = DateTime.now();
    final starts =
        _broken ||
        kind == EditKind.other ||
        kind != _lastKind ||
        now.difference(_lastTime) > _pause;
    _lastKind = kind;
    _lastTime = now;
    _broken = false;
    return starts;
  }

  /// Makes the next edit start a step of its own, whatever it is: the caret
  /// has moved, or the text changed from elsewhere.
  void breakStep() => _broken = true;
}
