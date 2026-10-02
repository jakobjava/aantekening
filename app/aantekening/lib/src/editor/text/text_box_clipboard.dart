part of 'text_box_editor.dart';

/// Cutting, copying and pasting.
extension _Clipboard on TextBoxEditorState {
  Future<void> _copy({bool cut = false}) async {
    if (_selection.isCollapsed) return;
    final formula = _formula;
    if (formula != null) {
      // Part of a formula's source is copied as the text it is.
      final (:source, :from, :to) = _sourceSelection(formula);
      await NoteClipboard.copy(PlainClip(source.substring(from, to)));
      if (cut && mounted && _formula != null) _replaceInFormula('');
      return;
    }
    final fragment = RichTextEditing.slice(_blocks, _selection);
    await NoteClipboard.copy(
      TextClip(RichTextEditing.plainTextOf(fragment), fragment),
    );
    if (cut && mounted) _deleteSelection();
  }

  /// Pastes what was copied — as it was, or as its text only — over the
  /// selection. Things copied from the page go into the text where they can
  /// — text boxes as their text, pictures and PDF pages as objects in it —
  /// and onto the page where they cannot, or where there is no text yet to
  /// put them in: at a bare caret on the paper.
  Future<void> _paste({bool textOnly = false}) async {
    final clip = textOnly
        ? await NoteClipboard.readText()
        : await NoteClipboard.read();
    if (clip == null || !mounted) return;
    if (_formula != null) {
      _undoSteps.breakStep();
      _replaceInFormula(clip.plain.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' '));
      return;
    }
    final blocks = switch (clip) {
      PlainClip() => null,
      TextClip(:final blocks) => blocks,
      // At a bare caret, things from the page are pasted as themselves.
      ElementsClip() when TextBoxEditor.isEmpty(_blocks) => null,
      ElementsClip(:final asBlocks) => asBlocks,
    };
    if (blocks != null) {
      _commit(
        RichTextEditing.insertFragment(_blocks, _selection, blocks),
        EditKind.other,
      );
    } else if (clip is ElementsClip) {
      widget.onPasteElements?.call(clip.elements);
    } else if (_isLink(clip.plain.trim())) {
      // A link pasted alone is pasted as one, to be followed.
      final link = clip.plain.trim();
      _commit(
        RichTextEditing.insertText(
          _blocks,
          _selection,
          link,
          marks: _typingMarks().withLink(link),
        ),
        EditKind.other,
      );
    } else {
      _undoSteps.breakStep();
      _insertText(clip.plain);
    }
  }

  /// Whether [text] is a link and nothing else: to a note, or on the web.
  static bool _isLink(String text) {
    if (text.contains(RegExp(r'\s'))) return false;
    if (NoteLink.isNoteLink(text)) return true;
    final uri = Uri.tryParse(text);
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }
}
