part of 'page_editor.dart';

/// The mode the page is in, worked out from what it is doing, and moving
/// from one mode to another.
extension _Modes on _PageEditorState {
  /// The mode the page is in: typing while a text box has the caret, else
  /// as the tool in hand says.
  EditorMode get _mode {
    if (_editingId != null) return EditorMode.insert;
    return switch (_controller.tool) {
      CanvasTool.select => EditorMode.normal,
      CanvasTool.lasso => EditorMode.select,
      CanvasTool.pen ||
      CanvasTool.highlighter ||
      CanvasTool.shape ||
      CanvasTool.eraser => EditorMode.draw,
    };
  }

  /// Tells the window the mode the page is in, once it has changed, if it
  /// has the keys. Not while the window is being built, which a change to
  /// what it shows may not be made in: then once it has been.
  void _syncMode() {
    if (!widget.active) return;
    final mode = _mode;
    if (mode == _reportedMode) return;
    _reportedMode = mode;
    void report() {
      if (!_disposed) ref.read(pageModeProvider.notifier).report(mode);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => report());
    } else {
      report();
    }
  }
}
