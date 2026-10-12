part of 'page_editor.dart';

/// The page editors open, so that one showing the same page as another —
/// the window split with it in both panes — shows what is done in the
/// other.
final _pageEditorsProvider = Provider<Set<_PageEditorState>>(
  (ref) => <_PageEditorState>{},
);

/// The same page open in both panes: each shows it from where it is
/// looking, and what is done to it in one is done in the other, which can
/// undo it too. Whichever made a change saves it.
extension _Twin on _PageEditorState {
  /// The other editor showing this one's page, read already, if there is
  /// one.
  _PageEditorState? get _twin {
    final pageId = widget.pageId;
    if (pageId == null) return null;
    for (final editor in _editors) {
      if (!identical(editor, this) &&
          !editor._disposed &&
          editor._ready &&
          editor.widget.pageId == pageId) {
        return editor;
      }
    }
    return null;
  }

  /// The page as the other editor is to show it: without the carets placed
  /// here, which are nothing yet.
  PageDocument get _sharedDocument {
    final document = _controller.document;
    return _placed.isEmpty ? document : document.withElementsRemoved(_placed);
  }

  /// Has the twin show the page as it is here now, if it has changed here.
  void _shareWithTwin() {
    final document = _controller.document;
    if (identical(document, _shared)) return;
    _shared = document;
    // Until the page has been read, the canvas still holds the one before.
    if (_following || !_ready) return;
    _twin?._follow(this);
  }

  /// Shows the page as [twin] has it, keeping the carets placed here.
  void _follow(_PageEditorState twin) {
    var document = twin._sharedDocument;
    for (final id in _placed) {
      final caret = _controller.elementById(id);
      if (caret != null && document.elementById(id) == null) {
        document = document.withElementAdded(caret);
      }
    }
    _following = true;
    try {
      _controller.follow(twin._controller, document);
    } finally {
      _following = false;
    }
  }
}
